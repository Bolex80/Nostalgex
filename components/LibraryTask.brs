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
    return info.GetVersion() + "|" + (nowSec \ 86400).ToStr() + "|" + NxLocalDay(nowSec).dayKey + "|" + FormatJson(bundles) + "|" + NxChoicesKey()
end function

'' The viewer's franchise, collection and server switches, as part of a cache key.
function NxChoicesKey() as String
    return FormatJson(NxFranchiseChoiceLists(NxSavedFranchiseChoices())) + "|" + FormatJson(NxCollectionKeyList(NxSavedCollectionKeys())) + "|" + NxSavedServersOnKey()
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
' packages, franchise and collection choices and servers on are the same.
function NxPoolCachePath() as String
    return "cachefs:/nostalgex-pools.json"
end function

function NxPoolCacheKey(month as Integer, bundles as Object) as String
    info = CreateObject("roAppInfo")
    return info.GetVersion() + "|" + month.ToStr() + "|" + FormatJson(bundles) + "|" + NxChoicesKey()
end function

' Written in pieces: one FormatJson of every pooled item, on top of the
' library itself, ran a Roku Stick Plus out of memory with 45 channels on
' (EXIT_CHANNEL_MEM_LIMIT_FG, Discussion #8). Each item is copied only for
' as long as it takes to format it, without what only the build reads: the
' filter cache, the enrichment record and the artwork paths. Every episode of
' a show shares one enrichment record in memory but would get its own copy
' in the file.
sub NxSavePools(ordered as Object, guide as Object, month as Integer)
    path = NxPoolCachePath()
    WriteAsciiFile(path, "{""key"":" + FormatJson(NxPoolCacheKey(month, guide.enabledBundles)) + ",""items"":[")
    index = {}
    count = 0
    parts = []
    chans = []
    for each ch in ordered
        saved = {}
        ' Keys come back lowercased from an AA's iteration, so they're compared
        ' that way: `k <> "basePool"` never matched, and every channel's pool
        ' was written out in full a second time (20 MB of a 23 MB file).
        for each k in ch
            lk = LCase(k)
            if lk <> "pool" and lk <> "basepool" then saved[k] = ch[k]
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
                    lk = LCase(k)
                    if lk <> "nxfilter" and lk <> "enrichment" and lk <> "thumb" and lk <> "art" then copy[k] = it[k]
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
    parts.Push(",""franchises"":" + FormatJson(guide.franchises))
    parts.Push(",""collections"":" + FormatJson(guide.collections) + "}")
    NxAppendText(path, parts)
end sub

function NxFileKB(path as String) as Integer
    st = CreateObject("roFileSystem").Stat(path)
    if st = invalid or st.size = invalid then return -1
    return st.size \ 1024
end function

' Appends the pieces to the file, UTF-8, and empties the list.
sub NxAppendText(path as String, parts as Object)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(parts.Join(""))
    bytes.AppendFile(path)
    parts.Clear()
end sub

' A file's text, or "". ReadAsciiFile refuses a pools file this big ("file
' is too big", 70 channels on a TV), so the bytes are read and turned into
' text instead.
function NxReadBigFile(path as String) as String
    bytes = CreateObject("roByteArray")
    if not bytes.ReadFile(path) then return ""
    return bytes.ToAsciiString()
end function

' The guide from the saved pools, as { ordered, guide }, or invalid when
' there are none for this key.
function NxGuideFromSavedPools(nowSec as LongInteger, month as Integer, bundles as Object) as Dynamic
    if not CreateObject("roFileSystem").Exists(NxPoolCachePath()) then return invalid
    saved = ParseJson(NxReadBigFile(NxPoolCachePath()))
    if type(saved) <> "roAssociativeArray" then return invalid
    if saved.key <> NxPoolCacheKey(month, bundles) or type(saved.channels) <> "roArray" or type(saved.items) <> "roArray" then return invalid
    ordered = []
    for each ch in saved.channels
        pool = []
        for each n in ch.poolIdx
            pool.Push(saved.items[n])
        end for
        ch.Delete("poolIdx")
        ' Collection channels air their collection unshuffled, as the web tuner's do.
        if NxTruthy(ch.built) and not NxTruthy(ch.collection) then pool = NxSeededShuffle(pool, nowSec)
        ch.pool = pool
        ordered.Push(ch)
    end for
    NxClearManifests()
    guide = {
        channels: NxScheduleGuide(ordered, nowSec), builtAt: nowSec, items: saved.libraryItems,
        bundles: saved.bundles, enabledBundles: bundles, franchises: saved.franchises,
        collections: saved.collections
    }
    return { ordered: ordered, guide: guide }
end function

sub loadLibrary()
    m.top.status = "loading"
    setPhase("preparing")
    timer = CreateObject("roTimespan")
    shown = false
    if m.top.useCache then
        clock0 = NxFilterClock()
        raw = ""
        if CreateObject("roFileSystem").Exists(NxGuideCachePath()) then raw = NxReadBigFile(NxGuideCachePath())
        if raw <> "" then
            saved = ParseJson(raw)
            if type(saved) = "roAssociativeArray" then
                if saved.key = NxGuideCacheKey(clock0.nowSec, NxEnabledBundles()) and type(saved.guide) = "roAssociativeArray" then
                    m.top.fromCache = true
                    m.top.guide = saved.guide
                    m.shownGuide = saved.guide
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
                m.shownGuide = fromPools.guide
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

    ' The saved library (source/plex/LibrarySnapshot.brs): a rebuild after a
    ' switch in Settings takes each server from it, and so does any load while
    ' a server's library signature is unchanged and its save under a day old,
    ' as the Apple TV app's refreshLibraryIfChanged skips the scan. A server
    ' read this time is saved again once the guide is up.
    snapDir = NxSnapshotDir()
    snap = NxSnapshotReadMeta(snapDir)
    m.top.firstRun = type(snap.servers) <> "roAssociativeArray" or snap.servers.Count() = 0
    nowSec& = NxFilterClock().nowSec
    ' Every server keeps its index, on or off, since items carry it, and its
    ' machine identifier keys its collections and its save.
    keys = []
    collections = { raw: [], serverKeys: {}, failed: 0 }
    for i = 0 to servers.Count() - 1
        key = NxToStr(servers[i].machineIdentifier)
        if key = "" then key = "plex"
        keys.Push(key)
        collections.serverKeys[i.ToStr()] = key
    end for
    items = []
    scanned = []
    serversOn = NxServersOn(servers, NxSavedServerChoices())
    setPhase("library")
    m.top.progress = "Connecting to your servers…"
    missing = NxPlexResolveSaved(servers, serversOn)
    usable = 0
    for i = 0 to servers.Count() - 1
        if serversOn[i] and NxToStr(servers[i].uri) <> "" then usable = usable + 1
    end for
    if usable = 0 then
        if shown then
            print "library: background refresh reached no server; keeping the saved guide"
            return
        end if
        if missing = invalid then
            fail("Can't reach plex.tv to find your servers. Check the TV's internet connection, then press OK to try again.")
        else
            fail("None of your Plex servers answered over a secure (HTTPS) connection. In Plex, set Settings > Network > Secure connections to Preferred. Press OK to try again.")
        end if
        return
    end if
    for i = 0 to servers.Count() - 1
        ' A server with no address is left out this time; it's tried again on
        ' the next load.
        if serversOn[i] and NxToStr(servers[i].uri) <> "" then
            saved = invalid
            if type(snap.servers[keys[i]]) = "roAssociativeArray" then
                fresh = m.top.rebuild
                if not fresh then
                    m.top.progress = "Checking your library on " + NxToStr(servers[i].name) + "…"
                    fresh = NxSnapshotFresh(snap.servers[keys[i]], NxPlexServerSignature(servers[i]), nowSec&)
                end if
                if fresh then saved = NxSnapshotLoadServer(snapDir, snap, keys[i], i)
            end if
            if saved <> invalid then
                items.Append(saved.items)
                if saved.collections <> invalid then
                    collections.raw.Append(saved.collections)
                else
                    collections.failed = collections.failed + 1
                end if
                print "library: "; saved.items.Count(); " items from the saved library, server "; i
            else
                m.top.progress = "Reading your library from " + NxToStr(servers[i].name) + "…"
                info = { signature: invalid }
                got = NxPlexScanServer(servers[i], i, m.top, info)
                if got = invalid then
                    if shown then
                        print "library: background refresh couldn't read the library; keeping the saved guide"
                        return
                    end if
                    fail("Couldn't read the library on " + NxToStr(servers[i].name) + ". Press OK to try again.")
                    return
                end if
                items.Append(got)
                scanned.Push({ index: i, key: keys[i], signature: info.signature, collections: invalid })
            end if
        end if
    end for
    print "library: "; items.Count(); " items in "; timer.TotalMilliseconds(); " ms ("; scanned.Count(); " servers scanned)"

    ' Server collections (source/collections/Collections.brs), read after the
    ' library as the web tuner's scan runs after its load, for the servers
    ' just scanned. A server whose collections can't be read just has none
    ' this time.
    timer.Mark()
    setPhase("collections")
    if scanned.Count() > 0 then m.top.progress = "Reading your collections…"
    for each s in scanned
        got = NxCollectionsFetchPlex(s.key, NxPlexCollectionsFetcher(servers[s.index]), m.top)
        if got = invalid then
            collections.failed = collections.failed + 1
        else
            collections.raw.Append(got)
            s.collections = got
        end if
    end for
    print "library: "; collections.raw.Count(); " server collections ("; collections.failed; " servers failed) in "; timer.TotalMilliseconds(); " ms"
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
    setPhase("metadata")
    m.top.progress = "Reading shared details…"
    state = NxEnrichFromCaches(items, opts)
    if not state.skipped then print "library: enrichment caches read in "; timer.TotalMilliseconds(); " ms"
    built = invalid
    if NxEnrichHasRemoteWork(state, opts) then
        if not shown then
            built = buildGuide(items, config, manifest, collections, false)
            shown = true
        end if
        timer.Mark()
        added = NxEnrichFromRemote(state, items, opts)
        print "library: enrichment remote step added "; added; " in "; timer.TotalMilliseconds(); " ms"
        if added > 0 then built = invalid
    end if
    if built = invalid then built = buildGuide(items, config, manifest, collections, shown)
    timer.Mark()
    for each s in scanned
        NxSnapshotSaveServer(snapDir, snap, s.key, items, s.index, s.collections, s.signature, nowSec&)
    end for
    NxSnapshotForgetServers(snapDir, snap, keys)
    if scanned.Count() > 0 then print "library: saved the library in "; timer.TotalMilliseconds(); " ms; memory "; CreateObject("roAppMemoryMonitor").GetMemoryLimitPercent(); "% of the app's limit"
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
function buildGuide(items as Object, config as Object, manifest as Object, collections as Object, shown as Boolean) as Object
    timer = CreateObject("roTimespan")
    ' A library load clears the day schedules, as upstream's does.
    NxClearManifests()
    exclusive = NxFilterExclusiveRules(config.exclusiveRules)
    clock = NxFilterClock()
    nowSec& = clock.nowSec
    bundles = NxEnabledBundles()
    poolIds = NxPoolChannelIds(config, bundles, clock.month)

    timer.Mark()
    setPhase("channels")
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
            m.top.bar = (built - 1) / poolIds.Count()
            m.top.barCaption = "Channel " + built.ToStr() + " of " + poolIds.Count().ToStr()
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
    setPhase("finishing")
    m.top.progress = ""

    ' FRANCHISES, as the Apple TV app has it (the web tuner doesn't call the
    ' builder): covered franchises join their classic's pool, and each found
    ' franchise switched on gets a channel from CH 300 that rides on the
    ' package's switch. Before the shuffle, so every pool shuffles alike.
    franchiseRows = []
    foundIDs = []
    franchiseBundleIDs = []
    fr = invalid
    defs = []
    for each bdl in NxList(config.bundles)
        if bdl.id = NxFranchisesBundleID() then franchiseBundleIDs = NxList(bdl.channelIDs)
    end for
    if NxHasValue(bundles, NxFranchisesBundleID()) then
        timer.Mark()
        m.top.progress = "Finding franchises…"
        defs = NxFranchiseDefinitions(ParseJson(ReadAsciiFile("pkg:/data/franchises.json")))
        fr = NxFranchiseStep({
            channels: channels, items: items, defs: defs,
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

    ' MY COLLECTIONS, as the web tuner has them: each collection switched on
    ' airs from CH 500, outside every package. One that is a franchise the
    ' package already carries folds into it instead, as on the Apple TV.
    timer.Mark()
    cl = NxCollectionsStep({
        channels: channels, raw: collections.raw, items: items, serverKeys: collections.serverKeys,
        manifest: manifest, enabledKeys: NxSavedCollectionKeys(),
        franchise: fr, franchiseBundleIDs: franchiseBundleIDs, defs: defs
    })
    collectionIDs = []
    for each ch in cl.channels
        channels.Push(ch)
        collectionIDs.Push(ch.id)
    end for
    print "library: collections: "; cl.rows.Count(); " listed, "; cl.folded.Count(); " folded into franchises, "; collectionIDs.Count(); " channels, "; cl.overCap; " past CH 699, in "; timer.TotalMilliseconds(); " ms"
    for each ch in channels
        ' Collection channels air their collection unshuffled, as the web
        ' tuner's do.
        if ch.built and not NxTruthy(ch.collection) then
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
    ' Collection channels belong to no package; the web tuner shows them
    ' whenever they are built. Here they ride on a package that is always on.
    guideBundles = []
    guideBundles.Append(bundles)
    if collectionIDs.Count() > 0 then
        guideConfig.bundles.Push({ id: "nx-collections", channelIDs: collectionIDs })
        guideBundles.Push("nx-collections")
    end if
    ordered = NxGuideOrder(guideConfig, channels, guideBundles, clock.month)
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
    guide = {
        channels: out, builtAt: nowSec&, items: items.Count(), bundles: bundleList, enabledBundles: bundles,
        franchises: franchiseRows, collections: { rows: cl.rows, overCap: cl.overCap, scanned: collections.raw.Count(), failed: collections.failed }
    }
    ' Only hand over a refresh that differs, so an unchanged library leaves the
    ' screen alone. Before the saves, so a first run's guide doesn't wait on
    ' them.
    ' The package list counts too: a new package that is off changes no
    ' channel, but Settings has to show it.
    ' Compared with the task's own copy: each read of m.top.guide copies the
    ' whole guide out of the node.
    old = m.shownGuide
    if shown and old <> invalid and FormatJson(guide.channels) = FormatJson(old.channels) and FormatJson(guide.bundles) = FormatJson(old.bundles) and FormatJson(guide.franchises) = FormatJson(old.franchises) and FormatJson(guide.collections) = FormatJson(old.collections) then
        print "library: background refresh matches the saved guide"
    else
        m.top.fromCache = false
        m.top.guide = guide
        m.shownGuide = guide
        m.top.status = "ready"
    end if
    WriteAsciiFile(NxGuideCachePath(), FormatJson({ key: NxGuideCacheKey(nowSec&, bundles), guide: guide }))
    timer.Mark()
    NxSavePools(ordered, guide, clock.month)
    print "library: saved the pools in "; timer.TotalMilliseconds(); " ms; memory "; CreateObject("roAppMemoryMonitor").GetMemoryLimitPercent(); "% of the app's limit; "; NxFileKB(NxPoolCachePath()); " KB"
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
    out = {
        startSec: b.startSec, endSec: b.endSec,
        ratingKey: NxToStr(it.ratingKey), line: NxGuideTitle(it), title: NxToStr(it.title),
        episodeTitle: NxToStr(it.episodeTitle), seasonNumber: it.seasonNumber, episodeNumber: it.episodeNumber,
        summary: NxToStr(it.summary), year: NxToStr(it.year), partKey: it.partKey,
        container: it.container, videoCodec: it.videoCodec, audioCodec: it.audioCodec,
        serverIndex: it.serverIndex, contentRating: NxToStr(it.contentRating), rating: 0,
        type: NxToStr(it.type)
    }
    if NxIsNumber(it.rating) then out.rating = it.rating
    ' Music videos also show their artist and genres (PlexMediaItem+MusicDisplay.swift).
    if it.librarySource = "musicVideo" then
        out.music = true
        out.artist = NxToStr(it.artist)
        out.genreLine = NxMusicGenreLine(it.genres)
    end if
    return out
end function

' musicGenreDisplay: up to four genres, less the generic music ones.
function NxMusicGenreLine(genres as Dynamic) as String
    useful = []
    for each g in NxList(genres)
        l = LCase(NxToStr(g))
        if l <> "" and Instr(1, l, "music video") = 0 and l <> "music" and l <> "musical" and useful.Count() < 4 then useful.Push(NxToStr(g))
    end for
    return useful.Join(" · ")
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

' A new step on the loading screen's rail; the last step's bar goes with it.
sub setPhase(phase as String)
    m.top.bar = -1
    m.top.barCaption = ""
    m.top.phase = phase
end sub

sub fail(message as String)
    m.top.message = message
    m.top.status = "error"
    print "library: "; message
end sub
