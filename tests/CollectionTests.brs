' Runs source/collections/Collections.brs against tests/vectors/collections.json,
' made by upstream's scripts/nostalgex-collections.js, and the fold and
' library-load cases transcribed from upstream's CollectionShowsTests.swift
' and FranchiseSettingsTests.swift (at the commit in data/UPSTREAM). Returns
' the failure count.

function NxRunCollectionTests(vectorsPath as String, configPath as String, dictionaryPath as String) as Integer
    v = ParseJson(ReadAsciiFile(vectorsPath))
    config = ParseJson(ReadAsciiFile(configPath))
    defs = NxFranchiseDefinitions(ParseJson(ReadAsciiFile(dictionaryPath)))
    if v = invalid or config = invalid or defs.Count() = 0 then
        print "FAIL cannot read "; vectorsPath; ", "; configPath; " or "; dictionaryPath
        return 1
    end if
    r = { pass: 0, fail: 0 }

    NxCheck(r, "id base", NxCollectionsIDBase().ToStr(), NxToStr(v.constants.ID_BASE))
    NxCheck(r, "number base", NxCollectionsNumberBase().ToStr(), NxToStr(v.constants.NUMBER_BASE))
    NxCheck(r, "capacity", NxCollectionsCapacity().ToStr(), NxToStr(v.constants.CAPACITY))

    for each t in v.text
        NxCheck(r, "cleanTitle " + FormatJson(t.title), NxCollectionsCleanTitle(t.title), t.clean)
        NxCheck(r, "decade " + FormatJson(t.title), NxClOrNull(NxCollectionsDecade(t.clean)), NxClOrNull(t.decade))
    end for

    for each t in v.match
        stock = v.lineup
        if t.stock = "smoke" then stock = v.smokeStock
        if t.stock = "unnamed" then stock = [{ id: 7, name: "" }]
        NxCheck(r, "match " + t.stock + " " + FormatJson(t.title), NxClOrNull(NxCollectionsMatchStatic(t.title, stock)), NxClOrNull(t.label))
    end for

    for each c in v.overlap
        threshold = 60
        if c.threshold <> invalid then threshold = c.threshold
        got = NxCollectionsContentOverlap(c.items, c.manifest, NxClByID(c.channels), threshold)
        NxCheck(r, "overlap " + c.name, NxClOverlap(got), NxClOverlap(c.overlap))
    end for

    for each c in v.candidates
        NxClCheckCandidates(r, c)
    end for

    for each c in v.plex
        fetcher = NxClStubFetcher(c.docs)
        got = NxCollectionsFetchPlex("mid", fetcher)
        NxCheck(r, "plex calls " + c.name, fetcher.calls.Join(","), NxClJoin(c.calls))
        want = "throws"
        if type(c.out) = "roArray" then want = NxClRaw(c.out)
        have = "throws"
        if got <> invalid then have = NxClRaw(got)
        NxCheck(r, "plex out " + c.name, have, want)
    end for

    NxClSwiftCases(r, config, defs)

    print "collection cases (upstream vectors and Swift tests): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' One buildCandidates and materialize case. Items take their serverID as
' their serverIndex, so the index is keyed by it, as upstream's is.
sub NxClCheckCandidates(r as Object, c as Object)
    for each it in c.items
        it.serverIndex = it.serverID
    end for
    targets = []
    for each ch in c.franchiseChannels
        pool = []
        for each rf in ch.pool
            pool.Push({ serverIndex: rf.serverID, ratingKey: rf.ratingKey })
        end for
        targets.Push(NxCollectionFoldTarget(NxCollectionsChannelLabel(ch), pool, invalid, ch.id))
    end for
    channelsByID = invalid
    if c.channels <> invalid then channelsByID = NxClByID(c.channels)
    index = NxCollectionsIndexLibrary(c.items, {})
    list = NxCollectionsBuildCandidates(c.raw, index, {
        staticChannels: c.staticChannels, channelsByID: channelsByID, manifest: c.manifest,
        enabledKeys: NxCollectionKeySet(c.enabledKeys), foldTargets: targets, defs: []
    })
    label = "candidates " + c.name
    NxCheck(r, label + ": ids", NxClField(list, "id"), NxClField(c.candidates, "id"))
    if list.Count() <> c.candidates.Count() then return
    for i = 0 to list.Count() - 1
        got = list[i]
        want = c.candidates[i]
        at = label + " [" + want.id + "]"
        NxCheck(r, at + " title", got.title, want.title)
        NxCheck(r, at + " counts", NxClCounts(got), NxClCounts(want))
        keys = []
        for each it in got.items
            keys.Push(NxFranchiseItemKey(it))
        end for
        NxCheck(r, at + " items", keys.Join(","), NxClJoin(want.items))
        NxCheck(r, at + " enabled", NxClBool(got.enabled), NxClBool(want.enabled))
        NxCheck(r, at + " matchedChannel", NxClOrNull(got.matchedChannel), NxClOrNull(want.matchedChannel))
        NxCheck(r, at + " contentOverlap", NxClOverlap(got.contentOverlap), NxClOverlap(want.contentOverlap))
        NxCheck(r, at + " foldedInto", NxClOrNull(got.foldedInto), NxClOrNull(want.foldedInto))
        NxCheck(r, at + " warning", NxClOrNull(NxCollectionsDuplicateWarning(got)), NxClOrNull(want.warning))
        NxCheck(r, at + " summary", NxCollectionsMemberSummary(got), want.summary)
    end for
    m0 = NxCollectionsMaterialize(list)
    NxCheck(r, label + ": overCap", m0.overCap.ToStr(), NxToStr(c.materialized.overCap))
    NxCheck(r, label + ": channel count", m0.channels.Count().ToStr(), c.materialized.channels.Count().ToStr())
    if m0.channels.Count() <> c.materialized.channels.Count() then return
    for i = 0 to m0.channels.Count() - 1
        got = m0.channels[i]
        want = c.materialized.channels[i]
        keys = []
        for each it in got.pool
            keys.Push(NxFranchiseItemKey(it))
        end for
        NxCheck(r, label + ": channel " + i.ToStr(), NxClChannel(got.id, got.number, got.name, got.colorHex, got.minItems, got.enabled, got.collectionID, keys.Join(",")), NxClChannel(want.id, want.number, want.name, want.colorHex, want.minItems, want.enabled, want.collectionID, NxClJoin(want.pool)))
    end for
end sub

' ── Upstream's Swift cases ──────────────────────────────────────────────────

sub NxClSwiftCases(r as Object, config as Object, defs as Object)
    ' CollectionShowsTests.testShowCollectionDoesNotFoldIntoAFilmsOnlyFranchise
    films = [NxClFilm("m1", "Star Wars"), NxClFilm("m2", "The Empire Strikes Back"), NxClFilm("m3", "Return of the Jedi")]
    mando = NxClEpisodes("The Mandalorian", "s1", 4)
    filmsOnlyTarget = NxCollectionFoldTarget("STAR WARS", films, invalid, invalid)
    mixedItems = []
    mixedItems.Append(films)
    mixedItems.Append(mando)
    mixed = NxClCollection("mixed", "STAR WARS", mixedItems, "STAR WARS")
    NxCheck(r, "swift: a show the target lacks", NxClBool(NxCollectionCarriesEveryShow(mixed, filmsOnlyTarget)), "false")
    withShowItems = []
    withShowItems.Append(films)
    withShowItems.Push(mando[2])
    withShow = NxCollectionFoldTarget("STAR WARS", withShowItems, invalid, invalid)
    NxCheck(r, "swift: one episode of the show is enough", NxClBool(NxCollectionCarriesEveryShow(mixed, withShow)), "true")
    filmsOnly = NxClCollection("films", "STAR WARS", films, invalid)
    NxCheck(r, "swift: films-only collections fold as before", NxClBool(NxCollectionCarriesEveryShow(filmsOnly, filmsOnlyTarget)), "true")

    ' CollectionShowsTests.testFoldsKeepsAMixedCollectionWhoseShowsTheFranchiseLacks
    films = [NxClFilm("m1", "John Wick"), NxClFilm("m2", "John Wick: Chapter 2"), NxClFilm("m3", "Parabellum")]
    continental = NxClEpisodes("The Continental", "s1", 3)
    label = "CH 104 JOHN WICK"
    target = NxCollectionFoldTarget(label, films, invalid, 104)
    mixedItems = []
    mixedItems.Append(films)
    mixedItems.Append(continental)
    mixed = NxClCollection("mixed", "JOHN WICK", mixedItems, label)
    filmsOnly = NxClCollection("films", "JOHN WICK", films, label)
    NxCheck(r, "swift: films-only folds on the name match", NxClOrNull(NxCollectionFold(filmsOnly, [target], [])), label)
    NxCheck(r, "swift: the mix stays its own channel", NxClOrNull(NxCollectionFold(mixed, [target], [])), "null")
    airsItems = []
    airsItems.Append(films)
    airsItems.Append(continental)
    airsShow = NxCollectionFoldTarget(label, airsItems, invalid, 104)
    NxCheck(r, "swift: the mix folds once the channel airs the show", NxClOrNull(NxCollectionFold(mixed, [airsShow], [])), label)

    ' FranchiseSettingsTests.testCollectionThatIsAFranchiseIsHiddenFromBothLists,
    ' through the franchise step and the collections step as the library load
    ' runs them. Star Wars, John Wick and Tom Hanks films, with the fixture
    ' enrichment; three collections, all switched on.
    t = { config: config, defs: defs }
    items = NxFgFilms(NxFgStarWars())
    items.Append(NxFgFilms(NxFgWick()))
    items.Append(NxFgFilms(NxFgHanks()))
    raw = [
        NxClRaw0("c-sw", "STAR WARS COLLECTION", ["sw1", "sw2", "sw3"]),
        NxClRaw0("c-wick", "JOHN WICK COLLECTION", ["w1", "w2", "w3"]),
        NxClRaw0("c-hanks", "TOM HANKS", ["t1", "t2", "t3"])
    ]
    on = NxCollectionKeySet(["0:c-sw", "0:c-wick", "0:c-hanks"])
    s = NxFgStep(t, items, NxFranchiseChoices([], []))
    NxCheck(r, "swift fold: star wars is covered by CH 100", NxFgFoundNames(s), "JOHN WICK")
    cs = NxClStep(t, s, items, raw, on)
    NxCheck(r, "swift fold: star wars folds into the classic", NxClFoldedInto(cs, "STAR WARS COLLECTION"), "CH 100 STAR WARS")
    NxCheck(r, "swift fold: john wick folds into the found franchise", NxClFoldedInto(cs, "JOHN WICK COLLECTION"), "JOHN WICK")
    NxCheck(r, "swift fold: the actor set stays listed", NxClRowIDs(cs), "0:c-hanks")
    NxCheck(r, "swift fold: only the actor set becomes a channel", NxClChannelNames(cs), "TOM HANKS")
    NxCheck(r, "swift fold: from CH 500", NxClChannelNumbers(cs), "500")
    NxCheck(r, "swift fold: row shows its channel", NxToStr(cs.rows[0].channelNumber), "500")
    NxCheck(r, "swift fold: row detail", cs.rows[0].detail, "3 movies")
    ' Turning the found franchise on gives exactly one JOHN WICK channel.
    s = NxFgStep(t, items, NxFranchiseChoices(["dict:JOHN WICK"], []))
    cs = NxClStep(t, s, items, raw, on)
    NxCheck(r, "swift fold: john wick on, one channel", NxFgChannelNames(s) + "|" + NxClChannelNames(cs), "JOHN WICK|TOM HANKS")
    NxCheck(r, "swift fold: still folded while it is on", NxClFoldedInto(cs, "JOHN WICK COLLECTION"), "JOHN WICK")

    ' With the FRANCHISES package off there is nothing to fold into, so every
    ' collection is listed and the switched-on ones air.
    cs = NxCollectionsStep({ channels: NxClStockChannels(t, items), raw: raw, items: items, serverKeys: {}, manifest: invalid, enabledKeys: on })
    NxCheck(r, "package off: no folds", NxClRowIDs(cs), "0:c-wick,0:c-sw,0:c-hanks")
    NxCheck(r, "package off: three channels", NxClChannelNames(cs) + "|" + NxClChannelNumbers(cs), "JOHN WICK COLLECTION,STAR WARS COLLECTION,TOM HANKS|500,501,502")
    NxCheck(r, "package off: name match warns", cs.rows[1].detail, "Exists: CH 100 STAR WARS")

    ' FranchiseCollectionFold step 4: a collection whose name says nothing
    ' folds into a found franchise that already airs most of it.
    s = NxFgStep(t, items, NxFranchiseChoices([], []))
    cs = NxClStep(t, s, items, [NxClRaw0("c-keanu", "KEANU NIGHTS", ["w1", "w2", "w3", "t1"])], on)
    NxCheck(r, "swift fold: 3 of 4 already in JOHN WICK", NxClFoldedInto(cs, "KEANU NIGHTS"), "JOHN WICK")

    ' Collections that hold shows, through the step: a show expands to its
    ' episodes, a Plex child that is a show key.
    eps = NxClEpisodes("Alpha Island", "s1", 4)
    eps.Append(NxClEpisodes("Bravo Kitchen", "s2", 5))
    for each it in eps
        it.serverIndex = 0
    end for
    lib = []
    lib.Append(items)
    lib.Append(eps)
    cs = NxCollectionsStep({ channels: NxClStockChannels(t, lib), raw: [{ id: "mid:tv", title: "Reality TV", childKeys: ["s1", "s2"], serverKey: "mid" }], items: lib, serverKeys: { "0": "mid" }, manifest: invalid, enabledKeys: NxCollectionKeySet(["mid:tv"]) })
    NxCheck(r, "shows: server key from the map", NxClRowIDs(cs), "mid:tv")
    NxCheck(r, "shows: detail", cs.rows[0].detail, "2 shows " + Chr(183) + " 9 episodes")
    NxCheck(r, "shows: the channel airs every episode", cs.channels[0].pool.Count().ToStr(), "9")
end sub

' The stock channels of the FRANCHISES package, built as the library load
' builds them, with minItems.
function NxClStockChannels(t as Object, items as Object) as Object
    s = NxFgStep(t, items, NxFranchiseChoices([], []))
    for each ch in s.stock
        for each def in t.config.channels
            if def.id = ch.id then ch.minItems = def.minItems
        end for
    end for
    return s.stock
end function

function NxClStep(t as Object, s as Object, items as Object, raw as Object, on as Object) as Object
    bundleIDs = []
    for each b in t.config.bundles
        if b.id = NxFranchisesBundleID() then bundleIDs = b.channelIDs
    end for
    for each ch in s.stock
        for each def in t.config.channels
            if def.id = ch.id then ch.minItems = def.minItems
        end for
    end for
    channels = []
    channels.Append(s.stock)
    channels.Append(s.channels)
    return NxCollectionsStep({
        channels: channels, raw: raw, items: items, serverKeys: {}, manifest: invalid, enabledKeys: on,
        franchise: s, franchiseBundleIDs: bundleIDs, defs: t.defs
    })
end function

function NxClRaw0(id as String, title as String, childKeys as Object) as Object
    return { id: "0:" + id, title: title, childKeys: childKeys, serverKey: "0" }
end function

function NxClFoldedInto(cs as Object, title as String) as String
    for each f in cs.folded
        if f.title = title then return f.into
    end for
    return "null"
end function

function NxClRowIDs(cs as Object) as String
    out = []
    for each row in cs.rows
        out.Push(row.id)
    end for
    return out.Join(",")
end function

function NxClChannelNames(cs as Object) as String
    out = []
    for each ch in cs.channels
        out.Push(ch.name)
    end for
    return out.Join(",")
end function

function NxClChannelNumbers(cs as Object) as String
    out = []
    for each ch in cs.channels
        out.Push(ch.number.ToStr())
    end for
    return out.Join(",")
end function

' ── Fixtures, as CollectionShowsTests.swift has them ────────────────────────

function NxClFilm(key as String, title as String) as Object
    return { ratingKey: key, serverIndex: "", title: title, type: "movie", duration: 100, librarySource: "movie", genres: [] }
end function

' `count` episodes of one show, keys "<showKey>-e<n>".
function NxClEpisodes(show as String, showKey as String, count as Integer) as Object
    out = []
    for i = 1 to count
        out.Push({ ratingKey: showKey + "-e" + i.ToStr(), serverIndex: "", title: show, showKey: showKey, type: "episode", duration: 22, librarySource: "tv", genres: [] })
    end for
    return out
end function

function NxClCollection(id as String, title as String, items as Object, matched as Dynamic) as Object
    return { id: id, title: title, items: items, matchedChannel: matched, contentOverlap: invalid }
end function

' ── Comparison helpers ──────────────────────────────────────────────────────

function NxClStubFetcher(docs as Object) as Object
    return {
        docs: docs, calls: [],
        getJSON: function(path as String) as Dynamic
            m.calls.Push(path)
            if m.docs.DoesExist(path) then return m.docs[path]
            return invalid
        end function
    }
end function

function NxClByID(channels as Object) as Object
    out = {}
    for each ch in channels
        out[NxToStr(ch.id)] = ch
    end for
    return out
end function

function NxClOrNull(v as Dynamic) as String
    if v = invalid then return "null"
    return NxToStr(v)
end function

function NxClBool(b as Dynamic) as String
    if b = true then return "true"
    return "false"
end function

function NxClJoin(list as Dynamic) as String
    out = []
    for each x in NxList(list)
        out.Push(NxToStr(x))
    end for
    return out.Join(",")
end function

function NxClField(list as Object, field as String) as String
    out = []
    for each x in list
        out.Push(NxToStr(x[field]))
    end for
    return out.Join(",")
end function

function NxClCounts(c as Object) as String
    return NxToStr(c.movieCount) + "/" + NxToStr(c.showCount) + "/" + NxToStr(c.episodeCount)
end function

function NxClOverlap(o as Dynamic) as String
    if o = invalid then return "null"
    return NxToStr(o.channelID) + "|" + NxToStr(o.channelName) + "|" + NxToStr(o.overlapCount) + "|" + NxToStr(o.totalCount) + "|" + NxToStr(o.percent)
end function

function NxClChannel(id as Dynamic, number as Dynamic, name as Dynamic, colorHex as Dynamic, minItems as Dynamic, enabled as Dynamic, collectionID as Dynamic, pool as String) as String
    return NxToStr(id) + "|" + NxToStr(number) + "|" + NxToStr(name) + "|" + NxToStr(colorHex) + "|" + NxToStr(minItems) + "|" + NxClBool(enabled) + "|" + NxToStr(collectionID) + "|" + pool
end function

' Scanned collections as text.
function NxClRaw(list as Object) as String
    out = []
    for each c in list
        out.Push(NxToStr(c.id) + "=" + NxToStr(c.title) + "@" + NxToStr(c.serverKey) + "[" + NxClJoin(c.childKeys) + "]")
    end for
    return out.Join(";")
end function
