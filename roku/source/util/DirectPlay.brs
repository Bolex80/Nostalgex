' Direct play only what this TV decodes (Discussion #8, phase 1 item 2). The
' players' container and codec lists say what may be sent as stored; this
' asks the TV, through roDeviceInfo's CanDecodeVideo and CanDecodeAudio,
' whether it decodes this file's video codec at its profile, and its audio
' codec.
' Upstream's Apple TV rules (PlexAPIService undecodableVideoReason: no
' 10-bit H.264, no Dolby Vision profile 7) answer for AVPlayer; a Roku
' answers for itself. A no sends the airing to the server stream, so a file
' the TV can't show no longer plays as a black screen.
'
' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

' The questions for an airing, in roDeviceInfo's terms. What the library
' didn't say is left out, and the TV answers for the rest. No Container: the
' players' lists already decide that, and a Roku names .mov and .m4v "mp4".
' `channels` is the audio question with the channel count, invalid when it
' isn't known. It is asked and printed but doesn't decide yet: these files
' played as stored before, a TV may downmix what it says no to, and a no
' for 6-channel AAC alone would send most of a library to the server.
function NxDecodeQueries(b as Object) as Object
    video = { Codec: NxRokuVideoCodec(LCase(NxToStr(b.videoCodec))) }
    profile = NxRokuVideoProfile(LCase(NxToStr(b.videoProfile)).Trim())
    if profile <> "" then video.Profile = profile
    audio = { Codec: LCase(NxToStr(b.audioCodec)) }
    channels = invalid
    if NxIsNumber(b.audioChannels) and b.audioChannels > 0 then channels = { Codec: audio.Codec, ChCnt: b.audioChannels }
    return { video: video, audio: audio, channels: channels }
end function

' Plex, Jellyfin and Emby say h264; roDeviceInfo says "mpeg4 avc".
function NxRokuVideoCodec(codec as String) as String
    if codec = "h264" or codec = "avc" then return "mpeg4 avc"
    return codec
end function

' A Roku names only main and high as H.264 profiles: a Streaming Stick Plus
' says no to "baseline" and "constrained baseline" alike. Constrained
' baseline, what Jellyfin and Emby name and what baseline files are in
' practice, is a subset of main, so both are asked as main.
function NxRokuVideoProfile(profile as String) as String
    if profile = "baseline" or profile = "constrained baseline" then return "main"
    return profile
end function

' Whether this TV decodes the airing's video and audio as stored. Each no is
' printed, codec and profile only, so a TV's console says why a file went to
' the server.
function NxDeviceDecodes(b as Object) as Boolean
    q = NxDecodeQueries(b)
    info = CreateObject("roDeviceInfo")
    videoOk = NxDecodeAnswer(info.CanDecodeVideo(q.video))
    audioOk = NxDecodeAnswer(info.CanDecodeAudio(q.audio))
    if audioOk and q.channels <> invalid then
        if not NxDecodeAnswer(info.CanDecodeAudio(q.channels)) then print "playback: this TV says no to "; FormatJson(q.channels); ", played as stored as before"
    end if
    if not videoOk then print "playback: this TV doesn't decode "; FormatJson(q.video); ", so the server streams it"
    if not audioOk then print "playback: this TV doesn't decode "; FormatJson(q.audio); ", so the server streams it"
    return videoOk and audioOk
end function

' Yes only for a Result that is true; no answer, or no Result, is a no.
function NxDecodeAnswer(res as Dynamic) as Boolean
    if type(res) <> "roAssociativeArray" then return false
    t = type(res.Result)
    if t <> "Boolean" and t <> "roBoolean" then return false
    return res.Result
end function
