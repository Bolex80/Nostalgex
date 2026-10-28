' Holds the Plex UTF-8 repair (source/plex/PlexApi.brs, issue #121) to
' upstream's scripts/utf8-repair-golden.json, the cases the Apple TV
' (PlexUTF8RepairGoldenTests) and the web tuner check: each case's bytes
' must come out as its text, with its count of repaired bytes. Off the TV a
' string can't hold a byte that isn't UTF-8, so the cases that go in as a
' string run on a TV only. Returns the failure count.
function NxRunUtf8RepairTests(goldenPath as String) as Integer
    r = { pass: 0, fail: 0 }
    g = ParseJson(ReadAsciiFile(goldenPath))
    if g = invalid then
        print "FAIL cannot read "; goldenPath
        return 1
    end if
    for each c in g.cases
        b = CreateObject("roByteArray")
        b.FromHexString(c.hex)
        want = NxUtf8TestHex(c.text) + " " + NxToStr(c.repairedBytes)
        got = NxUtf8RepairBytes(b)
        NxCheck(r, "bytes: " + c.name, NxUtf8TestHex(got.text) + " " + got.repairedBytes.ToStr(), want)
        if NxTestRuntime() = "device" then
            got = NxPlexUtf8Repair(b.ToAsciiString())
            NxCheck(r, "text: " + c.name, NxUtf8TestHex(got.text) + " " + got.repairedBytes.ToStr(), want)
        end if
    end for

    if NxTestRuntime() = "device" then
        ' A page with a Latin-1 title, through the step a Plex answer takes.
        b = CreateObject("roByteArray")
        b.FromHexString("7b224d65646961436f6e7461696e6572223a7b224d65746164617461223a5b7b227469746c65223a22436166e920536f6369657479227d5d7d7d")
        doc = NxParseJsonBody(NxPlexRepaired(b.ToAsciiString(), "http://192.0.2.5:32400/library/sections/1/all?includeGuids=1"))
        title = ""
        if type(doc) = "roAssociativeArray" then title = doc.MediaContainer.Metadata[0].title
        NxCheck(r, "a page with a Latin-1 title", title, "Caf" + Chr(233) + " Society")
        ' Split between items: a leading byte order mark, a bad byte in the
        ' second item, and a title that holds the separator itself.
        b.FromHexString("efbbbf7b224d65746164617461223a5b7b227469746c65223a2241227d2c7b227469746c65223a2242e9227d2c7b7d2c7b227469746c65223a22787d2c7b79227d5d7d")
        doc = NxParseJsonBody(NxPlexRepaired(b.ToAsciiString(), "http://192.0.2.5:32400/library/sections/2/all"))
        titles = []
        if type(doc) = "roAssociativeArray" then
            for each it in doc.Metadata
                titles.Push(NxToStr(it.title))
            end for
        end if
        NxCheck(r, "a page split between items", titles.Join("|"), "A|B" + Chr(233) + "||x},{y")
        ' ParseJson fails on a leading byte order mark; the repair drops it.
        b.FromHexString("efbbbf7b2261223a317d")
        doc = NxParseJsonBody(NxPlexRepaired(b.ToAsciiString(), "https://plex.tv/api/v2/resources"))
        NxCheck(r, "a page after a byte order mark", NxToStr(type(doc) = "roAssociativeArray"), "true")
    end if

    NxCheck(r, "log context: path and query", NxUrlPathAndQuery("http://192.0.2.5:32400/library/sections/1/all?includeGuids=1"), "/library/sections/1/all?includeGuids=1")
    NxCheck(r, "log context: no path", NxUrlPathAndQuery("https://plex.tv"), "/")

    print "utf-8 repair cases (upstream utf8-repair-golden.json): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' A string's bytes as hex, lower case.
function NxUtf8TestHex(s as String) as String
    b = CreateObject("roByteArray")
    b.FromAsciiString(s)
    return LCase(b.ToHexString())
end function
