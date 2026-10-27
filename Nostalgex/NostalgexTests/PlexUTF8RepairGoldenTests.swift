import XCTest
@testable import Nostalgex

/// Shared golden vectors for repairing a Plex response that holds bytes that are not UTF-8.
///
/// `scripts/utf8-repair-golden.json` is read by this test AND by the web tuner's node test
/// (`npm run test:utf8-repair`, scripts/nostalgex-utf8-repair-smoke.mjs). Both engines must turn
/// the same bytes into the same text, so a Latin-1 title reads "Café Society" on the Apple TV
/// and in the browser. The Roku port reads the same file.
final class PlexUTF8RepairGoldenTests: XCTestCase {

    private struct Golden: Decodable {
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let hex: String
        let text: String
        let repairedBytes: Int
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func golden() throws -> Golden {
        let url = Self.repoRoot.appendingPathComponent("scripts/utf8-repair-golden.json")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index ..< next], radix: 16)!)
            index = next
        }
        return data
    }

    /// What a JSON parser sees: one leading U+FEFF is ignored (the web drops it as Response.json()
    /// does, JSONDecoder skips it), a U+FEFF anywhere else stays.
    private func parsed(_ text: String) -> String {
        text.unicodeScalars.first == "\u{FEFF}" ? String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())) : text
    }

    func testEveryGoldenVector() throws {
        let cases = try golden().cases
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let input = bytes(c.hex)
            if let repaired = PlexUTF8Repair.repair(input) {
                XCTAssertEqual(parsed(String(decoding: repaired.data, as: UTF8.self)), c.text, c.name)
                XCTAssertEqual(repaired.repairedBytes, c.repairedBytes, c.name)
            } else {
                // Nil means the bytes were already valid UTF-8 and are decoded untouched.
                XCTAssertEqual(c.repairedBytes, 0, c.name)
                XCTAssertEqual(parsed(String(decoding: input, as: UTF8.self)), c.text, c.name)
            }
        }
    }
}
