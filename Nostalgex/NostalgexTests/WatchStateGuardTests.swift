import XCTest
@testable import Nostalgex

/// Report Playback must never leave a program in Continue Watching. These drive the real
/// `PlaybackTracker` and `PlexAPIService` request builders through a recording transport
/// and a fake clock, so the exact calls a two-minute surf makes are checked in
/// milliseconds. The live-server version of the same checks is in
/// docs/plex-session-reporting.md.
@MainActor
final class WatchStateGuardTests: XCTestCase {

    // MARK: - Fakes

    final class RecordingTransport: ReportTransport, @unchecked Sendable {
        struct Call {
            let method: String
            let path: String
            let query: [String: String]
            let body: [String: Any]?
        }

        private let lock = NSLock()
        private var recorded: [Call] = []
        /// "METHOD /path" -> responses served in order; the last one repeats.
        private var scripted: [String: [(Int, String)]] = [:]

        func respond(_ route: String, _ status: Int, _ body: String) {
            lock.lock(); defer { lock.unlock() }
            scripted[route, default: []].append((status, body))
        }

        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func send(_ request: URLRequest) async -> (status: Int, body: Data)? {
            guard let url = request.url,
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            var query: [String: String] = [:]
            comps.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let method = request.httpMethod ?? "GET"
            lock.lock(); defer { lock.unlock() }
            recorded.append(Call(method: method, path: comps.path, query: query, body: body))
            let route = "\(method) \(comps.path)"
            guard var queue = scripted[route], !queue.isEmpty else { return (200, Data()) }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            scripted[route] = queue
            return (next.0, Data(next.1.utf8))
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(rk: String, minutes: Int, type: MediaType) -> PlexMediaItem {
        PlexMediaItem(
            id: rk, title: "Item \(rk)", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 1999, originallyAvailableAt: nil, contentRating: nil,
            duration: minutes, ratingKey: rk, partKey: "/library/parts/\(rk)/file.mkv",
            container: "mkv", videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: type, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: type == .episode ? .tv : .movie
        )
    }

    private func tracker(_ item: PlexMediaItem, _ transport: RecordingTransport, _ queue: ReportQueue) -> PlaybackTracker {
        let api = PlexAPIService(serverURL: "http://plex.test", token: "tok", serverID: "srv", reportTransport: transport)
        return PlaybackTracker(item: item, seekOffset: 0, plexAPI: api, queue: queue, now: { [unowned self] in self.clock })
    }

    private func metadata(rk: String, type: String, viewOffset: Int? = nil, viewCount: Int? = nil, show: String? = nil) -> String {
        var fields = ["\"ratingKey\":\"\(rk)\"", "\"type\":\"\(type)\""]
        if let viewOffset { fields.append("\"viewOffset\":\(viewOffset)") }
        if let viewCount { fields.append("\"viewCount\":\(viewCount)") }
        if let show { fields.append("\"grandparentRatingKey\":\"\(show)\"") }
        return "{\"MediaContainer\":{\"Metadata\":[{\(fields.joined(separator: ","))}]}}"
    }

    private func continueWatching(_ entries: [(rk: String, show: String?)]) -> String {
        let items = entries.map { e -> String in
            e.show.map { "{\"ratingKey\":\"\(e.rk)\",\"type\":\"episode\",\"grandparentRatingKey\":\"\($0)\"}" }
                ?? "{\"ratingKey\":\"\(e.rk)\",\"type\":\"movie\"}"
        }
        return "{\"MediaContainer\":{\"Metadata\":[\(items.joined(separator: ","))]}}"
    }

    /// Plays `seconds` of the program in 10 second pulses, like the timer does.
    private func play(_ tracker: PlaybackTracker, seconds: Int) {
        tracker.onPlaybackReady()
        for _ in 0..<(seconds / 10) {
            clock += 10
            tracker.timelineTickForTesting()
        }
    }

    private func cleanupCalls(_ calls: [RecordingTransport.Call]) -> [RecordingTransport.Call] {
        calls.filter { ["/:/unscrobble", "/:/progress", "/actions/removeFromContinueWatching"].contains($0.path) }
    }

    // MARK: - Plex, through the tracker

    func testSurfTwoMinutesOnUnwatchedFilm_reportsTimelineThenUnscrobblesOnce() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/41418", 200, metadata(rk: "41418", type: "movie"))
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 120)
        t.stop()
        await queue.drain()

        let calls = transport.calls
        XCTAssertEqual(calls.first?.path, "/library/metadata/41418", "prior state is read before the first report")
        let timelines = calls.filter { $0.path == "/:/timeline" }
        XCTAssertEqual(timelines.count, 14, "ready + 12 pulses + stopped")
        XCTAssertEqual(timelines.last?.query["state"], "stopped")
        XCTAssertEqual(timelines.last?.query["time"], "120000", "Now Playing sees the real position")
        XCTAssertFalse(calls.contains { $0.path == "/:/scrobble" })
        let cleanup = cleanupCalls(calls)
        XCTAssertEqual(cleanup.map(\.path), ["/:/unscrobble"])
        XCTAssertEqual(cleanup.first?.query["key"], "41418")
        XCTAssertEqual(cleanup.first?.query["identifier"], "com.plexapp.plugins.library")
        XCTAssertEqual(calls.last?.path, "/:/unscrobble", "cleanup lands after the last report")
    }

    func testSurfFilmWithPriorResumePoint_restoresThatResumePoint() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/500", 200, metadata(rk: "500", type: "movie", viewOffset: 600_000))
        let queue = ReportQueue()
        let t = tracker(item(rk: "500", minutes: 100, type: .movie), transport, queue)

        play(t, seconds: 120)
        t.stop()
        await queue.drain()

        let cleanup = cleanupCalls(transport.calls)
        XCTAssertEqual(cleanup.count, 1)
        XCTAssertEqual(cleanup.first?.method, "PUT")
        XCTAssertEqual(cleanup.first?.path, "/:/progress")
        XCTAssertEqual(cleanup.first?.query["time"], "600000")
        XCTAssertEqual(cleanup.first?.query["state"], "stopped")
        XCTAssertEqual(cleanup.first?.query["key"], "500")
    }

    func testSurfWatchedFilm_onlyRemovesFromContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/600", 200, metadata(rk: "600", type: "movie", viewCount: 2))
        let queue = ReportQueue()
        let t = tracker(item(rk: "600", minutes: 100, type: .movie), transport, queue)

        play(t, seconds: 120)
        t.stop()
        await queue.drain()

        let cleanup = cleanupCalls(transport.calls)
        XCTAssertEqual(cleanup.map(\.path), ["/actions/removeFromContinueWatching"], "never unscrobble a watched film")
        XCTAssertEqual(cleanup.first?.method, "PUT")
        XCTAssertEqual(cleanup.first?.query["ratingKey"], "600")
    }

    func testQualifyingEpisodeWatch_scrobblesAndRemovesNextUpWhenShowWasNotInContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/48281", 200, metadata(rk: "48281", type: "episode", show: "48279"))
        // Before tune-in: someone else's show in the row. After the scrobble: Plex added the next episode.
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("900", "777")]))
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("900", "777"), ("48283", "48279")]))
        let queue = ReportQueue()
        let t = tracker(item(rk: "48281", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        XCTAssertTrue(t.scrobbled)
        t.stop()
        await queue.drain()

        let calls = transport.calls
        let scrobbles = calls.filter { $0.path == "/:/scrobble" }
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.query["key"], "48281", "bare rating key; /library/metadata/{rk} is a 404")
        let scrobbleIndex = calls.firstIndex { $0.path == "/:/scrobble" }!
        let laterTimelines = calls[scrobbleIndex...].filter { $0.path == "/:/timeline" }
        XCTAssertFalse(laterTimelines.isEmpty)
        XCTAssertTrue(laterTimelines.allSatisfy { $0.query["time"] == "0" }, "no fresh resume point on a watched item")
        let cleanup = cleanupCalls(calls)
        XCTAssertEqual(cleanup.map(\.path), ["/actions/removeFromContinueWatching"])
        XCTAssertEqual(cleanup.first?.query["ratingKey"], "48283", "only the next-up entry the scrobble created")
    }

    func testQualifyingEpisodeWatch_leavesNextUpWhenShowWasAlreadyInContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/48281", 200, metadata(rk: "48281", type: "episode", show: "48279"))
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("48280", "48279")]))
        let queue = ReportQueue()
        let t = tracker(item(rk: "48281", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        t.stop()
        await queue.drain()

        XCTAssertTrue(cleanupCalls(transport.calls).isEmpty)
    }

    func testMetadataFetchFailure_onlyRemovesFromContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/700", 500, "")
        let queue = ReportQueue()
        let t = tracker(item(rk: "700", minutes: 100, type: .movie), transport, queue)

        play(t, seconds: 120)
        t.stop()
        await queue.drain()

        let cleanup = cleanupCalls(transport.calls)
        XCTAssertEqual(cleanup.map(\.path), ["/actions/removeFromContinueWatching"], "never unscrobble on a guess")
        XCTAssertEqual(cleanup.first?.query["ratingKey"], "700")
    }

    func testTunedPastBeforePlaybackStarted_sendsNothing() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "800", minutes: 100, type: .movie), transport, queue)

        t.stop()
        await queue.drain()

        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testTurningReportingOffMidProgram_stillRestoresTheItem() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/41418", 200, metadata(rk: "41418", type: "movie"))
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 30)
        t.abandon()
        await queue.drain()

        XCTAssertEqual(cleanupCalls(transport.calls).map(\.path), ["/:/unscrobble"])
        XCTAssertFalse(transport.calls.contains { $0.path == "/:/timeline" && $0.query["state"] == "stopped" })
    }

    func testBackgrounding_restoresImmediately() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/41418", 200, metadata(rk: "41418", type: "movie"))
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 30)
        t.onBackground()
        await queue.drain()
        XCTAssertEqual(transport.calls.last?.path, "/:/unscrobble")
        t.stop()
    }

    // MARK: - Jellyfin / Emby guard

    private func mediaServerGuard(_ transport: RecordingTransport) -> MediaServerWatchStateGuard {
        MediaServerWatchStateGuard(serverURL: "http://jf.test", authorization: "MediaBrowser Token=\"t\"",
                                   userId: "u1", transport: transport)
    }

    func testMediaServerCapture_readsUserData() async {
        let transport = RecordingTransport()
        transport.respond("GET /Users/u1/Items/i1", 200,
                          "{\"UserData\":{\"PlaybackPositionTicks\":6000000000,\"PlayCount\":2,\"Played\":true,\"LastPlayedDate\":\"2026-10-11T18:03:04.0000000Z\"}}")
        let prior = await mediaServerGuard(transport).captureWatchState(for: item(rk: "i1", minutes: 90, type: .movie))
        XCTAssertEqual(prior, PriorWatchState(resumePosition: 6_000_000_000, playCount: 2, played: true,
                                              lastPlayedDate: "2026-10-11T18:03:04.0000000Z"))
    }

    func testMediaServerRestore_untouchedItemIsMarkedUnplayed() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 0, playCount: 0, played: false), countedWatch: false)
        XCTAssertEqual(transport.calls.map { "\($0.method) \($0.path)" }, ["DELETE /Users/u1/PlayedItems/i1"])
    }

    func testMediaServerRestore_writesPriorUserDataBack() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 6_000_000_000, playCount: 1, played: false, lastPlayedDate: "2026-10-01T00:00:00Z"),
            countedWatch: false)
        let call = transport.calls.first
        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(call?.method, "POST")
        XCTAssertEqual(call?.path, "/Users/u1/Items/i1/UserData")
        XCTAssertEqual(call?.body?["PlaybackPositionTicks"] as? Int, 6_000_000_000)
        XCTAssertEqual(call?.body?["PlayCount"] as? Int, 1)
        XCTAssertEqual(call?.body?["Played"] as? Bool, false)
        XCTAssertEqual(call?.body?["LastPlayedDate"] as? String, "2026-10-01T00:00:00Z")
    }

    func testMediaServerRestore_countedWatchIsPlayedOnceWithNoResumePoint() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 0, playCount: 0, played: false), countedWatch: true)
        let body = transport.calls.first?.body
        XCTAssertEqual(body?["PlaybackPositionTicks"] as? Int, 0)
        XCTAssertEqual(body?["PlayCount"] as? Int, 1)
        XCTAssertEqual(body?["Played"] as? Bool, true)
    }

    // MARK: - Shared decision table (web tuner reads the same file)

    private struct Golden: Decodable {
        struct Prior: Decodable {
            let resumePosition: Int
            let playCount: Int
            let played: Bool
            let lastPlayedDate: String?
            let showKey: String?
            let showInContinueWatching: Bool
        }
        struct Case: Decodable {
            let name: String
            let backend: String
            let counted: Bool
            let prior: Prior?
            let steps: [String]
        }
        let cases: [Case]
    }

    func testCleanupPlanMatchesSharedGoldenVectors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/watch-cleanup-golden.json"))
        let golden = try JSONDecoder().decode(Golden.self, from: data)
        XCTAssertGreaterThan(golden.cases.count, 10)
        for c in golden.cases {
            let prior = c.prior.map {
                PriorWatchState(resumePosition: $0.resumePosition, playCount: $0.playCount, played: $0.played,
                                lastPlayedDate: $0.lastPlayedDate, showKey: $0.showKey,
                                showInContinueWatching: $0.showInContinueWatching)
            }
            let steps = c.backend == "plex"
                ? WatchCleanupPlan.plex(prior: prior, countedWatch: c.counted)
                : WatchCleanupPlan.mediaServer(prior: prior, countedWatch: c.counted)
            XCTAssertEqual(steps.map(\.goldenDescription), c.steps, c.name)
        }
    }
}
