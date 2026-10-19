' Which channel press owns the player, after upstream's web tuner, where only
' the latest press updates the screen (scripts/web-tune-ownership-smoke.mjs,
' 7485d71). Plex refuses a second transcode while one runs, so a tune waits
' for the running one's stop. Presses made while it waits replace one another,
' and only the latest starts when the stop goes through: an older press must
' never land after a newer one.
function NxTuneQueue() as Object
    return { stopping: false, pending: -1 }
end function

' A press for channel idx; running says a transcode is up and must be stopped
' first. Returns "start" (start idx now), "stop" (stop the running one, idx
' waits for it) or "wait" (a stop is already going through, idx replaces
' whatever was waiting).
function NxTuneAsk(q as Object, idx as Integer, running as Boolean) as String
    if q.stopping then
        q.pending = idx
        return "wait"
    end if
    if running then
        q.stopping = true
        q.pending = idx
        return "stop"
    end if
    return "start"
end function

' The stop went through. Returns the channel to start, or -1 for none.
function NxTuneStopped(q as Object) as Integer
    q.stopping = false
    idx = q.pending
    q.pending = -1
    return idx
end function

' A new guide moved the channels: the one waiting (always the one the
' screen shows as tuned) now sits at idx. A waiting index from the old list
' would start whatever took its place, or nothing at all past the new end.
sub NxTuneMoved(q as Object, idx as Integer)
    if q.pending >= 0 then q.pending = idx
end sub

' Leaving the player: whatever was waiting never starts.
sub NxTuneDrop(q as Object)
    q.pending = -1
end sub
