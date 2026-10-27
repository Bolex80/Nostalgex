' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Dolby Vision profile 5 on a Roku whose display can't show Dolby Vision
' (#69). Such a TV draws a profile 5 file green and purple whichever server
' sends it: Plex 1.43.5 copies its HEVC to the Roku's request, and refuses to
' convert it when HEVC isn't offered (measured 2026-10-25 on a local server).
' So, as Chad chose (option (a) on #69), it goes on no channel on such a TV,
' as the shared Emby rule (NxIsLeftOffChannels) already does on every TV.
' The shared rule and its golden cases are unchanged; this is the Roku's own
' step before it, for a display the Apple TV never has to ask about.

' Whether this item stays off channels on a display that does or doesn't
' show Dolby Vision. Profile 8 carries an HDR10 or SDR base layer and plays.
function NxLeftOffForDisplay(item as Object, displayDolbyVision as Boolean) as Boolean
    if displayDolbyVision then return false
    return NxIsNumber(item.doviProfile) and item.doviProfile = 5
end function

' What the display reports (roDeviceInfo.GetDisplayProperties, DolbyVision).
' A Streaming Stick Plus on a TV without Dolby Vision says false.
function NxDisplayShowsDolbyVision() as Boolean
    props = CreateObject("roDeviceInfo").GetDisplayProperties()
    if type(props) <> "roAssociativeArray" then return false
    v = props.DolbyVision
    return (type(v) = "Boolean" or type(v) = "roBoolean") and v
end function

' items less the ones this display leaves off, in the same order.
function NxOnChannelsForDisplay(items as Object, displayDolbyVision as Boolean) as Object
    if displayDolbyVision then return items
    kept = []
    for each it in items
        if not NxLeftOffForDisplay(it, false) then kept.Push(it)
    end for
    return kept
end function
