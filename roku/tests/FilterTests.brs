' Runs source/filter/ChannelFilter.brs against tests/vectors/filter.json, the
' golden vectors generated from upstream's filter: every channel, real and
' synthetic, over the generated library under each pinned clock (each with
' the backend it runs as), with the vendored membership manifest. Returns the
' failure count.
'
' `shard` ({ index, count }, from tests/run.sh) checks only the channels whose
' position is `index` mod `count`, so several interpreters split the work;
' invalid checks them all, as on a TV.

function NxRunFilterTests(vectorsPath as String, manifestPath as String, shard = invalid as Dynamic) as Integer
    timer = CreateObject("roTimespan")
    v = ParseJson(ReadAsciiFile(vectorsPath))
    manifest = ParseJson(ReadAsciiFile(manifestPath))
    print "  filter: parsing vectors and manifest took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    evaluations = 0
    if v = invalid or manifest = invalid then
        print "FAIL cannot read "; vectorsPath; " or "; manifestPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    exclusive = NxFilterExclusiveRules(v.exclusiveRules)
    compiled = []
    for each c in v.channels
        compiled.Push(NxFilterChannel(c))
    end for

    shardIndex = 0
    shardCount = 1
    if shard <> invalid then
        shardIndex = shard.index
        shardCount = shard.count
    end if
    for each clock in v.clocks
        results = v.results[clock.name]
        for i = shardIndex to compiled.Count() - 1 step shardCount
            parts = []
            evaluations = evaluations + v.items.Count()
            for each row in NxFilterPool(v.items, compiled[i], manifest, exclusive, clock, clock.backend)
                parts.Push(row.item.ratingKey + ":" + row.via)
            end for
            label = "filter clock " + clock.name + " channel " + NxToStr(v.channels[i].id) + " (#" + i.ToStr() + ")"
            NxCheck(r, label, parts.Join(","), results[i])
        end for
    end for

    ms = timer.TotalMilliseconds()
    print "  filter: "; evaluations; " item-channel evaluations took "; ms; " ms"

    ' The interpreter's ParseJson folds key case, so `guid` and `Guid` become one
    ' key there. A TV keeps them apart, and a TV that didn't would fail here.
    folds = ParseJson("{""k"": 1, ""K"": 2}").Count() = 1
    for each c in v.parseTmdbIdFromPlex
        if shardIndex <> 0 then exit for
        if NxTruthy(c.bothCases) and folds and NxTestRuntime() = "interpreter" then
            print "  skip parseTmdbIdFromPlex with guid and Guid: this interpreter folds JSON key case"
        else
            got = NxParseTmdbIdFromPlex(c.raw, c.isEpisode)
            want = "null"
            if c.out <> invalid then want = c.out.ToStr()
            gotStr = "null"
            if got <> invalid then gotStr = got.ToStr()
            NxCheck(r, "parseTmdbIdFromPlex " + FormatJson(c.raw), gotStr, want)
        end if
    end for

    which = ""
    if shardCount > 1 then which = ", channels " + shardIndex.ToStr() + " mod " + shardCount.ToStr()
    print "filter vectors (upstream "; Left(v.upstream.commit, 7); which; "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
