' Plex library loader, ported from Nostalgex's web tuner.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: plex-tuner.html scanOnePlexServer, fetchPlexSectionPaged,
' pickBestVersion and resolutionHeight, and parseMusicVideoFromPlex from
' scripts/nostalgex-music-brainz.js. Items come out in upstream's order
' (section, then show, then episode), because the schedule's shuffle starts
' from that order, and with upstream's fields and fallbacks.
'
' Differences, none of which reach the filter or schedule:
'   - Items carry `serverIndex`, not upstream's serverUrl and serverToken: the
'     token stays in the registry, never on an item.
'   - `meta` (a display string) is built by the guide, not here.
'   - Items also carry the chosen version's videoCodec and audioCodec, for
'     the player's direct-play decision, and episodes their season and episode
'     numbers, for the info panel. No rule reads them.
'   - Requests run one at a time; upstream fetches five shows' episodes at
'     once. Its Promise.all keeps their order, so the result is the same.
'   - MusicBrainz/Deezer enrichment of music videos is not ported yet.
' Upstream reads tmdbID from a `Guid` list it never asks Plex for
' (no includeGuids=1), so most items have none. Mirrored on purpose.

' One GET against a server: its home-network address when there is one,
' else HTTPS, with up to three tries, since a home network can drop a
' request. Returns the MediaContainer, or invalid. Sets err.auth when the
' server rejected the token.
function NxPlexGetContainer(server as Object, path as String, err = invalid as Dynamic, timeoutMs = 15000 as Integer) as Dynamic
    base = NxToStr(server.uri)
    if NxTruthy(server.lanUri) then base = server.lanUri
    for attempt = 1 to 3
        res = NxPlexServerGet(base + path, NxToStr(server.accessToken), timeoutMs)
        if res.code = 401 or res.code = 403 or (res.code >= 200 and res.code <= 299) then exit for
        print "plex: a library request failed ("; res.code; "), try "; attempt; " of 3"
        if attempt = 2 and base <> NxToStr(server.uri) then base = NxToStr(server.uri)
    end for
    if res.code = 401 or res.code = 403 then
        if err <> invalid then err.auth = true
        return invalid
    end if
    if res.code < 200 or res.code > 299 then return invalid
    if type(res.json) <> "roAssociativeArray" then return invalid
    if type(res.json.MediaContainer) <> "roAssociativeArray" then return invalid
    return res.json.MediaContainer
end function

' Every item in a section, 300 at a time, as fetchPlexSectionPaged. invalid
' if a page fails (upstream throws and skips the section).
function NxPlexSectionItems(server as Object, key as String) as Dynamic
    pageSize = 300
    all = []
    start = 0
    while true
        mc = NxPlexGetContainer(server, "/library/sections/" + key + "/all?X-Plex-Container-Start=" + start.ToStr() + "&X-Plex-Container-Size=" + pageSize.ToStr(), invalid, 30000)
        if mc = invalid then return invalid
        page = NxList(mc.Metadata)
        all.Append(page)
        if page.Count() = 0 then exit while
        if NxIsNumber(mc.totalSize) then
            if all.Count() >= mc.totalSize then exit while
        else if page.Count() < pageSize then
            exit while
        end if
        start = start + pageSize
    end while
    return all
end function

' All of a server's playable items. `progress`, if given, is a node whose
' `progress` string field shows how far the scan has got. Returns invalid
' when the server rejected the token or its section list failed, as
' upstream's scan throws.
function NxPlexScanServer(server as Object, serverIndex as Integer, progress = invalid as Dynamic) as Dynamic
    err = { auth: false }
    mc = NxPlexGetContainer(server, "/library/sections", err)
    if mc = invalid then return invalid
    sections = NxList(mc.Directory)
    mvSection = CreateObject("roRegex", "music.?video|^music$|^mv[s]?$", "i")
    musicGenre = CreateObject("roRegex", "music", "i")

    out = []
    for each section in sections
        title = NxToStr(section.title)
        items = NxPlexSectionItems(server, NxToStr(section.key))
        if items = invalid then
            print "plex: skipped a section that failed to load"
        else
            isMusicVideoSection = mvSection.IsMatch(title.Trim())
            if section.type = "show" then
                shown = 0
                for each show in items
                    showGenres = NxTags(show.Genre)
                    leaves = NxPlexGetContainer(server, "/library/metadata/" + NxToStr(show.ratingKey) + "/allLeaves")
                    if leaves <> invalid then
                        for each ep in NxList(leaves.Metadata)
                            it = NxPlexEpisodeItem(ep, show, showGenres, isMusicVideoSection)
                            if it <> invalid then
                                it.serverIndex = serverIndex
                                out.Push(it)
                            end if
                        end for
                    end if
                    shown = shown + 1
                    if progress <> invalid then progress.progress = title + ": " + shown.ToStr() + " of " + items.Count().ToStr() + " shows"
                end for
            else
                for each raw in items
                    it = NxPlexMovieItem(raw, section, isMusicVideoSection, musicGenre)
                    if it <> invalid then
                        it.serverIndex = serverIndex
                        out.Push(it)
                    end if
                end for
                if progress <> invalid then progress.progress = title + ": " + items.Count().ToStr() + " items"
            end if
        end if
    end for
    return out
end function

function NxPlexEpisodeItem(ep as Object, show as Object, showGenres as Object, isMusicVideoSection as Boolean) as Dynamic
    durationMin = NxPlexMinutes(ep.duration)
    if durationMin <= 0 then return invalid
    media = NxPickBestVersion(ep.Media)
    partKey = invalid
    container = invalid
    codecs = { video: invalid, audio: invalid }
    if media <> invalid then
        container = media.container
        codecs = { video: media.videoCodec, audio: media.audioCodec }
        parts = NxList(media.Part)
        if parts.Count() > 0 then
            if type(parts[0]) = "roAssociativeArray" then partKey = parts[0].key
        end if
    end if
    librarySource = "tv"
    if isMusicVideoSection then librarySource = "musicVideo"
    return {
        title: NxOr(show.title, "Unknown"),
        episodeTitle: NxOr(ep.title, ""),
        summary: NxOr(ep.summary, NxOr(show.summary, "")),
        year: NxOr(show.year, ""),
        contentRating: NxOr(show.contentRating, NxOr(ep.contentRating, "")),
        duration: durationMin,
        ratingKey: ep.ratingKey,
        partKey: partKey,
        container: container,
        genres: showGenres,
        rating: NxOr(show.rating, 0),
        userRating: NxOr(show.userRating, 0),
        type: "episode",
        thumb: NxOr(ep.thumb, show.thumb),
        art: show.art,
        viewCount: NxOr(ep.viewCount, 0),
        addedAt: NxOr(ep.addedAt, 0),
        studio: NxOr(show.studio, ""),
        librarySource: librarySource,
        tmdbID: NxParseTmdbIdFromPlex(ep, true),
        artist: invalid,
        seasonNumber: ep.parentIndex,
        episodeNumber: ep.index,
        videoCodec: codecs.video,
        audioCodec: codecs.audio
    }
end function

function NxPlexMovieItem(item as Object, section as Object, isMusicVideoSection as Boolean, musicGenre as Object) as Dynamic
    genres = NxTags(item.Genre)
    hasMusicGenre = false
    for each g in genres
        if musicGenre.IsMatch(g) then hasMusicGenre = true
    end for
    if isMusicVideoSection and not hasMusicGenre then genres.Push("Music Video")

    durationMin = NxPlexMinutes(item.duration)
    if durationMin <= 0 then return invalid

    ' A music-video library, or a short item tagged with a Music genre (the
    ' 10-minute cap keeps musicals and biopics out).
    isMusicVideo = isMusicVideoSection or (durationMin <= 10 and hasMusicGenre)

    media = NxPickBestVersion(item.Media)
    partKey = invalid
    container = invalid
    codecs = { video: invalid, audio: invalid }
    if media <> invalid then
        container = media.container
        codecs = { video: media.videoCodec, audio: media.audioCodec }
        parts = NxList(media.Part)
        if parts.Count() > 0 then
            if type(parts[0]) = "roAssociativeArray" then partKey = parts[0].key
        end if
    end if

    sectionType = NxToStr(section.type)
    librarySource = sectionType
    if sectionType = "movie" then librarySource = "movie"
    if isMusicVideo then librarySource = "musicVideo"
    itemType = sectionType
    if sectionType = "show" then itemType = "episode"

    displayTitle = NxOr(item.title, "Unknown")
    artist = invalid
    if isMusicVideo then
        parsed = NxParseMusicVideoFromPlex(item, displayTitle)
        displayTitle = parsed.title
        artist = parsed.artist
    end if

    return {
        title: displayTitle,
        artist: artist,
        summary: NxOr(item.summary, ""),
        year: NxOr(item.year, ""),
        contentRating: NxOr(item.contentRating, ""),
        duration: durationMin,
        ratingKey: item.ratingKey,
        partKey: partKey,
        container: container,
        genres: genres,
        rating: NxOr(item.rating, 0),
        userRating: NxOr(item.userRating, 0),
        type: itemType,
        thumb: item.thumb,
        art: item.art,
        viewCount: NxOr(item.viewCount, 0),
        addedAt: NxOr(item.addedAt, 0),
        studio: NxOr(item.studio, ""),
        librarySource: librarySource,
        tmdbID: NxParseTmdbIdFromPlex(item, false),
        videoCodec: codecs.video,
        audioCodec: codecs.audio
    }
end function

' Plex milliseconds to whole minutes, rounded half up as JS Math.round.
function NxPlexMinutes(ms as Dynamic) as Integer
    if not NxTruthy(ms) or not NxIsNumber(ms) then return 0
    return Int(ms / 60000# + 0.5#)
end function

function NxTags(list as Dynamic) as Object
    out = []
    for each t in NxList(list)
        if type(t) = "roAssociativeArray" then out.Push(t.tag) else out.Push(invalid)
    end for
    return out
end function

' JS `a || b`.
function NxOr(a as Dynamic, b as Dynamic) as Dynamic
    if NxTruthy(a) then return a
    return b
end function

' The highest-bitrate version, ties to the taller picture; the first when none
' reports a bitrate. Mirrors pickBestVersion with Plex's getters.
function NxPickBestVersion(versions as Dynamic) as Dynamic
    list = NxList(versions)
    if list.Count() = 0 then return invalid
    anyBitrate = false
    for each v in list
        if type(v) = "roAssociativeArray" then
            if v.bitrate <> invalid then anyBitrate = true
        end if
    end for
    if not anyBitrate then return list[0]
    best = list[0]
    for i = 1 to list.Count() - 1
        v = list[i]
        bb = -1
        if best.bitrate <> invalid then bb = best.bitrate
        bv = -1
        if v.bitrate <> invalid then bv = v.bitrate
        if bv <> bb then
            if bv > bb then best = v
        else if NxResolutionHeight(v.videoResolution) > NxResolutionHeight(best.videoResolution) then
            best = v
        end if
    end for
    return best
end function

' Mirrors resolutionHeight, parseInt quirks included ("4k" is 4).
function NxResolutionHeight(res as Dynamic) as Integer
    if not NxTruthy(res) then return 0
    s = LCase(NxToStr(res))
    parts = s.Split("x")
    hit = CreateObject("roRegex", "^\s*([+-]?\d+)", "").Match(parts[parts.Count() - 1])
    if hit.Count() = 2 then return hit[1].ToInt()
    if Instr(1, s, "4k") > 0 then return 2160
    if Instr(1, s, "1080") > 0 then return 1080
    if Instr(1, s, "720") > 0 then return 720
    return 0
end function

' ── Music video titles (nostalgex-music-brainz.js) ──────────────────────────

function NxParseMusicVideoFromPlex(item as Object, rawTitle as String) as Object
    artistHint = invalid
    if NxTruthy(item.parentTitle) then
        artistHint = item.parentTitle
    else if NxTruthy(item.grandparentTitle) then
        artistHint = item.grandparentTitle
    end if
    parsed = NxParseMusicTitle(rawTitle)
    title = rawTitle
    if NxTruthy(parsed.song) then title = parsed.song
    artist = artistHint
    if artist = invalid and NxTruthy(parsed.artist) then artist = parsed.artist
    return { title: title, artist: artist }
end function

' Ripped filenames down to searchable text, as MusicTitleParser.clean.
function NxCleanMusicTitle(raw as String) as String
    t = raw.Replace("_", " ")
    t = CreateObject("roRegex", "\[[^\]]*\]|\{[^}]*\}", "").ReplaceAll(t, "")
    t = CreateObject("roRegex", "\s*\((?:19|20)\d\d\)\s*$", "").ReplaceAll(t, "")
    t = CreateObject("roRegex", "\([^)]*(?:19|20)\d\d[^)]*\)", "").ReplaceAll(t, "")
    t = CreateObject("roRegex", "\b(official|video|hd|hq|lyrics?|remaster(?:ed)?|mv|xvid|dvdrip|vgb|prv)\b!?", "i").ReplaceAll(t, "")
    t = CreateObject("roRegex", "\s+", "").ReplaceAll(t, " ")
    return CreateObject("roRegex", "^[\s\-!.]+|[\s\-!.]+$", "").ReplaceAll(t, "")
end function

function NxStripFeaturing(s as String, artistSide as Boolean) as String
    if artistSide then
        re = CreateObject("roRegex", "\s+(?:ft\.?|feat\.?|featuring|with|and the)\s+.*$", "i")
    else
        re = CreateObject("roRegex", "\s+(?:ft\.?|feat\.?|featuring)\s+.*$", "i")
    end if
    return CreateObject("roRegex", "^[\s,]+|[\s,]+$", "").ReplaceAll(re.Replace(s, ""), "")
end function

function NxParseMusicTitle(raw as String) as Object
    cleaned = NxCleanMusicTitle(raw)
    dash = Instr(1, cleaned, " - ") - 1
    if dash > 0 then
        artist = NxStripFeaturing(Left(cleaned, dash), true)
        song = Mid(cleaned, dash + 4).Trim()
        nextDash = Instr(1, song, " - ") - 1
        if nextDash > 0 then song = Left(song, nextDash)
        song = NxStripFeaturing(song, false)
        if artist <> "" and song <> "" then return { artist: artist, song: song }
    end if
    lower = LCase(cleaned)
    byIdx = -1
    at = Instr(1, lower, " by ")
    while at > 0
        byIdx = at - 1
        at = Instr(at + 1, lower, " by ")
    end while
    if byIdx > 0 then
        song = NxStripFeaturing(Left(cleaned, byIdx), false)
        artist = NxStripFeaturing(Mid(cleaned, byIdx + 5), true)
        if artist <> "" and song <> "" then return { artist: artist, song: song }
    end if
    lone = CreateObject("roRegex", "^(.{2,}?)-(.+)$", "").Match(cleaned)
    if lone.Count() = 3 then
        if Instr(1, lone[1], " - ") = 0 then
            artist = NxStripFeaturing(lone[1], true)
            song = NxStripFeaturing(lone[2], false)
            if artist.Len() >= 2 and song.Len() >= 2 then return { artist: artist, song: song }
        end if
    end if
    return { artist: invalid, song: NxStripFeaturing(cleaned, false) }
end function
