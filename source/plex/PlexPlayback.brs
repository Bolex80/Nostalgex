' Turns a guide airing into something Roku's Video node can play, joined at
' `offsetSec` so the channel plays like live TV.
'
' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Direct play when this TV decodes the file as stored; otherwise Plex's HLS
' transcode, as upstream's web tuner falls back to (plex-tuner.html
' playCurrentItem). Upstream decides for a browser, this decides for a Roku,
' so the direct-play list differs; what airs when doesn't.
'
' Security: the token goes in a request header, never in the URL, so it can't
' leak through a logged URL. Video uses the server's home-network address when
' one answered as that server (private addresses only, see
' source/plex/ServerResolve.brs), else
' HTTPS with certificates checked. Nothing here
' reports playback back to Plex (no timeline, no scrobble): the app reads
' your library and never changes it.

' The token for a block's server, for NxPlexApplyAuth. "" if unknown.
function NxPlexStreamToken(b as Object) as String
    servers = ParseJson(NxPlexRegistry().Read("servers"))
    if type(servers) <> "roArray" or b.serverIndex = invalid then return ""
    if b.serverIndex >= servers.Count() then return ""
    return NxToStr(servers[b.serverIndex].accessToken)
end function

' Video nodes take headers through their own ifHttpAgent; a ContentNode's
' HttpHeaders field alone left this TV buffering with no request reaching Plex.
sub NxPlexApplyAuth(video as Object, token as String)
    video.SetCertificatesFile("common:/certs/ca-bundle.crt")
    video.SetHeaders({ "X-Plex-Token": token })
end sub

' Returns { content, stopUrl } (stopUrl "" for direct play), or invalid.
function NxPlexStreamContent(b as Object, offsetSec as LongInteger) as Dynamic
    servers = ParseJson(NxPlexRegistry().Read("servers"))
    if type(servers) <> "roArray" or b.serverIndex = invalid then return invalid
    if b.serverIndex >= servers.Count() then return invalid
    s = servers[b.serverIndex]
    base = NxToStr(s.uri)
    if LCase(Left(base, 8)) <> "https://" then return invalid
    lan = NxToStr(s.lanUri)
    if lan <> "" and LCase(Left(lan, 7)) = "http://" then
        host = Mid(lan, 8)
        colon = Instr(1, host, ":")
        if colon > 0 then host = Left(host, colon - 1)
        if NxIsPrivateHost(host) then base = lan
    end if
    route = "HTTPS"
    if base <> NxToStr(s.uri) then route = "home network"
    if offsetSec < 0 then offsetSec = 0

    content = CreateObject("roSGNode", "ContentNode")
    content.title = b.line
    content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    content.HttpHeaders = ["X-Plex-Token:" + NxToStr(s.accessToken)]

    container = LCase(NxToStr(b.container))
    vcodec = LCase(NxToStr(b.videoCodec))
    acodec = LCase(NxToStr(b.audioCodec))
    direct = NxTruthy(b.partKey)
    ' Upstream's direct-play containers. MKV goes through Plex too: joining an
    ' MKV mid-file made this TV crawl (13% buffered after a minute) on a link
    ' that moves ~300 Mbit/s, while Plex can remux it and start at the offset.
    direct = direct and NxHasValue(["mp4", "mov", "m4v"], container)
    direct = direct and NxHasValue(["h264", "hevc"], vcodec)
    direct = direct and NxHasValue(["aac", "ac3", "eac3", "mp3"], acodec)

    if direct then
        stopUrl = ""
        content.url = base + NxToStr(b.partKey)
        content.streamFormat = "mp4"
        content.PlayStart = offsetSec
    else
        session = CreateObject("roDeviceInfo").GetRandomUUID()
        q = "path=" + NxUrlEncode("/library/metadata/" + NxToStr(b.ratingKey))
        q = q + "&mediaIndex=0&partIndex=0&protocol=hls&directStream=1&fastSeek=1"
        q = q + "&offset=" + offsetSec.ToStr()
        ' Plex's Roku profile re-encodes HEVC to H.264 unless told otherwise.
        ' On a TV that decodes HEVC, let it copy the video instead: no work on
        ' the server and the original picture.
        profile = "h264"
        if NxCanDecodeHevc() then profile = "hevc"
        ' Text subtitles come as a WebVTT track the TV shows or hides, as
        ' upstream's tvOS app asks (subtitles=auto). Without the target, Plex
        ' burns in a file's default subtitles and re-encodes the video to do it.
        ' Plex offers the one track that this Plex account has selected for the
        ' file; image subtitles (PGS, VobSub) are still burned in.
        extra = "add-transcode-target(type=subtitleProfile&context=streaming&protocol=hls&container=webvtt&subtitleCodec=webvtt)"
        if profile = "hevc" then
            extra = extra + "+add-transcode-target-codec(type=videoProfile&context=streaming&protocol=hls&videoCodec=hevc)"
        end if
        q = q + "&subtitles=auto"
        q = q + "&session=" + session + "&X-Plex-Session-Identifier=" + NxPlexPlaybackSessionId(profile + "-vtt")
        q = q + "&X-Plex-Client-Identifier=" + NxPlexClientId()
        q = q + "&X-Plex-Product=nostalgex-roku&X-Plex-Platform=Roku&X-Plex-Device=Roku"
        q = q + "&X-Plex-Client-Profile-Extra=" + NxUrlEncode(extra)
        content.url = base + "/video/:/transcode/universal/start.m3u8?" + q
        content.streamFormat = "hls"
        ' Plex's playlist spans the whole file from 0:00 whatever the offset
        ' (checked 2026-10-16: offset=1800 gave 5758 one-second segments for
        ' a 96-minute film), so the player is started at the offset as well;
        ' without it, playback starts at 0:00.
        content.PlayStart = offsetSec
        stopUrl = base + "/video/:/transcode/universal/stop?session=" + session
    end if
    return { content: content, stopUrl: stopUrl, route: route }
end function

function NxCanDecodeHevc() as Boolean
    res = CreateObject("roDeviceInfo").CanDecodeVideo({ Codec: "hevc" })
    return res <> invalid and res.Result = true
end function
