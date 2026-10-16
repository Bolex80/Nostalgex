' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "loadLibrary"
end sub

' The saved guide: the last build's output, reused only while a fresh build
' would give the same thing (same local day and UTC day, since upstream's
' pool shuffle is seeded by the UTC day, same packages, same servers on,
' same app version).
' It holds titles and schedules, nothing secret.
function NxGuideCachePath() as String
    return "cachefs:/nostalgex-guide.json"
end function

function NxGuideCacheKey(nowSec as LongInteger, bundles as Object) as String
    info = CreateObject("roAppInfo")
    return info.GetVersion() + "|" + (nowSec \ 86400).ToStr() + "|" + NxLocalDay(nowSec).dayKey + "|" + FormatJson(bundles) + "|" + FormatJson(NxFranchiseChoiceLists(NxSavedFranchiseChoices())) + "|" + NxSavedServersOnKey()
end function

' The servers on (source/plex/ServerChoice.brs), as the cache keys hold them.
function NxSavedServersOnKey() as String
    reg = NxPlexRegistry()
    servers = ParseJson(reg.Read("servers"))
    if type(servers) <> "roArray" then return ""
    return NxServersOnKey(servers, NxSavedServerChoices())
end function

' The saved pools: each guide channel's pool as the last build filtered it,
' before the shuffle, with the items they hold. Filtering is most of a build
' (over a minute on a TV), and a pool rarely changes from one day to the
' next, so when the saved guide is a day old these are shuffled and
' scheduled for today instead, in seconds, and the full build still runs
' behind them. Kept while the app version, month (seasonal packages),
' packages, franchise choices and servers on are the same.
function NxPoolCachePath() as String
    return "cachefs:/nostalgex-pools.json"
end function

function NxPoolCacheKey(month as Integer, bundles as Object) as String
    info = CreateObject("roAppInfo")
    return info.GetVersion() + "|" + month.ToStr() + "|" + FormatJson(bundles) + "|" + FormatJson(NxFranchiseChoiceLists(NxSavedFranchiseChoices())) + "|" + NxSavedServersOnKey()
end function

' Written in pieces: one FormatJson of every pooled item, on top of the
' library itself, ran a Roku Stick Plus out of memory with 45 channels on
' (EXIT_CHANNEL_MEM_LIMIT_FG, Discussion #8). Each item is copied, without
' its filter cache, only for as long as it takes to format it.
sub NxSavePools(ordered as Object, guide as Object, month as Integer)
    path = NxPoolCachePath()
    WriteAsciiFile(path, "{""key"":" + FormatJson(NxPoolCacheKey(month, guide.enabledBundles)) + ",""items"":[")
    index = {}
    count = 0
    parts = []
    chans = []
    for each ch in ordered
        saved = {}
        for each k in ch
            if k <> "pool" and k <> "basePool" then saved[k] = ch[k]
        end for
        pool = ch.basePool
        if pool = invalid then pool = ch.pool
        idx = []
        for each it in pool
            id = NxToStr(it.ratingKey) + "@" + NxToStr(it.serverIndex)
            n = index[id]
            if n = invalid then
                n = count
                count = count + 1
                index[id] = n
                copy = {}
                for each k in it
                    if k <> "nxFilter" then copy[k] = it[k]
                end for
                text = FormatJson(copy)
                if n > 0 then text = "," + text
                parts.Push(text)
                if parts.Count() >= 500 then NxAppendText(path, parts)
            end if
            idx.Push(n)
        end for
        saved.poolIdx = idx
        chans.Push(saved)
    end for
    parts.Push("],""channels"":" + FormatJson(chans))
    parts.Push(",""libraryItems"":" + FormatJson(guide.items))
    parts.Push(",""bundles"":" + FormatJson(guide.bundles))
    parts.Push(",""franchises"":" + FormatJson(guide.franchises) + "}")
    NxAppendText(path, parts)
end sub

' Appends the pieces to the file, UTF-8, and empties the list.
sub NxAppendText(path as String, parts as Object)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(parts.Join(""))
    bytes.AppendFile(path)
    parts.Clear()
end sub

' The guide from the saved pools, as { ordered, guide }, or invalid when
' there are none for this key.
function NxGuideFromSavedPools(nowSec as LongInteger, month as Integer, bundles as Object) as Dynamic
    if not CreateObject("roFileSystem").Exists(NxPoolCachePath()) then return invalid
    saved = ParseJson(ReadAsciiFile(NxPoolCachePath()))
    if type(saved) <> "roAssociativeArray" then return invalid
    if saved.key <> NxPoolCacheKey(month, bundles) or type(saved.channels) <> "roArray" or type(saved.items) <> "roArray" then return invalid
    ordered = []
    for each ch in saved.channels
        pool = []
        for each n in ch.poolIdx
            pool.Push(saved.items[n])
        end for
        ch.Delete("poolIdx")
        if NxTruthy(ch.built) then pool = NxSeededShuffle(pool, nowSec)
        ch.pool = pool
        ordered.Push(ch)
    end for
    NxClearManifests()
    guide = {
        channels: NxScheduleGuide(ordered, nowSec), builtAt: nowSec, items: saved.libraryItems,
        bundles: saved.bundles, enabledBundles: bundles, franchises: saved.franchises
    }
    return { ordered: ordered, guide: guide }
end function

sub loadLibrary()
    m.top.status = "loading"
    timer = CreateObject("roTimespan")
    shown = false
    if m.top.useCache then
        clock0 = NxFilterClock()
        raw = ""
        if CreateObject("roFileSystem").Exists(NxGuideCachePath()) then raw = ReadAsciiFile(NxGuideCachePath())
        if raw <> "" then
            saved = ParseJson(raw)
            if type(saved) = "roAssociativeArray" then
                if saved.key = NxGuideCacheKey(clock0.nowSec, NxEnabledBundles()) and type(saved.guide) = "roAssociativeArray" then
                    m.top.fromCache = true
                    m.top.guide = saved.guide
                    m.top.status = "ready"
                    shown = true
                    print "library: showing the saved guide after "; timer.TotalMilliseconds(); " ms; refreshing in the background"
                end if
            end if
        end if
        if not shown then
            m.top.progress = "Scheduling your channels…"
            fromPools = NxGuideFromSavedPools(clock0.nowSec, clock0.month, NxEnabledBundles())
            if fromPools <> invalid then
                m.top.fromCache = true
                m.top.guide = fromPools.guide
                m.top.status = "ready"
                shown = true
                print "library: showing the saved pools, scheduled for today, after "; timer.TotalMilliseconds(); " ms; refreshing in the background"
            end if
        end if
    end if
    servers = ParseJson(NxPlexRegistry().Read("servers"))
    if type(servers) <> "roArray" or servers.Count() = 0 then
        fail("No Plex server is set up on this TV. Press * to sign in again.")
        return
    end if

    items = []
    ' Every server keeps its index, on or off, since items carry it.
    serversOn = NxServersOn(servers, NxSavedServerChoices())
    for i = 0 to servers.Count() - 1
        if serversOn[i] then
            m.top.progress = "Reading your library from " + NxToStr(servers[i].name) + "…"
            got = NxPlexScanServer(servers[i], i, m.top)
            if got = invalid then
                if shown then
                    print "library: background refresh couldn't read the library; keeping the saved guide"
                    return
                end if
                fail("Couldn't read the library on " + NxToStr(servers[i].name) + ". Press OK to try again.")
                return
            end if
            items.Append(got)
        end if
    end for
    print "library: "; items.Count(); " items in "; timer.TotalMilliseconds(); " ms"
    config = ParseJson(ReadAsciiFile("pkg:/data/channels.json"))
    manifest = ParseJson(ReadAsciiFile("pkg:/data/channels-memberships.json"))

    ' Enrichment, when this build has it (source/enrich/Enrichment.brs): the
    ' local and shared caches first. If the relay or OMDb has more to give, a
    ' guide built from the caches goes up first, unless the saved one is
    ' already showing, and the guide is rebuilt only if they added anything.
    opts = {
        config: NxEnrichmentConfig(), net: NxEnrichmentNet(),
        cache: NxEnrichFileCache("cachefs:/nostalgex-enrichment.json"),
        nowSec: NxFilterClock().nowSec, channels: config.channels,
        backoff: NxEnrichOMDbBackoff(NxEnrichRegistryStore()), progress: NxEnrichTopProgress(m.top)
    }
    timer.Mark()
    m.top.progress = "Reading shared details…"
    state = NxEnrichFromCaches(items, opts)
    if not state.skipped then print "library: enrichment caches read in "; timer.TotalMilliseconds(); " ms"
    built = invalid
    if NxEnrichHasRemoteWork(state, opts) then
        if not shown then
            built = buildGuide(items, config, manifest, false)
            shown = true
        end if
        timer.Mark()
        added = NxEnrichFromRemote(state, items, opts)
        print "library: enrichment remote step added "; added; " in "; timer.TotalMilliseconds(); " ms"
        if added > 0 then built = invalid
    end if
    if built = invalid then built = buildGuide(items, config, manifest, shown)
    ' Only the pools are scheduled from here on, for as long as the app runs:
    ' let the rest of the library and every item's filter cache go.
    for each it in items
        it.Delete("nxFilter")
    end for
    items = invalid
    keepScheduling(built.ordered, built.guide)
end sub

' Builds the switched-on channels from the library, schedules them and hands
' the guide to the render thread, unless `shown` and it matches what is
' already on screen. Returns { ordered, guide } for keepScheduling.
function buildGuide(items as Object, config as Object, manifest as Object, shown as Boolean) as Object
    timer = CreateObject("roTimespan")
    ' A library load clears the day schedules, as upstream's does.
    NxClearManifests()
    exclusive = NxFilterExclusiveRules(config.exclusiveRules)
    clock = NxFilterClock()
    nowSec& = clock.nowSec
    bundles = NxEnabledBundles()
    poolIds = NxPoolChannelIds(config, bundles, clock.month)

    timer.Mark()
    channels = []
    built = 0
    for each def in config.channels
        ch = {
            id: def.id, number: def.number, name: NxToStr(def.name), colorHex: NxToStr(def.colorHex),
            minItems: def.minItems, isPremiereChannel: def.isPremiereChannel,
            timeRestrictions: def.timeRestrictions, enabled: true, built: false, pool: []
        }
        ' `enabled: def.enabled !== false`; comparing invalid to a Boolean is an error here.
        if type(def.enabled) = "Boolean" or type(def.enabled) = "roBoolean" then ch.enabled = def.enabled
        if poolIds.DoesExist(def.id.ToStr()) then
            built = built + 1
            m.top.progress = "Building channels: " + built.ToStr() + " of " + poolIds.Count().ToStr()
            matched = []
            for each row in NxFilterPool(items, NxFilterChannel(def), manifest, exclusive, clock)
                matched.Push(row.item)
            end for
            ch.pool = matched
            ch.built = true
            minItems = 50
            if NxTruthy(def.minItems) then minItems = def.minItems
            ch.enabled = ch.pool.Count() >= minItems
        end if
        channels.Push(ch)
    end for
    print "library: built "; built; " channels in "; timer.TotalMilliseconds(); " ms"

    ' FRANCHISES, as the Apple TV app has it (the web tuner doesn't call the
    ' builder): covered franchises join their classic's pool, and each found
    ' franchise switched on gets a channel from CH 300 that rides on the
    ' package's switch. Before the shuffle, so every pool shuffles alike.
    franchiseRows = []
    foundIDs = []
    franchiseBundleIDs = []
    for each bdl in NxList(config.bundles)
        if bdl.id = NxFranchisesBundleID() then franchiseBundleIDs = NxList(bdl.channelIDs)
    end for
    if NxHasValue(bundles, NxFranchisesBundleID()) then
        timer.Mark()
        m.top.progress = "Finding franchises…"
        fr = NxFranchiseStep({
            channels: channels, items: items,
            defs: NxFranchiseDefinitions(ParseJson(ReadAsciiFile("pkg:/data/franchises.json"))),
            choices: NxSavedFranchiseChoices(), bundleChannelIDs: franchiseBundleIDs,
            manifest: manifest, exclusiveRules: exclusive
        })
        for each ch in fr.channels
            channels.Push(ch)
            foundIDs.Push(ch.id)
        end for
        franchiseRows = fr.rows
        print "library: franchises: "; fr.found.Count(); " found, "; foundIDs.Count(); " channels, in "; timer.TotalMilliseconds(); " ms"
    end if
    for each ch in channels
        if ch.built then
            ch.basePool = ch.pool
            ch.pool = NxSeededShuffle(ch.pool, nowSec&)
        end if
    end for

    ' Found franchise channels show while the package is on; its own channel
    ' list stays the seven classics, as upstream's Settings row reads.
    guideConfig = { bundles: [] }
    for each bdl in NxList(config.bundles)
        if bdl.id = NxFranchisesBundleID() and foundIDs.Count() > 0 then
            ids = []
            ids.Append(NxList(bdl.channelIDs))
            ids.Append(foundIDs)
            guideConfig.bundles.Push({ id: bdl.id, channelIDs: ids, activeMonths: bdl.activeMonths })
        else
            guideConfig.bundles.Push(bdl)
        end if
    end for
    ordered = NxGuideOrder(guideConfig, channels, bundles, clock.month)
    out = NxScheduleGuide(ordered, nowSec&)
    bundleList = []
    for each bdl in NxList(config.bundles)
        entry = { id: bdl.id, name: NxToStr(bdl.name), channelIDs: NxList(bdl.channelIDs), activeMonths: bdl.activeMonths }
        ' The sidebar jumps to the first channel shown, found franchises included.
        if bdl.id = NxFranchisesBundleID() then
            jump = []
            jump.Append(entry.channelIDs)
            jump.Append(foundIDs)
            entry.jumpIDs = jump
        end if
        bundleList.Push(entry)
    end for
    guide = { channels: out, builtAt: nowSec&, items: items.Count(), bundles: bundleList, enabledBundles: bundles, franchises: franchiseRows }
    WriteAsciiFile(NxGuideCachePath(), FormatJson({ key: NxGuideCacheKey(nowSec&, bundles), guide: guide }))
    timer.Mark()
    NxSavePools(ordered, guide, clock.month)
    print "library: saved the pools in "; timer.TotalMilliseconds(); " ms; memory "; CreateObject("roAppMemoryMonitor").GetMemoryLimitPercent(); "% of the app's limit"
    ' Only hand over a refresh that differs, so an unchanged library leaves the
    ' screen alone.
    ' The package list counts too: a new package that is off changes no
    ' channel, but Settings has to show it.
    if shown and FormatJson(guide.channels) = FormatJson(m.top.guide.channels) and FormatJson(guide.bundles) = FormatJson(m.top.guide.bundles) and FormatJson(guide.franchises) = FormatJson(m.top.guide.franchises) then
        print "library: background refresh matches the saved guide"
    else
        m.top.fromCache = false
        m.top.guide = guide
        m.top.status = "ready"
    end if
    return { ordered: ordered, guide: guide }
end function

' What each channel airs today and tomorrow, as buildChannelSchedule
' computes it: the hour's time restrictions, then the day's schedule from the
' session cache.
function NxScheduleGuide(ordered as Object, nowSec as LongInteger) as Object
    day = NxLocalDay(nowSec)
    out = []
    for each ch in ordered
        today = NxManifestBlocks(ch, NxTimeFilteredPool(ch, ch.pool, day.hour), nowSec)
        tomorrowAt& = day.dayStartSec + 86400 + 60
        tomorrow = NxManifestBlocks(ch, NxTimeFilteredPool(ch, ch.pool, NxLocalDay(tomorrowAt&).hour), tomorrowAt&)
        blocks = []
        for each b in today
            blocks.Push(NxGuideBlock(b))
        end for
        for each b in tomorrow
            blocks.Push(NxGuideBlock(b))
        end for
        out.Push({ id: ch.id, number: NxChNum(ch), name: ch.name, color: ch.colorHex, blocks: blocks })
    end for
    return out
end function

' Stay up with the pools, re-checking schedules whenever asked (MainScene asks
' every 30 s, as upstream's rebuildAllSchedules runs): a time restriction
' lifting at 9 PM, or a new day, re-packs exactly as it would upstream.
sub keepScheduling(ordered as Object, guide as Object)
    port = CreateObject("roMessagePort")
    m.top.ObserveField("reschedule", port)
    last = FormatJson(guide.channels)
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGNodeEvent" then
            channels = NxScheduleGuide(ordered, CreateObject("roDateTime").AsSeconds())
            now = FormatJson(channels)
            if now <> last then
                last = now
                guide.channels = channels
                m.top.guide = guide
                m.top.status = "ready"
                print "library: schedules changed (new day or time restriction)"
            end if
        end if
    end while
end sub

' What the guide and player need from one airing; nothing secret.
function NxGuideBlock(b as Object) as Object
    it = b.item
    return {
        startSec: b.startSec, endSec: b.endSec,
        ratingKey: NxToStr(it.ratingKey), line: NxGuideTitle(it), title: NxToStr(it.title),
        episodeTitle: NxToStr(it.episodeTitle), seasonNumber: it.seasonNumber, episodeNumber: it.episodeNumber,
        summary: NxToStr(it.summary), year: NxToStr(it.year), partKey: it.partKey,
        container: it.container, videoCodec: it.videoCodec, audioCodec: it.audioCodec,
        serverIndex: it.serverIndex
    }
end function

' Switched-on bundles: saved on the TV, upstream's default until changed.
function NxEnabledBundles() as Object
    raw = CreateObject("roRegistrySection", "guide").Read("bundles")
    if raw <> "" then
        saved = ParseJson(raw)
        if type(saved) = "roArray" then return saved
    end if
    return ["nostalgex"]
end function

sub fail(message as String)
    m.top.message = message
    m.top.status = "error"
    print "library: "; message
end sub
