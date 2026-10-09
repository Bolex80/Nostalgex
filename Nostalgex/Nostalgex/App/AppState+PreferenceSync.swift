import Foundation

// Applying preferences that arrived from another Apple TV through iCloud.
// Outgoing writes happen in the existing didSet / save paths; see PreferenceSync.
extension AppState: PreferenceSyncApplying {
    func applyIncomingPreferences(_ values: [String: Any]) {
        if let v = values[PreferenceSync.retroModeKey] as? Bool, v != retroMode {
            retroMode = v
        }
        if let v = values[PreferenceSync.subtitlesFullscreenKey] as? Bool, v != subtitlesInFullscreenEnabled {
            subtitlesInFullscreenEnabled = v
        }
        if let v = values[PreferenceSync.autoSubsForeignAudioKey] as? Bool, v != autoSubtitlesForForeignAudioEnabled {
            autoSubtitlesForForeignAudioEnabled = v
        }
        if let v = values[PreferenceSync.subtitleLanguageKey] as? String, v != preferredSubtitleLanguageCode {
            preferredSubtitleLanguageCode = v
        }
        if let v = values[PreferenceSync.audioLanguageKey] as? String, v != preferredAudioLanguageCode {
            preferredAudioLanguageCode = v
        }
        if let v = values[PreferenceSync.enabledCollectionsKey] as? [String], Set(v) != enabledCollectionKeys {
            applyEnabledCollectionKeys(Set(v))
        }
        if let v = values[PreferenceSync.enabledBundlesKey] as? [String], !v.isEmpty, Set(v) != enabledBundleIDs {
            applyEnabledBundleIDs(Set(v))
        }
    }

    /// Replaces the enabled bundles and rebuilds the lineup the way a Settings toggle does.
    /// Ids this TV's lineup does not have are kept and match nothing.
    func applyEnabledBundleIDs(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let added = ids.subtracting(enabledBundleIDs)
        enabledBundleIDs = ids
        rebuildLineupAfterBundleChange(newlyEnabled: bundles.filter { added.contains($0.id) })
    }

    /// Replaces the enabled collections and re-materializes their channels the way
    /// `toggleCollection` does. Ids from a server this TV is not signed into are kept in
    /// the set (so they survive a round trip) and match no discovered collection here.
    func applyEnabledCollectionKeys(_ keys: Set<String>) {
        enabledCollectionKeys = keys
        var changed = false
        for i in discoveredCollections.indices {
            let on = keys.contains(discoveredCollections[i].id)
            if discoveredCollections[i].enabled != on {
                discoveredCollections[i].enabled = on
                changed = true
            }
        }
        saveCollectionPreferences()
        guard changed else { return }
        materializeDynamicChannels()
        applyBundleFilter()
        reselectIfCurrentChannelFilteredOut()
    }

    /// The bundle set to use after restoring a snapshot: the saved preference when there
    /// is one, plus the collection categories the snapshot has discoveries for (those are
    /// always on, see `syncCollectionCategoryBundlesWithDiscoveries`).
    nonisolated static func preferredBundleIDsAfterSnapshot(
        stored: [String]?,
        snapshotWithDiscoveries: Set<String>,
        discoveredCategoryBundleIDs: Set<String>
    ) -> Set<String> {
        guard let stored, !stored.isEmpty else { return snapshotWithDiscoveries }
        return Set(stored).union(discoveredCategoryBundleIDs)
    }

    #if DEBUG
    /// Hardware test hook: `-NostalgexSyncProbe retro=1` (or `retro=0`) sets retro mode on
    /// launch so it syncs like a Settings change. `retro=unset-local` removes the local value
    /// without touching iCloud, and `clear-cloud` removes the synced keys from iCloud.
    func runPreferenceSyncProbeIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-NostalgexSyncProbe"), i + 1 < args.count else { return }
        let probe = args[i + 1]
        print("[Sync] probe: \(probe), retro mode currently \(retroMode)")
        switch probe {
        case "retro=1": retroMode = true
        case "retro=0": retroMode = false
        case "retro=unset-local":
            UserDefaults.standard.removeObject(forKey: PreferenceSync.retroModeKey)
            print("[Sync] probe: removed local retro mode")
        case "clear-cloud":
            preferenceSync.debugClearCloud()
        default:
            print("[Sync] probe: unknown")
        }
        preferenceSync.cloud.synchronize()
    }
    #endif
}
