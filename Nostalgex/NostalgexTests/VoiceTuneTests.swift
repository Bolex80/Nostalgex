import XCTest
@testable import Nostalgex

/// Siri "tune to channel N": number lookup, the unknown-number message, and holding a
/// request that arrives while the lineup is still loading.
@MainActor
final class VoiceTuneTests: XCTestCase {

    private func channel(id: Int, number: Int, name: String = "CH") -> Channel {
        Channel(id: id, number: number, name: name, color: .blue, category: nil,
                rules: nil, timeRestrictions: nil, minItems: 0)
    }

    // MARK: - Pure lookup

    func testResolvesByGuideNumberNotByID() {
        // id and number differ for a few dozen channels; the spoken number is what the guide shows.
        let lineup = [channel(id: 122, number: 132, name: "SCREAM"), channel(id: 12, number: 14)]
        XCTAssertEqual(VoiceTune.resolve(number: 132, in: lineup, libraryReady: true), .tune(channelID: 122))
        XCTAssertEqual(VoiceTune.resolve(number: 14, in: lineup, libraryReady: true), .tune(channelID: 12))
    }

    func testIDThatIsNotAGuideNumberIsNotInLineup() {
        let lineup = [channel(id: 122, number: 132)]
        XCTAssertEqual(VoiceTune.resolve(number: 122, in: lineup, libraryReady: true), .notInLineup(number: 122))
    }

    func testUnknownNumberIsNotInLineup() {
        let lineup = [channel(id: 1, number: 2), channel(id: 3, number: 4)]
        XCTAssertEqual(VoiceTune.resolve(number: 12, in: lineup, libraryReady: true), .notInLineup(number: 12))
    }

    func testUnknownNumberMessage() {
        XCTAssertEqual(VoiceTune.notInLineupMessage(12), "No channel 12 in your lineup")
        XCTAssertEqual(VoiceTune.stillLoadingMessage, "Still loading your channels")
    }

    func testMessagesHaveNoEmDash() {
        XCTAssertFalse(VoiceTune.notInLineupMessage(7).contains("\u{2014}"))
        XCTAssertFalse(VoiceTune.stillLoadingMessage.contains("\u{2014}"))
    }

    func testNotReadyIsStillLoadingEvenWhenTheNumberExists() {
        let lineup = [channel(id: 12, number: 12)]
        XCTAssertEqual(VoiceTune.resolve(number: 12, in: lineup, libraryReady: false), .stillLoading)
    }

    func testEmptyLineupIsStillLoading() {
        XCTAssertEqual(VoiceTune.resolve(number: 12, in: [], libraryReady: true), .stillLoading)
    }

    // MARK: - AppState wiring (paths that do not start playback)

    func testTuneWhileLoadingIsQueuedWithANotice() {
        let state = AppState()
        state.didAttemptCredentialHydration = true
        state.isLoading = true

        state.handleVoiceRequest(.tune(channelNumber: 12))

        XCTAssertEqual(state.pendingVoiceRequest, .tune(channelNumber: 12))
        XCTAssertEqual(state.voiceNotice, "Still loading your channels")
        XCTAssertNil(state.currentChannel)
    }

    func testTuneBeforeKeychainReadIsQueued() {
        let state = AppState()
        state.didAttemptCredentialHydration = false

        state.handleVoiceRequest(.tune(channelNumber: 3))

        XCTAssertEqual(state.pendingVoiceRequest, .tune(channelNumber: 3))
    }

    func testPendingRequestIsNotDeliveredUntilReady() {
        let state = AppState()
        state.didAttemptCredentialHydration = true
        state.isLoading = true
        state.handleVoiceRequest(.tune(channelNumber: 12))

        state.deliverPendingVoiceRequestIfReady()
        XCTAssertEqual(state.pendingVoiceRequest, .tune(channelNumber: 12), "still loading, must stay queued")

        // Lineup arrives without channel 12: the queued request resolves to the banner.
        state.channels = [channel(id: 1, number: 1)]
        state.isLoading = false
        state.deliverPendingVoiceRequestIfReady()

        XCTAssertNil(state.pendingVoiceRequest)
        XCTAssertEqual(state.voiceNotice, "No channel 12 in your lineup")
        XCTAssertNil(state.currentChannel)
    }

    func testUnknownNumberShowsBannerAndDoesNotTune() {
        let state = AppState()
        state.didAttemptCredentialHydration = true
        state.channels = [channel(id: 1, number: 1)]

        state.handleVoiceRequest(.tune(channelNumber: 12))

        XCTAssertEqual(state.voiceNotice, "No channel 12 in your lineup")
        XCTAssertNil(state.pendingVoiceRequest)
        XCTAssertNil(state.currentChannel)
        XCTAssertFalse(state.isFullScreen)
    }

    func testOpenGuideLeavesFullScreenAndClearsAQueuedTune() {
        let state = AppState()
        state.didAttemptCredentialHydration = true
        state.isLoading = true
        state.handleVoiceRequest(.tune(channelNumber: 12))
        state.isFullScreen = true
        let before = state.guideRequestToken

        state.handleVoiceRequest(.openGuide)

        XCTAssertFalse(state.isFullScreen)
        XCTAssertNil(state.pendingVoiceRequest)
        XCTAssertEqual(state.guideRequestToken, before + 1)
    }

    // MARK: - Router

    func testRouterHoldsARequestUntilStateAttaches() {
        let router = VoiceIntentRouter()
        router.submit(.openGuide)
        XCTAssertEqual(router.pending, .openGuide)

        let state = AppState()
        state.isFullScreen = true
        router.attach(state)

        XCTAssertNil(router.pending)
        XCTAssertFalse(state.isFullScreen, "the held request must be delivered on attach")
    }
}
