' Runs source/filter/ChannelFilter.brs against tests/vectors/filter.json, the
' golden vectors generated from upstream's filter: every channel, real and
' synthetic, over the generated library under each pinned clock, with the
' vendored membership manifest. Returns the failure count.

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
            for each row in NxFilterPool(v.items, compiled[i], manifest, exclusive, clock)
                parts.Push(row.item.ratingKey + ":" + row.via)
            end for
            label = "filter clock " + clock.name + " channel " + NxToStr(v.channels[i].id) + " (#" + i.ToStr() + ")"
            NxCheck(r, label, parts.Join(","), results[i])
        end for
    end for

    ms = timer.TotalMilliseconds()
    print "  filter: "; evaluations; " item-channel evaluations took "; ms; " ms"

    for each c in v.parseTmdbIdFromPlex
        got = NxParseTmdbIdFromPlex(c.raw, c.isEpisode)
        want = "null"
        if c.out <> invalid then want = c.out.ToStr()
        gotStr = "null"
        if got <> invalid then gotStr = got.ToStr()
        NxCheck(r, "parseTmdbIdFromPlex " + FormatJson(c.raw), gotStr, want)
    end for

    print "filter vectors (upstream "; Left(v.upstream.commit, 7); "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
