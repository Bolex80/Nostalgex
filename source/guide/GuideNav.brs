' Vertical moves in the guide grid, after upstream's ChannelGuideView.swift
' (66033f6, "Up out of channel one belongs to SETTINGS, so only the downward
' wrap gets a sentinel"): Down from the last channel wraps to channel one, Up
' from channel one does not wrap. On the Roku, SETTINGS is the sidebar's first
' row, one Left press away. With fewer than two channels there is nothing to
' wrap to. Returns the new focus index, or -1 when the press isn't handled.
function NxGuideStep(focus as Integer, count as Integer, key as String) as Integer
    if key = "down" then
        if focus < count - 1 then return focus + 1
        if count > 1 then return 0
    else if key = "up" then
        if focus > 0 then return focus - 1
    end if
    return -1
end function
