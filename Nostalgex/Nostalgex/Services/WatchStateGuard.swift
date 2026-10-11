import Foundation

// Report Playback keeps Now Playing and real watches flowing to the user's server, but a
// program Nostalgex tuned past must never be left in Continue Watching (Plex), Resume
// (Jellyfin, Emby) or On Deck. The tracker captures what the server held for the item
// before the first report, and when the session ends it puts that state back. Measured
// against Plex, Emby 4.10 and Jellyfin 12.2 on 2026-10-11; the numbers are in
// docs/plex-session-reporting.md.
//
// The decision table (`WatchCleanupPlan`) is shared with the web tuner through
// scripts/watch-cleanup-golden.json, which both test suites read.

// MARK: - Transport

/// One HTTP round trip for playback reporting. Production goes through URLSession;
/// tests swap in a recorder so they can assert the exact calls without a server.
protocol ReportTransport: Sendable {
    /// Status code and body, or nil when the request never got an answer.
    func send(_ request: URLRequest) async -> (status: Int, body: Data)?
}

struct URLSessionReportTransport: ReportTransport {
    static let shared = URLSessionReportTransport()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    func send(_ request: URLRequest) async -> (status: Int, body: Data)? {
        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}

// MARK: - Ordering

/// Runs reporting calls one at a time, in the order they were queued, off the main actor.
///
/// Order is the whole point. Plex writes a resume point on every timeline report, so a
/// cleanup that lands before the last report is undone by it. Serialising also means
/// the next program's "what did the server hold before" read happens after the previous
/// program's cleanup, so back-to-back episodes of one show see the real row.
final class ReportQueue: @unchecked Sendable {
    static let shared = ReportQueue()

    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        tail = Task.detached {
            await previous?.value
            await operation()
        }
    }

    /// Waits for everything queued so far. Tests use it; the app never blocks on it.
    func drain() async {
        lock.lock()
        let last = tail
        lock.unlock()
        await last?.value
    }
}

// MARK: - Prior state and the cleanup decision

/// What the server held for an item before Nostalgex sent its first report.
struct PriorWatchState: Equatable, Sendable {
    /// Resume point in the server's own unit: Plex milliseconds, Jellyfin/Emby 100ns ticks.
    var resumePosition: Int
    var playCount: Int
    var played: Bool
    /// Jellyfin/Emby `LastPlayedDate`, sent back verbatim on restore. Nil on Plex.
    var lastPlayedDate: String? = nil
    /// Plex episodes: the show's rating key (`grandparentRatingKey`).
    var showKey: String? = nil
    /// Plex episodes: the show already had an entry in Continue Watching.
    var showInContinueWatching: Bool = false
}

enum WatchCleanupStep: Equatable, Sendable {
    /// Plex `/:/unscrobble`: back to never-watched. Only when it was never watched before.
    case unscrobble
    /// Plex `/:/progress`: put the user's own resume point back.
    case restoreResumePoint(Int)
    /// Plex `/actions/removeFromContinueWatching` for this item.
    case removeFromContinueWatching
    /// Plex: remove whatever Continue Watching entry the scrobble created for this show.
    case removeShowFromContinueWatching(String)
    /// Jellyfin/Emby `DELETE /Users/{id}/PlayedItems/{item}`: back to never-played.
    case markUnplayed
    /// Jellyfin/Emby `POST /Users/{id}/Items/{item}/UserData`.
    case setUserData(position: Int, playCount: Int?, played: Bool?, lastPlayedDate: String?)

    /// Compact form used by scripts/watch-cleanup-golden.json.
    var goldenDescription: String {
        switch self {
        case .unscrobble: return "unscrobble"
        case .restoreResumePoint(let ms): return "progress \(ms)"
        case .removeFromContinueWatching: return "removeFromContinueWatching"
        case .removeShowFromContinueWatching(let show): return "removeShowFromContinueWatching \(show)"
        case .markUnplayed: return "markUnplayed"
        case let .setUserData(position, playCount, played, lastPlayedDate):
            var parts = ["userData position=\(position)"]
            if let playCount { parts.append("playCount=\(playCount)") }
            if let played { parts.append("played=\(played)") }
            if let lastPlayedDate { parts.append("lastPlayedDate=\(lastPlayedDate)") }
            return parts.joined(separator: " ")
        }
    }
}

enum WatchCleanupPlan {
    /// Plex. `countedWatch` means this session scrobbled (the 15% / 75% gate passed).
    static func plex(prior: PriorWatchState?, countedWatch: Bool) -> [WatchCleanupStep] {
        if countedWatch {
            // The scrobble cleared the item's own resume point, and the tracker reports
            // position 0 after it. An episode scrobble also puts the NEXT episode in
            // Continue Watching; take that out unless the show was already there.
            // Unknown prior: leave it, rather than remove a row the user had.
            guard let prior, let show = prior.showKey, !prior.showInContinueWatching else { return [] }
            return [.removeShowFromContinueWatching(show)]
        }
        guard let prior else { return [.removeFromContinueWatching] }
        if prior.resumePosition > 0 { return [.restoreResumePoint(prior.resumePosition)] }
        if prior.playCount == 0 && !prior.played { return [.unscrobble] }
        return [.removeFromContinueWatching]
    }

    /// Jellyfin and Emby. Both bump PlayCount on the start report and store the stop
    /// position, so the restore writes the exact prior values back.
    static func mediaServer(prior: PriorWatchState?, countedWatch: Bool) -> [WatchCleanupStep] {
        guard let prior else {
            return [.setUserData(position: 0, playCount: nil, played: nil, lastPlayedDate: nil)]
        }
        if countedWatch {
            return [.setUserData(position: 0, playCount: prior.playCount + 1, played: true, lastPlayedDate: nil)]
        }
        if prior.resumePosition == 0 && prior.playCount == 0 && !prior.played {
            return [.markUnplayed]
        }
        return [.setUserData(position: prior.resumePosition, playCount: prior.playCount,
                             played: prior.played, lastPlayedDate: prior.lastPlayedDate)]
    }
}

// MARK: - Guards

protocol WatchStateGuarding: Sendable {
    /// Reads what the server holds for the item. Nil when the read failed.
    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState?
    /// Puts the item back the way the plan says. Best effort: one attempt per call.
    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async
}

struct PlexWatchStateGuard: WatchStateGuarding {
    static let libraryIdentifier = "com.plexapp.plugins.library"

    let serverURL: String
    let headers: [String: String]
    let transport: any ReportTransport

    func request(method: String, path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var components = URLComponents(string: "\(serverURL)\(path)") else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    /// `key` is the bare rating key. `/library/metadata/{rk}` is answered with 404.
    func scrobbleRequest(ratingKey: String) -> URLRequest? {
        request(method: "GET", path: "/:/scrobble", query: [
            .init(name: "key", value: ratingKey),
            .init(name: "identifier", value: Self.libraryIdentifier),
        ])
    }

    func request(for step: WatchCleanupStep, ratingKey: String) -> URLRequest? {
        switch step {
        case .unscrobble:
            return request(method: "GET", path: "/:/unscrobble", query: [
                .init(name: "key", value: ratingKey),
                .init(name: "identifier", value: Self.libraryIdentifier),
            ])
        case .restoreResumePoint(let ms):
            return request(method: "PUT", path: "/:/progress", query: [
                .init(name: "key", value: ratingKey),
                .init(name: "identifier", value: Self.libraryIdentifier),
                .init(name: "time", value: "\(ms)"),
                .init(name: "state", value: "stopped"),
            ])
        case .removeFromContinueWatching:
            return removeFromContinueWatchingRequest(ratingKey: ratingKey)
        case .removeShowFromContinueWatching, .markUnplayed, .setUserData:
            return nil
        }
    }

    func removeFromContinueWatchingRequest(ratingKey: String) -> URLRequest? {
        request(method: "PUT", path: "/actions/removeFromContinueWatching", query: [
            .init(name: "ratingKey", value: ratingKey),
        ])
    }

    private struct Container: Decodable {
        struct Inner: Decodable { let Metadata: [Entry]? }
        struct Entry: Decodable {
            let ratingKey: String?
            let type: String?
            let viewOffset: Int?
            let viewCount: Int?
            let grandparentRatingKey: String?
        }
        let MediaContainer: Inner
    }

    private func entries(_ req: URLRequest?) async -> [Container.Entry]? {
        guard let req, let (status, body) = await transport.send(req), (200...299).contains(status),
              let decoded = try? JSONDecoder().decode(Container.self, from: body) else { return nil }
        return decoded.MediaContainer.Metadata ?? []
    }

    private func continueWatching() async -> [Container.Entry]? {
        await entries(request(method: "GET", path: "/hubs/continueWatching/items", query: [
            .init(name: "count", value: "200"),
        ]))
    }

    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState? {
        guard let meta = await entries(request(method: "GET", path: "/library/metadata/\(item.ratingKey)"))?.first else {
            return nil
        }
        var prior = PriorWatchState(
            resumePosition: meta.viewOffset ?? 0,
            playCount: meta.viewCount ?? 0,
            played: (meta.viewCount ?? 0) > 0
        )
        if meta.type == "episode", let show = meta.grandparentRatingKey {
            prior.showKey = show
            // Unreadable row: assume the show was there, so we never remove a real entry.
            if let row = await continueWatching() {
                prior.showInContinueWatching = row.contains { $0.grandparentRatingKey == show || $0.ratingKey == show }
            } else {
                prior.showInContinueWatching = true
            }
        }
        return prior
    }

    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async {
        let rk = item.ratingKey
        for step in WatchCleanupPlan.plex(prior: prior, countedWatch: countedWatch) {
            if case .removeShowFromContinueWatching(let show) = step {
                let added = (await continueWatching() ?? [])
                    .filter { $0.grandparentRatingKey == show }
                    .compactMap(\.ratingKey)
                for key in added {
                    guard let req = removeFromContinueWatchingRequest(ratingKey: key) else { continue }
                    let status = await transport.send(req)?.status
                    print("[Tracker] cleanup rk=\(rk) removeFromContinueWatching next-up rk=\(key) HTTP \(status.map(String.init) ?? "failed")")
                }
                continue
            }
            guard let req = request(for: step, ratingKey: rk) else { continue }
            let status = await transport.send(req)?.status
            print("[Tracker] cleanup rk=\(rk) \(step.goldenDescription) HTTP \(status.map(String.init) ?? "failed")")
        }
    }
}

/// Jellyfin and Emby. Both answer the `/Users/{id}/...` routes (Jellyfin keeps them
/// for compatibility next to `/UserItems`), measured on Emby 4.10.1 and Jellyfin 12.2.
struct MediaServerWatchStateGuard: WatchStateGuarding {
    let serverURL: String
    let authorization: String
    let userId: String
    let transport: any ReportTransport

    private func path(_ suffix: String) -> String? {
        guard let user = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return "\(serverURL)/Users/\(user)\(suffix)"
    }

    private func itemPath(_ itemId: String) -> String? {
        itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private func request(method: String, url: String?, body: Data? = nil) -> URLRequest? {
        guard let url, let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    func request(for step: WatchCleanupStep, itemId: String) -> URLRequest? {
        guard let item = itemPath(itemId) else { return nil }
        switch step {
        case .markUnplayed:
            return request(method: "DELETE", url: path("/PlayedItems/\(item)"))
        case let .setUserData(position, playCount, played, lastPlayedDate):
            var body: [String: Any] = ["PlaybackPositionTicks": position]
            if let playCount { body["PlayCount"] = playCount }
            if let played { body["Played"] = played }
            if let lastPlayedDate { body["LastPlayedDate"] = lastPlayedDate }
            let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            return request(method: "POST", url: path("/Items/\(item)/UserData"), body: data)
        case .unscrobble, .restoreResumePoint, .removeFromContinueWatching, .removeShowFromContinueWatching:
            return nil
        }
    }

    private struct ItemResponse: Decodable {
        struct UserData: Decodable {
            let PlaybackPositionTicks: Int?
            let PlayCount: Int?
            let Played: Bool?
            let LastPlayedDate: String?
        }
        let UserData: UserData?
    }

    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState? {
        guard let id = itemPath(item.ratingKey),
              let req = request(method: "GET", url: path("/Items/\(id)")),
              let (status, body) = await transport.send(req), (200...299).contains(status),
              let decoded = try? JSONDecoder().decode(ItemResponse.self, from: body),
              let data = decoded.UserData else { return nil }
        return PriorWatchState(
            resumePosition: data.PlaybackPositionTicks ?? 0,
            playCount: data.PlayCount ?? 0,
            played: data.Played ?? false,
            lastPlayedDate: data.LastPlayedDate
        )
    }

    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async {
        for step in WatchCleanupPlan.mediaServer(prior: prior, countedWatch: countedWatch) {
            guard let req = request(for: step, itemId: item.ratingKey) else { continue }
            let status = await transport.send(req)?.status
            print("[Tracker] cleanup item=\(item.ratingKey) \(step.goldenDescription) HTTP \(status.map(String.init) ?? "failed")")
        }
    }
}

/// Holds the captured prior state. Only read and written from operations on one
/// `ReportQueue`, which runs them one at a time, so it needs no lock of its own.
final class PriorWatchStateBox: @unchecked Sendable {
    var prior: PriorWatchState?
}
