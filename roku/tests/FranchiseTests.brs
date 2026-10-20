' Runs source/franchise/FranchiseBuilder.brs against upstream's golden file,
' tests/vectors/franchise-golden.json (vendored unchanged, read here as
' upstream's scripts/nostalgex-franchise-smoke.mjs reads it), and against
' tests/vectors/franchise.json, the text and ordering edges generated from
' upstream's builder. Returns the failure count.

function NxRunFranchiseTests(goldenPath as String, vectorsPath as String, dictionaryPath as String) as Integer
    golden = ParseJson(ReadAsciiFile(goldenPath))
    v = ParseJson(ReadAsciiFile(vectorsPath))
    dictionary = ParseJson(ReadAsciiFile(dictionaryPath))
    if golden = invalid or v = invalid or dictionary = invalid then
        print "FAIL cannot read "; goldenPath; ", "; vectorsPath; " or "; dictionaryPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    defs = NxFranchiseDefinitions(dictionary)

    ' The dictionary file itself, as upstream's smoke test checks it.
    names = {}
    names.SetModeCaseSensitive()
    ids = {}
    idCount = 0
    for each d in defs
        names[d.canonicalName] = true
        for each id in d.tmdbCollectionIDs
            ids[id.ToStr()] = true
            idCount = idCount + 1
        end for
    end for
    NxCheck(r, "franchises.json: 19 definitions", defs.Count().ToStr(), "19")
    NxCheck(r, "franchises.json: unique names", names.Count().ToStr(), "19")
    NxCheck(r, "franchises.json: verified header", NxToStr(dictionary.verified), "2026-10-11")
    NxCheck(r, "franchises.json: no collection id claimed twice", ids.Count().ToStr(), idCount.ToStr())
    on = NxFranchiseDefaultOnIDs(defs)
    on.Sort()
    NxCheck(r, "franchises.json: default-on ids", on.Join(","), "dict:FAST & FURIOUS,dict:STAR TREK")
    NxCheck(r, "default-on ids in dictionary order", NxFranchiseDefaultOnIDs(defs).Join(","), v.defaultOn.Join(","))

    for each c in golden.cases
        NxFranchiseCheckCase(r, "golden", c, defs)
    end for
    for each t in golden.titleKeys
        NxCheck(r, "golden titleKey " + FormatJson(t.title), NxFranchiseTitleKey(t.title), t.key)
    end for
    for each t in golden.filmMatches
        def = NxFranchiseMatchFilm(t.title, defs)
        got = "null"
        if def <> invalid then got = def.canonicalName
        want = "null"
        if t.franchise <> invalid then want = t.franchise
        NxCheck(r, "golden filmMatch " + FormatJson(t.title), got, want)
    end for
    for each t in golden.mergeKeys
        NxCheck(r, "golden mergeKey " + FormatJson(t.name), NxFranchiseMergeKey(t.name), t.key)
    end for
    for each f in golden.collectionFolds
        NxFranchiseCheckFold(r, "golden collectionFold " + f.about, f, defs)
    end for

    for each t in v.text
        NxCheck(r, "normalizedTitle " + FormatJson(t.title), NxFranchiseNormalizedTitle(t.title), t.normalized)
        NxCheck(r, "titleKey " + FormatJson(t.title), NxFranchiseTitleKey(t.title), t.key)
    end for
    for each t in v.tokens
        got = "false"
        if NxFranchiseContainsToken(t.title, t.token) then got = "true"
        want = "false"
        if t.out then want = "true"
        NxCheck(r, "containsToken " + FormatJson(t.title) + " " + FormatJson(t.token), got, want)
    end for
    for each t in v.names
        NxCheck(r, "cleanName " + FormatJson(t.name), NxFranchiseCleanName(t.name), t.clean)
        NxCheck(r, "stripParenthetical " + FormatJson(t.name), NxFranchiseStripParenthetical(t.name), t.strip)
        NxCheck(r, "mergeKey " + FormatJson(t.name), NxFranchiseMergeKey(t.name), t.merge)
    end for
    for each c in v.cases
        NxFranchiseCheckCase(r, "edge", c, defs)
    end for
    for each f in v.collectionFolds
        NxFranchiseCheckFold(r, "collectionFold " + FormatJson(f.availableStockChannelIDs), f, defs)
    end for

    print "franchise vectors (upstream "; Left(v.upstream.commit, 7); "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

sub NxFranchiseCheckCase(r as Object, label as String, c as Object, defs as Object)
    caseDefs = defs
    if c.definitions <> invalid then caseDefs = NxFranchiseDefinitions(c.definitions)
    got = NxFranchiseBuild({
        movies: c.movies,
        tvItems: c.tvItems,
        defs: caseDefs,
        availableStockChannelIDs: c.availableStockChannelIDs,
        minimumFilms: c.minimumFilms
    })
    gotRows = []
    for each g in got
        gotRows.Push(NxFranchiseGroupingRow(g, true))
    end for
    wantRows = []
    for each g in c.expected
        wantRows.Push(NxFranchiseGroupingRow(g, false))
    end for
    NxCheck(r, label + " case " + c.name, gotRows.Join(" / "), wantRows.Join(" / "))
end sub

' One grouping as text. Built groupings hold items; expected ones hold ids.
function NxFranchiseGroupingRow(g as Object, holdsItems as Boolean) as String
    placement = g.placement.type
    if placement = "stock" then placement = placement + " " + NxToStr(g.placement.channelID)
    movies = []
    for each x in g.movies
        if holdsItems then movies.Push(x.id) else movies.Push(x)
    end for
    tv = []
    for each x in g.tvItems
        if holdsItems then tv.Push(x.id) else tv.Push(x)
    end for
    ids = []
    for each x in g.mergedFranchiseIDs
        ids.Push(NxToStr(x))
    end for
    return g.name + " | " + g.stableID + " | " + placement + " | movies " + movies.Join(",") + " | tv " + tv.Join(",") + " | ids " + ids.Join(",") + " | dict " + NxToStr(g.fromDictionary)
end function

sub NxFranchiseCheckFold(r as Object, label as String, f as Object, defs as Object)
    got = NxFranchiseCollectionStockChannel(f.items, defs, f.availableStockChannelIDs)
    gotStr = "null"
    if got <> invalid then gotStr = got.ToStr()
    want = "null"
    if f.stockChannelID <> invalid then want = NxToStr(f.stockChannelID)
    NxCheck(r, label, gotStr, want)
end sub
