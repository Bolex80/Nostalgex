import XCTest
@testable import Nostalgex

/// Shared golden table for STREAM QUALITY.
///
/// `scripts/stream-quality-golden.json` is read by this test AND by the web tuner's node test
/// (`npm run test:stream-quality`, scripts/nostalgex-stream-quality-smoke.mjs). Both engines
/// must carry the same levels, in the same order, with the same numbers, so Auto, Maximum,
/// High, Medium and Low ask a server for the same thing on the Apple TV and in the browser.
/// The Roku port reads the same file.
final class StreamQualityGoldenTests: XCTestCase {

    private struct Golden: Decodable {
        let storageKey: String
        let `default`: String
        let levels: [Level]
    }

    private struct Level: Decodable {
        let id: String
        let displayName: String
        let maxBitrateKbps: Int
        let width: Int
        let height: Int
        let videoQualityIndex: Int
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func golden() throws -> Golden {
        let url = Self.repoRoot.appendingPathComponent("scripts/stream-quality-golden.json")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testTheTableMatchesTheGoldenFile() throws {
        let g = try golden()
        XCTAssertEqual(StreamQuality.storageKey, g.storageKey)
        XCTAssertEqual(StreamQuality.auto.rawValue, g.default)
        XCTAssertEqual(StreamQuality.allCases.map(\.rawValue), g.levels.map(\.id), "same levels, same order")
        for (quality, level) in zip(StreamQuality.allCases, g.levels) {
            XCTAssertEqual(quality.displayName, level.displayName, level.id)
            XCTAssertEqual(quality.maxBitrateKbps, level.maxBitrateKbps, level.id)
            XCTAssertEqual(quality.maxBitrateBps, level.maxBitrateKbps * 1_000, level.id)
            XCTAssertEqual(quality.width, level.width, level.id)
            XCTAssertEqual(quality.height, level.height, level.id)
            XCTAssertEqual(quality.videoQualityIndex, level.videoQualityIndex, level.id)
        }
    }
}
