' Runs NxAutoEnableCandidates and NxBundlesWithContent
' (source/guide/BundleChoices.brs) against upstream's autoEnableBundlesWithContent
' (#60): a first run whose packages fill no channel switches on every other
' package with content, never a seasonal or collection one. The last cases
' run the real filter over a 20-film library against data/channels.json.
' Returns the failure count.

function NxRunSmallLibraryTests(configPath as String, manifestPath as String) as Integer
    r = { pass: 0, fail: 0 }
    config = ParseJson(ReadAsciiFile(configPath))
    manifest = ParseJson(ReadAsciiFile(manifestPath))

    fake = [{ id: "a", channelIDs: [1, 2] }, { id: "b", channelIDs: [3] }, { id: "season", channelIDs: [4], activeMonths: [10] }, { id: "collections-x", channelIDs: [5] }, { id: "c", channelIDs: [6] }]
    NxCheck(r, "candidates: not on, not seasonal, not collections", FormatJson(NxAutoEnableCandidates(fake, ["a"])), FormatJson(["b", "c"]))
    chans = [{ id: 1, built: true, enabled: false }, { id: 3, built: true, enabled: true }, { id: 4, built: true, enabled: true }, { id: 6, built: false, enabled: true }]
    NxCheck(r, "with content: a channel with enough items", FormatJson(NxBundlesWithContent(fake, ["b", "c"], chans)), FormatJson(["b"]))
    NxCheck(r, "nothing with content", FormatJson(NxBundlesWithContent(fake, ["c"], chans)), "[]")

    cands = NxAutoEnableCandidates(config.bundles, ["nostalgex"])
    NxCheck(r, "real packages: seasonal ones never", FormatJson(NxHasValue(cands, "seasonal") or NxHasValue(cands, "tis-the-season")), "false")
    NxCheck(r, "real packages: the rest", FormatJson(NxHasValue(cands, "kids") and NxHasValue(cands, "truecrime") and not NxHasValue(cands, "nostalgex")), "true")

    ' A 20-film library: true-crime documentaries only.
    items = []
    for i = 1 to 20
        items.Push({ ratingKey: "d" + i.ToStr(), title: "Case File " + i.ToStr(), type: "movie", librarySource: "movie", genres: ["Documentary", "Crime"], year: 2000 + i, contentRating: "TV-14", duration: 90, summary: "A true crime documentary about a murder investigation.", rating: 7, userRating: 0, viewCount: 0, addedAt: 0, studio: "", originallyAvailableAt: invalid, tmdbID: invalid })
    end for
    built = NxSmallLibraryBuild(items, config, manifest)
    nostalgex = NxBundlesWithContent(config.bundles, ["nostalgex"], built)
    NxCheck(r, "20 documentaries fill no NOSTALGEX channel", FormatJson(nostalgex), "[]")
    turnedOn = NxBundlesWithContent(config.bundles, cands, built)
    print "  small library switches on: "; FormatJson(turnedOn)
    ' Which packages they fill follows data/channels.json (ESSENTIALS today);
    ' at least one does, so the guide isn't empty.
    NxCheck(r, "20 documentaries switch on a package", FormatJson(turnedOn.Count() > 0), "true")
    NxCheck(r, "and no seasonal package", FormatJson(NxHasValue(turnedOn, "seasonal") or NxHasValue(turnedOn, "tis-the-season")), "false")

    print "small library cases (upstream autoEnableBundlesWithContent): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' Every channel of data/channels.json through the real filter, as buildGuide
' builds them: built, and enabled when its pool reaches minItems.
function NxSmallLibraryBuild(items as Object, config as Object, manifest as Object) as Object
    exclusive = NxFilterExclusiveRules(config.exclusiveRules)
    clock = NxFilterClock()
    out = []
    for each def in config.channels
        n = NxFilterPool(items, NxFilterChannel(def), manifest, exclusive, clock, "plex").Count()
        minItems = 50
        if NxTruthy(def.minItems) then minItems = def.minItems
        out.Push({ id: def.id, built: true, enabled: n >= minItems })
    end for
    return out
end function
