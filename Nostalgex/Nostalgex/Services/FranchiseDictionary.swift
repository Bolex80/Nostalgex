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

    /// Substrings a TV show title must contain to join by name (word-boundary, case
    /// insensitive). "star wars" catches "Star Wars: The Clone Wars" and "Star Wars
    /// Rebels"; it does not catch "The Mandalorian" (that needs `tvShowTitles`).
    let nameMatchTokens: [String]

    /// TV shows that belong but do NOT name-match (STAR WARS -> The Mandalorian).
    let tvShowTitles: [String]

    /// Marvel is defined by studio (CH101 carries a `studios` rule), not by collection
    /// grouping: its films live in dozens of tiny TMDB collections. When true the
    /// builder never folds `franchiseID` groups into this franchise; the stock
    /// channel's own studio rule owns membership. Documented here so Phase 2 knows.
    let studioRuled: Bool

    init(canonicalName: String,
         stockChannelID: Int? = nil,
         tmdbCollectionIDs: [Int] = [],
         nameMatchTokens: [String] = [],
         tvShowTitles: [String] = [],
         studioRuled: Bool = false) {
        self.canonicalName = canonicalName
        self.stockChannelID = stockChannelID
        self.tmdbCollectionIDs = tmdbCollectionIDs
        self.nameMatchTokens = nameMatchTokens
        self.tvShowTitles = tvShowTitles
        self.studioRuled = studioRuled
    }
}

/// STARTER SET, CHAD TO REVIEW.
///
/// TMDB collection ids below are a mix of ones that are well known and ones that are
/// a best guess from memory. They have NOT been verified against the live TMDB API in
/// this build. Every id marked `TODO verify` needs a look at
/// https://www.themoviedb.org/collection/<id> before it ships, and the franchises that
/// span several collections (STAR WARS anthology/sequels, STAR TREK's many series,
/// FAST & FURIOUS spin-offs) have TODOs for the extra ids to merge in.
///
/// None of this is wired into Settings yet (that is Phase 2). It exists so the logic is
/// listable and testable.
enum FranchiseDictionary {

    static let all: [FranchiseDefinition] = [

        // MARK: - Franchises with a stock channel (CH100-106)

        FranchiseDefinition(
            canonicalName: "STAR WARS",
            stockChannelID: 100,
            // 10 = "Star Wars Collection" (the Skywalker-saga films).
            // TODO verify + merge: the anthology films (Rogue One, Solo) and any
            // separate sequel-trilogy collection are not under id 10 on TMDB. Look up
            // their collection ids and add them here so all the films land on CH100.
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
            // is the wrong tool. The builder leaves CH101 to its studio rule.
            tmdbCollectionIDs: [],
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
            // 328 = "Jurassic Park Collection" (TMDB keeps the Jurassic World films in
            // the same collection). TODO verify this still holds for Jurassic World:
            // Rebirth and friends.
            tmdbCollectionIDs: [328],
            nameMatchTokens: ["jurassic"],
            tvShowTitles: ["Jurassic World: Camp Cretaceous", "Jurassic World: Chaos Theory"]
        ),

        FranchiseDefinition(
            canonicalName: "LORD OF THE RINGS",
            stockChannelID: 104,
            // 119 = "The Lord of the Rings Collection", 121 = "The Hobbit Collection".
            tmdbCollectionIDs: [119, 121],
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
            // Star Trek is many TMDB collections (TOS, TNG, Kelvin timeline, ...).
            // TODO verify + add their ids. Until then the films fold in only when they
            // share whichever collection id a user's library actually carries; the TV
            // side is carried by name-match + the explicit titles below, which is where
            // most of Star Trek lives anyway.
            tmdbCollectionIDs: [], // TODO verify: TOS 115575, Kelvin 115570, TNG 151416 (unconfirmed)
            nameMatchTokens: ["star trek"],
            tvShowTitles: [
                "Star Trek: The Next Generation", "Star Trek: Deep Space Nine",
                "Star Trek: Voyager", "Star Trek: Enterprise", "Star Trek: Discovery",
                "Star Trek: Picard", "Star Trek: Strange New Worlds",
                "Star Trek: Lower Decks", "Star Trek: Prodigy", "Star Trek: The Original Series"
            ]
        ),

        FranchiseDefinition(
            canonicalName: "FAST & FURIOUS",
            // 9485 = "The Fast and the Furious Collection" (given in the plan).
            // TODO verify + merge any separate spin-off collection (e.g. a Hobbs & Shaw
            // collection) if TMDB splits it out.
            tmdbCollectionIDs: [9485],
            nameMatchTokens: ["fast & furious", "fast and furious", "fast saga"],
            tvShowTitles: ["Fast & Furious Spy Racers"]
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
            // 8650 = "Transformers Collection". TODO verify: Bumblebee / Rise of the
            // Beasts may sit in a separate TMDB collection.
            tmdbCollectionIDs: [8650],
            nameMatchTokens: ["transformers"],
            tvShowTitles: []
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
