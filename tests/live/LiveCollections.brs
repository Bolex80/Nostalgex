' Live check of server collections, off-device: tests/live/collections.mjs
' records a real Plex server's collection responses and the library, and this
' replays them through source/collections/Collections.brs in the
' interpreter, printing one line per collection for the script to diff with
' upstream's module. It reads out/live-collections.json and prints library
' data, no token or address. Never part of a build.
sub Main(args = invalid as Dynamic)
    f = ParseJson(ReadAsciiFile("pkg:/out/live-collections.json"))
    if f = invalid then
        print "LIVECOL ERROR no out/live-collections.json"
        return
    end if
    raw = []
    for each s in f.servers
        fetcher = {
            docs: s.docs,
            getJSON: function(path as String) as Dynamic
                if m.docs.DoesExist(path) then return m.docs[path]
                return invalid
            end function
        }
        got = NxCollectionsFetchPlex(s.serverKey, fetcher)
        if got = invalid then
            print "LIVECOL SERVERFAILED " + s.serverKey
        else
            raw.Append(got)
        end if
    end for
    print "LIVECOL RAW " + raw.Count().ToStr()
    for each c in raw
        print "LIVECOL RAWROW " + c.id + " " + c.childKeys.Count().ToStr()
    end for

    targets = []
    for each ch in f.franchiseChannels
        targets.Push(NxCollectionFoldTarget(NxCollectionsChannelLabel(ch), ch.pool, invalid, ch.id))
    end for
    channelsByID = {}
    for each ch in f.channels
        channelsByID[NxToStr(ch.id)] = ch
    end for
    index = NxCollectionsIndexLibrary(f.items, f.serverKeys)
    list = NxCollectionsBuildCandidates(raw, index, {
        staticChannels: f.staticChannels, channelsByID: channelsByID, manifest: ParseJson(ReadAsciiFile("pkg:/data/channels-memberships.json")),
        enabledKeys: NxCollectionKeySet(f.enabledKeys), foldTargets: targets, defs: []
    })
    for each c in list
        keys = []
        for each it in c.items
            keys.Push(NxFranchiseItemKey(it))
        end for
        warning = NxCollectionsDuplicateWarning(c)
        if warning = invalid then warning = "-"
        folded = c.foldedInto
        if folded = invalid then folded = "-"
        print "LIVECOL CAND " + c.id + Chr(9) + c.title + Chr(9) + NxCollectionsMemberSummary(c) + Chr(9) + warning + Chr(9) + folded + Chr(9) + keys.Join(",")
    end for
    built = NxCollectionsMaterialize(list)
    for each ch in built.channels
        print "LIVECOL CHANNEL " + ch.number.ToStr() + " " + ch.collectionID + " " + ch.pool.Count().ToStr()
    end for
    print "LIVECOL DONE"
end sub
