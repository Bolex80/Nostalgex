import AppIntents
import Foundation

// MARK: - Siri / App Shortcuts
//
// Two intents, both of which open the app: tune a channel by number, and open the guide.
// No AppEntity on purpose: entities need tvOS 18.2 and the deployment target is 18.0, so
// channels are addressed by number, which works on every supported device.
//
// App Shortcut phrases may only interpolate AppEntity or AppEnum parameters. An Int
// cannot appear inside a phrase, so "Tune Nostalgex to channel 12" in one breath is not
// possible without an entity. The tune shortcut is spoken without the number and Siri
// asks "Which channel?" for it.

struct TuneChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Tune Channel"
    static let description = IntentDescription("Tunes Nostalgex to a channel number.")
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Channel",
        description: "The channel number to tune to.",
        inclusiveRange: (1, 9999),
        requestValueDialog: IntentDialog("Which channel?")
    )
    var channel: Int

    init() {}

    init(channel: Int) {
        self.channel = channel
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Tune to channel \(\.$channel)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceIntentRouter.shared.submit(.tune(channelNumber: channel))
        return .result()
    }
}

struct OpenGuideIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Guide"
    static let description = IntentDescription("Opens the Nostalgex channel guide.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceIntentRouter.shared.submit(.openGuide)
        return .result()
    }
}

/// "Watch Nostalgex": open the app and go full screen on whatever is on.
struct WatchNostalgexIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch Nostalgex"
    static let description = IntentDescription("Opens Nostalgex and plays the current channel.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceIntentRouter.shared.submit(.watch)
        return .result()
    }
}

struct NostalgexShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TuneChannelIntent(),
            phrases: [
                "Tune \(.applicationName) to a channel",
                "Change the channel on \(.applicationName)",
                "Change \(.applicationName) channel",
            ],
            shortTitle: "Tune Channel",
            systemImageName: "tv"
        )
        AppShortcut(
            intent: OpenGuideIntent(),
            phrases: [
                "Open the \(.applicationName) guide",
                "Show the \(.applicationName) guide",
            ],
            shortTitle: "Open Guide",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: WatchNostalgexIntent(),
            phrases: [
                "Watch \(.applicationName)",
                "Play \(.applicationName)",
            ],
            shortTitle: "Watch",
            systemImageName: "play.tv"
        )
    }
}

// MARK: - Request model (pure, testable)

enum VoiceRequest: Equatable {
    case tune(channelNumber: Int)
    case openGuide
    case watch
}

enum VoiceTuneResolution: Equatable {
    /// The number is in the lineup; tune the channel with this id.
    case tune(channelID: Int)
    /// Channels are not built yet; hold the request until they are.
    case stillLoading
    /// Channels exist but none carries this number.
    case notInLineup(number: Int)
}

enum VoiceTune {
    static let stillLoadingMessage = "Still loading your channels"

    static func notInLineupMessage(_ number: Int) -> String {
        "No channel \(number) in your lineup"
    }

    /// Looks the spoken number up in the visible lineup (`AppState.channels`, i.e. enabled
    /// bundles only). Matches `Channel.number`, which is what the guide shows, never `id`:
    /// the two differ for a few dozen channels.
    static func resolve(number: Int, in channels: [Channel], libraryReady: Bool) -> VoiceTuneResolution {
        guard libraryReady, !channels.isEmpty else { return .stillLoading }
        if let match = channels.first(where: { $0.number == number }) {
            return .tune(channelID: match.id)
        }
        return .notInLineup(number: number)
    }
}

// MARK: - Router

/// Hands intent requests to the live `AppState`. On a cold launch from Siri the intent can
/// run before `RootView` has appeared, so a request that arrives with no state attached is
/// held and delivered on `attach`.
@MainActor
final class VoiceIntentRouter {
    static let shared = VoiceIntentRouter()

    private weak var appState: AppState?
    private(set) var pending: VoiceRequest?

    func attach(_ state: AppState) {
        appState = state
        if let request = pending {
            pending = nil
            state.handleVoiceRequest(request)
        }
    }

    func submit(_ request: VoiceRequest) {
        print("[Plex90] SIRI: \(request)")
        if let state = appState {
            state.handleVoiceRequest(request)
        } else {
            pending = request
        }
    }
}
