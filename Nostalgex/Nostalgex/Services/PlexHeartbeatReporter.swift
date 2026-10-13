import Foundation

/// Deliberately narrower than history sync: this transport has no position,
/// duration, or watched/scrobble operation.
protocol PlexHeartbeatTransport: Sendable {
    func reportHeartbeat(ratingKey: String, state: String, sessionID: String) async -> Bool
}

/// One ordered queue per server. Session identities belong to playback trackers,
/// so channel changes, disable and backgrounding close exactly what was opened.
/// There is no elapsed-time cutoff. Pending requests cannot overtake a final stop.
@MainActor
final class PlexHeartbeatReporter {
    private struct Session { let ratingKey: String; let id: String }
    private let transport: any PlexHeartbeatTransport
    private let predecessor: Task<Void, Never>?
    private let onFailure: @MainActor (String) -> Void
    private var accepting = true
    private var active: [String: Session] = [:]
    private var pending: Task<Void, Never>?
    private var sequence = 0

    init(transport: any PlexHeartbeatTransport, predecessor: Task<Void, Never>? = nil,
         onFailure: @escaping @MainActor (String) -> Void = { _ in }) {
        self.transport = transport; self.predecessor = predecessor; self.onFailure = onFailure
    }

    func report(ratingKey: String, state: String, sessionID: String) {
        guard accepting, ["playing", "paused", "buffering", "stopped"].contains(state) else { return }
        enqueue { [self] in
            guard accepting else { return }
            let session = Session(ratingKey: ratingKey, id: sessionID)
            // Retain the attempted identity even if a response is lost. Cleanup may
            // close this same session, but can never affect an unrelated client.
            if state != "stopped" { active[sessionID] = session }
            let acknowledged = await transport.reportHeartbeat(ratingKey: ratingKey, state: state, sessionID: sessionID)
            if acknowledged {
                if state == "stopped" { active.removeValue(forKey: sessionID) }
            } else {
                accepting = false
                let closed = await closeActiveSessions()
                onFailure(closed ? "Plex activity reporting stopped after a failed request. Playback continues."
                    : "Plex activity reporting stopped. Session cleanup could not be confirmed; playback continues.")
            }
        }
    }

    /// Decline queued/new updates immediately; let an in-flight request settle,
    /// then send position-free stopped reports. The stream itself is untouched.
    @discardableResult
    func disable() -> Task<Void, Never> {
        accepting = false
        return enqueue { [self] in
            if !(await closeActiveSessions()) {
                onFailure("Plex activity reporting is off. Session cleanup could not be confirmed; playback continues.")
            }
        }
    }

    func waitForPendingReports() async { await pending?.value }

    private func closeActiveSessions() async -> Bool {
        let sessions = active.values.sorted { $0.id < $1.id }
        active.removeAll() // One bounded attempt per identity; no retry loop.
        var succeeded = true
        for session in sessions {
            let acknowledged = await transport.reportHeartbeat(ratingKey: session.ratingKey, state: "stopped", sessionID: session.id)
            succeeded = succeeded && acknowledged
        }
        return succeeded
    }

    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pending
        sequence += 1
        let ticket = sequence
        // Strong capture keeps a channel's final stop alive after its tracker goes away.
        let task = Task { @MainActor [self] in
            await predecessor?.value
            await previous?.value
            await operation()
            if sequence == ticket { pending = nil }
        }
        pending = task
        return task
    }
}
