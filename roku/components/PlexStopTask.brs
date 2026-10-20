' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "stopTranscode"
end sub

sub stopTranscode()
    code = NxStopStream(m.top.stopUrl, m.top.serverIndex)
    print "player: stopped the previous transcode ("; code; ")"
end sub
