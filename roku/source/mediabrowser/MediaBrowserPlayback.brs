' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Turns a guide airing from a Jellyfin or Emby server into something Roku's
' Video node can play, joined at `offsetSec` as NxPlexStreamContent does for
' Plex, and the stream calls that pick between the two by the airing's server.
'
' Direct play when this TV decodes the file as stored, as
' source/util/DirectPlay.brs asks it (/Videos/{id}/stream.<ext>?Static=true);
' otherwise the server's HLS (/Videos/{id}/master.m3u8), copying the video when the TV decodes it and
' converting only what it doesn't. The HLS address is built here, as the
' Apple TV app's fallback is, rather than asked of PlaybackInfo:
'   - that needs a POST, and network requests can't run on the render thread;
'   - PlaybackInfo had Jellyfin 12.2 burn a file's subtitles into the picture
'     (SubtitleMethod=Encode), a full re-encode, even when asked for none.
' Both server kinds showed a picture for every case this way on a Roku TV,
' joining 20 minutes in (docs/JELLYFIN-EMBY.md, the playback spike); sound
' needed TS segments (below).
'
' Joining part-way: the player starts at PlayStart. Never StartTimeTicks on an
' HLS address: Jellyfin then rejects every segment (HTTP 400), and the
' playlist covers the whole file from 0 anyway.
'
' Security: the token goes in the Authorization header, never in the URL,
' as for Plex. Emby wants it on the playlist, Jellyfin on every segment too,
' and the Video node sends its headers with each request. Nothing here
' reports playback back to the server.

' Returns { content, stopUrl, route } (stopUrl "" for direct play), or invalid.
function NxMbStreamContent(b as Object, offsetSec as LongInteger, s as Object) as Dynamic
    base = NxToStr(s.uri)
    lower = LCase(base)
    onLan = Left(lower, 7) = "http://" and NxIsPrivateHost(NxUrlHost(base))
    if Left(lower, 8) <> "https://" and not onLan then return invalid
    route = "HTTPS"
    if onLan then route = "home network"
    if offsetSec < 0 then offsetSec = 0
    itemId = NxToStr(b.ratingKey)
    msid = NxToStr(NxOr(b.partKey, itemId))

    content = CreateObject("roSGNode", "ContentNode")
    content.title = b.line
    content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    content.HttpHeaders = ["Authorization:" + NxMbAuthHeader(NxToStr(s.accessToken))]
    content.PlayStart = offsetSec

    container = LCase(NxToStr(b.container))
    vcodec = LCase(NxToStr(b.videoCodec))
    acodec = LCase(NxToStr(b.audioCodec))
    hevc = NxCanDecodeHevc()
    videoOk = vcodec = "h264" or (vcodec = "hevc" and hevc)
    audioOk = NxHasValue(["aac", "ac3", "eac3", "mp3"], acodec)
    ' MKV only on the home network: joined part-way it played at once over
    ' plain HTTP on the LAN, while through Plex over HTTPS it crawled.
    containers = ["mp4", "mov", "m4v"]
    if onLan then containers.Push("mkv")
    direct = NxHasValue(containers, container) and videoOk and audioOk
    ' And only what this TV decodes, profile and channels included.
    if direct then direct = NxDeviceDecodes(b)

    if direct then
        ' .mp4 on the MP4 family: Jellyfin labels a static stream by the
        ' file's name otherwise (scripts/nostalgex-jellyfin-urls.js).
        ext = "mkv"
        format = "mkv"
        if container <> "mkv" then
            ext = "mp4"
            format = "mp4"
        end if
        content.url = base + "/Videos/" + NxUrlEncode(itemId) + "/stream." + ext + "?Static=true&MediaSourceId=" + NxUrlEncode(msid)
        content.streamFormat = format
        return { content: content, stopUrl: "", route: route }
    end if

    ' Emby needs a PlaySessionId on a hand-built address or every segment
    ' fails (EmbyAPIService.buildTranscodeURL); Jellyfin takes one as well.
    session = LCase(CreateObject("roDeviceInfo").GetRandomUUID().Replace("-", ""))
    videoCodecs = "h264"
    if hevc then videoCodecs = "h264,hevc"
    q = "MediaSourceId=" + NxUrlEncode(msid)
    q = q + "&DeviceId=" + NxUrlEncode(NxPlexClientId())
    q = q + "&PlaySessionId=" + session
    q = q + "&VideoCodec=" + videoCodecs
    info = CreateObject("roDeviceInfo")
    ac3 = NxDecodeAnswer(info.CanDecodeAudio({ Codec: "ac3" }))
    eac3 = NxDecodeAnswer(info.CanDecodeAudio({ Codec: "eac3" }))
    aac51 = NxDecodeAnswer(info.CanDecodeAudio({ Codec: "aac", ChCnt: 6 }))
    q = q + NxMbAudioQuery(ac3, eac3, aac51)
    ' High enough that the server copies the video rather than re-encode it
    ' to fit, as the web tuner asks.
    q = q + "&VideoBitrate=120000000"
    ' TS segments on both servers, HEVC included. A Roku played no sound
    ' from fMP4, even stereo AAC, on Emby and on Jellyfin (Discussion #8,
    ' 2026-10-22), and TS carries the source timestamps, so a join stays in
    ' sync where fMP4's ran up to a GOP early (docs/JELLYFIN-EMBY.md).
    q = q + "&SegmentContainer=ts"
    ' 2-second segments, not the servers' 6, so a piece of a 4K remux fits
    ' the player's buffer: one stopped with error -3, "Requested reservation
    ' (11065599+56589021) is larger than the entire buffer" (issue #58).
    ' Plex sends 1 s. With the video copied the server cuts only at
    ' keyframes, so a file whose keyframes are further apart still gets
    ' longer pieces (docs/JELLYFIN-EMBY.md).
    q = q + "&SegmentLength=2"
    content.url = base + "/Videos/" + NxUrlEncode(itemId) + "/master.m3u8?" + q
    content.streamFormat = "hls"
    stopUrl = base + "/Videos/ActiveEncodings?deviceId=" + NxUrlEncode(NxPlexClientId()) + "&playSessionId=" + session
    return { content: content, stopUrl: stopUrl, route: route }
end function

' The audio the server stream may carry: AAC, and AC3 or E-AC-3 only when
' this TV decodes them, at most 5.1 only when it decodes 5.1 AAC. A codec in
' the list is copied as stored, so offering Dolby to a TV that says no to it
' played silent (Discussion #8: E-AC-3 on a Streaming Stick Plus set to
' Stereo). Without the cap a 5.1 film came back as 5.1 AAC, which that stick
' doesn't decode either; with it, stereo AAC, as Plex sends.
function NxMbAudioQuery(ac3 as Boolean, eac3 as Boolean, aac51 as Boolean) as String
    codecs = "aac"
    if ac3 then codecs = codecs + ",ac3"
    if eac3 then codecs = codecs + ",eac3"
    channels = "2"
    if aac51 then channels = "6"
    return "&AudioCodec=" + codecs + "&TranscodingMaxAudioChannels=" + channels
end function

' The saved server an airing comes from, or invalid.
function NxStreamServer(b as Object) as Dynamic
    ' Signing out empties the list while a stream may still be stopping.
    raw = NxPlexRegistry().Read("servers")
    if raw = "" then return invalid
    servers = ParseJson(raw)
    if type(servers) <> "roArray" or b.serverIndex = invalid then return invalid
    if b.serverIndex >= servers.Count() then return invalid
    return servers[b.serverIndex]
end function

' The airing as something to play, from whichever kind of server it is on:
' { content, stopUrl, route }, or invalid.
function NxStreamContent(b as Object, offsetSec as LongInteger) as Dynamic
    s = NxStreamServer(b)
    if s = invalid then return invalid
    if NxServerKind(s) = "plex" then return NxPlexStreamContent(b, offsetSec)
    return NxMbStreamContent(b, offsetSec, s)
end function

' Video nodes take headers through their own ifHttpAgent; a ContentNode's
' HttpHeaders field alone left a TV buffering with no request reaching Plex.
sub NxApplyStreamAuth(video as Object, b as Object)
    s = NxStreamServer(b)
    if s = invalid then return
    if NxServerKind(s) = "plex" then
        NxPlexApplyAuth(video, NxToStr(s.accessToken))
        return
    end if
    video.SetCertificatesFile("common:/certs/ca-bundle.crt")
    video.SetHeaders({ "Authorization": NxMbAuthHeader(NxToStr(s.accessToken)) })
end sub

' Ends the server's work on a stream the guide has left (PlexStopTask).
' Jellyfin and Emby: DELETE /Videos/ActiveEncodings, which ends an encode
' within about a second (the web tuner sends only this). Returns the HTTP code.
function NxStopStream(stopUrl as String, serverIndex as Integer) as Integer
    s = NxStreamServer({ serverIndex: serverIndex })
    if s = invalid then return 0
    if NxServerKind(s) = "plex" then return NxPlexVideoRequest(stopUrl, NxToStr(s.accessToken))
    return NxServerRequest("DELETE", stopUrl, NxMbHeaders(NxToStr(s.accessToken)), "", 5000).code
end function
