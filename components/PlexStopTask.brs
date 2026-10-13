' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "stopTranscode"
end sub

sub stopTranscode()
    token = NxPlexStreamToken({ serverIndex: m.top.serverIndex })
    code = NxPlexVideoRequest(m.top.stopUrl, token)
    print "player: stopped the previous Plex transcode ("; code; ")"
end sub
