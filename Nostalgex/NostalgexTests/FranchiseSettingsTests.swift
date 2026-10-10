import XCTest
@testable import Nostalgex

/// Phase 2 of the franchise bundle: the Settings wiring around `FranchiseChannelBuilder`.
/// Drives `AppState` directly with an injected enrichment lookup (no network, no server)
/// and checks the four things the UI relies on: a found franchise's switch persists,
/// ADD ALL / REMOVE ALL rebuild the lineup, the retired NOTABLE STARS state migrates,
/// and a server collection that IS a franchise is folded out of both lists.
@MainActor
final class FranchiseSettingsTests: XCTestCase {

    private let franchisesKey = AppState.enabledFranchisesKey
    private let bundlesKey = "nostalgex_enabled_bundles"
    private let collectionsKey = "nostalgex_enabled_collections"
    private var savedBundles: [String]?
    private var savedCollections: [String]?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedBundles = d.stringArray(forKey: bundlesKey)
        savedCollections = d.stringArray(forKey: collectionsKey)
        d.removeObject(forKey: franchisesKey)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        d.removeObject(forKey: franchisesKey)
        if let savedBundles { d.set(savedBundles, forKey: bundlesKey) } else { d.removeObject(forKey: bundlesKey) }
        if let savedCollections { d.set(savedCollections, forKey: collectionsKey) } else { d.removeObject(forKey: collectionsKey) }
        super.tearDown()
    }

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

    private func episode(_ id: String, show: String) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: show, artist: nil, episodeTitle: "Pilot", seTag: "S01E01",
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

    private func lookup(_ table: [String: (Int, String)]) -> (PlexMediaItem) -> MediaEnrichment? {
        var map: [String: MediaEnrichment] = [:]
        for (id, pair) in table { map[id] = enrichment(franchiseID: pair.0, franchiseName: pair.1) }
        return { map[$0.id] }
    }

    private let wick = ["w1": "John Wick", "w2": "John Wick: Chapter 2", "w3": "John Wick: Chapter 3 - Parabellum"]
    private let hunger = ["h1": "The Hunger Games", "h2": "The Hunger Games: Catching Fire", "h3": "The Hunger Games: Mockingjay - Part 1"]
    private let spyKids = ["s1": "Spy Kids", "s2": "Spy Kids 2", "s3": "Spy Kids 3"]
    private let starWars = ["sw1": "Star Wars: Episode IV - A New Hope", "sw2": "Star Wars: Episode V - The Empire Strikes Back", "sw3": "Star Wars: Episode VI - Return of the Jedi"]
    private let hanks = ["t1": "Big", "t2": "Cast Away", "t3": "Forrest Gump"]

    private func films(_ table: [String: String]) -> [PlexMediaItem] {
        table.keys.sorted().map { movie($0, table[$0]!) }
    }

    /// The enrichment table for every fixture film: real TMDB collection ids where the
    /// dictionary has them, an invented one for Spy Kids, none for the actor set.
    private var fixtureLookup: (PlexMediaItem) -> MediaEnrichment? {
        var table: [String: (Int, String)] = [:]
        for id in wick.keys { table[id] = (404609, "John Wick Collection") }
        for id in hunger.keys { table[id] = (131635, "The Hunger Games Collection") }
        for id in spyKids.keys { table[id] = (99999, "Spy Kids Collection") }
        for id in starWars.keys { table[id] = (10, "Star Wars Collection") }
        return lookup(table)
    }

    /// An AppState with the stock FRANCHISES package on and (optionally) CH100 built.
    private func makeState(stockStarWars: Bool = false) -> AppState {
        let state = AppState()
        state.bundles = [
            ChannelBundle(id: AppState.franchisesBundleID, name: "FRANCHISES", description: nil,
                          channelIDs: [100, 101, 102, 103, 104, 105, 106], activeMonths: nil, enabled: true)
        ]
        state.enabledBundleIDs = [AppState.franchisesBundleID]
        state.discoveredCollections = []
        if stockStarWars {
            var ch = Channel(id: 100, number: 100, name: "STAR WARS", color: .blue, category: "franchise",
                             rules: ChannelRules(titleContains: ["Star Wars"]), timeRestrictions: nil, minItems: 3)
            ch.itemPool = films(starWars)
            state.allChannels = [ch]
        } else {
            state.allChannels = []
        }
        return state
    }

    private func collection(_ id: String, _ title: String, _ items: [PlexMediaItem],
                            category: CollectionCategory, enabled: Bool = true) -> DiscoveredCollection {
        DiscoveredCollection(id: id, title: title, movieCount: items.count, items: items,
                             enabled: enabled, matchedChannel: nil, contentOverlap: nil, category: category)
    }

    // MARK: - Persistence round-trip

    func testFoundFranchiseDefaultsOffAndItsSwitchPersistsAcrossRelaunch() {
        let state = makeState()
        state.allItems = films(wick)
        state.rebuildFoundFranchises(enrichmentFor: fixtureLookup)

        guard let found = state.listedFoundFranchises.first else {
            return XCTFail("John Wick should be found from three films")
        }
        XCTAssertEqual(found.id, "dict:JOHN WICK")
        XCTAssertEqual(found.countLabel, "3 movies")
        XCTAssertFalse(found.enabled, "found franchises default OFF")
        XCTAssertFalse(state.channels.contains { $0.name == "JOHN WICK" })

        state.toggleFranchise(found)

        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: franchisesKey), ["dict:JOHN WICK"])
        XCTAssertTrue(state.channels.contains { $0.name == "JOHN WICK" && $0.rules == nil },
                      "toggling on puts the channel in the guide immediately")

        // A fresh AppState (relaunch) reads the key back and the rebuilt list honours it.
        let relaunched = makeState()
        XCTAssertTrue(relaunched.enabledFranchiseIDs.contains("dict:JOHN WICK"))
        relaunched.allItems = films(wick)
        relaunched.rebuildFoundFranchises(enrichmentFor: fixtureLookup)
        XCTAssertEqual(relaunched.listedFoundFranchises.first?.enabled, true)
        relaunched.materializeDynamicChannels()
        relaunched.applyBundleFilter()
        XCTAssertTrue(relaunched.channels.contains { $0.name == "JOHN WICK" })

        // Off again: key empties, channel leaves.
        state.toggleFranchise(state.listedFoundFranchises[0])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: franchisesKey), [])
        XCTAssertFalse(state.channels.contains { $0.name == "JOHN WICK" })
    }

    func testEnabledIDsPersistAsAPlainStringArray() {
        // A later iCloud sync carries this key as-is, so it must stay a flat [String].
        let state = makeState()
        state.allItems = films(wick) + films(hunger)
        state.rebuildFoundFranchises(enrichmentFor: fixtureLookup)
        state.setAllFoundFranchises(enabled: true)
        let stored = UserDefaults.standard.object(forKey: franchisesKey) as? [String]
        XCTAssertEqual(stored, ["dict:JOHN WICK", "dict:THE HUNGER GAMES"])
    }

    // MARK: - ADD ALL / REMOVE ALL

    func testAddAllThenRemoveAllRebuildTheLineup() {
        let state = makeState()
        state.allItems = films(wick) + films(hunger) + films(spyKids)
        state.rebuildFoundFranchises(enrichmentFor: fixtureLookup)
        XCTAssertEqual(state.listedFoundFranchises.map(\.name), ["JOHN WICK", "SPY KIDS", "THE HUNGER GAMES"])
        XCTAssertTrue(state.listedFoundFranchises.allSatisfy { !$0.enabled })

        state.setAllFoundFranchises(enabled: true)

        XCTAssertTrue(state.listedFoundFranchises.allSatisfy(\.enabled))
        let dynamic = state.channels.filter { $0.rules == nil }
        XCTAssertEqual(dynamic.map(\.name), ["JOHN WICK", "SPY KIDS", "THE HUNGER GAMES"])
        // Collection numbering convention: display numbers from the FRANCHISES range.
        XCTAssertEqual(dynamic.map(\.number), [220, 221, 222])
        XCTAssertEqual(dynamic.map(\.id), [1_000_000, 1_000_001, 1_000_002])
        XCTAssertEqual(Set(UserDefaults.standard.stringArray(forKey: franchisesKey) ?? []),
                       ["dict:JOHN WICK", "dict:THE HUNGER GAMES", "tmdb:99999"])

        // The found channels ride on the package switch.
        state.enabledBundleIDs.remove(AppState.franchisesBundleID)
        state.applyBundleFilter()
        XCTAssertTrue(state.channels.isEmpty, "package off hides every found franchise channel")
        state.enabledBundleIDs.insert(AppState.franchisesBundleID)
        state.applyBundleFilter()
        XCTAssertEqual(state.channels.count, 3)

        state.setAllFoundFranchises(enabled: false)

        XCTAssertTrue(state.listedFoundFranchises.allSatisfy { !$0.enabled })
        XCTAssertTrue(state.channels.filter { $0.rules == nil }.isEmpty)
        XCTAssertTrue(state.allChannels.filter { ChannelIDSpace.isDynamic($0.id) }.isEmpty)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: franchisesKey), [])
    }

    // MARK: - NOTABLE STARS retired

    func testRetiredActorsBundleIDMigratesToCustom() {
        let state = makeState()
        state.enabledBundleIDs = ["nostalgex", AppState.retiredActorsBundleID]

        state.migrateCollectionBundleIDs()

        XCTAssertFalse(state.enabledBundleIDs.contains(AppState.retiredActorsBundleID))
        XCTAssertTrue(state.enabledBundleIDs.contains(CollectionCategory.custom.bundleID))
        XCTAssertTrue(state.enabledBundleIDs.contains("nostalgex"))
        XCTAssertEqual(Set(UserDefaults.standard.stringArray(forKey: bundlesKey) ?? []),
                       ["nostalgex", CollectionCategory.custom.bundleID])
    }

    func testSnapshotRowFromTheActorsCategoryResolvesToCustomAndStillMaterialises() {
        // A snapshot written by an older build still carries "actors" rows.
        let row = StoredDiscoveredCollection(
            id: "c-hanks", title: "TOM HANKS", movieCount: 3,
            itemRatingKeys: ["t1", "t2", "t3"], enabled: true, matchedChannel: nil,
            categoryRaw: "actors"
        )
        let lookupByID = Dictionary(uniqueKeysWithValues: films(hanks).map { ($0.id, $0) })
        let resolved = row.resolve(itemLookup: lookupByID)
        XCTAssertEqual(resolved.category, .custom)
        XCTAssertEqual(resolved.items.count, 3)
        XCTAssertNil(resolved.foldedIntoFranchise)

        let state = makeState()
        state.enabledBundleIDs = [CollectionCategory.custom.bundleID]
        state.discoveredCollections = [resolved]
        state.materializeDynamicChannels()
        state.applyBundleFilter()
        let channel = state.channels.first { $0.name == "TOM HANKS" }
        XCTAssertNotNil(channel, "the collection is not lost, it moves to OTHER COLLECTIONS")
        XCTAssertEqual(channel?.category, CollectionCategory.custom.rawValue)
        XCTAssertEqual(channel?.number, CollectionCategory.custom.displayNumberBase)
        XCTAssertFalse(CollectionCategory.allCases.map(\.rawValue).contains("actors"))
    }

    func testClassifierNeverReturnsARetiredCategory() {
        for category in CollectionCategory.allCases {
            XCTAssertNotEqual(category.displayName, "NOTABLE STARS")
        }
        XCTAssertEqual(CollectionCategory.custom.displayName, "OTHER COLLECTIONS")
    }

    // MARK: - Fold

    func testCollectionThatIsAFranchiseIsHiddenFromBothLists() {
        let state = makeState(stockStarWars: true)
        state.allItems = films(starWars) + films(wick) + films(hanks)
        state.discoveredCollections = [
            collection("c-sw", "STAR WARS COLLECTION", films(starWars), category: .franchises),
            collection("c-wick", "JOHN WICK COLLECTION", films(wick), category: .franchises),
            collection("c-hanks", "TOM HANKS", films(hanks), category: .custom)
        ]

        state.rebuildFoundFranchises(enrichmentFor: fixtureLookup)

        // STAR WARS folds into the classic: not listed with a switch, shown as covered.
        XCTAssertEqual(state.listedFoundFranchises.map(\.name), ["JOHN WICK"])
        XCTAssertEqual(state.coveredFoundFranchises.map(\.name), ["STAR WARS"])
        XCTAssertEqual(state.coveredFoundFranchises.first?.coveredByChannelID, 100)

        // Both franchise collections fold; the actor set does not.
        let byID = Dictionary(uniqueKeysWithValues: state.discoveredCollections.map { ($0.id, $0) })
        XCTAssertEqual(byID["c-sw"]?.foldedIntoFranchise, "CH 100 STAR WARS")
        XCTAssertEqual(byID["c-wick"]?.foldedIntoFranchise, "JOHN WICK")
        XCTAssertNil(byID["c-hanks"]?.foldedIntoFranchise)
        XCTAssertEqual(state.visibleDiscoveredCollections.map(\.id), ["c-hanks"])

        // Even though both folded collections were switched on, neither becomes a channel.
        state.materializeDynamicChannels()
        state.applyBundleFilter()
        let dynamicNames = state.allChannels.filter { $0.rules == nil }.map(\.name)
        XCTAssertEqual(dynamicNames, ["TOM HANKS"])
        XCTAssertFalse(state.enabledBundleIDs.contains(CollectionCategory.franchises.bundleID),
                       "a category whose only collections folded does not get a bundle")

        // Turning the found franchise on yields exactly one JOHN WICK channel.
        state.toggleFranchise(state.listedFoundFranchises[0])
        XCTAssertEqual(state.allChannels.filter { $0.name == "JOHN WICK" }.count, 1)
        XCTAssertEqual(state.allChannels.filter { $0.name == "STAR WARS" }.count, 1, "only the classic")
    }

    func testFoldSurvivesTheSnapshotRoundTrip() {
        let items = films(wick)
        let folded = DiscoveredCollection(
            id: "c-wick", title: "JOHN WICK COLLECTION", movieCount: 3, items: items, enabled: true,
            matchedChannel: nil, contentOverlap: nil, category: .franchises, foldedIntoFranchise: "JOHN WICK"
        )
        let stored = StoredDiscoveredCollection.from(folded)
        XCTAssertEqual(stored.foldedIntoFranchise, "JOHN WICK")
        let lookupByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertEqual(stored.resolve(itemLookup: lookupByID).foldedIntoFranchise, "JOHN WICK")

        let franchise = FoundFranchise(id: "dict:JOHN WICK", name: "JOHN WICK", movies: items, tvItems: [],
                                       coveredByChannelID: nil, fromDictionary: true, enabled: true)
        let row = StoredFoundFranchise.from(franchise)
        let back = row.resolve(itemLookup: lookupByID, enabledIDs: ["dict:JOHN WICK"])
        XCTAssertEqual(back, franchise)
        XCTAssertFalse(row.resolve(itemLookup: lookupByID, enabledIDs: []).enabled)
    }

    func testTVJoinShowsInTheCountLabel() {
        let state = makeState()
        state.allItems = films(wick) + [episode("e1", show: "The Continental: From the World of John Wick"),
                                        episode("e2", show: "The Continental: From the World of John Wick")]
        state.rebuildFoundFranchises(enrichmentFor: fixtureLookup)
        XCTAssertEqual(state.listedFoundFranchises.first?.countLabel, "3 movies, 1 show")
        state.toggleFranchise(state.listedFoundFranchises[0])
        XCTAssertEqual(state.channels.first { $0.name == "JOHN WICK" }?.itemPool.count, 5)
    }
}
