' Runs source/filter/ChannelFilter.brs against tests/vectors/filter.json, the
' golden vectors generated from upstream's filter: every channel, real and
' synthetic, over the generated library under each pinned clock (each with
' the backend it runs as), with the vendored membership manifest. Returns the
' failure count.

function NxRunFilterTests(vectorsPath as String, manifestPath as String) as Integer
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

    for each clock in v.clocks
        results = v.results[clock.name]
        for i = 0 to compiled.Count() - 1
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

    print "filter vectors (upstream "; Left(v.upstream.commit, 7); "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
