import XCTest
@testable import Nostalgex

/// Shared golden cases for the Jellyfin and Emby connect screens (the 1.0.28 sign-in).
///
/// `scripts/signin-golden.json` is read by this test, by the web tuner's node test
/// (`npm run test:signin`, scripts/nostalgex-signin-smoke.mjs) and by the Roku port, so the
/// three platforms parse servers, pick the way in and check an address the same way.
///
/// Not read here:
/// - `candidates` cases with `defaultScheme`: the hosted web page defaults to https; the
///   Apple TV always starts from http.
/// - `quickConnectPoll`: the Apple TV's poll loop lives in AppState's sign-in code, not in
///   a function this test can call. It makes the same 150 polls, 2 s apart, and stops the
///   same way on approval and on network errors; it calls the code expired on the next
///   tick after the 150th unanswered poll, 2 s later than the golden file's "expired".
final class SignInGoldenTests: XCTestCase {

    /// Repo root, found from this source file: NostalgexTests -> Nostalgex -> root.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func golden() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent("scripts/signin-golden.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func cases(_ key: String) throws -> [[String: Any]] {
        let list = try XCTUnwrap(try golden()[key] as? [[String: Any]], "no \(key) in signin-golden.json")
        XCTAssertFalse(list.isEmpty, "\(key) is empty")
        return list
    }

    private func kind(_ name: Any?) -> MediaBackendKind? {
        switch name as? String {
        case "jellyfin": return .jellyfin
        case "emby": return .emby
        case "plex": return .plex
        default: return nil
        }
    }

    /// JSON null and a missing key both mean "none".
    private func optionalBool(_ value: Any?) -> Bool? {
        value is NSNull ? nil : value as? Bool
    }

    private func users(_ value: Any?) -> [SignInFlow.PublicUser] {
        (value as? [[String: Any]] ?? []).map {
            SignInFlow.PublicUser(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "",
                                  hasPassword: $0["hasPassword"] as? Bool ?? true)
        }
    }

    // MARK: - Pure parts

    func testCandidates() throws {
        var read = 0
        for c in try cases("candidates") where c["defaultScheme"] == nil {
            let raw = try XCTUnwrap(c["raw"] as? String)
            XCTAssertEqual(ServerURLNormalizer.candidates(raw), c["out"] as? [String], "raw: \(raw)")
            read += 1
        }
        XCTAssertGreaterThan(read, 10)
    }

    func testDiscoveryReplies() throws {
        for c in try cases("discoveryReplies") {
            let k = try XCTUnwrap(kind(c["kind"]))
            let got = LANServerDiscovery.parse(reply: Data((c["reply"] as? String ?? "").utf8), kind: k)
            if let out = c["out"] as? [String: Any] {
                XCTAssertEqual(got, DiscoveredServer(kind: try XCTUnwrap(kind(out["kind"])), name: out["name"] as? String ?? "",
                                                     address: out["address"] as? String ?? "", id: out["id"] as? String ?? ""),
                               "reply: \(c["reply"] ?? "")")
            } else {
                XCTAssertNil(got, "should not parse: \(c["reply"] ?? "")")
            }
        }
    }

    func testOutcomes() throws {
        for c in try cases("outcomes") {
            let servers = (c["servers"] as? [[String]] ?? []).map {
                DiscoveredServer(kind: .jellyfin, name: $0[0], address: $0[1], id: $0[0])
            }
            let ids = c["ids"] as? [String] ?? []
            switch (SignInFlow.outcome(of: servers), c["out"] as? String) {
            case (.none, "none"):
                break
            case (.single(let one), "single"):
                XCTAssertEqual([one.id], ids)
                if let keep = c["keep"] as? String { XCTAssertEqual(one.address, keep) }
            case (.several(let list), "several"):
                XCTAssertEqual(list.map(\.id), ids)
            case (let got, let want):
                XCTFail("servers \(servers.map(\.id)): got \(got), want \(want ?? "?")")
            }
        }
    }

    func testPublicInfo() throws {
        for c in try cases("publicInfo") {
            let got = SignInFlow.parsePublicInfo(Data((c["body"] as? String ?? "").utf8))
            if let out = c["out"] as? [String: Any] {
                XCTAssertEqual(got, SignInFlow.PublicInfo(id: out["id"] as? String ?? "", name: out["name"] as? String ?? "",
                                                          kind: try XCTUnwrap(kind(out["kind"]))),
                               "body: \(c["body"] ?? "")")
            } else {
                XCTAssertNil(got, "not a server: \(c["body"] ?? "")")
            }
        }
    }

    func testQuickConnectEnabled() throws {
        for c in try cases("quickConnectEnabled") {
            let got = SignInFlow.parseQuickConnectEnabled(Data((c["body"] as? String ?? "").utf8),
                                                          statusCode: c["status"] as? Int ?? 0)
            XCTAssertEqual(got, optionalBool(c["out"]), "body \(c["body"] ?? "") status \(c["status"] ?? "")")
        }
    }

    func testPublicUsers() throws {
        for c in try cases("publicUsers") {
            XCTAssertEqual(SignInFlow.parsePublicUsers(Data((c["body"] as? String ?? "").utf8)), users(c["out"]),
                           "body: \(c["body"] ?? "")")
        }
    }

    func testMethod() throws {
        for c in try cases("method") {
            let k = try XCTUnwrap(kind(c["kind"]))
            let enabled = optionalBool(c["quickConnectEnabled"])
            let preferred: SignInFlow.Method = c["preferred"] as? String == "quickConnect" ? .quickConnect : .password
            XCTAssertEqual(SignInFlow.preferredMethod(kind: k, quickConnectEnabled: enabled), preferred, "\(c)")
            XCTAssertEqual(SignInFlow.offersQuickConnect(kind: k, quickConnectEnabled: enabled), c["offers"] as? Bool, "\(c)")
        }
    }

    // MARK: - Quick Connect start, through the app's own request

    /// start | off | notJellyfin | failed, read from what the app shows for the error.
    @MainActor
    func testQuickConnectInitiate() async throws {
        for c in try cases("quickConnectInitiate") {
            let status = c["status"] as? Int ?? 0
            let body = c["body"] as? String ?? ""
            let want = c["out"] as? String
            do {
                _ = try await JellyfinAPIService.quickConnectInitiate(serverURL: "http://192.0.2.10:8096") { request in
                    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
                }
                XCTAssertEqual(want, "start", "status \(status) body \(body)")
            } catch {
                let message = AppState.quickConnectFailureMessage(error)
                let got: String
                if message.hasPrefix("Quick Connect is off") { got = "off" }
                else if message.contains("isn't Jellyfin") { got = "notJellyfin" }
                else { got = "failed" }
                XCTAssertEqual(got, want, "status \(status) body \(body): \(message)")
            }
        }
    }

    // MARK: - The address check

    private final class FakeServer: @unchecked Sendable {
        var routes: [String: (Int, String)] = [:]
        var refused: [String] = []
        var timeouts: [String] = []
        private(set) var asked: [String] = []
        private let lock = NSLock()

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let url = request.url!.absoluteString
            lock.withLock { asked.append(url) }
            if timeouts.contains(where: { url.hasPrefix($0) }) { throw URLError(.timedOut) }
            if refused.contains(where: { url.hasPrefix($0) }) { throw URLError(.cannotConnectToHost) }
            let (status, body) = routes[url] ?? (404, "not found")
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testCheck() async throws {
        for c in try cases("check") {
            let name = c["name"] as? String ?? "?"
            let fake = FakeServer()
            for (url, pair) in c["routes"] as? [String: [Any]] ?? [:] {
                fake.routes[url] = (pair[0] as? Int ?? 0, pair[1] as? String ?? "")
            }
            fake.refused = c["refused"] as? [String] ?? []
            fake.timeouts = c["timeout"] as? [String] ?? []
            do {
                let got = try await SignInFlow.check(address: c["address"] as? String ?? "", send: fake.send)
                let out = try XCTUnwrap(c["out"] as? [String: Any], "\(name): expected an error, got \(got)")
                XCTAssertEqual(got.kind, kind(out["kind"]), name)
                XCTAssertEqual(got.url, out["url"] as? String, name)
                XCTAssertEqual(got.name, out["name"] as? String, name)
                XCTAssertEqual(got.quickConnectEnabled, optionalBool(out["quickConnectEnabled"]), name)
                XCTAssertEqual(got.users, users(out["users"]), name)
                let preferred: SignInFlow.Method = out["preferred"] as? String == "quickConnect" ? .quickConnect : .password
                XCTAssertEqual(got.preferredMethod, preferred, name)
            } catch {
                let want = try XCTUnwrap(c["error"] as? String, "\(name): unexpected error \(error)")
                switch want {
                case "notAServer": XCTAssertEqual(error as? SignInFlow.CheckError, .notAServer, name)
                case "network": XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost, name)
                case "timeout": XCTAssertEqual((error as? URLError)?.code, .timedOut, name)
                default: XCTFail("\(name): unknown error kind \(want)")
                }
            }
            if let asked = c["asked"] as? Int {
                XCTAssertEqual(fake.asked.count, asked, "\(name): asked \(fake.asked)")
            }
        }
    }
}
