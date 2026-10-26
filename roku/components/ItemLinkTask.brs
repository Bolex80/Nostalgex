' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "find"
end sub

sub find()
    found = invalid
    servers = ParseJson(NxPlexRegistry().Read("servers"))
    if type(servers) = "roArray" then
        ' Each server's save key, as LibraryTask keys them.
        keys = []
        for each s in servers
            key = NxToStr(s.machineIdentifier)
            if key = "" then key = "plex"
            keys.Push(key)
        end for
        dir = NxSnapshotDir()
        meta = NxSnapshotReadMeta(dir)
        ' What was there to look in, so a miss says whether the save was gone
        ' (the OS clears cachefs:, which lives in RAM) or the id wasn't in it.
        saved = 0
        savedServers = 0
        for each key in keys
            entry = meta.servers[key]
            if type(entry) = "roAssociativeArray" and NxIsNumber(entry.count) then
                saved = saved + entry.count
                savedServers = savedServers + 1
            end if
        end for
        print "deep link: the saved library holds "; saved; " items, from "; savedServers; " of "; keys.Count(); " servers"
        found = NxSnapshotFindItem(dir, meta, keys, m.top.itemId)
    else
        print "deep link: no server is set up"
    end if
    if found = invalid then
        m.top.airing = {}
    else
        m.top.airing = NxLinkedAiring(found, CreateObject("roDateTime").AsSeconds())
    end if
end sub
