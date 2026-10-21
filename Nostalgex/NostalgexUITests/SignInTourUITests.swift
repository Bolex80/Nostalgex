import XCTest

/// Walks the connect screens with the remote, counting presses from a fresh launch to a
/// signed-in library, and saves a screenshot of each screen with focus on different
/// controls. Needs real servers, so it only runs when asked:
///
///   TEST_RUNNER_NOSTALGEX_SIGNIN_TOUR=1 TEST_RUNNER_NOSTALGEX_SHOTS_DIR=/some/dir \
///   xcodebuild test -scheme NostalgexUITests -only-testing:NostalgexUITests/SignInTourUITests/<test>
///
/// Each test wants a fresh install and an empty keychain (`simctl erase` between runs).
/// Servers and accounts come from TEST_RUNNER_ variables (see SignInTourSupport):
/// - Plex: NX_PLEX_TOKEN and NX_PLEX_CLIENT for an account whose code the tour links.
/// - Jellyfin: one Jellyfin answering discovery with Quick Connect on; NX_JF_BASE,
///   NX_JF_KEY (an API key) and NX_JF_USERID approve the code; NX_JF_USER / NX_JF_PASS.
/// - Emby: NX_EMBY_ADDR, NX_EMBY_USER, NX_EMBY_PASS, plus a user with no password called
///   nxnopass for the one-press case. testE needs one Emby answering discovery and stops
///   before signing in, so it can run against a server nobody has the password for.
final class SignInTourUITests: SignInTourCase {

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["NOSTALGEX_SIGNIN_TOUR"] == "1" else {
            throw XCTSkip("Sign-in tour. Set TEST_RUNNER_NOSTALGEX_SIGNIN_TOUR=1 to run.")
        }
    }

    /// Moves focus around for screenshots without counting those presses.
    private func gallery(_ steps: [(XCUIRemote.Button, String)]) {
        let counted = presses
        for (button, name) in steps {
            press(button)
            if !name.isEmpty { shot(name) }
        }
        presses = counted
        note("(gallery presses above are not counted)")
    }

    private func launchFresh() {
        launch()
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].waitForExistence(timeout: 40))
        sleep(2)
        note("start, focus: \(focusedDescription())")
    }

    private func waitForText(_ text: String, timeout: TimeInterval = 30) -> Bool {
        app.staticTexts[text].waitForExistence(timeout: timeout)
    }

    func testA_Picker() {
        launchFresh()
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].hasFocus, "a fresh launch should start on CONNECT TO PLEX")
        // VERSION stays; the keychain and storage diagnostics line is gone from every build.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'VERSION '")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'DEFAULTS' AND label CONTAINS 'MARKER'")).firstMatch.exists,
                       "the diagnostics line should not be on the connect screen")
        shot("after-01-picker-focus-plex")
        gallery([(.down, "after-02-picker-focus-jellyfin"), (.down, "after-03-picker-focus-emby"),
                 (.down, "after-04-picker-focus-demo")])
        writeLog("after-A-picker")
    }

    func testB_PlexToGuide() {
        launchFresh()
        press(.select, "CONNECT TO PLEX")
        guard let code = codeOnScreen(length: 4, timeout: 30) else { return XCTFail("no Plex code") }
        shot("after-05-plex-code-focus-cancel")
        XCTAssertTrue(linkPlexPIN(code: code))
        let next = app.buttons["CONTINUE"]
        let start = Date()
        while Date().timeIntervalSince(start) < 60 {
            if next.exists {
                sleep(1)
                shot("after-06-plex-libraries-focus-continue")
                press(.select, "CONTINUE")
                break
            }
            if app.descendants(matching: .any)["tunerSettingsButton"].exists { break }
            sleep(1)
        }
        XCTAssertTrue(waitForGuide(), "Plex never reached a library")
        shot("after-07-plex-guide")
        note("Plex presses from a fresh launch to a built guide: \(presses) (plus the code at plex.tv/link)")
        writeLog("after-B-plex")
    }

    func testC_JellyfinQuickConnect() {
        launchFresh()
        moveFocus(to: app.buttons["JELLYFIN"], .down)
        press(.select, "JELLYFIN")
        // The search starts as the screen opens.
        shot("after-11-jellyfin-searching")
        // One Jellyfin answers and has Quick Connect on: no pick, no typing, straight to the code.
        guard let code = codeOnScreen(length: 6, timeout: 30) else { return XCTFail("no Quick Connect code") }
        shot("after-12-jellyfin-quickconnect-focus-password")
        gallery([(.down, "after-13-jellyfin-quickconnect-focus-back"), (.up, "")])
        note("Jellyfin Quick Connect presses before approval: \(presses)")
        XCTAssertTrue(approveJellyfinQuickConnect(code: code))
        XCTAssertTrue(waitForGuide(), "Jellyfin never reached a library")
        shot("after-14-jellyfin-loaded")
        note("Jellyfin Quick Connect presses from a fresh launch to a loaded library: \(presses)")
        writeLog("after-C-jellyfin-quickconnect")
    }

    func testD_JellyfinPassword() {
        let env = ProcessInfo.processInfo.environment
        launchFresh()
        moveFocus(to: app.buttons["JELLYFIN"], .down)
        press(.select, "JELLYFIN")
        guard codeOnScreen(length: 6, timeout: 30) != nil else { return XCTFail("no Quick Connect code") }
        let usePassword = app.buttons["SIGN IN WITH A PASSWORD"]
        XCTAssertTrue(usePassword.hasFocus)
        press(.select, "SIGN IN WITH A PASSWORD")
        XCTAssertTrue(waitForText("SIGN IN TO"))
        sleep(1)
        shot("after-15-jellyfin-password-focus-username")
        typeIntoFocusedField(env["NX_JF_USER"] ?? "")
        moveFocus(to: app.secureTextFields["jellyfinPasswordField"], .down)
        shot("after-16-jellyfin-password-focus-password")
        typeIntoFocusedField(env["NX_JF_PASS"] ?? "", secret: true)
        moveFocus(to: app.buttons["SIGN IN"], .down)
        shot("after-17-jellyfin-password-focus-signin")
        gallery([(.down, "after-18-jellyfin-password-focus-quickconnect"), (.up, ""),
                 (.up, "after-16b-jellyfin-password-focused-filled"), (.down, "")])
        press(.select, "SIGN IN")
        XCTAssertTrue(waitForGuide(), "Jellyfin never reached a library")
        note("Jellyfin password presses from a fresh launch to a loaded library: \(presses)")
        writeLog("after-D-jellyfin-password")
    }

    /// Against a real Emby nobody here has the password for: stops at the password field.
    func testE_EmbyDiscoveredToPassword() {
        launchFresh()
        moveFocus(to: app.buttons["EMBY"], .down)
        press(.select, "EMBY")
        XCTAssertTrue(waitForText("SIGN IN TO"), "one Emby answering should open its sign-in with no pick")
        sleep(1)
        shot("after-20-emby-found-users-focus-first")
        note("Emby presses from a fresh launch to the user tiles: \(presses), focus: \(focusedDescription())")
        press(.select, "first user tile")
        sleep(1)
        shot("after-21-emby-found-password-focused")
        note("Emby presses to the password field of a discovered server: \(presses), focus: \(focusedDescription())")
        writeLog("after-E-emby-discovered")
    }

    /// Nothing answering the search (the stand-in), which is also what a declined Local
    /// Network prompt looks like: focus has to land on TYPE AN ADDRESS by itself.
    func testF_EmbyTypedAddressToGuide() {
        let env = ProcessInfo.processInfo.environment
        launch(["-uiTestDiscovery", "none"])
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].waitForExistence(timeout: 40))
        sleep(2)
        moveFocus(to: app.buttons["EMBY"], .down)
        press(.select, "EMBY")
        let type = app.buttons["TYPE AN ADDRESS"]
        XCTAssertTrue(app.staticTexts["embyNoServersFound"].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(type.hasFocus, "nothing found should leave focus on TYPE AN ADDRESS")
        shot("after-19-emby-nothing-answered-focus-type")
        press(.select, "TYPE AN ADDRESS")
        XCTAssertTrue(app.textFields["serverAddressField"].waitForExistence(timeout: 10))
        sleep(1)
        shot("after-22-emby-address-focus-field")
        gallery([(.down, "after-23-emby-address-focus-back"), (.up, "")])
        typeIntoFocusedField(env["NX_EMBY_ADDR"] ?? "")
        // Closing the keyboard checks the address: no DOWN, no CONNECT.
        if !app.staticTexts["SIGN IN TO"].waitForExistence(timeout: 3) { shot("debug-F-after-address") }
        XCTAssertTrue(waitForText("SIGN IN TO"))
        sleep(1)
        shot("after-24-emby-users-focus-first")
        gallery([(.down, "after-24b-emby-users-focus-someone-else"), (.up, "")])
        let user = app.buttons[env["NX_EMBY_USER"] ?? ""]
        moveFocus(to: user, .right)
        shot("after-25-emby-focus-user")
        press(.select, "user tile")
        sleep(1)
        shot("after-26-emby-password-focused")
        typeIntoFocusedField(env["NX_EMBY_PASS"] ?? "", secret: true)
        moveFocus(to: app.buttons["SIGN IN"], .down)
        shot("after-27-emby-focus-signin")
        gallery([(.down, "after-28-emby-focus-back"), (.up, "")])
        press(.select, "SIGN IN")
        XCTAssertTrue(waitForGuide(), "Emby never reached a library")
        shot("after-29-emby-guide")
        note("Emby typed-address presses from a fresh launch to a built guide: \(presses)")
        writeLog("after-F-emby-typed")
    }

    func testG_EmbyUserWithNoPassword() {
        let env = ProcessInfo.processInfo.environment
        launch(["-uiTestDiscovery", "none"])
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].waitForExistence(timeout: 40))
        sleep(2)
        moveFocus(to: app.buttons["EMBY"], .down)
        press(.select, "EMBY")
        let type = app.buttons["TYPE AN ADDRESS"]
        XCTAssertTrue(app.staticTexts["embyNoServersFound"].waitForExistence(timeout: 10))
        sleep(1)
        moveFocus(to: type, .down)
        press(.select, "TYPE AN ADDRESS")
        XCTAssertTrue(app.textFields["serverAddressField"].waitForExistence(timeout: 10))
        sleep(1)
        typeIntoFocusedField(env["NX_EMBY_ADDR"] ?? "")
        XCTAssertTrue(waitForText("SIGN IN TO"))
        sleep(1)
        let user = app.buttons["nxnopass"]
        moveFocus(to: user, .right)
        note("tiles reached; picking a user with no password")
        let before = presses
        press(.select, "nxnopass")
        XCTAssertTrue(waitForGuide(), "Emby never reached a library")
        note("presses from the user tiles to a built guide for a user with no password: \(presses - before)")
        note("Emby typed-address, no-password presses from a fresh launch to a built guide: \(presses)")
        writeLog("after-G-emby-nopassword")
    }

    /// Screens one test network never produces: several servers answering, then picking
    /// one that does not answer (a TEST-NET address), with the check's waiting line and
    /// the reason it failed. Uses the `-uiTestDiscovery` stand-in.
    func testH_SeveralServersAndADeadOne() {
        launch(["-uiTestDiscovery", "several"])
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].waitForExistence(timeout: 40))
        sleep(2)
        moveFocus(to: app.buttons["JELLYFIN"], .down)
        press(.select, "JELLYFIN")
        let first = app.buttons["jellyfinDiscoveredServer-fixture-1"]
        if !first.waitForExistence(timeout: 10) {
            shot("debug-H-after-find")
            print("[TOUR] buttons: \(app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })")
        }
        XCTAssertTrue(first.exists)
        sleep(1)
        XCTAssertTrue(first.hasFocus, "the first server should take focus")
        shot("after-30-jellyfin-several-focus-first")
        gallery([(.down, "after-31-jellyfin-several-focus-second"), (.up, "")])
        press(.select, "Living Room")
        sleep(1)
        shot("after-32-jellyfin-connecting")
        XCTAssertTrue(app.staticTexts["signInFlowMessage"].waitForExistence(timeout: 30))
        sleep(1)
        shot("after-33-jellyfin-server-did-not-answer")
        note("after a failed check, focus: \(focusedDescription())")
        gallery([(.down, ""), (.down, "after-33b-jellyfin-find-focus-search-again"), (.down, "after-33c-jellyfin-find-focus-type"),
                 (.down, "after-33d-jellyfin-find-focus-back")])
        writeLog("after-H-several-and-dead")
    }

    func testI_NoServerAnswered() {
        launch(["-uiTestDiscovery", "none"])
        XCTAssertTrue(app.buttons["CONNECT TO PLEX"].waitForExistence(timeout: 40))
        sleep(2)
        moveFocus(to: app.buttons["EMBY"], .down)
        press(.select, "EMBY")
        XCTAssertTrue(app.staticTexts["embyNoServersFound"].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(app.buttons["TYPE AN ADDRESS"].hasFocus, "nothing found should move focus to TYPE AN ADDRESS")
        shot("after-34-emby-nothing-found-focus-type")
        writeLog("after-I-none")
    }
}
