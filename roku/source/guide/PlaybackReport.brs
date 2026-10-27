' SHOW NOW PLAYING and MARK WATCHED (issue #72): the viewer's two choices and
' the watch clock, on the guide's thread. What goes to the server, and in
' what order, is source/guide/ReportExecutor.brs, run by components/ReportTask.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: the Apple TV app's Services/PlaybackReportingPreferences.swift and
' Services/PlaybackTracker.swift, at the commit in data/UPSTREAM, with the
' web tuner's scripts/nostalgex-watch-state.js, which shares
' scripts/watch-cleanup-golden.json with it. Both choices are off until the
' viewer turns them on; with both off nothing is sent.
'
' The tracker here is pure: each call takes the clock and returns the events
' to hand to the report task, so tests/ReportTests.brs drives it on a
' synthetic clock. Events: { kind: "report", state, pulse, ticks,
' durationTicks } (a Now Playing report, or the session's stop), { kind:
' "mark" } (count the watch) and { kind: "cleanup" } (put the item's watch
' state back), each with the session, the item and the choices' epochs.
'
' Differences from upstream:
'   - No iCloud sync and no legacy single switch: the Roku never had one.
'   - No backgrounding: a Roku app that leaves the screen exits. Leaving with
'     Back waits for the stop and the cleanup to go out, up to 4 seconds.
'   - The clock runs from the first picture to the stop, as upstream's does
'     for a one-part file; the Roku has no multi-part files.

' ── The choices ─────────────────────────────────────────────────────────────

' { nowPlaying, markWatched }, off unless the viewer turned them on.
function NxReportPrefs() as Object
    reg = NxRegSection("player")
    if reg = invalid then return { nowPlaying: false, markWatched: false }
    return { nowPlaying: reg.Read("reportNowPlaying") = "1", markWatched: reg.Read("reportMarkWatched") = "1" }
end function

sub NxSaveReportPrefs(prefs as Object)
    reg = NxRegSection("player")
    if reg = invalid then return
    reg.Write("reportNowPlaying", NxReportFlag(prefs.nowPlaying = true))
    reg.Write("reportMarkWatched", NxReportFlag(prefs.markWatched = true))
    reg.Flush()
end sub

function NxReportFlag(on as Boolean) as String
    if on then return "1"
    return "0"
end function

' PlaybackReportingControlScope: the choices, with an epoch each that moves
' when that choice changes. Work queued under an old epoch is dropped, so
' turning a choice off revokes it at once, and on again never revives it.
function NxReportScope(prefs as Object) as Object
    return { nowPlaying: prefs.nowPlaying = true, markWatched: prefs.markWatched = true, activityEpoch: 0, markEpoch: 0 }
end function

sub NxReportScopeUpdate(scope as Object, prefs as Object)
    if scope.nowPlaying <> (prefs.nowPlaying = true) then
        scope.nowPlaying = prefs.nowPlaying = true
        scope.activityEpoch = scope.activityEpoch + 1
    end if
    if scope.markWatched <> (prefs.markWatched = true) then
        scope.markWatched = prefs.markWatched = true
        scope.markEpoch = scope.markEpoch + 1
    end if
end sub

function NxReportAllowsActivity(scope as Dynamic, epoch as Dynamic) as Boolean
    if scope = invalid then return false
    return scope.nowPlaying = true and NxToStr(epoch) = NxToStr(scope.activityEpoch)
end function

function NxReportAllowsMark(scope as Dynamic, epoch as Dynamic) as Boolean
    if scope = invalid then return false
    return scope.markWatched = true and NxToStr(epoch) = NxToStr(scope.markEpoch)
end function

' ── The gate ────────────────────────────────────────────────────────────────

' Tuned in during the first 15% of the programme.
function NxReportEligible(offsetSec as Dynamic, durationMin as Dynamic) as Boolean
    if not NxIsNumber(durationMin) or not NxIsNumber(offsetSec) then return false
    total = durationMin * 60.0
    if total <= 0 then return false
    return offsetSec / total <= 0.15
end function

' At least 75% of the programme's runtime watched.
function NxReportCounted(activeSec as Double, durationMin as Dynamic) as Boolean
    if not NxIsNumber(durationMin) then return false
    total = durationMin * 60.0
    if total <= 0 then return false
    return activeSec / total >= 0.75
end function

' ── The tracker ─────────────────────────────────────────────────────────────

' One tune-in of one airing. b is the guide block, offsetSec where it joined,
' kind the server's ("plex", "jellyfin", "emby").
function NxReportTracker(b as Object, offsetSec as Dynamic, kind as String, sessionId as String) as Object
    offset = 0
    if NxIsNumber(offsetSec) then offset = offsetSec
    duration = 0
    if NxIsNumber(b.duration) then duration = b.duration
    return {
        sessionId: sessionId, kind: kind, serverIndex: b.serverIndex,
        ratingKey: NxToStr(b.ratingKey), partKey: NxToStr(NxOr(b.partKey, b.ratingKey)), type: NxToStr(b.type),
        startSec: b.startSec, durationMin: duration, offset: offset,
        eligible: NxReportEligible(offset, duration),
        activeSec: 0.0, watchStart: invalid, ready: false, stopped: false, scrobbled: false, playerState: invalid
    }
end function

' The same airing: a retry or a step down keeps its tracker.
function NxReportSameAiring(t as Dynamic, b as Dynamic) as Boolean
    if t = invalid or b = invalid then return false
    return t.ratingKey = NxToStr(b.ratingKey) and NxToStr(t.startSec) = NxToStr(b.startSec) and NxToStr(t.serverIndex) = NxToStr(b.serverIndex)
end function

sub NxReportAccumulate(t as Object, nowSec as Double)
    if t.watchStart = invalid then return
    t.activeSec = t.activeSec + (nowSec - t.watchStart)
    t.watchStart = invalid
end sub

' Where the programme is, as the reports carry it: ms, then 100 ns ticks.
function NxReportTicks(t as Object) as LongInteger
    ms& = t.offset * 1000& + Int(t.activeSec * 1000)
    return ms& * 10000&
end function

function NxReportEvent(t as Object, scope as Object, kind as String) as Object
    duration& = t.durationMin
    return {
        kind: kind, sessionId: t.sessionId, backend: t.kind, serverIndex: t.serverIndex,
        ratingKey: t.ratingKey, partKey: t.partKey, type: t.type,
        durationTicks: duration& * 600000000&, activityEpoch: scope.activityEpoch, markEpoch: scope.markEpoch
    }
end function

' sendTimeline: a report while Now Playing is on; a stop always, which the
' report task sends only for a session it reported.
function NxReportTimeline(t as Object, scope as Object, state as String, pulse = false as Boolean) as Object
    if state <> "stopped" and scope.nowPlaying <> true then return []
    ev = NxReportEvent(t, scope, "report")
    ev.state = state
    if state = "playing" and t.playerState <> invalid then ev.state = t.playerState
    ev.pulse = pulse
    ev.ticks = NxReportTicks(t)
    return [ev]
end function

' evaluateAndScrobble: once, when Mark Watched is on, the entry gate passed
' and 75% of the runtime has been watched.
function NxReportEvaluate(t as Object, scope as Object) as Object
    if scope.markWatched <> true or not t.eligible or t.scrobbled then return []
    if not NxReportCounted(t.activeSec, t.durationMin) then return []
    t.scrobbled = true
    return [NxReportEvent(t, scope, "mark")]
end function

' onPlaybackReady: the first picture starts the clock and the pulses.
function NxReportReady(t as Object, scope as Object, nowSec as Double) as Object
    if t.stopped then return []
    if t.watchStart = invalid then t.watchStart = nowSec
    t.ready = true
    return NxReportTimeline(t, scope, "playing")
end function

' The 10-second pulse.
function NxReportTick(t as Object, scope as Object, nowSec as Double) as Object
    if t.stopped or not t.ready then return []
    NxReportAccumulate(t, nowSec)
    t.watchStart = nowSec
    out = NxReportTimeline(t, scope, "playing", true)
    out.Append(NxReportEvaluate(t, scope))
    return out
end function

' onHeartbeatPlaybackState: on Plex a pause or a stall shows at once. The
' clock isn't touched.
function NxReportPlayerState(t as Object, scope as Object, state as String) as Object
    if t.stopped or not t.ready or NxToStr(t.playerState) = state then return []
    t.playerState = state
    if t.kind <> "plex" then return []
    return NxReportTimeline(t, scope, state)
end function

' stop: the programme ended, the channel changed, or the app is leaving.
function NxReportStop(t as Object, scope as Object, nowSec as Double) as Object
    if t.stopped then return []
    t.stopped = true
    NxReportAccumulate(t, nowSec)
    out = NxReportTimeline(t, scope, "stopped")
    out.Append(NxReportEvaluate(t, scope))
    last = NxReportEvent(t, scope, "cleanup")
    last.final = true
    out.Push(last)
    return out
end function

' updateReporting: a choice changed while a programme plays. The clock goes
' on; turning Now Playing off stops the session, turning either off puts the
' item back, turning Now Playing on reports at once.
function NxReportUpdate(t as Object, was as Object, scope as Object) as Object
    out = []
    wasShowing = was.nowPlaying = true
    wasMarking = was.markWatched = true
    if wasShowing = (scope.nowPlaying = true) and wasMarking = (scope.markWatched = true) then return out
    ' A mark the report task already sent is never sent again (it keeps
    ' that per session); one still queued was dropped by the new epoch.
    if wasMarking <> (scope.markWatched = true) then t.scrobbled = false
    if wasShowing and scope.nowPlaying <> true then out.Append(NxReportTimeline(t, scope, "stopped"))
    if (wasShowing and scope.nowPlaying <> true) or (wasMarking and scope.markWatched <> true) then out.Push(NxReportEvent(t, scope, "cleanup"))
    if not wasShowing and scope.nowPlaying = true and not t.stopped and t.ready then
        state = "playing"
        if t.playerState <> invalid then state = t.playerState
        out.Append(NxReportTimeline(t, scope, state))
    end if
    return out
end function
