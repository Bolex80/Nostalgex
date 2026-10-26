' What SHOW NOW PLAYING and MARK WATCHED send (issue #72), one event at a
' time, in the order the guide made them (source/guide/PlaybackReport.brs).
' components/ReportTask runs it on its own thread, so nothing here ever
' holds up the picture or the guide.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: the Apple TV app's Services/PlaybackTracker.swift (the queued
' operations), Services/WatchStateGuard.swift (PulseBackoff,
' WatchCleanupPlan, the guards' requests), Services/MediaBackend.swift
' (MediaServerPlaybackReport) and PlexAPIService.heartbeatRequest, at the
' commit in data/UPSTREAM. The backoff and the plans are held to
' scripts/nostalgex-watch-state.js and scripts/watch-cleanup-golden.json
' (tests/vectors/watch.json and watch-cleanup-golden.json).
'
' The rule, as upstream's: the server sees what plays and a real watch
' counts, but a programme the guide played is never left in Continue
' Watching (Plex) or Resume (Jellyfin, Emby).
'   - Plex: Now Playing reports carry no position, so Plex stores nothing.
'     A counted episode's next-up entry is removed unless the show was in
'     Continue Watching before tune-in.
'   - Jellyfin and Emby count a play on the start report, so the item's
'     UserData is read first and put back when the session ends. With no
'     reading there is no report and no mark for that programme. The stop
'     is capped at 89% of the runtime, short of the server's own "finished".
'
' net is the transport: net.send(method, url, headers, body) returns
' { code, json } (code 0 or negative when nothing answered), net.server(i)
' the saved server i as { kind, base, token, userId } or invalid, and
' net.sleep(ms). Tests give a fake one.

function NxReportExecutor() as Object
    return { boxes: {} }
end function

' PlaybackReportState, per session, plus that session's PulseBackoff.
function NxReportBox(ex as Object, sessionId as String) as Object
    rs = ex.boxes[sessionId]
    if rs = invalid then
        rs = { captureAttempted: false, prior: invalid, sessionAttempted: false, needsCleanup: false, markAttempted: false, backoff: NxPulseBackoff() }
        ex.boxes[sessionId] = rs
    end if
    return rs
end function

' ── PulseBackoff ────────────────────────────────────────────────────────────

' A server that stops answering gets fewer pulses, never a changed setting:
' each failure skips 1, 2, 4 ... up to 30 pulses; an answer resets it.
function NxPulseBackoff() as Object
    return { failures: 0, skip: 0 }
end function

function NxPulseAllow(b as Object) as Boolean
    if b.skip > 0 then
        b.skip = b.skip - 1
        return false
    end if
    return true
end function

sub NxPulseRecord(b as Object, success as Boolean)
    if success then
        b.failures = 0
        b.skip = 0
        return
    end if
    b.failures = b.failures + 1
    shift = b.failures - 1
    if shift > 5 then shift = 5
    s = 1
    for i = 1 to shift
        s = s * 2
    end for
    if s > 30 then s = 30
    b.skip = s
end sub

' ── WatchCleanupPlan ────────────────────────────────────────────────────────

' prior: { resumePosition, playCount, played, lastPlayedDate, showKey,
' showInContinueWatching }, or invalid when it couldn't be read. Steps:
' { kind: "removeShowFromContinueWatching", show }, { kind: "markUnplayed" }
' or { kind: "userData", position, playCount, played, lastPlayedDate }.
function NxPlexCleanupPlan(prior as Dynamic, counted as Boolean) as Object
    if not counted or prior = invalid then return []
    if not NxTruthy(prior.showKey) or prior.showInContinueWatching = true then return []
    return [{ kind: "removeShowFromContinueWatching", show: NxToStr(prior.showKey) }]
end function

function NxMediaServerCleanupPlan(prior as Dynamic, counted as Boolean) as Object
    ' An unreadable baseline never turns into a reset.
    if prior = invalid then return []
    if counted then return [{ kind: "userData", position: 0, playCount: NxNumberOr0(prior.playCount) + 1, played: true }]
    if NxNumberOr0(prior.resumePosition) = 0 and NxNumberOr0(prior.playCount) = 0 and prior.played <> true then return [{ kind: "markUnplayed" }]
    stp = { kind: "userData", position: NxNumberOr0(prior.resumePosition), playCount: NxNumberOr0(prior.playCount), played: prior.played = true }
    if NxTruthy(prior.lastPlayedDate) then stp.lastPlayedDate = prior.lastPlayedDate
    return [stp]
end function

' The golden file's form of a step.
function NxCleanupDescribe(stp as Object) as String
    if stp.kind = "removeShowFromContinueWatching" then return "removeShowFromContinueWatching " + stp.show
    if stp.kind = "markUnplayed" then return "markUnplayed"
    parts = ["userData position=" + NxToStr(stp.position)]
    if stp.playCount <> invalid then parts.Push("playCount=" + NxToStr(stp.playCount))
    if stp.played <> invalid then parts.Push("played=" + NxToStr(stp.played))
    if NxTruthy(stp.lastPlayedDate) then parts.Push("lastPlayedDate=" + NxToStr(stp.lastPlayedDate))
    return parts.Join(" ")
end function

' ── Requests ────────────────────────────────────────────────────────────────

' heartbeatRequest: PUT /:/timeline with no time or duration, the session in
' X-Plex-Session-Identifier. invalid for a state or key upstream refuses.
function NxPlexTimelineRequest(srv as Object, ratingKey as String, state as String, sessionId as String) as Dynamic
    if not NxHasValue(["playing", "paused", "buffering", "stopped"], state) then return invalid
    if ratingKey = "" or sessionId = "" or not CreateObject("roRegex", "^[0-9]+$", "").IsMatch(ratingKey) then return invalid
    headers = NxPlexHeaders(NxToStr(srv.token))
    headers["X-Plex-Session-Identifier"] = sessionId
    url = srv.base + "/:/timeline?ratingKey=" + ratingKey + "&key=/library/metadata/" + ratingKey + "&state=" + state
    return { method: "PUT", url: url, headers: headers, body: "" }
end function

function NxPlexReportRequest(srv as Object, method as String, path as String, query as String) as Object
    url = srv.base + path
    if query <> "" then url = url + "?" + query
    return { method: method, url: url, headers: NxPlexHeaders(NxToStr(srv.token)), body: "" }
end function

' MediaServerPlaybackReport: /Sessions/Playing, /Progress or /Stopped.
function NxMbReportRequest(srv as Object, event as String, itemId as String, mediaSourceId as String, sessionId as String, ticks as LongInteger) as Object
    path = "/Sessions/Playing"
    if event = "progress" then path = "/Sessions/Playing/Progress"
    if event = "stopped" then path = "/Sessions/Playing/Stopped"
    body = "{""ItemId"":" + FormatJson(itemId) + ",""PlaySessionId"":" + FormatJson(sessionId) + ",""MediaSourceId"":" + FormatJson(mediaSourceId) + ",""PositionTicks"":" + ticks.ToStr() + ",""IsPaused"":false}"
    return { method: "POST", url: srv.base + path, headers: NxMbReportHeaders(srv, true), body: body }
end function

function NxMbReportHeaders(srv as Object, json as Boolean) as Object
    h = { "Accept": "application/json", "Authorization": NxMbAuthHeader(NxToStr(srv.token)) }
    if json then h["Content-Type"] = "application/json"
    return h
end function

function NxMbUserPath(srv as Object, suffix as String) as String
    return srv.base + "/Users/" + NxUrlEncode(NxToStr(srv.userId)) + suffix
end function

' A cleanup step as a request, or invalid (a Plex step has its own lookups).
function NxMbCleanupRequest(srv as Object, stp as Object, itemId as String) as Dynamic
    item = NxUrlEncode(itemId)
    if stp.kind = "markUnplayed" then return { method: "DELETE", url: NxMbUserPath(srv, "/PlayedItems/" + item), headers: NxMbReportHeaders(srv, false), body: "" }
    if stp.kind <> "userData" then return invalid
    ' Keys sorted, as upstream's JSONSerialization .sortedKeys.
    parts = []
    if NxTruthy(stp.lastPlayedDate) then parts.Push("""LastPlayedDate"":" + FormatJson(NxToStr(stp.lastPlayedDate)))
    parts.Push("""PlaybackPositionTicks"":" + NxReportNumber(stp.position))
    if stp.playCount <> invalid then parts.Push("""PlayCount"":" + NxReportNumber(stp.playCount))
    if stp.played <> invalid then parts.Push("""Played"":" + NxToStr(stp.played = true))
    ' JSONSerialization sorts by key: LastPlayedDate, PlayCount, PlaybackPositionTicks, Played.
    ordered = []
    for each key in ["""LastPlayedDate""", """PlayCount""", """PlaybackPositionTicks""", """Played"""]
        for each p in parts
            if Left(p, key.Len()) = key then ordered.Push(p)
        end for
    end for
    return { method: "POST", url: NxMbUserPath(srv, "/Items/" + item + "/UserData"), headers: NxMbReportHeaders(srv, true), body: "{" + ordered.Join(",") + "}" }
end function

' A whole number as JSON, whatever its BrightScript type.
function NxReportNumber(v as Dynamic) as String
    if not NxIsNumber(v) then return "0"
    t = type(v)
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
        l& = v
        return l&.ToStr()
    end if
    return v.ToStr()
end function

function NxReportOk(res as Dynamic) as Boolean
    return res <> invalid and NxIsNumber(res.code) and res.code >= 200 and res.code <= 299
end function

function NxReportSend(net as Object, req as Dynamic) as Dynamic
    if req = invalid then return invalid
    return net.send(req.method, req.url, req.headers, req.body)
end function

' ── Capture ─────────────────────────────────────────────────────────────────

' Plex: an episode's show, and whether it was in Continue Watching before
' tune-in. A film costs no request (invalid).
function NxPlexCapture(net as Object, srv as Object, ev as Object) as Dynamic
    if ev.type <> "episode" then return invalid
    res = NxReportSend(net, NxPlexReportRequest(srv, "GET", "/library/metadata/" + ev.ratingKey, ""))
    meta = NxPlexFirstEntry(res)
    if meta = invalid then return invalid
    if meta.type <> "episode" or not NxTruthy(meta.grandparentRatingKey) then return invalid
    show = NxToStr(meta.grandparentRatingKey)
    row = NxPlexContinueWatching(net, srv)
    ' An unreadable row: assume the show was there, so no real entry goes.
    inRow = true
    if row <> invalid then
        inRow = false
        for each e in row
            if NxToStr(e.grandparentRatingKey) = show or NxToStr(e.ratingKey) = show then inRow = true
        end for
    end if
    return { resumePosition: 0, playCount: 0, played: false, lastPlayedDate: invalid, showKey: show, showInContinueWatching: inRow }
end function

function NxPlexFirstEntry(res as Dynamic) as Dynamic
    if not NxReportOk(res) or type(res.json) <> "roAssociativeArray" then return invalid
    mc = res.json.MediaContainer
    if type(mc) <> "roAssociativeArray" then return invalid
    list = NxList(mc.Metadata)
    if list.Count() = 0 or type(list[0]) <> "roAssociativeArray" then return invalid
    return list[0]
end function

function NxPlexContinueWatching(net as Object, srv as Object) as Dynamic
    res = NxReportSend(net, NxPlexReportRequest(srv, "GET", "/hubs/continueWatching/items", "count=200"))
    if not NxReportOk(res) or type(res.json) <> "roAssociativeArray" then return invalid
    if type(res.json.MediaContainer) <> "roAssociativeArray" then return invalid
    return NxList(res.json.MediaContainer.Metadata)
end function

' Jellyfin and Emby: the item's UserData, or invalid.
function NxMbCapture(net as Object, srv as Object, ev as Object) as Dynamic
    res = net.send("GET", NxMbUserPath(srv, "/Items/" + NxUrlEncode(ev.ratingKey)), NxMbReportHeaders(srv, false), "")
    if not NxReportOk(res) or type(res.json) <> "roAssociativeArray" then return invalid
    data = res.json.UserData
    if type(data) <> "roAssociativeArray" then return invalid
    last = invalid
    if NxTruthy(data.LastPlayedDate) then last = NxToStr(data.LastPlayedDate)
    return { resumePosition: NxNumberOr0(data.PlaybackPositionTicks), playCount: NxNumberOr0(data.PlayCount), played: data.Played = true, lastPlayedDate: last, showKey: invalid, showInContinueWatching: false }
end function

sub NxReportCaptureIfNeeded(net as Object, srv as Object, rs as Object, ev as Object)
    if rs.captureAttempted then return
    rs.captureAttempted = true
    if ev.backend = "plex" then
        rs.prior = NxPlexCapture(net, srv, ev)
    else
        rs.prior = NxMbCapture(net, srv, ev)
    end if
end sub

' ── One event ───────────────────────────────────────────────────────────────

' Runs one event against the choices as they are now (scope), so turning a
' choice off revokes what is still queued. Returns what it did, for the log.
function NxReportRun(ex as Object, ev as Object, scope as Dynamic, net as Object) as String
    ' The guide sends the server with the event, so a stop still reaches it
    ' after a sign-out; otherwise the saved one.
    srv = ev.server
    if type(srv) <> "roAssociativeArray" then srv = net.server(ev.serverIndex)
    if srv = invalid then return "no server"
    rs = NxReportBox(ex, NxToStr(ev.sessionId))
    if ev.kind = "report" then return NxReportRunTimeline(rs, ev, scope, net, srv)
    if ev.kind = "mark" then return NxReportRunMark(rs, ev, scope, net, srv)
    if ev.kind = "cleanup" then return NxReportRunCleanup(ex, rs, ev, net, srv)
    return "unknown"
end function

function NxReportRunTimeline(rs as Object, ev as Object, scope as Dynamic, net as Object, srv as Object) as String
    if ev.state = "stopped" then
        ' Only a session that reported gets a stop; it always goes out.
        if not rs.sessionAttempted then return "no session to stop"
        if ev.backend = "plex" then
            res = NxReportSend(net, NxPlexTimelineRequest(srv, ev.ratingKey, "stopped", ev.sessionId))
        else
            ' Short of the server's own completion line; cleanup repairs the
            ' start report's count.
            ticks& = ev.ticks
            if ev.durationTicks > 0 then
                ' 89% exactly: the runtime is whole minutes of ticks.
                cap& = (ev.durationTicks \ 100) * 89
                if ticks& > cap& then ticks& = cap&
            end if
            res = NxReportSend(net, NxMbReportRequest(srv, "stopped", ev.ratingKey, ev.partKey, ev.sessionId, ticks&))
        end if
        NxPulseRecord(rs.backoff, NxReportOk(res))
        rs.sessionAttempted = false
        rs.needsCleanup = true
        return "stopped " + NxToStr(NxReportCode(res))
    end if
    if ev.pulse = true and not NxPulseAllow(rs.backoff) then return "pulse skipped"
    if not NxReportAllowsActivity(scope, ev.activityEpoch) then return "now playing off"
    if ev.backend <> "plex" or scope.markWatched = true then NxReportCaptureIfNeeded(net, srv, rs, ev)
    ' Jellyfin and Emby count a play on the start report: without a reading
    ' there is nothing to put back, so this programme isn't reported.
    if ev.backend <> "plex" and rs.prior = invalid then return "no reading, not reported"
    started = rs.sessionAttempted
    rs.sessionAttempted = true
    rs.needsCleanup = true
    if ev.backend = "plex" then
        res = NxReportSend(net, NxPlexTimelineRequest(srv, ev.ratingKey, ev.state, ev.sessionId))
    else
        event = "started"
        if started then event = "progress"
        res = NxReportSend(net, NxMbReportRequest(srv, event, ev.ratingKey, ev.partKey, ev.sessionId, ev.ticks))
    end if
    NxPulseRecord(rs.backoff, NxReportOk(res))
    return ev.state + " " + NxToStr(NxReportCode(res))
end function

function NxReportRunMark(rs as Object, ev as Object, scope as Dynamic, net as Object, srv as Object) as String
    if rs.markAttempted then return "already marked"
    if not NxReportAllowsMark(scope, ev.markEpoch) then return "mark watched off"
    NxReportCaptureIfNeeded(net, srv, rs, ev)
    if ev.backend <> "plex" and rs.prior = invalid then return "no reading, not marked"
    rs.markAttempted = true
    rs.needsCleanup = true
    if ev.backend = "plex" then
        res = NxReportSend(net, NxPlexReportRequest(srv, "GET", "/:/scrobble", "key=" + ev.ratingKey + "&identifier=com.plexapp.plugins.library"))
    else
        ' Always explicit: the session's stops stay short of completion.
        res = net.send("POST", NxMbUserPath(srv, "/PlayedItems/" + NxUrlEncode(ev.ratingKey)), NxMbReportHeaders(srv, false), "")
    end if
    return "marked " + NxToStr(NxReportCode(res))
end function

function NxReportRunCleanup(ex as Object, rs as Object, ev as Object, net as Object, srv as Object) as String
    if not rs.needsCleanup then return "nothing to put back"
    done = []
    if ev.backend = "plex" then
        for each stp in NxPlexCleanupPlan(rs.prior, rs.markAttempted)
            ' Plex adds the next episode about a second after the scrobble.
            ' Look up to three times.
            for attempt = 0 to 2
                added = []
                for each e in NxList(NxPlexContinueWatching(net, srv))
                    if NxToStr(e.grandparentRatingKey) = stp.show and NxTruthy(e.ratingKey) then added.Push(NxToStr(e.ratingKey))
                end for
                for each key in added
                    res = NxReportSend(net, NxPlexReportRequest(srv, "PUT", "/actions/removeFromContinueWatching", "ratingKey=" + key))
                    done.Push("removed " + key + " " + NxToStr(NxReportCode(res)))
                end for
                if added.Count() > 0 or attempt = 2 then exit for
                net.sleep(1000)
            end for
        end for
    else
        for each stp in NxMediaServerCleanupPlan(rs.prior, rs.markAttempted)
            res = NxReportSend(net, NxMbCleanupRequest(srv, stp, ev.ratingKey))
            done.Push(NxCleanupDescribe(stp) + " " + NxToStr(NxReportCode(res)))
        end for
    end if
    rs.needsCleanup = false
    ' The programme's last cleanup: its session keeps nothing more.
    if ev.final = true then ex.boxes.Delete(NxToStr(ev.sessionId))
    if done.Count() = 0 then return "put back, nothing to do"
    return "put back: " + done.Join("; ")
end function

function NxReportCode(res as Dynamic) as Dynamic
    if res = invalid then return "refused"
    return res.code
end function
