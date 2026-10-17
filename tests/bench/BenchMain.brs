' Channel build benchmark, run by tests/bench/run.sh: the library from
' out/bench/library.json (tests/bench/dump-library.mjs), its enrichment
' attached as the TV attaches it, then every channel's pool filtered as
' LibraryTask's buildGuide does. Prints the time and, per channel, the pool
' as "ratingKey:via" so two runs can be diffed for an identical build.
sub Main(args = invalid as Dynamic)
    lib = ParseJson(ReadAsciiFile("pkg:/out/bench/library.json"))
    items = lib.items
    records = {}
    for each row in lib.enrichmentRows
        e = NxEnrichFromSupabaseRow(row, 0&)
        if e <> invalid and not records.DoesExist(e.tmdbID) then records[e.tmdbID] = e
    end for
    NxEnrichAttach(items, records)
    config = ParseJson(ReadAsciiFile("pkg:/data/channels.json"))
    manifest = ParseJson(ReadAsciiFile("pkg:/data/channels-memberships.json"))
    exclusive = NxFilterExclusiveRules(config.exclusiveRules)
    ' A fixed instant, so year and date rules give the same answer every run.
    clock = NxFilterClock(1792195200&)

    timer = CreateObject("roTimespan")
    pools = []
    for each def in config.channels
        pools.Push({ id: def.id, rows: NxFilterPool(items, NxFilterChannel(def), manifest, exclusive, clock) })
    end for
    ms = timer.TotalMilliseconds()

    for each p in pools
        parts = []
        for each row in p.rows
            parts.Push(NxToStr(row.item.ratingKey) + ":" + row.via)
        end for
        print "POOL "; p.id.ToStr(); " "; p.rows.Count().ToStr(); " "; parts.Join(",")
    end for
    print "BENCH "; items.Count().ToStr(); " items, "; pools.Count().ToStr(); " channels in "; ms.ToStr(); " ms"
end sub
