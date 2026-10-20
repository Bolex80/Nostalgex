' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' When an airing hands over to the next, after upstream's advanceToNextItem
' (App/AppState+Playback.swift). The schedule counts whole minutes, but a file
' runs to its own length, which can be up to a minute past its slot (Plex's
' milliseconds rounded) or short of it. Upstream moves on when the file ends,
' not when the slot does, and starts the next item from its beginning, so the
' last seconds of an episode are never cut. The player itself lives in
' components/GuideView.brs.

' How long an airing may run past its slot before the clock takes over
' anyway: a stream that reports playing but never finishes must not hold the
' channel. Upstream has no such cap; five minutes is well past any rounding
' or metadata drift (upstream measured 40+ s).
function NxOverrunCapSec() as Integer
    return 300
end function

' Whether the clock should take the channel off the airing it plays. Not
' while the file is still playing past its slot: it ends on its own.
function NxAiringEnded(playing as Dynamic, t as LongInteger, videoState as String) as Boolean
    if playing = invalid or t < playing.endSec then return false
    if videoState = "playing" and t < playing.endSec + NxOverrunCapSec() then return false
    return true
end function

' The airing to start from its beginning when the playing one's file ends at
' t. What airs now, if the schedule has moved past it (the file ran over);
' else the one after it (the file ended early). invalid when neither exists.
function NxNextAiring(blocks as Object, playing as Object, t as LongInteger) as Dynamic
    now = invalid
    after = invalid
    for each b in blocks
        if t >= b.startSec and t < b.endSec then now = b
        if after = invalid and b.startSec >= playing.endSec then after = b
    end for
    if now <> invalid and now.startSec <> playing.startSec then return now
    return after
end function
