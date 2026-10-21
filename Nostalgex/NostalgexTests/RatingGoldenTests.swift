import XCTest
@testable import Nostalgex

/// Shared golden cases for ratings from other countries (GitHub #41).
///
/// `scripts/rating-golden.json` is read by this test, by the web tuner's node test
/// (`npm run test:ratings`, scripts/nostalgex-rating-smoke.mjs) and by the Roku port's
/// RatingGoldenTests.brs. Each case is a raw rating, an item type and the US label the
/// channel rules must read for it. All three engines must agree, so a UK Jellyfin library
/// fills the same kids channels on the Apple TV, in the browser and on a Roku.
final class RatingGoldenTests: XCTestCase {

    private struct Golden: Decodable {
        let cases: [Case]
    }

    private struct Case: Decodable {
        let raw: String?
        let type: String
        let us: String?
    }

    /// Repo root, found from this source file: NostalgexTests -> Nostalgex -> root.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func golden() throws -> Golden {
        try JSONDecoder().decode(
            Golden.self,
            from: Data(contentsOf: Self.repoRoot.appendingPathComponent("scripts/rating-golden.json")))
    }

    private func mediaType(_ type: String) -> MediaType {
        type == "episode" ? .episode : .movie
    }

    func testEveryGoldenRatingReadsAsTheSameUSLabelAsTheWebEngine() throws {
        let cases = try golden().cases
        XCTAssertGreaterThan(cases.count, 200)
        for c in cases {
            XCTAssertEqual(ContentRating.usLabel(c.raw, type: mediaType(c.type)), c.us,
                           "\(c.raw.map { "\"\($0)\"" } ?? "nil") as \(c.type)")
        }
    }

    /// A label added to the Swift tables without a golden case would hold neither the web
    /// tuner nor the Roku to it.
    func testEveryTableLabelHasAGoldenCase() throws {
        let seen = Set(try golden().cases.compactMap { c in
            c.raw.map { "\(String($0.uppercased().filter { !$0.isWhitespace }))|\(c.type)" }
        })
        func covered(_ forms: [String]) -> Bool {
            ["movie", "episode"].allSatisfy { t in forms.contains { seen.contains("\($0)|\(t)") } }
        }
        for label in ContentRating.usLabels {
            XCTAssertTrue(covered([label]), "US label \(label) has no golden case")
        }
        for (country, table) in ContentRating.words {
            for label in table.keys {
                XCTAssertTrue(covered(["\(country)-\(label)", "\(country)/\(label)"]), "\(country)-\(label) has no golden case")
            }
        }
        for label in ContentRating.bare.keys {
            XCTAssertTrue(covered([label, "TV-\(label)"]), "bare \(label) has no golden case")
        }
    }

    /// The filter reads the US label, not the raw one, and only the filter does: the item
    /// keeps GB-15 for display.
    func testFilterCacheCarriesTheUSLabelAndKeepsTheRawOne() {
        let film = item("a", rating: "GB-15", type: .movie)
        let episode = item("b", rating: "GB-15", type: .episode)
        let cache = { (i: PlexMediaItem) in
            AppState.FilterCache(item: i, titleLower: "", episodeTitleLower: "", genresLowerSet: [],
                                 enrichment: nil, itemStudioLower: "")
        }
        XCTAssertEqual(cache(film).usContentRating, "R")
        XCTAssertEqual(cache(episode).usContentRating, "TV-MA")
        XCTAssertEqual(cache(film).item.contentRating, "GB-15")
        XCTAssertEqual(cache(item("c", rating: "PG-13", type: .movie)).usContentRating, "PG-13")
        XCTAssertNil(cache(item("d", rating: nil, type: .movie)).usContentRating)
    }

    /// VHS VAULT holds R and NC-17 until 9 PM, and a GB-18 or FSK-16 film waits with them.
    /// `blockBefore: 24` holds at every hour, so the result doesn't depend on the clock.
    func testBlockRatingsHoldsRatingsFromOtherCountries() {
        let pool = [("r", "R"), ("pg", "PG"), ("gb18", "GB-18"), ("gb15", "GB-15"), ("gbpg", "GB-PG"),
                    ("fsk16", "FSK-16"), ("gb12", "gb/12"), ("none", nil)]
            .map { item($0.0, rating: $0.1, type: .movie) }
        var channel = Channel(
            id: 7, number: 7, name: "VHS VAULT", color: .blue, category: "nostalgex", rules: ChannelRules(),
            timeRestrictions: TimeRestrictions(
                blockRatings: BlockRatings(ratings: ["R", "NC-17"], blockBefore: 24, blockAfter: nil)),
            minItems: 0)
        channel.itemPool = pool
        XCTAssertEqual(channel.filteredPool().map(\.id), ["pg", "gbpg", "gb12", "none"])
    }

    private func item(_ id: String, rating: String?, type: MediaType) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: id, artist: nil, episodeTitle: nil, seTag: nil, summary: "", year: 2000,
            originallyAvailableAt: nil, contentRating: rating, duration: 100, ratingKey: id,
            partKey: nil, container: nil, videoCodec: nil, audioCodec: nil, videoProfile: nil,
            bitrate: nil, genres: ["Comedy"], rating: 0, userRating: 0, type: type, thumb: nil,
            art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: type == .episode ? .tv : .movie, serverID: nil
        )
    }
}
