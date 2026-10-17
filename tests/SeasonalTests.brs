' Runs source/guide/SeasonalPrompt.brs, with the cases of upstream's
' SeasonalPromptTests.swift transcribed over an in-memory store. Returns the
' failure count.

function NxRunSeasonalTests() as Integer
    r = { pass: 0, fail: 0 }
    lineup = [
        { id: "nostalgex", activeMonths: invalid },
        { id: "seasonal", activeMonths: [10] },
        { id: "tis-the-season", activeMonths: [12] }
    ]
    store = NxSeasonalMemStore()
    offer = function(lineup, store, month, year, enabled = [] as Object) as String
        b = NxSeasonalOffer(lineup, enabled, month, year, store)
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
