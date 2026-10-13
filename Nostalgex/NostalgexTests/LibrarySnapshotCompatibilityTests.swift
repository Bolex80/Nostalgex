import XCTest
@testable import Nostalgex

/// #21 added version and part fields to PlexMediaItem without bumping the snapshot
/// schema. A bump clears every user's snapshot and forces a full rescan, so these prove
/// a snapshot written before those fields existed still loads and plays as it did.
final class LibrarySnapshotCompatibilityTests: XCTestCase {
    private let identity = "snapshot-compat-test"
    private let addedKeys = ["mediaIndex", "partIndex", "playbackParts", "exactDurationSeconds"]

    override func setUp() {
        super.setUp()
        LibrarySnapshotStore.clear()
    }

    override func tearDown() {
        LibrarySnapshotStore.clear()
        super.tearDown()
    }

    private func snapshotURL() throws -> URL {
        try XCTUnwrap(LocalStore.rootDirectory).appendingPathComponent("library_snapshot_v1.json")
    }

    private func item(id: String) -> PlexMediaItem {
        PlexMediaItem(id: id, title: "T\(id)", artist: nil, episodeTitle: nil, seTag: nil, summary: "", year: 2020,
                      originallyAvailableAt: nil, contentRating: nil, duration: 180, ratingKey: id,
                      partKey: "/library/parts/\(id)/part1.mkv",
                      container: "mkv", videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 6000,
                      genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil, viewCount: 0, addedAt: 0,
                      studio: nil, tmdbID: nil, imdbID: nil, librarySource: .movie, serverID: "server-a",
                      additionalPartKeys: nil, videoBitDepth: 8, doviProfile: nil, videoWidth: 1920, videoHeight: 1080)
    }

    /// A three-part film on its third version, with every #21 field set.
    private func threePartFilm() -> PlexMediaItem {
        var film = item(id: "1")
        film.additionalPartKeys = ["/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"]
        film.mediaIndex = 2
        film.partIndex = 0
        film.playbackParts = ["/library/parts/1/part1.mkv", "/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"].map {
            PlexPartPlaybackInfo(key: $0, container: "mkv", videoCodec: "h264", audioCodec: "aac",
                                 bitDepth: 8, doviProfile: nil, durationSeconds: 60)
        }
        film.exactDurationSeconds = 180.5
        return film
    }

    private func save(_ items: [PlexMediaItem]) throws {
        try LibrarySnapshotStore.save(
            identity: identity, serverName: "Test", librarySignature: "sig",
            lastLoadAtUnix: Int(Date().timeIntervalSince1970), allItems: items,
            channelConfigChannels: [], allChannels: [], bundles: [], enabledBundleIDs: [],
            exclusiveRules: [], discoveredCollections: []
        )
    }

    func testSnapshotFromBeforeVersionAndPartFieldsStillLoads() throws {
        try save([threePartFilm(), item(id: "2")])

        // Strip the keys #21 added from every item. The pre-#21 encoder never wrote them,
        // so what is left is the shape of a snapshot already on a user's device.
        let url = try snapshotURL()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2, "the schema must match what pre-#21 builds wrote")
        let rows = try XCTUnwrap(json["allItems"] as? [[String: Any]])
        XCTAssertTrue(rows[0].keys.contains("mediaIndex"), "fixture sanity: the new keys were written and are being removed")
        json["allItems"] = rows.map { row in
            var legacy = row
            addedKeys.forEach { legacy.removeValue(forKey: $0) }
            return legacy
        }
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: identity),
                                   "an old snapshot must load, not force a rescan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "an old snapshot must not be cleared")
        XCTAssertEqual(loaded.snapshot.allItems.map(\.id), ["1", "2"])

        let film = loaded.snapshot.allItems[0]
        XCTAssertEqual(film.mediaIndex, 0)
        XCTAssertEqual(film.partIndex, 0)
        XCTAssertNil(film.playbackParts)
        XCTAssertNil(film.exactDurationSeconds)
        XCTAssertEqual(film.partKey, "/library/parts/1/part1.mkv")
        XCTAssertEqual(film.additionalPartKeys, ["/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"])
        XCTAssertEqual(film.serverID, "server-a")

        // Defaults reproduce pre-#21 behaviour: no part mapping without part lengths...
        let position = film.playbackPosition(at: 135)
        XCTAssertEqual(position.item.partKey, film.partKey)
        XCTAssertEqual(position.baseSeconds, 0)
        XCTAssertEqual(position.offsetSeconds, 135)
        // ...and the same first-version, first-part transcode request as before.
        let query = PlexAPIService.transcodeQueryItems(for: film, sessionID: "test", offsetSeconds: 12,
            isLocal: true, quality: .low, token: "synthetic", clientID: "synthetic", hevcCapable: true)
        XCTAssertEqual(query.first { $0.name == "mediaIndex" }?.value, "0")
        XCTAssertEqual(query.first { $0.name == "partIndex" }?.value, "0")
    }

    func testVersionAndPartFieldsSurviveTheSnapshot() throws {
        let original = threePartFilm()
        try save([original])

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: identity))
        let film = try XCTUnwrap(loaded.snapshot.allItems.first)
        XCTAssertEqual(film.mediaIndex, 2)
        XCTAssertEqual(film.partIndex, 0)
        XCTAssertEqual(film.playbackParts, original.playbackParts)
        XCTAssertEqual(film.exactDurationSeconds, 180.5)
        XCTAssertEqual(film.playbackPosition(at: 135).item.partKey, "/library/parts/1/part3.mkv")
    }
}
