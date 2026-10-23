' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "probe"
end sub

sub probe()
    m.top.code = NxProbeStream(m.top.url, m.top.serverIndex)
end sub
