' Franchise step benchmark, run by `tests/bench/run.sh franchise`: the
' FRANCHISES package's channels filtered from out/bench/library.json as
' buildGuide does, then NxFranchiseStep timed on its own. Prints the time and
' every result (found franchises, the channels and pools it leaves, Settings
' rows) as lines two runs can be diffed on.
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
    clock = NxFilterClock(1792195200&)

    bundleIDs = []
    for each b in config.bundles
        if b.id = NxFranchisesBundleID() then bundleIDs = b.channelIDs
    end for
    channels = []
    for each def in config.channels
        ch = { id: def.id, number: def.number, name: NxToStr(def.name), enabled: true, built: false, pool: [] }
        if NxHasValue(bundleIDs, def.id) then
            for each row in NxFilterPool(items, NxFilterChannel(def), manifest, exclusive, clock)
                ch.pool.Push(row.item)
            end for
            ch.built = true
            minItems = 50
            if NxTruthy(def.minItems) then minItems = def.minItems
            ch.enabled = ch.pool.Count() >= minItems
        end if
        channels.Push(ch)
    end for
    defs = NxFranchiseDefinitions(ParseJson(ReadAsciiFile("pkg:/data/franchises.json")))

    timer = CreateObject("roTimespan")
    fr = NxFranchiseStep({
        channels: channels, items: items, defs: defs,
        choices: NxFranchiseChoices([], []), bundleChannelIDs: bundleIDs,
        manifest: manifest, exclusiveRules: exclusive
    })
    ms = timer.TotalMilliseconds()

    for each f in fr.found
        print "FOUND "; f.id; " | "; f.name; " | "; NxToStr(f.coveredByChannelID); " | "; NxBenchKeys(f.movies); " | "; NxBenchKeys(f.tvItems)
    end for
    for each ch in fr.channels
        print "FCHANNEL "; FormatJson(ch.id); " "; FormatJson(ch.number); " "; ch.name; " "; NxBenchKeys(NxList(ch.pool))
    end for
    for each ch in channels
        if ch.built then print "STOCK "; ch.id.ToStr(); " "; ch.enabled.ToStr(); " "; NxBenchKeys(ch.pool)
    end for
    print "ROWS "; FormatJson(fr.rows)
    print "BENCH franchise step: "; fr.found.Count().ToStr(); " found in "; ms.ToStr(); " ms"
end sub

function NxBenchKeys(list as Object) as String
    parts = []
    for each it in list
        parts.Push(NxToStr(it.ratingKey))
    end for
    return parts.Join(",")
end function
