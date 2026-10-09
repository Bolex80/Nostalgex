import XCTest
import SwiftUI
@testable import Nostalgex

final class PreferenceSyncMergeTests: XCTestCase {
    private let keys = PreferenceSync.syncedKeys
    private let bundles = PreferenceSync.enabledBundlesKey
    private let collections = PreferenceSync.enabledCollectionsKey
    private let retro = PreferenceSync.retroModeKey
    private let subLang = PreferenceSync.subtitleLanguageKey

    func testLaunchWithNothingLocalAdoptsCloud() {
        let plan = PreferenceSyncMerge.plan(
            local: [:],
            cloud: [bundles: ["nostalgex", "decades"], retro: false],
            keys: keys, trigger: .launch)
        XCTAssertEqual(plan.applyLocally[bundles] as? [String], ["decades", "nostalgex"])
        XCTAssertEqual(plan.applyLocally[retro] as? Bool, false)
        XCTAssertTrue(plan.pushToCloud.isEmpty)
    }

    func testLaunchWithNothingInCloudSeedsCloudFromLocal() {
        let plan = PreferenceSyncMerge.plan(
            local: [retro: true, subLang: "en"], cloud: [:], keys: keys, trigger: .launch)
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertEqual(plan.pushToCloud[retro] as? Bool, true)
        XCTAssertEqual(plan.pushToCloud[subLang] as? String, "en")
    }

    func testExternalChangeCloudWinsWhenBothPresent() {
        let plan = PreferenceSyncMerge.plan(
            local: [retro: true, bundles: ["nostalgex"]],
            cloud: [retro: false, bundles: ["nostalgex", "kids"]],
            keys: keys, trigger: .external(changedKeys: [retro, bundles]))
        XCTAssertEqual(plan.applyLocally[retro] as? Bool, false)
        XCTAssertEqual(plan.applyLocally[bundles] as? [String], ["kids", "nostalgex"])
        XCTAssertTrue(plan.pushToCloud.isEmpty)
    }

    func testExternalChangeOnlyTouchesChangedKeys() {
        let plan = PreferenceSyncMerge.plan(
            local: [retro: true, subLang: "en"],
            cloud: [retro: false, subLang: "fr"],
            keys: keys, trigger: .external(changedKeys: [subLang]))
        XCTAssertNil(plan.applyLocally[retro])
        XCTAssertEqual(plan.applyLocally[subLang] as? String, "fr")
    }

    func testExternalRemovalNeitherClearsLocalNorPushes() {
        let plan = PreferenceSyncMerge.plan(
            local: [retro: true], cloud: [:], keys: keys, trigger: .external(changedKeys: [retro]))
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertTrue(plan.pushToCloud.isEmpty)
    }

    func testSameValuesProduceNoWork() {
        let plan = PreferenceSyncMerge.plan(
            local: [bundles: ["b", "a"], retro: true],
            cloud: [bundles: ["a", "b", "a"], retro: true],
            keys: keys, trigger: .launch)
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertTrue(plan.pushToCloud.isEmpty)
    }

    func testUnknownCollectionIdsAreKeptVerbatim() {
        let fromOtherServer = "otherServerMachineID:12345"
        let plan = PreferenceSyncMerge.plan(
            local: [collections: ["mine:1"]],
            cloud: [collections: ["mine:1", fromOtherServer]],
            keys: keys, trigger: .external(changedKeys: [collections]))
        XCTAssertEqual(plan.applyLocally[collections] as? [String], ["mine:1", fromOtherServer])
    }

    func testEmptyCollectionsSyncButEmptyBundlesNever() {
        let plan = PreferenceSyncMerge.plan(
            local: [collections: ["a"], bundles: ["nostalgex"]],
            cloud: [collections: [String](), bundles: [String]()],
            keys: keys, trigger: .external(changedKeys: [collections, bundles]))
        XCTAssertEqual(plan.applyLocally[collections] as? [String], [])
        XCTAssertNil(plan.applyLocally[bundles], "an empty lineup from iCloud must never be applied")
    }

    func testWrongTypesAreIgnored() {
        let plan = PreferenceSyncMerge.plan(
            local: [:],
            cloud: [retro: "yes", bundles: 42, subLang: ""],
            keys: keys, trigger: .launch)
        XCTAssertTrue(plan.applyLocally.isEmpty)
    }

    func testKeysOutsideTheSyncedListAreNeverConsidered() {
        let plan = PreferenceSyncMerge.plan(
            local: ["plex_token": "secret", "nostalgex_sync_plex_activity": true],
            cloud: ["plex_server_url": "http://10.0.0.2:32400"],
            keys: keys, trigger: .launch)
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertTrue(plan.pushToCloud.isEmpty)
    }

    func testSnapshotRestorePrefersSavedLineupPlusDiscoveredCategories() {
        let preferred = AppState.preferredBundleIDsAfterSnapshot(
            stored: ["nostalgex", "kids"],
            snapshotWithDiscoveries: ["nostalgex", "collections-franchises"],
            discoveredCategoryBundleIDs: ["collections-franchises"])
        XCTAssertEqual(preferred, ["nostalgex", "kids", "collections-franchises"])
        XCTAssertEqual(
            AppState.preferredBundleIDsAfterSnapshot(stored: nil, snapshotWithDiscoveries: ["x"], discoveredCategoryBundleIDs: []),
            ["x"])
    }
}

@MainActor
final class PreferenceSyncServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "PreferenceSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Everything that must stay on the device. None of these may ever reach iCloud.
    static let neverSyncedKeys = [
        "plex_server_url", "plex_token", "plex_servers", "backend_kind", "jellyfin_user_id",
        "plex90_client_id", "nostalgex_sync_plex_activity", "nostalgex_stream_quality",
        "nostalgex_last_scan_date", "nostalgex_last_load_at_unix", "nostalgex_completed_initial_load",
        "nostalgex_has_held_sign_in",
    ]

    func testBootstrapNeverPushesNeverSyncedKeys() {
        for key in Self.neverSyncedKeys { defaults.set("value", forKey: key) }
        defaults.set(false, forKey: PreferenceSync.retroModeKey)
        let store = InMemoryKeyValueStore()
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)

        sync.bootstrap()

        XCTAssertEqual(store.writes.map(\.key), [PreferenceSync.retroModeKey])
        for key in Self.neverSyncedKeys { XCTAssertNil(store.values[key], key) }
    }

    func testRecordRefusesKeysOutsideTheSyncedList() {
        let store = InMemoryKeyValueStore()
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)
        for key in Self.neverSyncedKeys { sync.record(key, value: "value") }
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testBootstrapAdoptsCloudBeforeDefaultsAreRead() {
        let store = InMemoryKeyValueStore([
            PreferenceSync.enabledBundlesKey: ["nostalgex", "decades"],
            PreferenceSync.retroModeKey: false,
        ])
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)

        sync.bootstrap()

        XCTAssertEqual(Set(defaults.stringArray(forKey: PreferenceSync.enabledBundlesKey) ?? []), ["nostalgex", "decades"])
        XCTAssertEqual(defaults.object(forKey: PreferenceSync.retroModeKey) as? Bool, false)
        XCTAssertTrue(store.writes.isEmpty, "adopting must not write anything back")
        XCTAssertFalse(sync.holdingOutgoing)
    }

    func testNewTVHoldsWritesUntilICloudDelivers() {
        let store = InMemoryKeyValueStore()
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)
        sync.bootstrap()
        XCTAssertTrue(sync.holdingOutgoing)

        // First load writes default lineup and retro mode on this empty install.
        defaults.set(["nostalgex"], forKey: PreferenceSync.enabledBundlesKey)
        sync.record(PreferenceSync.enabledBundlesKey, value: ["nostalgex"])
        defaults.set(true, forKey: PreferenceSync.retroModeKey)
        sync.record(PreferenceSync.retroModeKey, value: true)
        XCTAssertTrue(store.writes.isEmpty)

        // The household's lineup arrives; it wins, and only the key iCloud lacked is pushed.
        store.values[PreferenceSync.enabledBundlesKey] = ["nostalgex", "kids"]
        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange,
                                  changedKeys: [PreferenceSync.enabledBundlesKey])

        XCTAssertFalse(sync.holdingOutgoing)
        XCTAssertEqual(Set(defaults.stringArray(forKey: PreferenceSync.enabledBundlesKey) ?? []), ["nostalgex", "kids"])
        XCTAssertEqual(store.writes.map(\.key), [PreferenceSync.retroModeKey])
    }

    func testQuotaViolationAppliesNothing() {
        let store = InMemoryKeyValueStore([PreferenceSync.retroModeKey: false])
        defaults.set(true, forKey: PreferenceSync.retroModeKey)
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)
        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreQuotaViolationChange,
                                  changedKeys: [PreferenceSync.retroModeKey])
        XCTAssertEqual(defaults.object(forKey: PreferenceSync.retroModeKey) as? Bool, true)
    }

    func testAccountChangeRepullsEverything() {
        let store = InMemoryKeyValueStore([PreferenceSync.subtitleLanguageKey: "de"])
        defaults.set("en", forKey: PreferenceSync.subtitleLanguageKey)
        defaults.set(true, forKey: PreferenceSync.retroModeKey)
        let sync = PreferenceSync(cloud: store, defaults: defaults, observeNotifications: false, keys: PreferenceSync.syncedKeys)
        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreAccountChange, changedKeys: [])
        XCTAssertEqual(defaults.string(forKey: PreferenceSync.subtitleLanguageKey), "de")
        XCTAssertEqual(store.values[PreferenceSync.retroModeKey] as? Bool, true, "seeds the new account")
    }
}

/// AppState wired to a fake store. AppState writes UserDefaults.standard directly, so the
/// synced keys are saved and restored around each test.
@MainActor
final class PreferenceSyncAppStateTests: XCTestCase {
    private var saved: [String: Any] = [:]
    private var store: InMemoryKeyValueStore!
    private var sync: PreferenceSync!
    private var state: AppState!

    override func setUp() {
        for key in PreferenceSync.syncedKeys + ["nostalgex_sync_plex_activity"] {
            if let v = UserDefaults.standard.object(forKey: key) { saved[key] = v }
        }
        store = InMemoryKeyValueStore()
        sync = PreferenceSync(cloud: store, defaults: .standard, observeNotifications: false, keys: PreferenceSync.syncedKeys)
        state = AppState(preferenceSync: sync)
    }

    override func tearDown() {
        state = nil
        for key in PreferenceSync.syncedKeys + ["nostalgex_sync_plex_activity"] {
            if let v = saved[key] { UserDefaults.standard.set(v, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    func testLocalChangesGoToICloudThroughTheExistingDidSets() {
        state.retroMode.toggle()
        state.preferredAudioLanguageCode = "ja"
        XCTAssertEqual(store.values[PreferenceSync.retroModeKey] as? Bool, state.retroMode)
        XCTAssertEqual(store.values[PreferenceSync.audioLanguageKey] as? String, "ja")
    }

    func testNeverSyncedPreferencesStayLocal() {
        state.syncPlexActivity.toggle()
        state.serverURL = "http://192.168.1.20:32400"
        state.token = "secret-token"
        let allowed = Set(PreferenceSync.syncedKeys)
        for write in store.writes { XCTAssertTrue(allowed.contains(write.key), write.key) }
        XCTAssertNil(store.values["nostalgex_sync_plex_activity"])
    }

    func testIncomingChangeIsAppliedWithoutEcho() {
        let target = !state.retroMode
        store.values[PreferenceSync.retroModeKey] = target
        store.values[PreferenceSync.subtitlesFullscreenKey] = true
        let writesBefore = store.writes.count

        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreServerChange,
                                  changedKeys: [PreferenceSync.retroModeKey, PreferenceSync.subtitlesFullscreenKey])

        XCTAssertEqual(state.retroMode, target)
        XCTAssertTrue(state.subtitlesInFullscreenEnabled)
        XCTAssertEqual(UserDefaults.standard.object(forKey: PreferenceSync.retroModeKey) as? Bool, target)
        XCTAssertEqual(store.writes.count, writesBefore, "an incoming value must not be written back to iCloud")
    }

    func testIncomingBundlesRebuildTheLineupLikeASettingsToggle() {
        func channel(_ id: Int) -> Channel {
            Channel(id: id, number: id, name: "CH\(id)", color: .blue, category: nil,
                    rules: nil, timeRestrictions: nil, minItems: 0, itemPool: [])
        }
        state.allChannels = [channel(1), channel(2)]
        state.bundles = [
            ChannelBundle(id: "nostalgex", name: "A", description: "", channelIDs: [1], activeMonths: nil, enabled: true),
            ChannelBundle(id: "kids", name: "B", description: "", channelIDs: [2], activeMonths: nil, enabled: false),
        ]
        state.enabledBundleIDs = ["nostalgex"]
        state.applyBundleFilter()
        XCTAssertEqual(state.channels.map(\.id), [1])
        let writesBefore = store.writes.count

        store.values[PreferenceSync.enabledBundlesKey] = ["nostalgex", "kids", "collections-from-other-server"]
        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreServerChange,
                                  changedKeys: [PreferenceSync.enabledBundlesKey])

        XCTAssertEqual(state.channels.map(\.id), [1, 2])
        XCTAssertTrue(state.bundles.allSatisfy(\.enabled))
        XCTAssertTrue(state.enabledBundleIDs.contains("collections-from-other-server"), "unknown ids are kept")
        XCTAssertEqual(store.writes.count, writesBefore)
    }

    func testIncomingCollectionIdsFromAnotherServerAreKeptButMatchNothing() {
        store.values[PreferenceSync.enabledCollectionsKey] = ["otherServer:99"]
        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreServerChange,
                                  changedKeys: [PreferenceSync.enabledCollectionsKey])
        XCTAssertEqual(state.enabledCollectionKeys, ["otherServer:99"])
        XCTAssertTrue(state.discoveredCollections.isEmpty)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: PreferenceSync.enabledCollectionsKey), ["otherServer:99"])
    }
}
