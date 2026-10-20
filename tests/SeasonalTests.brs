' Runs source/guide/SeasonalPrompt.brs: the cases of upstream's
' SeasonalPromptTests.swift transcribed over an in-memory store, and
' upstream's scripts/season-golden.json (copied unchanged to tests/vectors/)
' over the shipped bundles. Returns the failure count.

function NxRunSeasonalTests(goldenPath as String, configPath as String) as Integer
    return NxRunSeasonalPromptCases() + NxRunSeasonGoldenTests(goldenPath, configPath)
end function

function NxRunSeasonalPromptCases() as Integer
    r = { pass: 0, fail: 0 }
    lineup = [
        { id: "nostalgex", activeMonths: invalid },
        { id: "seasonal", activeMonths: [10] },
        { id: "tis-the-season", activeMonths: [12] }
    ]
    store = NxSeasonalMemStore()
    offer = function(lineup, store, month, year, enabled = [] as Object) as String
        b = NxSeasonalOffer(lineup, enabled, { year: year, month: month, day: 15 }, store)
        if b = invalid then return "none"
        return b.id
    end function

    NxCheck(r, "SCREAM all October", offer(lineup, store, 10, 2026), "seasonal")
    NxCheck(r, "nothing in September", offer(lineup, store, 9, 2026), "none")
    NxCheck(r, "nothing in November", offer(lineup, store, 11, 2026), "none")
    NxCheck(r, "December's package", offer(lineup, store, 12, 2026), "tis-the-season")
    NxCheck(r, "never an enabled one", offer(lineup, store, 10, 2026, ["seasonal"]), "none")
    NxCheck(r, "yes turns it on", FormatJson(store.record("yes", "seasonal", 2026)), "true")
    NxCheck(r, "yes doesn't silence", offer(lineup, store, 10, 2026), "seasonal")
    NxCheck(r, "not now turns nothing on", FormatJson(store.record("notNow", "seasonal", 2026)), "false")
    NxCheck(r, "not now holds this October", offer(lineup, store, 10, 2026), "none")
    NxCheck(r, "asked again next October", offer(lineup, store, 10, 2027), "seasonal")
    store = NxSeasonalMemStore()
    store.record("never", "seasonal", 2026)
    NxCheck(r, "never, this year", offer(lineup, store, 10, 2026), "none")
    NxCheck(r, "never, next year", offer(lineup, store, 10, 2027), "none")
    NxCheck(r, "never, 2030", offer(lineup, store, 10, 2030), "none")
    NxCheck(r, "the other package alone", offer(lineup, store, 12, 2026), "tis-the-season")

    print "seasonal invite cases (upstream SeasonalPromptTests): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxSeasonalMemStore() as Object
    return {
        flags: {},
        isSilenced: function(id as String, year as Integer) as Boolean
            return m.flags.DoesExist("never_" + id) or m.flags.DoesExist(id + "_" + year.ToStr())
        end function,
        record: function(answer as String, id as String, year as Integer) as Boolean
            if answer = "yes" then return true
            if answer = "never" then m.flags["never_" + id] = true else m.flags[id + "_" + year.ToStr()] = true
            return false
        end function
    }
end function

' upstream's season-golden.json. `at` is a local wall-clock time; every rule
' reads only its date, so the zones the file lists all answer the same here.
function NxRunSeasonGoldenTests(goldenPath as String, configPath as String) as Integer
    golden = ParseJson(ReadAsciiFile(goldenPath))
    config = ParseJson(ReadAsciiFile(configPath))
    if golden = invalid or config = invalid then
        print "FAIL cannot read "; goldenPath; " or "; configPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    bundles = NxList(config.bundles)
    byId = {}
    for each b in bundles
        byId[b.id] = b
    end for

    for each c in golden.thanksgiving
        start = NxSeasonStartDate(byId["tis-the-season"], c.year)
        NxCheck(r, "Thanksgiving " + c.year.ToStr(), c.year.ToStr() + "-11-" + Right("0" + NxUsThanksgivingDay(c.year).ToStr(), 2), c.thanksgiving)
        NxCheck(r, "TIS THE SEASON starts " + c.year.ToStr(), NxSeasonDateStr(start), c.tisTheSeasonStart)
    end for
    for each c in golden.inSeason
        NxCheck(r, "in season: " + c.name, FormatJson(NxIsInSeason(NxSeasonCaseBundle(c, byId), NxSeasonAt(c.at))), FormatJson(c.want))
    end for
    none = NxSeasonalMemStore()
    for each c in golden.offer
        NxCheck(r, "offer: " + c.name, NxSeasonOfferId(bundles, NxList(c.on), c.at, none), NxSeasonIdOrNull(c.want))
    end for
    for each c in golden.lead
        want = []
        for each id in NxList(c.want)
            want.Append(NxList(byId[id].channelIDs))
        end for
        NxCheck(r, "lead: " + c.name, FormatJson(NxSeasonalLeadIds(bundles, NxList(c.on), NxSeasonAt(c.at))), FormatJson(want))
    end for
    for each a in golden.answers
        store = NxSeasonalMemStore()
        enabled = []
        for each st in a.steps
            now = NxSeasonAt(st.at)
            if st.answer <> invalid then
                if store.record(st.answer, st.bundle, now.year) then enabled.Push(st.bundle)
            else if st.silenced <> invalid then
                NxCheck(r, a.name + ": " + st.silenced + " silenced at " + st.at, FormatJson(store.isSilenced(st.silenced, now.year)), FormatJson(st.want))
            else
                NxCheck(r, a.name + ": offer at " + st.at, NxSeasonOfferId(bundles, enabled, st.at, store), NxSeasonIdOrNull(st.offer))
            end if
        end for
    end for
    for each c in golden.headline
        NxCheck(r, "headline at " + c.at, NxSeasonalHeadline(NxSeasonCaseBundle(c, byId), NxSeasonAt(c.at)), c.want)
    end for
    for each c in golden.label
        NxCheck(r, "label at " + c.at, UCase(NxSeasonSpotlightLabel(NxSeasonCaseBundle(c, byId), NxSeasonAt(c.at))), UCase(c.want))
    end for
    print "season golden cases (upstream season-golden.json): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' "2026-11-19T00:00" as { year, month, day }.
function NxSeasonAt(at as String) as Object
    return { year: Mid(at, 1, 4).ToInt(), month: Mid(at, 6, 2).ToInt(), day: Mid(at, 9, 2).ToInt() }
end function

function NxSeasonDateStr(d as Dynamic) as String
    if d = invalid then return "null"
    return d.year.ToStr() + "-" + Right("0" + d.month.ToStr(), 2) + "-" + Right("0" + d.day.ToStr(), 2)
end function

' A case's bundle: a shipped one by id, or `def` inline, as the smoke test's
' bundleFor fills it in.
function NxSeasonCaseBundle(c as Object, byId as Object) as Object
    if type(c.def) <> "roAssociativeArray" then return byId[c.bundle]
    b = { id: "def", name: "DEF", channelIDs: [1], activeMonths: invalid }
    b.Append(c.def)
    return b
end function

function NxSeasonOfferId(bundles as Object, enabled as Object, at as String, store as Object) as String
    b = NxSeasonalOffer(bundles, enabled, NxSeasonAt(at), store)
    if b = invalid then return "null"
    return b.id
end function

function NxSeasonIdOrNull(v as Dynamic) as String
    if v = invalid then return "null"
    return v
end function
