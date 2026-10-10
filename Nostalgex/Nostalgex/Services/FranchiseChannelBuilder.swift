import Foundation

/// Turns a library plus its TMDB enrichment into the franchise channel list.
///
/// Pure and injectable on purpose: it takes the items and an enrichment lookup as
/// arguments and returns value types, so it unit-tests without a network, a server,
/// or `AppState`. Phase 2 feeds its output into Settings and the guide; this file only
/// decides WHAT the franchise channels are, never renders or schedules them.
///
/// Two sources feed a franchise:
///   1. Movies grouped by TMDB `franchiseID` (`belongs_to_collection`). 3+ owned films
///      in a group that has no stock channel make a dynamic channel. This is the
///      "found in your library" source.
///   2. TV shows, which have no `franchiseID`, joined by name-match against the
///      franchise name or by an explicit `FranchiseDictionary` entry.
///
/// The dictionary also merges several collections into one franchise and folds found
/// films/shows into a stock `channels.json` channel (CH100-106) instead of making a
/// duplicate.
enum FranchiseChannelBuilder {

    /// One resolved franchise: either a fold into an existing stock channel, or a new
    /// dynamic channel.
    struct FranchiseGrouping: Equatable {
        enum Placement: Equatable {
            /// Folds into this stock `channels.json` channel. No duplicate is made.
            case stock(channelID: Int)
            /// Its own runtime channel (like a discovered-collection channel).
            case dynamic
        }

        /// Channel-ready display name, upper-cased.
        let name: String
        let placement: Placement
        /// Movies claimed by `franchiseID`.
        let movies: [PlexMediaItem]
        /// TV items joined by name-match or dictionary.
        let tvItems: [PlexMediaItem]
        /// TMDB collection ids merged into this franchise (sorted, for diagnostics).
        let mergedFranchiseIDs: [Int]
        /// True when a `FranchiseDictionary` entry drove this grouping.
        let fromDictionary: Bool

        var allItems: [PlexMediaItem] { movies + tvItems }
        var itemCount: Int { movies.count + tvItems.count }

        static func == (lhs: FranchiseGrouping, rhs: FranchiseGrouping) -> Bool {
            lhs.name == rhs.name
                && lhs.placement == rhs.placement
                && lhs.movies.map(\.id) == rhs.movies.map(\.id)
                && lhs.tvItems.map(\.id) == rhs.tvItems.map(\.id)
                && lhs.mergedFranchiseIDs == rhs.mergedFranchiseIDs
                && lhs.fromDictionary == rhs.fromDictionary
        }
    }

    /// Build the franchise channel list.
    ///
    /// - Parameters:
    ///   - movies: library movie items (anything whose `type` is `.movie`).
    ///   - tvItems: library TV items (one per show is enough; episodes also work).
    ///   - enrichmentFor: resolves a TMDB enrichment for an item, or nil when the item
    ///     is not enriched yet. Injected so the builder stays pure.
    ///   - availableStockChannelIDs: which stock channels actually exist in the current
    ///     lineup. A franchise only folds into a stock channel that is present.
    ///   - definitions: the stock dictionary (overridable for tests).
    ///   - minimumFilms: films required for a dynamic channel. Stock folds are not gated.
    static func build(
        movies: [PlexMediaItem],
        tvItems: [PlexMediaItem] = [],
        enrichmentFor: (PlexMediaItem) -> MediaEnrichment?,
        availableStockChannelIDs: Set<Int> = [],
        definitions: [FranchiseDefinition] = FranchiseDictionary.all,
        minimumFilms: Int = 3
    ) -> [FranchiseGrouping] {

        let byCollectionID: [Int: FranchiseDefinition] = {
            var map: [Int: FranchiseDefinition] = [:]
            for def in definitions where !def.studioRuled {
                for id in def.tmdbCollectionIDs { map[id] = def }
            }
            return map
        }()

        // A working bucket keyed either by a dictionary franchise's canonical name or by
        // a found franchise's own id ("found:<fid>").
        struct Bucket {
            var name: String
            var definition: FranchiseDefinition?
            var movies: [PlexMediaItem] = []
            var tvItems: [PlexMediaItem] = []
            var franchiseIDs: Set<Int> = []
        }
        var buckets: [String: Bucket] = [:]
        // Remembers which key a given dictionary franchise lives under, so TV and extra
        // movie collections merge into the same bucket.
        func keyForDefinition(_ def: FranchiseDefinition) -> String { "dict:\(def.canonicalName)" }

        // MARK: 1. Movies grouped by franchiseID

        var moviesByFranchiseID: [Int: [PlexMediaItem]] = [:]
        for movie in movies {
            guard let fid = enrichmentFor(movie)?.franchiseID else { continue }
            moviesByFranchiseID[fid, default: []].append(movie)
        }

        for (fid, films) in moviesByFranchiseID {
            if let def = byCollectionID[fid] {
                let key = keyForDefinition(def)
                var bucket = buckets[key] ?? Bucket(name: def.canonicalName, definition: def)
                bucket.movies.append(contentsOf: films)
                bucket.franchiseIDs.insert(fid)
                buckets[key] = bucket
            } else {
                // Found franchise with no dictionary entry: name itself from the
                // enrichment's franchiseName.
                let rawName = films.compactMap { enrichmentFor($0)?.franchiseName }.first ?? ""
                let name = FranchiseDictionary.cleanFranchiseName(rawName).uppercased()
                guard !name.isEmpty else { continue }
                let key = "found:\(fid)"
                var bucket = buckets[key] ?? Bucket(name: name, definition: nil)
                bucket.movies.append(contentsOf: films)
                bucket.franchiseIDs.insert(fid)
                buckets[key] = bucket
            }
        }

        // MARK: 2. TV joined by dictionary entry, then by name-match

        for tv in tvItems {
            let titleLower = Self.normalizedTitle(tv.title)

            // Dictionary first: explicit titles, then name tokens. Explicit beats token.
            var matchedDef: FranchiseDefinition?
            for def in definitions where !def.studioRuled {
                if def.tvShowTitles.contains(where: { Self.normalizedTitle($0) == titleLower }) {
                    matchedDef = def
                    break
                }
            }
            if matchedDef == nil {
                for def in definitions where !def.studioRuled {
                    if def.nameMatchTokens.contains(where: { Self.titleContainsToken(titleLower, $0) }) {
                        matchedDef = def
                        break
                    }
                }
            }

            if let def = matchedDef {
                let key = keyForDefinition(def)
                var bucket = buckets[key] ?? Bucket(name: def.canonicalName, definition: def)
                bucket.tvItems.append(tv)
                buckets[key] = bucket
                continue
            }

            // No dictionary match: try to join a found (dynamic) franchise by its name.
            // Only found buckets with a non-empty name are candidates.
            for (key, bucket) in buckets where bucket.definition == nil {
                if Self.titleContainsToken(titleLower, bucket.name.lowercased()) {
                    buckets[key]?.tvItems.append(tv)
                    break
                }
            }
        }

        // MARK: 3. Resolve each bucket to a grouping

        var groupings: [FranchiseGrouping] = []
        for bucket in buckets.values {
            let mergedIDs = bucket.franchiseIDs.sorted()
            let fromDict = bucket.definition != nil

            if let def = bucket.definition,
               let stockID = def.stockChannelID,
               availableStockChannelIDs.contains(stockID) {
                // Fold into the stock channel. Not gated on film count: the stock
                // channel already exists; we are only recording that found content maps
                // to it so Phase 2 doesn't also build a duplicate. Needs at least one
                // found item to be worth recording.
                guard bucket.movies.count + bucket.tvItems.count >= 1 else { continue }
                groupings.append(FranchiseGrouping(
                    name: def.canonicalName,
                    placement: .stock(channelID: stockID),
                    movies: bucket.movies,
                    tvItems: bucket.tvItems,
                    mergedFranchiseIDs: mergedIDs,
                    fromDictionary: fromDict
                ))
            } else {
                // Dynamic channel. Gated on owned films, per "3+ owned films is a
                // candidate". TV augments the pool but does not by itself create a
                // channel here (a TV-only franchise has no franchiseID to group on).
                guard bucket.movies.count >= minimumFilms else { continue }
                groupings.append(FranchiseGrouping(
                    name: bucket.name,
                    placement: .dynamic,
                    movies: bucket.movies,
                    tvItems: bucket.tvItems,
                    mergedFranchiseIDs: mergedIDs,
                    fromDictionary: fromDict
                ))
            }
        }

        // Deterministic order: stock folds first (by channel), then dynamic by name.
        return groupings.sorted { a, b in
            switch (a.placement, b.placement) {
            case let (.stock(l), .stock(r)): return l < r
            case (.stock, .dynamic): return true
            case (.dynamic, .stock): return false
            case (.dynamic, .dynamic): return a.name < b.name
            }
        }
    }

    /// The stock channel a Plex/Jellyfin server collection maps to, if any, decided by
    /// the TMDB franchiseIDs of its member items. Lets the scan path fold a server
    /// collection into a stock channel instead of showing it twice. Returns the stock
    /// channel id when 2+ members share a dictionary-mapped franchiseID.
    static func stockChannel(
        forCollectionItems items: [PlexMediaItem],
        enrichmentFor: (PlexMediaItem) -> MediaEnrichment?,
        availableStockChannelIDs: Set<Int>,
        definitions: [FranchiseDefinition] = FranchiseDictionary.all
    ) -> Int? {
        let byCollectionID: [Int: FranchiseDefinition] = {
            var map: [Int: FranchiseDefinition] = [:]
            for def in definitions where !def.studioRuled {
                for id in def.tmdbCollectionIDs { map[id] = def }
            }
            return map
        }()

        var stockHits: [Int: Int] = [:]
        for item in items {
            guard let fid = enrichmentFor(item)?.franchiseID,
                  let def = byCollectionID[fid],
                  let stockID = def.stockChannelID,
                  availableStockChannelIDs.contains(stockID) else { continue }
            stockHits[stockID, default: 0] += 1
        }
        return stockHits.first(where: { $0.value >= 2 })?.key
    }

    // MARK: - Helpers

    /// Lowercased, with any trailing " (YYYY)" suffix dropped (Plex's TMDB agent appends
    /// release year). Kept local so the builder stays nonisolated and pure; this mirrors
    /// the logic of `AppState.stripTrailingYearSuffix`.
    private static func normalizedTitle(_ raw: String) -> String {
        let s = raw.lowercased()
        guard s.count >= 7, s.hasSuffix(")") else { return s }
        let endIdx = s.index(s.endIndex, offsetBy: -7)
        let chars = Array(s[endIdx..<s.endIndex])
        guard chars[0] == " ", chars[1] == "(",
              chars[2].isNumber, chars[3].isNumber,
              chars[4].isNumber, chars[5].isNumber,
              chars[6] == ")" else { return s }
        return String(s[..<endIdx])
    }

    /// Word-boundary, case-insensitive containment so "star wars" matches "Star Wars
    /// Rebels" but "men" does not match "Mentalist". Both inputs are already lowercased.
    /// Mirrors `AppState.titleContainsWordLower`.
    private static func titleContainsToken(_ titleLower: String, _ tokenLower: String) -> Bool {
        guard !tokenLower.isEmpty else { return false }
        var searchStart = titleLower.startIndex
        while let range = titleLower.range(of: tokenLower, range: searchStart..<titleLower.endIndex) {
            let leftOK: Bool
            if range.lowerBound == titleLower.startIndex {
                leftOK = true
            } else {
                let prev = titleLower[titleLower.index(before: range.lowerBound)]
                leftOK = !prev.isLetter && !prev.isNumber
            }
            let rightOK: Bool
            if range.upperBound == titleLower.endIndex {
                rightOK = true
            } else {
                let next = titleLower[range.upperBound]
                rightOK = !next.isLetter && !next.isNumber
            }
            if leftOK && rightOK { return true }
            searchStart = titleLower.index(after: range.lowerBound)
        }
        return false
    }
}
