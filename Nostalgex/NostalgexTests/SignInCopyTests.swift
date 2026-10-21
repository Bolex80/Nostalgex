import XCTest
@testable import Nostalgex

/// Sign-in messages have to point at things the screen actually has. "Code expired. Tap
/// Connect to try again." named a Connect button that neither code screen has, and "tap"
/// is a touch word on a TV that's driven with a remote.
@MainActor
final class SignInCopyTests: XCTestCase {

    /// Lands on the picker, where CONNECT TO PLEX gets a new code.
    func testPlexCodeExpiryNamesThePickersButton() {
        XCTAssertTrue(AppState.plexCodeExpiredMessage.contains("CONNECT TO PLEX"))
    }

    /// Lands on the Jellyfin password screen, which has USE QUICK CONNECT and the fields.
    func testQuickConnectExpiryNamesThatScreensButtons() {
        XCTAssertTrue(AppState.quickConnectCodeExpiredMessage.contains(SignInFlow.Copy.useQuickConnect))
        XCTAssertTrue(AppState.quickConnectCodeExpiredMessage.contains("password"))
    }

    /// A failed code request also lands on the picker.
    func testPlexRequestFailuresNameThePickersButton() {
        let errors: [Error?] = [nil, URLError(.notConnectedToInternet), URLError(.timedOut), URLError(.cannotFindHost),
                                PlexAPIService.APIError.httpFailure(statusCode: 429)]
        for error in errors {
            let message = AppState.pinRequestFailureMessage(error)
            XCTAssertTrue(message.contains("CONNECT TO PLEX"), message)
        }
    }

    private var everySignInLine: [String] {
        let urlErrors: [URLError.Code] = [.appTransportSecurityRequiresSecureConnection, .cannotFindHost, .cannotConnectToHost,
                                          .timedOut, .notConnectedToInternet, .serverCertificateUntrusted, .badServerResponse]
        let unreachable = urlErrors.map { AppState.serverUnreachableMessage(URLError($0), backend: "Emby") }
            + [AppState.serverUnreachableMessage(NSError(domain: "x", code: 1), backend: "Jellyfin")]
        let plex = ([nil, URLError(.notConnectedToInternet), URLError(.timedOut), URLError(.cannotFindHost),
                     PlexAPIService.APIError.httpFailure(statusCode: 429), PlexAPIService.APIError.httpFailure(statusCode: 502)] as [Error?])
            .map { AppState.pinRequestFailureMessage($0) }
        let quickConnectErrors: [Error] = [PlexAPIService.APIError.unauthorized, PlexAPIService.APIError.httpFailure(statusCode: 404),
                                           PlexAPIService.APIError.invalidResponse, URLError(.cannotConnectToHost)]
        let quickConnect = quickConnectErrors.map { AppState.quickConnectFailureMessage($0) }
        return unreachable + plex + quickConnect
            + [AppState.plexCodeExpiredMessage, AppState.quickConnectCodeExpiredMessage]
            + SignInFlow.Copy.all + LANServerDiscovery.Copy.all
    }

    /// The remote has no tap, and the screens say "address", never "URL".
    func testNoTouchWordsAndNoURL() {
        for line in everySignInLine {
            let words = line.lowercased().split(whereSeparator: { !$0.isLetter })
            XCTAssertFalse(words.contains("tap"), "tap in: \(line)")
            XCTAssertFalse(words.contains("url"), "URL in: \(line)")
            XCTAssertFalse(line.contains("\u{2014}"), "em dash in: \(line)")
        }
    }
}
