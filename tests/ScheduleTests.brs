' Runs source/schedule/DailyManifest.brs against tests/vectors/schedule.json,
' the golden vectors generated from upstream's engine. Prints each failure and
' a summary line, and returns the failure count. The same file runs in the
' off-device interpreter (tests/run.sh) and on a TV (scripts/deploy.sh --test).

function NxRunScheduleTests(vectorsPath as String) as Integer
    v = ParseJson(ReadAsciiFile(vectorsPath))
    if v = invalid then
        print "FAIL cannot read "; vectorsPath
        return 1
    end if
    r = { pass: 0, fail: 0 }

    for each c in v.rng.splitmix64
        NxCheck(r, "splitmix64(" + c.in.ToStr() + ")", NxHex64(NxSplitmix64(c.in)), c.out)
    end for
    for each c in v.rng.next
        rng = NxSeededRng(c.seed)
        for i = 0 to c.out.Count() - 1
            NxCheck(r, "next seed " + c.seed.ToStr() + " #" + i.ToStr(), NxHex64(NxRngNext(rng)), c.out[i])
        end for
    end for
    for each c in v.rng.bounded
        rng = NxSeededRng(c.seed)
        for i = 0 to c.bounds.Count() - 1
            got = NxRngBounded(rng, c.bounds[i])
            NxCheck(r, "bounded seed " + c.seed.ToStr() + " #" + i.ToStr(), got.ToStr(), c.out[i].ToStr())
        end for
    end for

    NxCheckOffsets(r, "swift ", v.swift.premiereOffset)
    NxCheckOffsets(r, "", v.premiereOffset)
    NxCheckOrders(r, "swift ", v.swift.order, v.fixtures.A)
    NxCheckOrders(r, "", v.order, v.fixtures.B)

    for each c in v.packDay
        aired = {}
        aired.SetModeCaseSensitive()
        for each k in c.aired
            aired[k] = true
        end for
        got = NxPackDay(v.fixtures[c.pool].pool, c.dayStart, c.day, c.channel, aired, c.premiere, c.last)
        parts = []
        for each b in got
            parts.Push(b.ratingKey + "@" + b.startSec.ToStr() + "-" + b.endSec.ToStr())
        end for
        NxCheck(r, "packDay " + c.name, parts.Join(","), c.blocks)
    end for

    print "schedule vectors (upstream "; Left(v.upstream.commit, 7); "): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

sub NxCheckOffsets(r as Object, label as String, cases as Object)
    for each key in cases
        sep = Instr(1, key, ":")
        ch = Left(key, sep - 1).ToInt()
        rk = Mid(key, sep + 1)
        NxCheck(r, label + "premiereOffset " + key, NxPremiereOffset(ch, rk).ToStr(), cases[key].ToStr())
    end for
end sub

' Keys are STAGE:seed:day. INTER interleaves; PROMO adds premieres; SEQ then
' groups sequels; SEQONLY groups sequels straight after the interleave.
sub NxCheckOrders(r as Object, label as String, cases as Object, fixture as Object)
    for each key in cases
        f = key.Split(":")
        seed = f[1].ToInt()
        day = f[2].ToInt()
        got = NxInterleaveByShow(fixture.pool, seed, day)
        if f[0] = "PROMO" or f[0] = "SEQ" then got = NxPromoteRecentlyAdded(got, fixture.dayStart, seed)
        if f[0] = "SEQ" or f[0] = "SEQONLY" then got = NxGroupSequelParts(got)
        keys = []
        for each item in got
            keys.Push(item.ratingKey)
        end for
        NxCheck(r, label + key, keys.Join(","), cases[key])
    end for
end sub

sub NxCheck(r as Object, name as String, got as String, want as String)
    if got = want then
        r.pass = r.pass + 1
    else
        r.fail = r.fail + 1
        print "FAIL "; name
        print "    want "; want
        print "    got  "; got
    end if
end sub

' Unsigned 16-digit hex of a 64-bit value.
function NxHex64(x as LongInteger) as String
    digits = "0123456789abcdef"
    s = ""
    for i = 1 to 16
        s = Mid(digits, (x and 15) + 1, 1) + s
        x = NxShr(x, 16&)
    end for
    return s
end function
