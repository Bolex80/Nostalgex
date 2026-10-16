import AVFoundation
import XCTest
@testable import Nostalgex

/// How a failed programme is reported. Real AppState, real AVPlayer; the backends hand
/// out files that are missing, which fail in milliseconds.
@MainActor
final class PlaybackFailureRunTests: XCTestCase {
    private var savedReportPreference: Any?

    override func setUp() {
        savedReportPreference = UserDefaults.standard.object(forKey: AppState.syncPlexActivityDefaultsKey)
        UserDefaults.standard.set(false, forKey: AppState.syncPlexActivityDefaultsKey)
    }

    override func tearDown() {
        if let savedReportPreference {
            UserDefaults.standard.set(savedReportPreference, forKey: AppState.syncPlexActivityDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppState.syncPlexActivityDefaultsKey)
        }
        Analytics.configure(with: NoOpAnalytics())
        UserDefaults.standard.removePersistentDomain(forName: "PlaybackFailureRunTests")
    }

    // MARK: - Fixtures

    private final class Recorder: AnalyticsService, @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [(at: Date, event: AnalyticsEvent)] = []
        var events: [(at: Date, event: AnalyticsEvent)] { lock.lock(); defer { lock.unlock() }; return _events }
        var errors: [AnalyticsEvent] { events.map(\.event).filter { $0.name == "playback.error" } }
        func configure() {}
        func track(_ event: AnalyticsEvent, contextParameters: [String: String]) {
            lock.lock(); _events.append((Date(), event)); lock.unlock()
        }
    }

    private struct NoCredentials: CredentialStoring {
        func save(key: String, value: String) -> Bool { true }
        func load(key: String) -> String? { nil }
        func delete(key: String) {}
    }

    /// `direct` and `transcode` decide which URLs each item gets; every call is counted so
    /// a test can tell whether the app is still asking the server for anything.
    private final class Backend: MediaBackend, @unchecked Sendable {
        let direct: @Sendable (PlexMediaItem) -> URL?
        let transcode: @Sendable (PlexMediaItem) -> URL?
        private let lock = NSLock()
        private var _requests = 0
        var requests: Int { lock.lock(); defer { lock.unlock() }; return _requests }
        init(direct: @escaping @Sendable (PlexMediaItem) -> URL?, transcode: @escaping @Sendable (PlexMediaItem) -> URL? = { _ in nil }) {
            self.direct = direct
            self.transcode = transcode
        }
        let serverID = "synthetic"
        let authHeaders: [String: String] = [:]
        func testConnection() async throws -> String { "synthetic" }
        func loadLibrary(progress: LoadProgress?) async throws -> [PlexMediaItem] { [] }
        func loadSections() async throws -> [PlexSection] { [] }
        func loadCollections(sectionKey: String) async throws -> [PlexCollection] { [] }
        func loadCollectionItems(collectionKey: String) async throws -> [String] { [] }
        func buildDirectPlayURL(for item: PlexMediaItem) -> URL? {
            lock.lock(); _requests += 1; lock.unlock()
            return direct(item)
        }
        func buildTranscodeURL(for item: PlexMediaItem) -> URL? { transcode(item) }
        func thumbnailURL(for item: PlexMediaItem, width: Int) -> URL? { nil }
    }

    static let missingFile = URL(fileURLWithPath: "/nostalgex-missing.mp4")
    static let missingPlaylist = URL(fileURLWithPath: "/nostalgex-missing.m3u8")

    private func item(_ key: String) -> PlexMediaItem {
        PlexMediaItem(id: key, title: "Synthetic \(key)", artist: nil, episodeTitle: nil, seTag: nil,
                      summary: "", year: nil, originallyAvailableAt: nil, contentRating: nil,
                      duration: 30, ratingKey: key, partKey: nil, container: "mp4", videoCodec: "h264",
                      audioCodec: "aac", videoProfile: nil, bitrate: nil, genres: [], rating: 0,
                      userRating: 0, type: .movie, thumb: nil, art: nil, viewCount: 0, addedAt: 0,
                      studio: nil, tmdbID: nil, imdbID: nil, librarySource: .movie, serverID: "synthetic")
    }

    private func channel(_ id: Int, keys: [String]) -> Channel {
        Channel(id: id, number: id, name: "SYNTHETIC \(id)", color: .blue, category: "nostalgex",
                rules: ChannelRules(), timeRestrictions: nil, minItems: 0, itemPool: keys.map(item))
    }

    private func makeState(_ backend: Backend, channels: [Channel]) -> AppState {
        let defaults = UserDefaults(suiteName: "PlaybackFailureRunTests")!
        let sync = PreferenceSync(cloud: InMemoryKeyValueStore(), defaults: defaults,
                                  observeNotifications: false, keys: PreferenceSync.syncedKeys)
        let state = AppState(credentialStore: NoCredentials(), preferenceSync: sync)
        state.backendOverride = { _ in backend }
        state.allChannels = channels
        state.channels = channels
        return state
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isShowingFailure(_ state: AppState) -> Bool {
        if case .error = state.playbackState { return true }
        return false
    }

    private func tearDown(_ state: AppState) {
        state.invalidatePlaybackAttempt()
        state.player?.pause()
        state.player = nil
    }

    // MARK: - One report per failure

    /// Direct play fails and there is no server stream: the player retries once, the
    /// retry fails, the card shows. That is one failure and one `playback.error`.
    func testRetryPathReportsOneErrorPerFailure() async {
        let backend = Backend(direct: { _ in Self.missingFile })
        let ch = channel(1, keys: ["a", "b", "c"])
        let state = makeState(backend, channels: [ch])
        let recorder = Recorder()
        Analytics.configure(with: recorder, gate: nil)
        state.selectChannel(ch)
        await waitUntil(5) { isShowingFailure(state) }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(isShowingFailure(state))
        XCTAssertEqual(recorder.errors.count, 1, "\(recorder.errors.map { $0.parameters["code"] ?? "" })")
        tearDown(state)
    }

    /// Direct play fails, the server stream is tried and fails too: one fallback signal,
    /// one `playback.error`.
    func testTranscodeFailedPathReportsOneErrorPerFailure() async {
        let backend = Backend(direct: { _ in Self.missingFile }, transcode: { _ in Self.missingPlaylist })
        let ch = channel(2, keys: ["a", "b", "c"])
        let state = makeState(backend, channels: [ch])
        let recorder = Recorder()
        Analytics.configure(with: recorder, gate: nil)
        state.selectChannel(ch)
        await waitUntil(5) { isShowingFailure(state) }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(isShowingFailure(state))
        XCTAssertEqual(recorder.events.filter { $0.event.name == "playback.transcode_fallback" }.count, 1)
        XCTAssertEqual(recorder.errors.count, 1, "\(recorder.errors.map { $0.parameters["code"] ?? "" })")
        tearDown(state)
    }
}
