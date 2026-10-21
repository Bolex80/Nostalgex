import XCTest
@testable import Nostalgex

/// Daylight-saving harness, Apple TV side. Skipped unless pointed at a plan.
///
/// `node scripts/dst-harness/run.mjs` writes `scripts/dst-harness/out/plan.json` (the zones,
/// the change days, the channels and the instants to pack and sample) and runs the web
/// tuner's engine over it. This runs the app's own engine over the same plan, the way the
/// app calls it: no calendar is passed, so every day boundary comes from `Calendar.current`
/// in the zone under test. It writes the same JSON shape, and `run.mjs --swift <file>`
/// compares the two.
///
///     TEST_RUNNER_DST_HARNESS_PLAN=<abs>/plan.json TEST_RUNNER_DST_HARNESS_OUT=<abs>/swift.json \
///       xcodebuild test ... -only-testing:NostalgexTests/DSTHarnessTests
///
/// The zone is set with `NSTimeZone.default`, so one run covers every zone. Set
/// `TEST_RUNNER_DST_HARNESS_USE_PROCESS_TZ=1` with `TEST_RUNNER_TZ=<zone>` and
/// `TEST_RUNNER_DST_HARNESS_ZONE=<zone>` to run one zone with the process's own zone instead.
final class DSTHarnessTests: XCTestCase {

    private struct Plan: Decodable {
        struct Item: Decodable {
            let ratingKey: String
            let title: String
            let type: String
            let duration: Int
        }
        struct ChannelDef: Decodable {
            let id: Int
            let name: String
            let pool: [Item]
        }
        struct Day: Decodable {
            let date: String
            let noon: Double
        }
        struct Scenario: Decodable {
            let days: [Day]
            let samples: [Double]
        }
        let zones: [String: [String: Scenario]]
        let channels: [ChannelDef]
    }

    private func item(_ i: Plan.Item) -> PlexMediaItem {
        PlexMediaItem(
            id: i.ratingKey, title: i.title, artist: nil, episodeTitle: nil, seTag: nil, summary: "",
            year: 2000, originallyAvailableAt: nil, contentRating: nil, duration: i.duration,
            ratingKey: i.ratingKey, partKey: nil, container: "mp4", videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0,
            type: i.type == "episode" ? .episode : .movie, thumb: nil, art: nil, viewCount: 0,
            addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: i.type == "episode" ? .tv : .movie
        )
    }

    private func channel(_ c: Plan.ChannelDef) -> Channel {
        Channel(id: c.id, number: c.id, name: c.name, color: .blue, category: nil, rules: nil,
                timeRestrictions: nil, minItems: 1, itemPool: c.pool.map(item), enabled: true)
    }

    private func unix(_ d: Date) -> Int { Int(d.timeIntervalSince1970) }

    /// What the guide row draws one hour after `t`, through the same ProgramRowLayout the
    /// guide uses over the same two-hour window. nil is empty air in the row.
    private func guideAt(_ schedule: ChannelSchedule, _ t: Date) -> String? {
        let ws = ChannelScheduleBuilder.visibleWindowStart(at: t)
        let segments = ProgramRowLayout.segments(
            intervals: schedule.entries.map { ($0.startTime, $0.endTime) },
            windowStart: ws, windowDuration: 7200)
        let target = t.addingTimeInterval(3600).timeIntervalSince(ws)
        var x: Double = 0
        for segment in segments {
            let w = Double(segment.fraction) * 7200
            if target >= x - 0.001 && target < x + w - 0.001 {
                if case .block(let index, _) = segment { return schedule.entries[index].item.ratingKey }
                return nil
            }
            x += w
        }
        return nil
    }

    func testRunHarness() throws {
        let env = ProcessInfo.processInfo.environment
        guard let planPath = env["DST_HARNESS_PLAN"], let outPath = env["DST_HARNESS_OUT"] else {
            throw XCTSkip("set TEST_RUNNER_DST_HARNESS_PLAN and TEST_RUNNER_DST_HARNESS_OUT to run")
        }
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
        let onlyZone = env["DST_HARNESS_ZONE"]
        let useProcessTZ = env["DST_HARNESS_USE_PROCESS_TZ"] == "1"
        let originalDefault = NSTimeZone.default
        defer {
            NSTimeZone.default = originalDefault
            DailyManifestScheduler.invalidateMemo()
        }

        var zonesOut: [String: Any] = [:]
        for (zone, scenarios) in plan.zones.sorted(by: { $0.key < $1.key }) {
            if let onlyZone, onlyZone != zone { continue }
            let want = try XCTUnwrap(TimeZone(identifier: zone))
            if useProcessTZ {
                // TEST_RUNNER_TZ reached the test process.
                XCTAssertEqual(TimeZone.current.identifier, want.identifier)
            } else {
                // Measured 2026-10-20: this moves Calendar.current but NOT TimeZone.current,
                // which stays on the host's zone. The schedule code only reads Calendar.current.
                NSTimeZone.default = want
            }
            // The app passes no calendar, so this is the zone every day boundary below uses.
            XCTAssertEqual(Calendar.current.timeZone.identifier, want.identifier)

            var scenariosOut: [String: Any] = [:]
            for (change, p) in scenarios {
                let fp = "dst-harness-\(zone.replacingOccurrences(of: "/", with: "_"))-\(change)"
                DailyManifestStore.clearAll(credentialFingerprint: fp)
                let channels = plan.channels.map(channel)

                var days: [[String: Any]] = []
                for d in p.days {
                    let noon = Date(timeIntervalSince1970: d.noon)
                    var ch: [String: Any] = [:]
                    for c in channels {
                        ch[String(c.id)] = DailyManifestScheduler.blocks(for: c, at: noon, credentialFingerprint: fp)
                            .map { [$0.item.ratingKey, unix($0.startTime), unix($0.endTime)] as [Any] }
                    }
                    days.append([
                        "date": d.date,
                        "dayKey": DailyManifestStore.localDayKey(for: noon),
                        "dayStart": unix(DailyManifestStore.startOfLocalDay(for: noon)),
                        "dayNumber": DailyManifestStore.localDayNumber(for: noon),
                        "ch": ch,
                    ])
                }

                var samples: [[String: Any]] = []
                for t in p.samples {
                    let now = Date(timeIntervalSince1970: t)
                    var ch: [String: Any] = [:]
                    for c in channels {
                        guard let s = ChannelScheduleBuilder.buildSchedule(for: c, at: now, credentialFingerprint: fp) else {
                            ch[String(c.id)] = ["now": NSNull(), "next": NSNull(), "firstNow": NSNull(), "guide60": NSNull()]
                            continue
                        }
                        let np: Any = s.nowPlaying.map { [$0.item.ratingKey, unix($0.startTime), unix($0.endTime)] as [Any] } ?? NSNull()
                        ch[String(c.id)] = [
                            "now": np,
                            "next": s.upNext?.item.ratingKey ?? NSNull(),
                            // buildSchedule keeps the LAST entry covering now; upNext follows the FIRST.
                            "firstNow": s.entries.first { $0.isNowPlaying }?.item.ratingKey ?? NSNull(),
                            "guide60": guideAt(s, now) ?? NSNull(),
                        ] as [String: Any]
                    }
                    samples.append(["t": Int(t), "ch": ch])
                }
                scenariosOut[change] = ["days": days, "samples": samples]
                DailyManifestStore.clearAll(credentialFingerprint: fp)
            }
            zonesOut[zone] = scenariosOut
        }

        let out: [String: Any] = ["engine": "apple tv", "zones": zonesOut]
        let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
        print("[DSTHarness] wrote \(data.count) bytes to \(outPath)")
    }
}
