' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' STREAM QUALITY (issue #65), the Apple TV's setting (Models/StreamQuality
' .swift): how much a server is asked to send. The five levels and their
' numbers are upstream's scripts/stream-quality-golden.json, which
' tests/StreamQualityTests.brs holds this table to. Kept on the TV, read
' when a programme is tuned, so a new level reaches the next programme.
'
' What a level changes:
'   Plex           High, Medium and Low add maxVideoBitrate, videoQuality,
'                  videoResolution and autoAdjustQuality=0 to the server
'                  stream, the four the Apple TV sends (NxSqPlexQuery).
'   Jellyfin/Emby  High, Medium and Low set VideoBitrate and MaxWidth on the
'                  server stream (NxMbVideoQuery).
'   Direct play    a file over the ceiling plays through the server instead
'                  (NxSqDirectPlayAllowed).
' Auto and Maximum leave the server stream as it was, as the web tuner
' leaves its own (scripts/nostalgex-stream-quality.js): on Jellyfin and Emby
' that already is the Apple TV's Auto, 40 Mbps at up to 4K; Plex is asked
' for no ceiling. They differ in the remote direct-play ceiling only, as on
' the Apple TV. The ladder's 1080p step (the "capped" rung) asks what it
' did, as the Apple TV's cappedTranscodeURL asks for 1080p whatever the
' level.

' In the Apple TV's order. maxBitrateKbps is Plex's maxVideoBitrate and,
' times 1000, the bits per second Jellyfin and Emby take; videoQualityIndex
' is Plex's videoQuality. remoteCeilingKbps is remoteDirectPlayCeilingKbps,
' -1 for none. detail is the Apple TV's line under each choice.
function NxSqLevels() as Object
    return [
        { id: "auto", name: "Auto", maxBitrateKbps: 40000, width: 3840, height: 2160, videoQualityIndex: 100, remoteCeilingKbps: 20000, detail: "Up to 4K, drops quality when the connection can't keep up." }
        { id: "maximum", name: "Maximum", maxBitrateKbps: 40000, width: 3840, height: 2160, videoQualityIndex: 100, remoteCeilingKbps: -1, detail: "4K, 40 Mbps, never reduced. Fast local networks only." }
        { id: "high", name: "High", maxBitrateKbps: 12000, width: 1920, height: 1080, videoQualityIndex: 90, remoteCeilingKbps: 12000, detail: "1080p, 12 Mbps." }
        { id: "medium", name: "Medium", maxBitrateKbps: 4000, width: 1280, height: 720, videoQualityIndex: 75, remoteCeilingKbps: 4000, detail: "720p, 4 Mbps. Works on most hotel and cafe wifi." }
        { id: "low", name: "Low", maxBitrateKbps: 1500, width: 854, height: 480, videoQualityIndex: 60, remoteCeilingKbps: 1500, detail: "480p, 1.5 Mbps. For weak or metered connections." }
    ]
end function

' The level with this id, else Auto.
function NxSqLevel(id as Dynamic) as Object
    levels = NxSqLevels()
    for each l in levels
        if l.id = NxToStr(id) then return l
    end for
    return levels[0]
end function

' The saved choice, Auto until chosen or when the saved value is no level.
function NxSqCurrent() as String
    return NxSqLevel(NxRegSection("player").Read("streamQuality")).id
end function

sub NxSqSave(id as String)
    reg = NxRegSection("player")
    reg.Write("streamQuality", NxSqLevel(id).id)
    reg.Flush()
end sub

' High, Medium and Low: the levels that change a server stream.
function NxSqIsCapped(id as Dynamic) as Boolean
    return NxHasValue(["high", "medium", "low"], NxToStr(id))
end function

' What a level adds to Plex's server stream, with a leading &; "" for Auto
' and Maximum.
function NxSqPlexQuery(id as Dynamic) as String
    if not NxSqIsCapped(id) then return ""
    l = NxSqLevel(id)
    q = "&maxVideoBitrate=" + l.maxBitrateKbps.ToStr() + "&videoQuality=" + l.videoQualityIndex.ToStr()
    return q + "&videoResolution=" + l.width.ToStr() + "x" + l.height.ToStr() + "&autoAdjustQuality=0"
end function

' Whether a file may direct play under a level. `bitrate` is the file's, in
' kbps; one nobody knows plays direct, as on the Apple TV. Plex: the remote
' ceiling only, and only away from home (PlexAPIService.buildDirectPlayURL).
' Jellyfin and Emby: the Apple TV sends the level's bitrate as the device
' profile's MaxStaticBitrate, the server's limit for direct play, wherever
' the server is; here High, Medium and Low hold direct play to it, and Auto
' and Maximum keep direct play at home as it was, the remote ceiling away.
function NxSqDirectPlayAllowed(kind as String, id as Dynamic, bitrate as Dynamic, isLocal as Boolean) as Boolean
    if not NxIsNumber(bitrate) or bitrate <= 0 then return true
    l = NxSqLevel(id)
    ceiling = -1
    if not isLocal then ceiling = l.remoteCeilingKbps
    if kind <> "plex" and NxSqIsCapped(l.id) then ceiling = l.maxBitrateKbps
    return ceiling < 0 or bitrate <= ceiling
end function

' The Apple TV's isLikelyLocalServer, on the host a stream is fetched from:
' localhost, .local, and the private, loopback and link-local IPv4 ranges,
' plex.direct's dashed addresses (192-168-1-50.abc.plex.direct) included.
' Narrower than NxIsPrivateHost, which lets plain HTTP through: a Tailscale
' or CGNAT address counts as away here, as there.
function NxSqIsLocalHost(host as String) as Boolean
    h = LCase(host)
    if h = "localhost" or (Len(h) > 6 and Right(h, 6) = ".local") then return true
    octets = []
    for each part in h.Replace("-", ".").Split(".")
        if CreateObject("roRegex", "^[0-9]+$", "").IsMatch(part) then octets.Push(part.ToInt())
    end for
    if octets.Count() < 4 then return false
    a = octets[0]
    b = octets[1]
    if a = 10 or a = 127 then return true
    if a = 192 and b = 168 then return true
    if a = 172 and b >= 16 and b <= 31 then return true
    if a = 169 and b = 254 then return true
    return false
end function

' What a level adds to the Plex session's key (NxPlexPlaybackSessionId):
' Plex keeps a session's first decision, so a new ceiling needs its own
' session. "" for Auto and Maximum and on the 1080p rung, which send none.
function NxSqSessionKey(id as Dynamic, rung as String) as String
    if rung = "capped" or not NxSqIsCapped(id) then return ""
    return "-" + NxSqLevel(id).id
end function
