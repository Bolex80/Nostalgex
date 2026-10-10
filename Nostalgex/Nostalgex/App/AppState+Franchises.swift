import Foundation
import SwiftUI

// Found franchises: the "FOUND IN YOUR LIBRARY" half of the FRANCHISES package.
//
// `FranchiseChannelBuilder` decides WHAT the franchises are from the library plus its
// TMDB enrichment. This file owns everything around that: when the list is rebuilt, how
// a viewer's on/off choices persist, how an enabled franchise becomes a runtime channel,
// and how a server collection that is really one of these franchises gets folded away so
// it is not offered twice. The schedule engine and playback are untouched: a found
// franchise channel is a dynamic channel (rules == nil) exactly like a collection channel.

/// One franchise the builder found in the viewer's library, as Settings lists it.
struct FoundFranchise: Identifiable, Equatable {
    /// `FranchiseGrouping.stableID`: survives relaunch, rescan and a later iCloud sync.
    let id: String
    /// Channel-ready name, upper-cased ("JOHN WICK").
    let name: String
    let movies: [PlexMediaItem]
    /// Episodes of the shows that joined (the show title is `PlexMediaItem.title`).
    let tvItems: [PlexMediaItem]
    /// The stock channel (CH100-106) this franchise folds into, when one exists. Such a
    /// franchise is already on with the FRANCHISES bundle and gets no switch of its own.
    let coveredByChannelID: Int?
    let fromDictionary: Bool
    var enabled: Bool

    var isCoveredByStock: Bool { coveredByChannelID != nil }
    var items: [PlexMediaItem] { movies + tvItems }
    var showCount: Int { Set(tvItems.map(\.title)).count }

    /// "3 movies", "1 movie", "5 movies, 2 shows".
    var countLabel: String {
        var parts: [String] = []
        if !movies.isEmpty { parts.append(movies.count == 1 ? "1 movie" : "\(movies.count) movies") }
        let shows = showCount
        if shows > 0 { parts.append(shows == 1 ? "1 show" : "\(shows) shows") }
        return parts.joined(separator: ", ")
    }

    static func == (lhs: FoundFranchise, rhs: FoundFranchise) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.movies.map(\.id) == rhs.movies.map(\.id)
            && lhs.tvItems.map(\.id) == rhs.tvItems.map(\.id)
            && lhs.coveredByChannelID == rhs.coveredByChannelID
            && lhs.fromDictionary == rhs.fromDictionary
            && lhs.enabled == rhs.enabled
    }
}

extension AppState {

    static let enabledFranchisesKey = "nostalgex_enabled_franchises"
    /// The stock FRANCHISES bundle in channels.json (CH100-106). Found franchise channels
    /// ride on this switch.
    static let franchisesBundleID = "franchises"

    // MARK: - What Settings reads

    var isFranchisesBundleOn: Bool { enabledBundleIDs.contains(Self.franchisesBundleID) }

    /// Found franchises that get a switch: not folded into a stock channel.
    var listedFoundFranchises: [FoundFranchise] {
        foundFranchises.filter { !$0.isCoveredByStock }
    }

    /// Found franchises already carried by a stock channel. Shown greyed, no switch.
    var coveredFoundFranchises: [FoundFranchise] {
        foundFranchises.filter(\.isCoveredByStock)
    }

    /// Server collections that still belong under MY COLLECTIONS: everything the fold
    /// did not credit to a franchise.
    var visibleDiscoveredCollections: [DiscoveredCollection] {
        discoveredCollections.filter { !$0.isFoldedIntoFranchise }
    }

    /// Stock franchise channels present in the current lineup, by id.
    private var availableStockFranchiseChannelIDs: Set<Int> {
        let bundleIDs = Set(bundles.first(where: { $0.id == Self.franchisesBundleID })?.channelIDs ?? [])
        return Set(allChannels.filter { bundleIDs.contains($0.id) }.map(\.id))
    }

    // MARK: - Rebuild

    /// Runs the builder over the library and the enrichment cache, then re-folds the
    /// server collections against the result. Called after every enrichment pass (first
    /// load, RESCAN, background refresh) and after the FRANCHISES bundle's own pools are
    /// built, since a fold only targets a stock channel that is actually in the lineup.
    ///
    /// - Parameter enrichmentFor: injectable lookup for tests and fixtures; defaults to a
    ///   snapshot of the enrichment service's cache so the builder stays off the actor.
    func rebuildFoundFranchises(enrichmentFor: ((PlexMediaItem) -> MediaEnrichment?)? = nil) {
        let lookup: (PlexMediaItem) -> MediaEnrichment? = enrichmentFor ?? { [cache = enrichmentService.cache] item in
            guard let tmdbID = item.tmdbID else { return nil }
            return cache[tmdbID]
        }
        // Music videos live in a movie-typed library; they are never franchise films.
        let movies = allItems.filter { $0.type == .movie && ($0.librarySource ?? .movie) == .movie }
        let tv = allItems.filter { $0.type == .episode }

        let groupings = FranchiseChannelBuilder.build(
            movies: movies,
            tvItems: tv,
            enrichmentFor: lookup,
            availableStockChannelIDs: availableStockFranchiseChannelIDs
        )

        foundFranchises = groupings.map { g in
            let covered: Int? = {
                if case let .stock(channelID) = g.placement { return channelID }
                return nil
            }()
            return FoundFranchise(
                id: g.stableID,
                name: g.name,
                movies: g.movies,
                tvItems: g.tvItems,
                coveredByChannelID: covered,
                fromDictionary: g.fromDictionary,
                enabled: covered == nil && enabledFranchiseIDs.contains(g.stableID)
            )
        }

        applyFranchiseFolds(enrichmentFor: lookup)

        let listed = listedFoundFranchises
        let folded = discoveredCollections.filter(\.isFoldedIntoFranchise).count
        print("[Plex90] FRANCHISES: \(listed.count) found (\(listed.filter(\.enabled).count) on), \(coveredFoundFranchises.count) covered by stock channels, \(folded) collection(s) folded")
        for f in foundFranchises {
            let where_ = f.coveredByChannelID.map { "on CH \($0)" } ?? (f.enabled ? "ON" : "off")
            print("[Plex90] FRANCHISES:   \(f.name) \(f.countLabel) [\(where_)]")
        }
    }

    /// Marks every discovered collection that IS a franchise the package already carries.
    /// Safe to call whenever either side changes: after a collection scan and after a
    /// franchise rebuild.
    func applyFranchiseFolds(enrichmentFor: ((PlexMediaItem) -> MediaEnrichment?)? = nil) {
        guard !discoveredCollections.isEmpty else { return }
        let lookup: (PlexMediaItem) -> MediaEnrichment? = enrichmentFor ?? { [cache = enrichmentService.cache] item in
            guard let tmdbID = item.tmdbID else { return nil }
            return cache[tmdbID]
        }

        var targets: [FranchiseCollectionFold.Target] = []
        let stockIDs = availableStockFranchiseChannelIDs
        for channel in allChannels where stockIDs.contains(channel.id) {
            let dictName = FranchiseDictionary.all.first(where: { $0.stockChannelID == channel.id })?.canonicalName
            targets.append(FranchiseCollectionFold.Target(
                label: "CH \(channel.number) \(channel.name)",
                itemIDs: Set(channel.itemPool.map(\.id)),
                dictionaryName: dictName,
                stockChannelID: channel.id
            ))
        }
        for franchise in foundFranchises where !franchise.isCoveredByStock {
            targets.append(FranchiseCollectionFold.Target(
                label: franchise.name,
                itemIDs: Set(franchise.items.map(\.id)),
                dictionaryName: franchise.fromDictionary ? franchise.name : nil
            ))
        }

        let folds = FranchiseCollectionFold.folds(
            collections: discoveredCollections,
            targets: targets,
            enrichmentFor: lookup
        )
        for i in discoveredCollections.indices {
            let label = folds[discoveredCollections[i].id]
            if discoveredCollections[i].foldedIntoFranchise != label {
                discoveredCollections[i].foldedIntoFranchise = label
                if let label {
                    print("[Plex90] FRANCHISES: collection '\(discoveredCollections[i].title)' folds into \(label)")
                }
            }
        }
    }

    // MARK: - Switches

    /// Flips one found franchise and rebuilds the lineup, the same path `toggleCollection`
    /// takes so the guide never shows a stale row.
    func toggleFranchise(_ franchise: FoundFranchise) {
        guard let idx = foundFranchises.firstIndex(where: { $0.id == franchise.id }),
              !foundFranchises[idx].isCoveredByStock else { return }
        foundFranchises[idx].enabled.toggle()
        let nowEnabled = foundFranchises[idx].enabled
        if nowEnabled {
            enabledFranchiseIDs.insert(franchise.id)
        } else {
            enabledFranchiseIDs.remove(franchise.id)
        }
        // No id in the event: a franchise id says which films the viewer owns.
        Analytics.track(.settingChanged(key: "franchise", value: nowEnabled ? "true" : "false"))
        saveFranchisePreferences()
        materializeDynamicChannels()
        applyBundleFilter()
        reselectIfCurrentChannelLeft()
    }

    /// ADD ALL / REMOVE ALL over the listed (non-covered) found franchises.
    func setAllFoundFranchises(enabled: Bool) {
        var changed = false
        for i in foundFranchises.indices where !foundFranchises[i].isCoveredByStock {
            if foundFranchises[i].enabled != enabled {
                foundFranchises[i].enabled = enabled
                changed = true
            }
            if enabled {
                enabledFranchiseIDs.insert(foundFranchises[i].id)
            } else {
                enabledFranchiseIDs.remove(foundFranchises[i].id)
            }
        }
        guard changed else { return }
        Analytics.track(.settingChanged(key: "franchise:all", value: enabled ? "true" : "false"))
        saveFranchisePreferences()
        materializeDynamicChannels()
        applyBundleFilter()
        reselectIfCurrentChannelLeft()
    }

    func saveFranchisePreferences() {
        UserDefaults.standard.set(Array(enabledFranchiseIDs).sorted(), forKey: Self.enabledFranchisesKey)
    }

    /// Removing the channel the viewer is on must not leave the player pointed at a row
    /// the guide no longer shows. Same rule `toggleBundle` applies.
    private func reselectIfCurrentChannelLeft() {
        if let current = currentChannel, !channels.contains(where: { $0.id == current.id }) {
            if let first = channels.first {
                selectChannel(first)
            } else {
                currentChannel = nil
                currentItem = nil
            }
        }
    }

    // MARK: - Demo fixture

    /// `-uiTestFranchiseFixture`: layers a small enriched library over demo mode so the
    /// FOUND IN YOUR LIBRARY block and a found-franchise channel can be seen on a
    /// simulator with no server and no Supabase franchise columns. Never runs without the
    /// launch argument. See `DemoData.franchiseFixture`.
    func installFranchiseFixture() async {
        let fixture = DemoData.franchiseFixture()
        let demoChannelIDs = allChannels.map(\.id)
        allItems.append(contentsOf: fixture.items)
        enrichmentService.seedCache(fixture.enrichment)

        let config = ChannelConfigLoader.loadBundled()
        channelConfigChannels = config.channels
        exclusiveRules = config.exclusiveRules
        let demoBundle = ChannelBundle(
            id: "demo", name: "DEMO", description: "Sample channels",
            channelIDs: demoChannelIDs, activeMonths: nil, enabled: true
        )
        let franchisesBundle = config.bundles
            .first(where: { $0.id == Self.franchisesBundleID })?
            .toChannelBundle(enabled: true)
        bundles = [demoBundle] + (franchisesBundle.map { [$0] } ?? [])
        enabledBundleIDs = Set(bundles.map(\.id))

        let stockIDs = Set(franchisesBundle?.channelIDs ?? [])
        let built = await rebuildStaticChannelPools(
            configChannels: config.channels, items: allItems, onlyChannelIDs: stockIDs
        )
        allChannels = (allChannels.filter { !stockIDs.contains($0.id) } + built)
            .sorted { $0.number < $1.number }

        discoveredCollections = fixture.collections
        rebuildFoundFranchises()
        materializeDynamicChannels()
        applyBundleFilter()
        print("[Plex90] FRANCHISES: fixture installed, \(channels.count) channels in the guide")
    }
}
