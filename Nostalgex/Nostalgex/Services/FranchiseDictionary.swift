import Foundation

/// One canonical franchise and everything that rolls up into it.
///
/// This is the hand-maintained half of franchise channel building. The automatic
/// half (`FranchiseChannelBuilder`) groups a library's movies by their TMDB
/// `belongs_to_collection` id. That handles the common case, but it can't know that
/// the prequel-trilogy collection and the sequel-trilogy collection are both "Star
/// Wars", or that The Mandalorian belongs with the films even though its title never
/// says "Star Wars". This dictionary carries that editorial knowledge.
struct FranchiseDefinition {
    /// Channel-ready display name, upper-cased to match the rest of the lineup.
    let canonicalName: String

    /// The stock `channels.json` channel this franchise maps to, when one exists.
    /// Found films and shows fold INTO this channel rather than making a duplicate
    /// runtime channel next to it. nil means "no stock channel, build it dynamically".
    let stockChannelID: Int?

    /// TMDB `belongs_to_collection` ids that all roll up into this one franchise. A
    /// movie whose `franchiseID` is in here is claimed by this franchise, and several
    /// collections (LORD OF THE RINGS + THE HOBBIT) merge into a single channel.
    /// Empty for a studio-ruled franchise (see `studioRuled`).
    let tmdbCollectionIDs: [Int]

    /// Substrings a title must contain to join by name (word-boundary, case
    /// insensitive). Applies to TV shows AND, for dictionary franchises only, to films
    /// that TMDB leaves outside any collection: "star wars" catches "Star Wars: The
    /// Clone Wars" and "Rogue One: A Star Wars Story" (belongs_to_collection is null on
    /// TMDB); "transformers" catches "Transformers: Rise of the Beasts" (also null).
    /// It does not catch "The Mandalorian" or "Bumblebee" (those need the explicit
    /// title lists). Auto-found franchises never use tokens, so a token cannot
    /// over-match a franchise the dictionary does not know about.
    let nameMatchTokens: [String]

    /// TV shows that belong but do NOT name-match (STAR WARS -> The Mandalorian).
    let tvShowTitles: [String]

    /// Films that belong but have no `belongs_to_collection` on TMDB AND do not
    /// name-match (TRANSFORMERS -> Bumblebee). Exact title, case insensitive, with any
    /// trailing " (YYYY)" ignored.
    let filmTitles: [String]

    /// Marvel is defined by studio (CH101 carries a `studios` rule), not by collection
    /// grouping: its films live in dozens of tiny TMDB collections. When true the
    /// builder never places a FILM in this franchise (no `franchiseID` grouping, no
    /// `filmTitles`, no name tokens); the stock channel's studio rule owns the films.
    /// TV still joins, by exact `tvShowTitles` only, since a studio rule cannot see
    /// shows (CH101's rule is `type: movie`).
    let studioRuled: Bool

    /// A found franchise with this flag starts switched ON (a dynamic franchise only;
    /// a stock fold is always on with the package). The viewer can still turn it off,
    /// and that choice is kept (`nostalgex_disabled_franchises`). Nothing is built when
    /// the library has none of it: the usual three-film gate still applies.
    let defaultOn: Bool

    init(canonicalName: String,
         stockChannelID: Int? = nil,
         tmdbCollectionIDs: [Int] = [],
         nameMatchTokens: [String] = [],
         tvShowTitles: [String] = [],
         filmTitles: [String] = [],
         studioRuled: Bool = false,
         defaultOn: Bool = false) {
        self.canonicalName = canonicalName
        self.stockChannelID = stockChannelID
        self.tmdbCollectionIDs = tmdbCollectionIDs
        self.nameMatchTokens = nameMatchTokens
        self.tvShowTitles = tvShowTitles
        self.filmTitles = filmTitles
        self.studioRuled = studioRuled
        self.defaultOn = defaultOn
    }

    /// The `FoundFranchise` / `FranchiseGrouping.stableID` this definition produces.
    var stableID: String { "dict:\(canonicalName)" }
}

/// STARTER SET, CHAD TO REVIEW.
///
/// Every TMDB collection id below was verified against the live TMDB API on
/// 2026-10-10 (collection exists, holds the films named in its comment). Along the
/// way two ids from memory turned out to be dead and were replaced (The Hobbit is
/// 121938, not 121; Star Trek TNG is 115570, not 151416), and the big sagas were
/// confirmed to live in one collection each: Star Wars 10 holds all nine Skywalker
/// films, Fast & Furious 9485 all twelve, Jurassic 328 all eight.
///
/// What TMDB cannot carry, and the dictionary covers instead:
/// - Films with `belongs_to_collection: null`. Rogue One, Solo, Bumblebee and
///   Transformers: Rise of the Beasts are all null on TMDB. The "A Star Wars Story"
///   pair and Rise of the Beasts join by `nameMatchTokens`; Bumblebee, whose title
///   says nothing, is listed in `filmTitles`. That was the only membership gap found.
/// - MARVEL stays studio-ruled by design (CH101's `studios` rule), never grouped by
///   collection id.
/// - TV has no collection id at all, so it joins by token or by `tvShowTitles`.
///
/// Open items for Chad: the TV and film title lists are editorial and will drift as
/// new seasons and spin-offs land; the lists here are a starting point, not a census.
///
/// None of this is wired into Settings yet (that is Phase 2). It exists so the logic is
/// listable and testable.
enum FranchiseDictionary {

    static let all: [FranchiseDefinition] = [

        // MARK: - Franchises with a stock channel (CH100-106)

        FranchiseDefinition(
            canonicalName: "STAR WARS",
            stockChannelID: 100,
            // 10 = "Star Wars Collection": all nine Skywalker-saga films (verified
            // against TMDB 2026-10-10). Rogue One and Solo are titled "...: A Star
            // Wars Story", so they join by name match.
            tmdbCollectionIDs: [10],
            nameMatchTokens: ["star wars"],
            tvShowTitles: [
                "The Mandalorian", "Andor", "Ahsoka", "Obi-Wan Kenobi",
                "The Book of Boba Fett", "Star Wars: The Clone Wars",
                "Star Wars Rebels", "The Acolyte", "Star Wars: Visions",
                "Young Jedi Adventures", "Tales of the Jedi"
            ]
        ),

        FranchiseDefinition(
            canonicalName: "MARVEL",
            stockChannelID: 101,
            // Intentionally empty: CH101 is a studio channel (studios: ["Marvel
            // Studios"]). MCU films scatter across dozens of tiny TMDB collections
            // (Iron Man Collection, Avengers Collection, ...), so franchiseID grouping
            // is the wrong tool. The builder leaves CH101's films to its studio rule.
            tmdbCollectionIDs: [],
            // Shows join CH101 by EXACT title (case and punctuation ignored, see
            // `FranchiseChannelBuilder.explicitTitleKey`), never by token, so a short
            // title like "Echo" cannot pull in "Echo Park". Chad can trim this list:
            // drop the Netflix and ABC era if they should not air next to the MCU.
            // The "Marvel's ..." spellings are how TVDB and older Plex agents title them.
            tvShowTitles: [
                // Disney+ MCU
                "WandaVision", "The Falcon and the Winter Soldier", "Loki", "What If...?",
                "Hawkeye", "Moon Knight", "Ms. Marvel", "She-Hulk: Attorney at Law",
                "Secret Invasion", "Echo", "Agatha All Along", "Daredevil: Born Again",
                "Ironheart",
                // Netflix era
                "Daredevil", "Jessica Jones", "Luke Cage", "Iron Fist", "The Defenders",
                "The Punisher",
                "Marvel's Daredevil", "Marvel's Jessica Jones", "Marvel's Luke Cage",
                "Marvel's Iron Fist", "Marvel's The Defenders", "Marvel's The Punisher",
                // ABC era
                "Agents of S.H.I.E.L.D.", "Agent Carter", "Inhumans",
                "Marvel's Agents of S.H.I.E.L.D.", "Marvel's Agent Carter", "Marvel's Inhumans"
            ],
            studioRuled: true
        ),

        FranchiseDefinition(
            canonicalName: "HARRY POTTER",
            stockChannelID: 102,
            // 1241 = "Harry Potter Collection", 435259 = "Fantastic Beasts Collection".
            // Together they are the Wizarding World; both fold onto CH102.
            tmdbCollectionIDs: [1241, 435259],
            nameMatchTokens: ["harry potter", "fantastic beasts"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "JURASSIC PARK",
            stockChannelID: 103,
            // 328 = "Jurassic Park Collection": all eight films, Jurassic World
            // included (verified against TMDB 2026-10-10).
            tmdbCollectionIDs: [328],
            nameMatchTokens: ["jurassic"],
            tvShowTitles: ["Jurassic World: Camp Cretaceous", "Jurassic World: Chaos Theory"]
        ),

        FranchiseDefinition(
            canonicalName: "LORD OF THE RINGS",
            stockChannelID: 104,
            // 119 = "The Lord of the Rings Collection", 121938 = "The Hobbit
            // Collection" (both verified against TMDB 2026-10-10).
            tmdbCollectionIDs: [119, 121938],
            nameMatchTokens: ["lord of the rings", "hobbit", "rings of power"],
            tvShowTitles: ["The Lord of the Rings: The Rings of Power"]
        ),

        FranchiseDefinition(
            canonicalName: "MISSION IMPOSSIBLE",
            stockChannelID: 105,
            // 87359 = "Mission: Impossible Collection".
            tmdbCollectionIDs: [87359],
            nameMatchTokens: ["mission impossible", "mission: impossible"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "JASON BOURNE",
            stockChannelID: 106,
            // 31562 = "The Bourne Collection".
            tmdbCollectionIDs: [31562],
            nameMatchTokens: ["bourne"],
            tvShowTitles: ["Treadstone"]
        ),

        // MARK: - Franchises with no stock channel (built dynamically)

        FranchiseDefinition(
            canonicalName: "STAR TREK",
            // Star Trek is three TMDB collections, merged here (verified 2026-10-10):
            // 151 = The Original Series films, 115570 = The Next Generation films,
            // 115575 = Alternate Reality (the 2009 Kelvin reboot). The TV side joins by
            // name match plus the explicit titles below.
            tmdbCollectionIDs: [151, 115570, 115575],
            nameMatchTokens: ["star trek"],
            tvShowTitles: [
                "Star Trek: The Next Generation", "Star Trek: Deep Space Nine",
                "Star Trek: Voyager", "Star Trek: Enterprise", "Star Trek: Discovery",
                "Star Trek: Picard", "Star Trek: Strange New Worlds",
                "Star Trek: Lower Decks", "Star Trek: Prodigy", "Star Trek: The Original Series"
            ],
            defaultOn: true
        ),

        FranchiseDefinition(
            canonicalName: "FAST & FURIOUS",
            // 9485 = "The Fast and the Furious Collection": all twelve films including
            // Tokyo Drift and Hobbs & Shaw (verified against TMDB 2026-10-10).
            tmdbCollectionIDs: [9485],
            nameMatchTokens: ["fast & furious", "fast and furious", "fast saga"],
            tvShowTitles: ["Fast & Furious Spy Racers"],
            defaultOn: true
        ),

        FranchiseDefinition(
            canonicalName: "JAMES BOND",
            // 645 = "James Bond Collection".
            tmdbCollectionIDs: [645],
            nameMatchTokens: ["james bond", "007"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "THE MATRIX",
            // 2344 = "The Matrix Collection".
            tmdbCollectionIDs: [2344],
            nameMatchTokens: ["matrix"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "INDIANA JONES",
            // 84 = "Indiana Jones Collection".
            tmdbCollectionIDs: [84],
            nameMatchTokens: ["indiana jones"],
            tvShowTitles: ["The Young Indiana Jones Chronicles"]
        ),

        FranchiseDefinition(
            canonicalName: "PIRATES OF THE CARIBBEAN",
            // 295 = "Pirates of the Caribbean Collection".
            tmdbCollectionIDs: [295],
            nameMatchTokens: ["pirates of the caribbean"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "TRANSFORMERS",
            // 8650 = "Transformers Collection" (verified 2026-10-10). Bumblebee and
            // Transformers: Rise of the Beasts are belongs_to_collection: null on
            // TMDB. Rise of the Beasts joins by the "transformers" token; Bumblebee has
            // no franchise word in its title, so it is listed explicitly.
            tmdbCollectionIDs: [8650],
            nameMatchTokens: ["transformers"],
            tvShowTitles: [],
            filmTitles: ["Bumblebee"]
        ),

        FranchiseDefinition(
            canonicalName: "JOHN WICK",
            // 404609 = "John Wick Collection" (confirmed by the Phase 0 parse test).
            tmdbCollectionIDs: [404609],
            nameMatchTokens: ["john wick"],
            tvShowTitles: ["The Continental: From the World of John Wick"]
        ),

        FranchiseDefinition(
            canonicalName: "THE HUNGER GAMES",
            // 131635 = "The Hunger Games Collection".
            tmdbCollectionIDs: [131635],
            nameMatchTokens: ["hunger games"],
            tvShowTitles: []
        ),

        FranchiseDefinition(
            canonicalName: "THE TERMINATOR",
            // 528 = "The Terminator Collection".
            tmdbCollectionIDs: [528],
            nameMatchTokens: ["terminator"],
            tvShowTitles: ["Terminator: The Sarah Connor Chronicles", "Terminator Zero"]
        ),

        FranchiseDefinition(
            canonicalName: "BACK TO THE FUTURE",
            // 264 = "Back to the Future Collection".
            tmdbCollectionIDs: [264],
            nameMatchTokens: ["back to the future"],
            tvShowTitles: []
        )
    ]

    // MARK: - Lookups

    /// franchiseID -> definition, for every definition that declares collection ids.
    /// A studio-ruled franchise (Marvel) declares none, so it never appears here and is
    /// never matched by franchiseID.
    static let byCollectionID: [Int: FranchiseDefinition] = {
        var map: [Int: FranchiseDefinition] = [:]
        for def in all {
            for id in def.tmdbCollectionIDs { map[id] = def }
        }
        return map
    }()

    static func definition(forFranchiseID id: Int) -> FranchiseDefinition? {
        byCollectionID[id]
    }

    /// Stable ids of the franchises that start switched on (STAR TREK, FAST & FURIOUS).
    static let defaultOnIDs: Set<String> = Set(all.filter(\.defaultOn).map(\.stableID))

    /// Whether a found franchise is on: an explicit choice wins either way, otherwise
    /// the dictionary default. Shared by the rebuild, the snapshot restore and iCloud
    /// arrivals so all three agree.
    static func isOn(_ id: String, enabledIDs: Set<String>, disabledIDs: Set<String>) -> Bool {
        if enabledIDs.contains(id) { return true }
        if disabledIDs.contains(id) { return false }
        return defaultOnIDs.contains(id)
    }

    /// Strip a trailing " Collection" (case insensitive) and tidy whitespace.
    /// "John Wick Collection" -> "John Wick".
    static func cleanFranchiseName(_ raw: String) -> String {
        var name = raw
        let suffix = " collection"
        if name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
