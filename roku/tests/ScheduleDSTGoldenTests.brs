' Runs upstream's scripts/schedule-dst-golden.json (copied unchanged to
' tests/vectors/), the vectors NostalgexTests/ScheduleDSTGoldenTests.swift and
' npm run test:schedule-dst also read, on the days the clocks change and the
' days around them in ten zones:
'   days: the day's start, the next day's start and yesterday's key;
'   fill: a full day of schedule from the day's start to the next midnight,
'         with no empty last hour and no hour run into tomorrow;
'   yesterday: the day after airs nothing the day before aired.
' tests/vectors/schedule-dst-zones.json holds each zone's UTC offsets over
' those dates, from the tz database, for the port to pin as LineupTests does.
' Returns the failure count.

function NxRunScheduleDSTGoldenTests(goldenPath as String, zonesPath as String) as Integer
    golden = ParseJson(ReadAsciiFile(goldenPath))
    tz = ParseJson(ReadAsciiFile(zonesPath))
    if golden = invalid or tz = invalid then
        print "FAIL cannot read "; goldenPath; " or "; zonesPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    g = GetGlobalAA()
    g.nxTzOffsetSec = invalid
    small = NxDSTGoldenPool(golden.pools.small)
    big = NxDSTGoldenPool(golden.pools.big)

    ' By index throughout: a nested `for each` over the same array shares its
    ' place on a TV.
    for i = 0 to golden.days.Count() - 1
        d = golden.days[i]
        name = d.zone + " " + d.date
        g.nxTzOffsets = tz.zones[d.zone]
        if g.nxTzOffsets = invalid then
            NxCheck(r, name + " has offsets", "no", "yes")
        else
            for each t in d.at
                day = NxLocalDay(t)
                got = day.dayKey + " " + day.dayStartSec.ToStr() + " " + NxStartOfNextLocalDaySec(t).ToStr() + " " + NxPreviousLocalDayKey(t)
                want = d.date + " " + d.start.ToStr() + " " + d.nextStart.ToStr() + " " + d.previous
                NxCheck(r, "days " + name + " at " + t.ToStr(), got, want)
            end for

            NxClearManifests()
            blocks = NxManifestBlocks({ id: 201 }, small, d.at[2])
            got = "empty"
            if blocks.Count() > 0 then
                holes = 0
                for k = 1 to blocks.Count() - 1
                    if blocks[k].startSec <> blocks[k - 1].endSec then holes = holes + 1
                end for
                got = blocks[0].startSec.ToStr() + "-" + blocks.Peek().endSec.ToStr() + ", " + holes.ToStr() + " holes or overlaps"
            end if
            NxCheck(r, "fill " + name, got, d.start.ToStr() + "-" + d.nextStart.ToStr() + ", 0 holes or overlaps")
        end if
    end for

    for i = 0 to golden.yesterday.Count() - 1
        y = golden.yesterday[i]
        name = "yesterday " + y.zone + " " + y.date
        g.nxTzOffsets = tz.zones[y.zone]
        before = NxDSTGoldenNoon(golden.days, y.zone, y.previous)
        after = NxDSTGoldenNoon(golden.days, y.zone, y.date)
        if g.nxTzOffsets = invalid or before = invalid or after = invalid then
            NxCheck(r, name + " has offsets and both days", "no", "yes")
        else
            NxClearManifests()
            aired = {}
            aired.SetModeCaseSensitive()
            for each b in NxManifestBlocks({ id: 203 }, big, before)
                aired[NxToStr(b.item.ratingKey)] = true
            end for
            repeats = 0
            for each b in NxManifestBlocks({ id: 203 }, big, after)
                if aired.DoesExist(NxToStr(b.item.ratingKey)) then repeats = repeats + 1
            end for
            got = "nothing aired the day before"
            if aired.Count() > 0 then got = "something aired the day before"
            NxCheck(r, name, got + ", " + repeats.ToStr() + " of it again", "something aired the day before, 0 of it again")
        end if
    end for

    g.nxTzOffsets = invalid
    NxClearManifests()
    print "schedule dst golden cases (upstream schedule-dst-golden.json):"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' The golden file's [ratingKey, title, type, minutes] rows as pool items.
function NxDSTGoldenPool(rows as Object) as Object
    pool = []
    for each row in rows
        pool.Push({ ratingKey: row[0], title: row[1], type: row[2], duration: row[3], addedAt: 0 })
    end for
    return pool
end function

' The golden day's midday instant (its third `at`), or invalid.
function NxDSTGoldenNoon(days as Object, zone as String, date as String) as Dynamic
    for i = 0 to days.Count() - 1
        if days[i].zone = zone and days[i].date = date then return days[i].at[2]
    end for
    return invalid
end function
