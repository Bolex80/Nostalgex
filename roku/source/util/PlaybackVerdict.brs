' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' The line a playback that was given up on leaves for Settings' RESCAN
' LIBRARY row (#66), as upstream's PlaybackDiagnostics.record and
' PlaybackFailure.diagnosticSummary. Stored by NxRecordPlaybackVerdict
' (source/util/RescanInfo.brs).

' One stored verdict, as record(outcome:title:detail:) writes it:
' `Oct 25 19:30 Emby unreachable: "The Matrix", Can't reach your server`.
' e is giveUp's event (NxPlaybackFailure's argument), card what it made, and
' stopped whether the channel stopped (PlaybackFailure.channelStopped).
function NxPlaybackVerdictLine(e as Object, card as Object, stopped as Boolean, title as String, nowSec as LongInteger) as String
    probe = 1
    if NxIsNumber(e.probe) then probe = e.probe
    status = 0
    if NxProbeVerdict(probe) = "refused" then status = probe
    outcome = NxFailureSummary(card.kind, NxToStr(e.server), status, e.codec)
    detail = card.headline
    if stopped then
        outcome = "channel stopped after " + NxFailureRunLimit().ToStr() + " failures in a row; last: " + outcome
        detail = NxChannelStoppedCard(card).headline
    end if
    if title = "" then title = "?"
    return NxVerdictStamp(nowSec) + " " + outcome + ": " + Chr(34) + title + Chr(34) + ", " + detail
end function

' PlaybackFailure.diagnosticSummary.
function NxFailureSummary(kind as String, server as String, status as Integer, codec as Dynamic) as String
    if kind = "serverRefused" then return server + " HTTP " + status.ToStr() + ", refused before video"
    if kind = "fileMissing" then return server + " HTTP 404, file not on disk"
    if kind = "notAuthorised" then return server + " rejected credentials"
    if kind = "serverTooSlow" then return server + " below real time on the capped stream"
    if kind = "serverUnreachable" then return server + " unreachable"
    if kind = "deviceCannotRender" then
        what = NxToStr(codec)
        if what = "" then what = "the stream"
        return "device could not decode " + what
    end if
    if kind = "noPlayableSource" then return server + " returned no stream URL"
    return server + " failed with no usable signal"
end function

' The diagnostics clock, "MMM d HH:mm", in the TV's time zone.
function NxVerdictStamp(nowSec as LongInteger) as String
    dt = CreateObject("roDateTime")
    dt.FromSeconds(nowSec)
    dt.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    hh = dt.GetHours().ToStr()
    if Len(hh) < 2 then hh = "0" + hh
    mm = dt.GetMinutes().ToStr()
    if Len(mm) < 2 then mm = "0" + mm
    return months[dt.GetMonth() - 1] + " " + dt.GetDayOfMonth().ToStr() + " " + hh + ":" + mm
end function
