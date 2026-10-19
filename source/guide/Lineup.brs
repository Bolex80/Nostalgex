' Which channels the guide shows, in what order, and what each one airs.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: plex-tuner.html shuffleArray, getTimeFilteredPool,
' staticChannelIDsForPoolBuild, applyBundleFilter, sortChannelsForGuide,
' buildChannelSchedule, and nostalgex-daily-manifest.js getManifestBlocks
' with its day helpers and pool fingerprint. Checked against
' tests/vectors/lineup.json.
'
' Upstream clears its per-day schedule cache on every library load, which on
' the web is every page load, so the cache only ever lives for a session.
' Here it lives in memory (NxManifestCache) for the same reason, and the
' library load clears it the same way.

' ── Local time ──────────────────────────────────────────────────────────────

' { dayStartSec, dayKey, dayNumber } for the local day holding epochSec, as
' startOfLocalDayMs, localDayKey and localDayNumber. Tests pin the zone by
' setting GetGlobalAA().nxTzOffsetSec, or nxTzOffsets for a zone whose
' clocks change.
function NxLocalDay(epochSec as LongInteger) as Object
    dt = NxLocalClock(epochSec)
    secOfDay = NxClockSecOfDay(dt)
    dayStart& = epochSec - secOfDay
    ' On a day the clocks change, the clock's time since midnight is an hour
    ' off the real one, so look at what the clock says at that guess. Where
    ' midnight itself is skipped, the day starts at its first moment, as
    ' setHours(0, 0, 0, 0) has it.
    at = NxLocalClock(dayStart&)
    if NxClockSameDate(at, dt) then
        s = NxClockSecOfDay(at)
        if s > 0 and NxClockSameDate(NxLocalClock(dayStart& - s), dt) then dayStart& = dayStart& - s
    else
        dayStart& = dayStart& + 86400 - NxClockSecOfDay(at)
    end if
    key = dt.GetYear().ToStr() + "-" + NxPad2(dt.GetMonth()) + "-" + NxPad2(dt.GetDayOfMonth())
    return { dayStartSec: dayStart&, dayKey: key, dayNumber: NxFloorDivLong(dayStart&, 86400), hour: dt.GetHours(), month: dt.GetMonth() }
end function

' An roDateTime showing the local wall clock at epochSec. nxTzOffsets is
' [{ fromSec, offsetSec }] in time order, each offset holding from its
' fromSec on.
function NxLocalClock(epochSec as LongInteger) as Object
    g = GetGlobalAA()
    off = g.nxTzOffsetSec
    if type(g.nxTzOffsets) = "roArray" then
        for each z in g.nxTzOffsets
            if epochSec >= z.fromSec then off = z.offsetSec
        end for
    end if
    dt = CreateObject("roDateTime")
    if off <> invalid then
        dt.FromSeconds(epochSec + off)
    else
        dt.FromSeconds(epochSec)
        dt.ToLocalTime()
    end if
    return dt
end function

function NxClockSecOfDay(dt as Object) as Integer
    return dt.GetHours() * 3600 + dt.GetMinutes() * 60 + dt.GetSeconds()
end function

function NxClockSameDate(a as Object, b as Object) as Boolean
    return a.GetDayOfMonth() = b.GetDayOfMonth() and a.GetMonth() = b.GetMonth() and a.GetYear() = b.GetYear()
end function

function NxPad2(n as Integer) as String
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function NxFloorDivLong(a as LongInteger, b as LongInteger) as Integer
    q = a \ b
    if (a mod b) <> 0 and a < 0 then q = q - 1
    return q
end function

' ── Pools ───────────────────────────────────────────────────────────────────

' JS ToInt32.
function NxToInt32(x as LongInteger) as LongInteger
    r = x mod 4294967296&
    if r < 0 then r = r + 4294967296&
    if r >= 2147483648& then r = r - 4294967296&
    return r
end function

' Mirrors shuffleArray: a linear congruential shuffle seeded by the UTC day
' number (Date.now() / 86400000), so a pool holds still for a day. Returns
' a new array.
function NxSeededShuffle(arr as Object, nowSec as LongInteger) as Object
    shuffled = []
    shuffled.Append(arr)
    s& = nowSec \ 86400
    left = shuffled.Count()
    while left > 0
        s& = NxToInt32(s& * 1664525 + 1013904223)
        a& = s&
        if a& < 0 then a& = -a&
        i% = a& mod left ' an Integer: array indexes can't be LongInteger
        left = left - 1
        tmp = shuffled[left]
        shuffled[left] = shuffled[i%]
        shuffled[i%] = tmp
    end while
    return shuffled
end function

' Mirrors getTimeFilteredPool at a local hour (0-23).
function NxTimeFilteredPool(channel as Object, pool as Object, hour as Integer) as Object
    tr = channel.timeRestrictions
    if type(tr) <> "roAssociativeArray" then return pool
    out = pool

    br = tr.blockRatings
    if type(br) = "roAssociativeArray" then
        blocked = false
        if br.blockBefore <> invalid then
            if hour < br.blockBefore then blocked = true
        end if
        if br.blockAfter <> invalid then
            if hour >= br.blockAfter then blocked = true
        end if
        if blocked then
            filtered = []
            for each it in out
                if not NxHasValue(NxList(br.ratings), it.contentRating) then filtered.Push(it)
            end for
            if filtered.Count() >= 2 then out = filtered
        end if
    end if

    if tr.tvOnlyBefore <> invalid then
        if hour < tr.tvOnlyBefore then
            episodes = []
            for each it in out
                if it.type = "episode" then episodes.Push(it)
            end for
            if episodes.Count() >= 2 then out = episodes
        end if
    end if

    if tr.onlyAfterHour <> invalid then
        if hour < tr.onlyAfterHour then return []
    end if
    return out
end function

' ── Lineup ──────────────────────────────────────────────────────────────────

' Channel ids whose pools get built: those in switched-on bundles that are in
' season (staticChannelIDsForPoolBuild, as on any load after the first).
function NxPoolChannelIds(config as Object, enabledBundles as Object, month as Integer) as Object
    ids = {}
    for each b in NxList(config.bundles)
        if NxHasValue(enabledBundles, b.id) and NxBundleInSeason(b, month) then
            for each id in NxList(b.channelIDs)
                ids[id.ToStr()] = true
            end for
        end if
    end for
    return ids
end function

function NxBundleInSeason(bundle as Object, month as Integer) as Boolean
    if not NxTruthy(bundle.activeMonths) then return true
    return NxHasValue(NxList(bundle.activeMonths), month)
end function

' The guide's channels, in guide order: those in switched-on bundles
' (applyBundleFilter) and with enough items, seasonal packages that are on
' and in season first, the rest by number (sortChannelsForGuide).
' `channels` are channels.json entries with an `enabled` flag set.
function NxGuideOrder(config as Object, channels as Object, enabledBundles as Object, month as Integer) as Object
    inBundles = {}
    lead = []
    for each b in NxList(config.bundles)
        if NxHasValue(enabledBundles, b.id) then
            for each id in NxList(b.channelIDs)
                inBundles[id.ToStr()] = true
            end for
            if NxTruthy(b.activeMonths) and NxBundleInSeason(b, month) then
                for each id in NxList(b.channelIDs)
                    if not NxHasValue(lead, id) then lead.Push(id)
                end for
            end if
        end if
    end for

    leading = []
    for each id in lead
        for each ch in channels
            if ch.id = id and inBundles.DoesExist(ch.id.ToStr()) and ch.enabled then leading.Push(ch)
        end for
    end for
    rest = []
    for each ch in channels
        if inBundles.DoesExist(ch.id.ToStr()) and ch.enabled and not NxHasValue(lead, ch.id) then
            ' Stable insertion by number (chNum: number, else id).
            i = rest.Count()
            rest.Push(ch)
            while i > 0 and NxChNum(rest[i - 1]) > NxChNum(ch)
                rest[i] = rest[i - 1]
                i = i - 1
            end while
            rest[i] = ch
        end if
    end for
    leading.Append(rest)
    return leading
end function

function NxChNum(ch as Object) as Integer
    if NxTruthy(ch.number) then return ch.number
    return ch.id
end function

' ── Schedule ────────────────────────────────────────────────────────────────

' Mirrors poolFingerprint: a 32-bit string hash of the sorted ratingKeys.
function NxPoolFingerprint(pool as Object) as String
    keys = []
    for each it in pool
        keys.Push(NxToStr(it.ratingKey))
    end for
    keys.Sort()
    ' Over the bytes, in one pass: Mid() on a long string is slow enough that a
    ' character loop made a 1,000-item channel take most of a minute. Bytes
    ' equal JS UTF-16 code units for the ASCII ratingKeys Plex uses.
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(keys.Join(","))
    ' Kept unsigned mod 2^32 inside the loop and made signed once at the end,
    ' which gives what ToInt32 at every step would: a call per byte was most
    ' of the cost.
    h& = 0
    for each c in bytes
        h& = (h& * 31 + c) mod 4294967296&
    end for
    return NxToInt32(h&).ToStr()
end function

' The session's schedule cache: channelId_dayKey -> { fp, blocks }.
function NxManifestCache() as Object
    g = GetGlobalAA()
    if g.nxManifests = invalid then g.nxManifests = {}
    return g.nxManifests
end function

sub NxClearManifests()
    GetGlobalAA().nxManifests = {}
end sub

' The day's blocks for a channel as [{ item, startSec, endSec }]. Mirrors
' getManifestBlocks: reuse the day's schedule while the pool is unchanged,
' otherwise pack it fresh, skipping what aired yesterday.
' `memo`, when given, holds what depends only on the pool (its playable
' items, their lookup and its fingerprint) from an earlier call with the same
' pool: the fingerprint alone took most of a 30 s re-check at 120 channels.
function NxManifestBlocks(channel as Object, pool as Object, atSec as LongInteger, memo = invalid as Dynamic) as Object
    if memo <> invalid and memo.fp <> invalid then
        valid = memo.valid
        lookup = memo.lookup
        fp = memo.fp
    else
        valid = []
        lookup = {}
        lookup.SetModeCaseSensitive()
        for each it in pool
            if it <> invalid and NxDuration(it) > 0 then
                valid.Push(it)
                lookup[NxToStr(it.ratingKey)] = it
            end if
        end for
        fp = invalid
        if valid.Count() > 0 then fp = NxPoolFingerprint(valid)
        if memo <> invalid then
            memo.valid = valid
            memo.lookup = lookup
            memo.fp = fp
        end if
    end if
    if valid.Count() = 0 then return []

    day = NxLocalDay(atSec)
    cache = NxManifestCache()
    key = channel.id.ToStr() + "_" + day.dayKey
    cached = cache[key]
    if cached = invalid or cached.fp <> fp then
        yesterday = cache[channel.id.ToStr() + "_" + NxLocalDay(day.dayStartSec - 86400).dayKey]
        aired = {}
        aired.SetModeCaseSensitive()
        last = invalid
        if yesterday <> invalid then
            for each b in yesterday.blocks
                aired[b.ratingKey] = true
            end for
            if yesterday.blocks.Count() > 0 then last = yesterday.blocks.Peek().ratingKey
        end if
        packed = NxPackDay(valid, day.dayStartSec, day.dayNumber, channel.id, aired, NxTruthy(channel.isPremiereChannel), last)
        cached = { fp: fp, blocks: packed }
        cache[key] = cached
    end if

    out = []
    for each b in cached.blocks
        it = lookup[b.ratingKey]
        if it <> invalid then out.Push({ item: it, startSec: b.startSec, endSec: b.endSec })
    end for
    return out
end function

' The block on air at nowSec, as buildChannelSchedule finds it: the one
' spanning now, else the latest that has started. Its index, or -1.
function NxNowBlockIndex(blocks as Object, nowSec as LongInteger) as Integer
    for i = 0 to blocks.Count() - 1
        if nowSec >= blocks[i].startSec and nowSec < blocks[i].endSec then return i
    end for
    best = -1
    for i = 0 to blocks.Count() - 1
        if nowSec >= blocks[i].startSec then
            if best = -1 then
                best = i
            else if blocks[i].startSec > blocks[best].startSec then
                best = i
            end if
        end if
    end for
    return best
end function

' What the guide prints for an item (itemDisplayLine).
function NxGuideTitle(item as Object) as String
    if item.librarySource = "musicVideo" then
        if NxTruthy(item.artist) then return NxToStr(item.artist) + " — " + NxToStr(item.title)
        return NxToStr(item.title)
    end if
    if NxTruthy(item.episodeTitle) then return NxToStr(item.title) + ": " + NxToStr(item.episodeTitle)
    return NxToStr(item.title)
end function
