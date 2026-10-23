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
' isn't known. A no to it sends the airing to the server too: a Streaming
' Stick Plus says no to 6-channel AAC and played such a file as stored with
' no sound, while through the server it came as stereo AAC with sound
' (PR #80, 2026-10-23).
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
    answers = { video: info.CanDecodeVideo(q.video), audio: info.CanDecodeAudio(q.audio) }
    if q.channels <> invalid then answers.channels = info.CanDecodeAudio(q.channels)
    nos = NxDecodeNos(q, answers)
    for each no in nos
        print "playback: this TV doesn't decode "; FormatJson(no); ", so the server streams it"
    end for
    return nos.Count() = 0
end function

' The questions the TV said no to, from its answers to NxDecodeQueries. The
' channel count is asked only when the codec is a yes.
function NxDecodeNos(q as Object, answers as Object) as Object
    nos = []
    if not NxDecodeAnswer(answers.video) then nos.Push(q.video)
    if not NxDecodeAnswer(answers.audio) then
        nos.Push(q.audio)
    else if q.channels <> invalid and not NxDecodeAnswer(answers.channels) then
        nos.Push(q.channels)
    end if
    return nos
end function

' Yes only for a Result that is true; no answer, or no Result, is a no.
function NxDecodeAnswer(res as Dynamic) as Boolean
    if type(res) <> "roAssociativeArray" then return false
    t = type(res.Result)
    if t <> "Boolean" and t <> "roBoolean" then return false
    return res.Result
end function
