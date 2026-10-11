import XCTest
@testable import Nostalgex

private actor HeartbeatTransportFixture: PlexHeartbeatTransport {
    struct Call: Equatable { let item: String; let state: String; let session: String }
    private var calls: [Call] = []
    private var holdFirst = false
    private var started = false
    private var gate: CheckedContinuation<Void, Never>?
    private var replies: [Bool]
    init(replies: [Bool] = [], holdFirst: Bool = false) { self.replies = replies; self.holdFirst = holdFirst }
    func reportHeartbeat(ratingKey: String, state: String, sessionID: String) async -> Bool {
        started = true
        if holdFirst { holdFirst = false; await withCheckedContinuation { gate = $0 } }
        calls.append(Call(item: ratingKey, state: state, session: sessionID))
        return replies.isEmpty ? true : replies.removeFirst()
    }
    func waitUntilStarted() async { while !started { await Task.yield() } }
    func release() { gate?.resume(); gate = nil }
    func snapshot() -> [Call] { calls }
}

@MainActor
final class PlexHeartbeatReporterTests: XCTestCase {
    private func item() -> PlexMediaItem {
        PlexMediaItem(id: "1", title: "Test", artist: nil, episodeTitle: nil, seTag: nil,
                      summary: "", year: 2020, originallyAvailableAt: nil, contentRating: nil,
                      duration: 1, ratingKey: "1", partKey: "/library/parts/1/file.mp4",
                      container: "mp4", videoCodec: "h264", audioCodec: "aac", videoProfile: nil,
                      bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
                      thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil,
                      tmdbID: nil, imdbID: nil, librarySource: .movie)
    }
    func testHeartbeatPreferenceIsSeparateExclusiveAndPlexOnly() {
        let defaults = UserDefaults.standard
        let keys = [AppState.syncPlexActivityDefaultsKey, AppState.plexHeartbeatOnlyDefaultsKey]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: AppState.plexHeartbeatOnlyDefaultsKey)
        let state = AppState()
        XCTAssertFalse(state.plexHeartbeatOnly)
        state.syncPlexActivity = true; state.plexHeartbeatOnly = true
        XCTAssertFalse(state.syncPlexActivity); XCTAssertTrue(state.heartbeatReportingActive)
        XCTAssertEqual(defaults.bool(forKey: AppState.plexHeartbeatOnlyDefaultsKey), true)
        state.isDemoMode = true; XCTAssertFalse(state.heartbeatReportingActive)
        state.isDemoMode = false; state.backendKind = .jellyfin; XCTAssertFalse(state.heartbeatReportingActive)
        state.backendKind = .plex; state.syncPlexActivity = true
        XCTAssertFalse(state.plexHeartbeatOnly)
        XCTAssertEqual(AppState.syncPlexActivityDefaultsKey, "nostalgex_sync_plex_activity", "Preserve the existing history preference")
    }

    func testTrackerBackgroundForegroundAndDroppedOwnerCloseExactSession() async {
        let api = HeartbeatTransportFixture(); let reporter = PlexHeartbeatReporter(transport: api)
        var tracker: PlaybackTracker? = PlaybackTracker(item: item(), seekOffset: 0, plexAPI: nil, heartbeatReporter: reporter)
        tracker?.onHeartbeatPlaybackState("playing")
        tracker?.onBackground(); tracker?.onBackground(); tracker?.onTimelineTick()
        await reporter.waitForPendingReports()
        let background = await api.snapshot()
        XCTAssertEqual(background.map(\.state), ["playing", "stopped"])
        tracker?.onForeground(); tracker?.onHeartbeatPlaybackState("playing")
        tracker?.stop(); tracker = nil
        await reporter.waitForPendingReports(); await reporter.disable().value
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped", "buffering", "playing", "stopped"])
        XCTAssertEqual(Set(calls.map(\.session)).count, 1)
    }

    func testDisableLeavesTrackerUsableAndReactivationGetsFreshIdentity() async {
        let api = HeartbeatTransportFixture(); let first = PlexHeartbeatReporter(transport: api)
        let tracker = PlaybackTracker(item: item(), seekOffset: 0, plexAPI: nil, heartbeatReporter: first)
        tracker.onHeartbeatPlaybackState("playing")
        await first.waitForPendingReports()
        let cleanup = first.disable()
        tracker.setReporters(plexAPI: nil, watchReporter: nil, heartbeatReporter: nil)
        tracker.onHeartbeatPlaybackState("paused")
        let second = PlexHeartbeatReporter(transport: api, predecessor: cleanup)
        tracker.setReporters(plexAPI: nil, watchReporter: nil, heartbeatReporter: second)
        await second.waitForPendingReports(); tracker.stop(); await second.waitForPendingReports()
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped", "paused", "stopped"])
        XCTAssertNotEqual(calls.first?.session, calls.last?.session)
        XCTAssertFalse(tracker.scrobbled)
    }

    func testActualRequestOmitsProgressAndUsesExactSession() throws {
        let api = PlexAPIService(serverURL: "https://synthetic.invalid", token: "synthetic-token")
        for state in ["playing", "paused", "buffering", "stopped"] {
            let request = try XCTUnwrap(api.heartbeatRequest(ratingKey: "42", state: state, sessionID: "exact-session"))
            let parts = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(parts.path, "/:/timeline")
            XCTAssertEqual(Set(parts.queryItems!.map(\.name)), ["ratingKey", "key", "state"])
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "key" })?.value, "/library/metadata/42")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier"), "exact-session")
            XCTAssertFalse(request.url!.absoluteString.contains("synthetic-token"))
        }
        XCTAssertNil(api.heartbeatRequest(ratingKey: "../other", state: "playing", sessionID: "x"))
        XCTAssertNil(api.heartbeatRequest(ratingKey: "42", state: "watched", sessionID: "x"))
    }

    func testChannelChangePreservesOrderedSessionStops() async {
        let api = HeartbeatTransportFixture(holdFirst: true)
        let reporter = PlexHeartbeatReporter(transport: api)
        reporter.report(ratingKey: "42", state: "playing", sessionID: "first")
        await api.waitUntilStarted()
        reporter.report(ratingKey: "42", state: "stopped", sessionID: "first")
        reporter.report(ratingKey: "43", state: "playing", sessionID: "second")
        await api.release(); await reporter.waitForPendingReports()
        await reporter.disable().value
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped", "playing", "stopped"])
        XCTAssertEqual(calls.map(\.session), ["first", "first", "second", "second"])
    }

    func testDisableWaitsForInFlightThenClosesOnlyItsSession() async {
        let api = HeartbeatTransportFixture(holdFirst: true)
        let reporter = PlexHeartbeatReporter(transport: api)
        reporter.report(ratingKey: "42", state: "playing", sessionID: "first")
        await api.waitUntilStarted()
        reporter.report(ratingKey: "43", state: "playing", sessionID: "queued")
        let cleanup = reporter.disable()
        reporter.report(ratingKey: "44", state: "playing", sessionID: "later")
        await api.release(); await cleanup.value; await reporter.disable().value
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped"])
        XCTAssertEqual(calls.map(\.session), ["first", "first"])
    }

    func testBackgroundStopThenDisableDoesNotRepeatStop() async {
        let api = HeartbeatTransportFixture(); let reporter = PlexHeartbeatReporter(transport: api)
        reporter.report(ratingKey: "42", state: "playing", sessionID: "same")
        reporter.report(ratingKey: "42", state: "stopped", sessionID: "same")
        await reporter.waitForPendingReports(); await reporter.disable().value
        let calls = await api.snapshot(); XCTAssertEqual(calls.map(\.state), ["playing", "stopped"])
    }

    func testOneHundredPulsesHaveNoArtificialCountCutoff() async {
        let api = HeartbeatTransportFixture(); let reporter = PlexHeartbeatReporter(transport: api)
        for _ in 0..<100 { reporter.report(ratingKey: "42", state: "playing", sessionID: "same") }
        await reporter.waitForPendingReports()
        let before = await api.snapshot(); XCTAssertEqual(before.count, 100)
        XCTAssertTrue(before.allSatisfy { $0.state == "playing" })
        await reporter.disable().value
        let after = await api.snapshot(); XCTAssertEqual(after.last?.state, "stopped")
    }

    func testFailureStopsUpdatesAndAttemptsBoundedCleanup() async {
        let api = HeartbeatTransportFixture(replies: [false, false]); var notice: String?
        let reporter = PlexHeartbeatReporter(transport: api, onFailure: { notice = $0 })
        reporter.report(ratingKey: "42", state: "playing", sessionID: "same")
        reporter.report(ratingKey: "43", state: "playing", sessionID: "queued")
        await reporter.waitForPendingReports()
        reporter.report(ratingKey: "44", state: "playing", sessionID: "later")
        await reporter.waitForPendingReports(); await reporter.disable().value
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped"])
        XCTAssertTrue(calls.allSatisfy { $0.session == "same" })
        XCTAssertTrue(notice?.contains("could not be confirmed") == true)
    }

    func testReactivationWaitsForEarlierCleanup() async {
        let api = HeartbeatTransportFixture(holdFirst: true)
        let old = PlexHeartbeatReporter(transport: api)
        old.report(ratingKey: "42", state: "playing", sessionID: "old")
        await api.waitUntilStarted()
        let cleanup = old.disable()
        let next = PlexHeartbeatReporter(transport: api, predecessor: cleanup)
        next.report(ratingKey: "42", state: "playing", sessionID: "new")
        await api.release(); await next.waitForPendingReports(); await next.disable().value
        let calls = await api.snapshot()
        XCTAssertEqual(calls.map(\.state), ["playing", "stopped", "playing", "stopped"])
        XCTAssertEqual(calls.map(\.session), ["old", "old", "new", "new"])
    }

    func testQueueRetainsFinalStopAfterOwnerReleasesReporter() async {
        let api = HeartbeatTransportFixture()
        var reporter: PlexHeartbeatReporter? = PlexHeartbeatReporter(transport: api)
        reporter?.report(ratingKey: "42", state: "playing", sessionID: "same")
        await reporter?.waitForPendingReports()
        let cleanup = reporter!.disable(); weak var released = reporter; reporter = nil
        await cleanup.value
        let calls = await api.snapshot(); XCTAssertEqual(calls.map(\.state), ["playing", "stopped"])
        XCTAssertNil(released)
    }
}
