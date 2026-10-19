' Runs source/guide/Lineup.brs against tests/vectors/lineup.json: the daily
' pool shuffle, time-of-day restrictions, the pool fingerprint, and the
' session schedule cache across consecutive days. Pins the zone to UTC, as
' the vectors were made. Returns the failure count.

function NxRunLineupTests(vectorsPath as String) as Integer
    v = ParseJson(ReadAsciiFile(vectorsPath))
    if v = invalid then
        print "FAIL cannot read "; vectorsPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    g = GetGlobalAA()
    g.nxTzOffsetSec = 0

    for each c in v.shuffle
        part = []
        for i = 0 to c.n - 1
            part.Push(v.pool[i])
        end for
        NxCheck(r, "shuffle n=" + c.n.ToStr() + " at " + c.nowSec.ToStr(), NxLineupKeys(NxSeededShuffle(part, c.nowSec)), c.out)
    end for

    for each c in v.timeFilter
        got = NxTimeFilteredPool({ timeRestrictions: c.tr }, v.rated, c.hour)
        NxCheck(r, "timeFilter " + FormatJson(c.tr) + " hour " + c.hour.ToStr(), NxLineupKeys(got), c.out)
    end for

    for each c in v.fingerprint
        part = []
        for i = 0 to c.n - 1
            part.Push(v.pool[i])
        end for
        NxCheck(r, "fingerprint n=" + c.n.ToStr(), NxPoolFingerprint(part), c.out)
    end for

    NxClearManifests()
    stepNo = 0
    for each c in v.manifests
        stepNo = stepNo + 1
        if c.clear = true then
            NxClearManifests()
        else
            part = []
            for i = 0 to c.n - 1
                part.Push(v.pool[i])
            end for
            parts = []
            for each b in NxManifestBlocks(c.channel, part, c.atSec)
                parts.Push(NxToStr(b.item.ratingKey) + "@" + b.startSec.ToStr() + "-" + b.endSec.ToStr())
            end for
            NxCheck(r, "manifest stepNo " + stepNo.ToStr(), parts.Join(","), c.out)
            ' NxScheduleGuide's memo: filled on the first call, read on the second.
            memo = {}
            for pass = 1 to 2
                parts = []
                for each b in NxManifestBlocks(c.channel, part, c.atSec, memo)
                    parts.Push(NxToStr(b.item.ratingKey) + "@" + b.startSec.ToStr() + "-" + b.endSec.ToStr())
                end for
                NxCheck(r, "manifest stepNo " + stepNo.ToStr() + " memo pass " + pass.ToStr(), parts.Join(","), c.out)
            end for
        end if
    end for

    g.nxTzOffsetSec = invalid
    print "lineup vectors (upstream "; Left(v.upstream.commit, 7); "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxLineupKeys(items as Object) as String
    keys = []
    for each it in items
        keys.Push(NxToStr(it.ratingKey))
    end for
    return keys.Join(",")
end function
