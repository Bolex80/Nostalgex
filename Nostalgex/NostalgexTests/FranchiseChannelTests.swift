import XCTest
@testable import Nostalgex

/// Phase 1 of the franchise bundle: pure logic that turns a library + enrichment into
/// the franchise channel list. No Settings wiring, no schedule/playback change — these
/// tests drive `FranchiseChannelBuilder` and `FranchiseDictionary` directly with
/// golden vectors and an injected enrichment lookup (no network).
final class FranchiseChannelTests: XCTestCase {

    // MARK: - Fixtures

    private func movie(_ id: String, _ title: String) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: title, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2000, originallyAvailableAt: nil, contentRating: nil,
            duration: 120, ratingKey: id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: id, imdbID: nil, librarySource: .movie
        )
    }

    private func show(_ id: String, _ title: String) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: title, artist: nil, episodeTitle: "Pilot", seTag: "S01E01",
            summary: "", year: 2020, originallyAvailableAt: nil, contentRating: nil,
            duration: 45, ratingKey: id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .episode, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: id, imdbID: nil, librarySource: .tv
        )
    }

    private func enrichment(franchiseID: Int?, franchiseName: String?) -> MediaEnrichment {
        MediaEnrichment(
            tmdbID: UUID().uuidString, imdbID: nil, mediaType: "movie",
            keywords: [], networks: [], productionCompanies: [], tmdbGenres: [],
            imdbRating: nil, imdbVotes: nil, rottenTomatoesScore: nil, metacriticScore: nil,
            awards: nil, franchiseID: franchiseID, franchiseName: franchiseName, fetchedAt: Date()
        )
    }

    /// Build an enrichment lookup from an [itemID: (fid, name)] table.
    private func lookup(_ table: [String: (Int, String)]) -> (PlexMediaItem) -> MediaEnrichment? {
        var map: [String: MediaEnrichment] = [:]
        for (id, pair) in table {
            map[id] = enrichment(franchiseID: pair.0, franchiseName: pair.1)
        }
        return { map[$0.id] }
    }

    // MARK: - Grouping threshold

    func testThreeFilmsMakeAChannel() {
        let movies = [movie("a", "Spy Kids"), movie("b", "Spy Kids 2"), movie("c", "Spy Kids 3")]
        let look = lookup([
            "a": (99999, "Spy Kids Collection"),
            "b": (99999, "Spy Kids Collection"),
            "c": (99999, "Spy Kids Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.name, "SPY KIDS")
        XCTAssertEqual(groupings.first?.placement, .dynamic)
        XCTAssertEqual(groupings.first?.movies.count, 3)
    }

    func testTwoFilmsDoNotMakeAChannel() {
        let movies = [movie("a", "Spy Kids"), movie("b", "Spy Kids 2")]
        let look = lookup([
            "a": (99999, "Spy Kids Collection"),
            "b": (99999, "Spy Kids Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        XCTAssertTrue(groupings.isEmpty)
    }

    // MARK: - Dictionary fold into a stock channel

    func testDictionaryFranchiseFoldsIntoStockChannelWithoutDuplicate() {
        let movies = [movie("a", "Star Wars"), movie("b", "The Empire Strikes Back"), movie("c", "Return of the Jedi")]
        let look = lookup([
            "a": (10, "Star Wars Collection"),
            "b": (10, "Star Wars Collection"),
            "c": (10, "Star Wars Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [100])

        XCTAssertEqual(groupings.count, 1, "no duplicate dynamic channel next to the stock one")
        let sw = groupings.first
        XCTAssertEqual(sw?.name, "STAR WARS")
        XCTAssertEqual(sw?.placement, .stock(channelID: 100))
        XCTAssertEqual(sw?.movies.count, 3)
        XCTAssertFalse(groupings.contains { $0.placement == .dynamic })
    }

    func testStockFoldMergesMultipleCollections() {
        // LOTR (119) + The Hobbit (121) roll up into one franchise on CH104.
        let movies = [
            movie("a", "The Fellowship of the Ring"), movie("b", "The Two Towers"),
            movie("c", "An Unexpected Journey"), movie("d", "The Desolation of Smaug")
        ]
        let look = lookup([
            "a": (119, "The Lord of the Rings Collection"),
            "b": (119, "The Lord of the Rings Collection"),
            "c": (121, "The Hobbit Collection"),
            "d": (121, "The Hobbit Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [104])
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.placement, .stock(channelID: 104))
        XCTAssertEqual(groupings.first?.movies.count, 4)
        XCTAssertEqual(groupings.first?.mergedFranchiseIDs, [119, 121])
    }

    // MARK: - Unmapped found franchise becomes its own channel

    func testUnmappedFranchiseIsItsOwnDynamicChannel() {
        let movies = [movie("a", "Cube"), movie("b", "Cube 2: Hypercube"), movie("c", "Cube Zero")]
        let look = lookup([
            "a": (12345, "Cube Collection"),
            "b": (12345, "Cube Collection"),
            "c": (12345, "Cube Collection")
        ])
        // Even with CH100 present, an unmapped franchise does not fold into it.
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [100, 101, 102])
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.name, "CUBE")
        XCTAssertEqual(groupings.first?.placement, .dynamic)
        XCTAssertFalse(groupings.first!.fromDictionary)
    }

    // MARK: - TV joins by name and by dictionary

    func testTVShowJoinsByNameAndByDictionary() {
        let movies = [movie("a", "Star Wars"), movie("b", "The Empire Strikes Back"), movie("c", "Return of the Jedi")]
        let look = lookup([
            "a": (10, "Star Wars Collection"),
            "b": (10, "Star Wars Collection"),
            "c": (10, "Star Wars Collection")
        ])
        let tv = [
            show("t1", "Star Wars: The Clone Wars"), // name-match on "star wars"
            show("t2", "The Mandalorian"),           // dictionary title, no name-match
            show("t3", "Breaking Bad")               // unrelated, must not join
        ]
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, tvItems: tv, enrichmentFor: look, availableStockChannelIDs: [100])

        XCTAssertEqual(groupings.count, 1)
        let joined = Set(groupings.first?.tvItems.map(\.id) ?? [])
        XCTAssertTrue(joined.contains("t1"), "name-match should attach The Clone Wars")
        XCTAssertTrue(joined.contains("t2"), "dictionary title should attach The Mandalorian")
        XCTAssertFalse(joined.contains("t3"), "unrelated show must not attach")
    }

    // MARK: - Marvel stays studio-based

    func testMarvelStaysStudioBased() {
        // The Avengers Collection (86311) is a real Marvel collection, but Marvel is
        // studio-ruled in the dictionary (no collection ids), so these films must NOT
        // fold into CH101 — they fall through to their own dynamic channel instead.
        let movies = [movie("a", "The Avengers"), movie("b", "Age of Ultron"), movie("c", "Infinity War")]
        let look = lookup([
            "a": (86311, "The Avengers Collection"),
            "b": (86311, "The Avengers Collection"),
            "c": (86311, "The Avengers Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [101])

        XCTAssertFalse(groupings.contains { $0.placement == .stock(channelID: 101) },
                       "franchiseID grouping must never claim the studio-ruled Marvel channel")
        let avengers = groupings.first { $0.name == "THE AVENGERS" }
        XCTAssertEqual(avengers?.placement, .dynamic)

        // And the dictionary entry itself documents the studio rule.
        let marvel = FranchiseDictionary.all.first { $0.canonicalName == "MARVEL" }
        XCTAssertEqual(marvel?.stockChannelID, 101)
        XCTAssertTrue(marvel?.studioRuled ?? false)
        XCTAssertTrue(marvel?.tmdbCollectionIDs.isEmpty ?? false)
    }

    // MARK: - Server-collection fold helper

    func testServerCollectionMapsToStockChannel() {
        let items = [movie("a", "Harry Potter 1"), movie("b", "Harry Potter 2"), movie("c", "Harry Potter 3")]
        let look = lookup([
            "a": (1241, "Harry Potter Collection"),
            "b": (1241, "Harry Potter Collection"),
            "c": (1241, "Harry Potter Collection")
        ])
        let stock = FranchiseChannelBuilder.stockChannel(
            forCollectionItems: items, enrichmentFor: look, availableStockChannelIDs: [102])
        XCTAssertEqual(stock, 102)

        // Unmapped collection maps to nothing.
        let other = lookup([
            "a": (55555, "Whatever Collection"),
            "b": (55555, "Whatever Collection"),
            "c": (55555, "Whatever Collection")
        ])
        XCTAssertNil(FranchiseChannelBuilder.stockChannel(
            forCollectionItems: items, enrichmentFor: other, availableStockChannelIDs: [102]))
    }

    // MARK: - Dictionary sanity

    func testDictionaryCoversRequiredStockChannels() {
        let byChannel = Dictionary(uniqueKeysWithValues:
            FranchiseDictionary.all.compactMap { d in d.stockChannelID.map { ($0, d.canonicalName) } })
        XCTAssertEqual(byChannel[100], "STAR WARS")
        XCTAssertEqual(byChannel[101], "MARVEL")
        XCTAssertEqual(byChannel[102], "HARRY POTTER")
        XCTAssertEqual(byChannel[103], "JURASSIC PARK")
        XCTAssertEqual(byChannel[104], "LORD OF THE RINGS")
        XCTAssertEqual(byChannel[105], "MISSION IMPOSSIBLE")
        XCTAssertEqual(byChannel[106], "JASON BOURNE")
    }

    func testCleanFranchiseNameStripsCollectionSuffix() {
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("John Wick Collection"), "John Wick")
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("Star Wars collection"), "Star Wars")
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("Alien"), "Alien")
    }
}
