' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' The sleep timer's choices and labels, as upstream's SleepTimerLogic
' (Services/NowPlayingPanelLogic.swift). The timer itself, and the STILL
' WATCHING? prompt it ends with, live in components/GuideView.brs.

function NxSleepPresets() as Object
    return [15, 30, 60]
end function

' The minute rows the panel shows: the presets, plus a running timer's own
' length if it isn't one of them, in order, so its countdown keeps a row.
function NxSleepOffered(armed as Integer) as Object
    out = NxSleepPresets()
    if armed <= 0 or NxHasValue(out, armed) then return out
    sorted = []
    placed = false
    for each p in out
        if not placed and armed < p then
            sorted.Push(armed)
            placed = true
        end if
        sorted.Push(p)
    end for
    if not placed then sorted.Push(armed)
    return sorted
end function

' "30 MIN", "1 HR", "1 HR 30 MIN"; "OFF" for none.
function NxSleepLabel(minutes as Integer) as String
    if minutes <= 0 then return "OFF"
    hours = minutes \ 60
    mins = minutes mod 60
    if hours = 0 then return mins.ToStr() + " MIN"
    if mins = 0 then return hours.ToStr() + " HR"
    return hours.ToStr() + " HR " + mins.ToStr() + " MIN"
end function

' "m:ss", or "h:mm:ss" from an hour.
function NxSleepCountdown(remainingSec as Integer) as String
    if remainingSec < 0 then remainingSec = 0
    hours = remainingSec \ 3600
    minutes = (remainingSec mod 3600) \ 60
    seconds = remainingSec mod 60
    ss = Right("0" + seconds.ToStr(), 2)
    if hours > 0 then return hours.ToStr() + ":" + Right("0" + minutes.ToStr(), 2) + ":" + ss
    return minutes.ToStr() + ":" + ss
end function
