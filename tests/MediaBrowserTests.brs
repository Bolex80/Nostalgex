' Runs NxMbScanServer (source/mediabrowser/MediaBrowserLibrary.brs) over the
' saved server answers in tests/fixtures/mediabrowser-server.json, served the
' way tests/gen-mediabrowser.mjs serves them to upstream's own
' fetchJellyfinLibraryFromServer, and holds it to that function's requests
' and items (tests/vectors/mediabrowser.json). Plus hand-written cases for
' the date parser and the Emby libraries path. Returns the failure count.

function NxRunMediaBrowserTests(vectorsPath as String, fixturePath as String) as Integer
    r = { pass: 0, fail: 0 }
    v = ParseJson(ReadAsciiFile(vectorsPath))
    fx = ParseJson(ReadAsciiFile(fixturePath))
    if v = invalid or fx = invalid then
        print "FAIL cannot read "; vectorsPath; " or "; fixturePath
        return 1
    end if

    fetcher = NxMbFixtureFetcher(fx)
    got = NxMbScanServer(fetcher, "jellyfin", fx.userId, 2)
    NxCheck(r, "scan returns items", NxToStr(got <> invalid), "true")
    if got <> invalid then
        NxCheck(r, "requests", fetcher.requests.Join(" | "), NxList(v.requests).Join(" | "))
        NxCheck(r, "item count", got.Count().ToStr(), NxList(v.items).Count().ToStr())
        ' Port-only fields: none reaches the filter or schedule.
        extras = { serverIndex: true, seasonNumber: true, episodeNumber: true }
        n = NxMinInt(got.Count(), NxList(v.items).Count())
        for i = 0 to n - 1
            want = v.items[i]
            it = got[i]
            label = "item " + i.ToStr() + " " + NxToStr(want.ratingKey)
            for each k in want
                NxCheck(r, label + " " + k, FormatJson(NxMbJsonValue(it[k])), FormatJson(NxMbJsonValue(want[k])))
            end for
            ' By lowercased name: on a TV an AA literal's keys iterate
            ' lowercased, while ParseJson's keep their case.
            wantKeys = {}
            for each k in want
                wantKeys[LCase(k)] = true
            end for
            for each k in it
                if not wantKeys.DoesExist(LCase(k)) and not extras.DoesExist(k) then NxCheck(r, label + " has no field " + k, "present", "absent")
            end for
            NxCheck(r, label + " serverIndex", NxToStr(it.serverIndex), "2")
        end for
    end if

    ' A rejected token fails the scan.
    denied = NxMbFixtureFetcher(fx)
    denied.deny = true
    NxCheck(r, "rejected token: invalid", NxToStr(NxMbScanServer(denied, "jellyfin", fx.userId, 0) = invalid), "true")

    ' Emby lists libraries under the user.
    NxCheck(r, "views path, jellyfin", NxMbViewsPath("jellyfin", "u 1"), "/UserViews?userId=u%201")
    NxCheck(r, "views path, emby", NxMbViewsPath("emby", "u1"), "/Users/u1/Views")

    ' DateCreated as Date.parse reads it, floored to seconds. LongInteger
    ' literals: on Roku OS 16 these (all past 2^30) came out as Floats and
    ' printed as 1.69208e+09, while 951868799 stayed an Integer.
    dates = [
        ["2023-08-15T07:19:45.0000000Z", 1692083985&],
        ["1970-01-01T00:00:00Z", 0],
        ["2000-02-29T23:59:59.999Z", 951868799],
        ["2024-12-31T12:00:00+02:00", 1735639200&],
        ["2024-12-31T12:00:00-05:30", 1735666200&],
        ["2021-06-01", 1622505600&],
        ["2021-06-01T08:30Z", 1622536200&],
        ["not a date", 0],
        ["", 0],
        [invalid, 0]
    ]
    for each d in dates
        NxCheck(r, "date " + NxToStr(d[0]), NxMbUnixSeconds(d[0]).ToStr(), d[1].ToStr())
    end for


    ' What someone types as a server address.
    addrs = [
        ["172.16.0.5", "http://172.16.0.5:8096 http://172.16.0.5"],
        [" http://10.0.0.2:8920/web/index.html#!/home ", "http://10.0.0.2:8920"],
        ["https://media.example.org/jellyfin/", "https://media.example.org/jellyfin"],
        ["http://nas.local/emby", "http://nas.local:8096/emby http://nas.local/emby"],
        ["HTTPS://Box:443", "https://Box:443"],
        ["", ""],
        ["http://", ""]
    ]
    for each a in addrs
        NxCheck(r, "address " + a[0], NxMbAddressCandidates(a[0]).Join(" "), a[1])
    end for

    ' /System/Info/Public as each server answers it (trimmed).
    jf = { code: 200, json: { LocalAddress: "http://10.0.0.2:8096", ServerName: "den", Version: "12.2.0", ProductName: "Jellyfin Server", Id: "9a88", StartupWizardCompleted: true } }
    em = { code: 200, json: { LocalAddresses: [], RemoteAddresses: [], ServerName: "", Version: "4.10.1.0", Id: "1cc8" } }
    NxCheck(r, "public info, jellyfin", FormatJson(NxMbReadPublicInfo(jf)), FormatJson({ name: "den", id: "9a88", kind: "jellyfin", version: "12.2.0" }))
    NxCheck(r, "public info, emby", FormatJson(NxMbReadPublicInfo(em)), FormatJson({ name: "Emby Server", id: "1cc8", kind: "emby", version: "4.10.1.0" }))
    NxCheck(r, "public info, a web page", NxToStr(NxMbReadPublicInfo({ code: 200, json: invalid }) = invalid), "true")
    NxCheck(r, "public info, something else", NxToStr(NxMbReadPublicInfo({ code: 200, json: { ServerName: "x" } }) = invalid), "true")

    ' AuthenticateByName's answer.
    ok = { code: 200, json: { User: { Name: "n", Id: "u1" }, AccessToken: "t1", ServerId: "s1" } }
    NxCheck(r, "auth, accepted", FormatJson(NxMbReadAuth(ok)), FormatJson({ token: "t1", userId: "u1", serverId: "s1" }))
    NxCheck(r, "auth, refused", FormatJson(NxMbReadAuth({ code: 401, json: invalid })), """""")
    NxCheck(r, "auth, no token", FormatJson(NxMbReadAuth({ code: 200, json: { User: { Id: "u1" } } })), """""")
    NxCheck(r, "auth, unreachable", NxToStr(NxMbReadAuth({ code: -28, json: invalid }) = invalid), "true")

    print "mediabrowser cases:"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' JSON null and a missing field read alike, as the vectors drop neither.
function NxMbJsonValue(x as Dynamic) as Dynamic
    if x = invalid then return invalid
    return x
end function

' A fetcher over the fixture, as gen-mediabrowser.mjs's serveFixture: the
' libraries list, then /Items by ParentId and IncludeItemTypes, paged by
' StartIndex and Limit. A parent in `fail` answers as a failed request.
function NxMbFixtureFetcher(fx as Object) as Object
    return {
        fx: fx,
        requests: [],
        auth: false,
        deny: false,
        getJSON: function(path as String) as Dynamic
            m.requests.Push(path)
            if m.deny then
                m.auth = true
                return invalid
            end if
            q = {}
            cut = Instr(1, path, "?")
            base = path
            if cut > 0 then
                base = Left(path, cut - 1)
                for each pair in Mid(path, cut + 1).Split("&")
                    eq = Instr(1, pair, "=")
                    if eq > 0 then q[Left(pair, eq - 1)] = Mid(pair, eq + 1)
                end for
            end if
            if base = "/UserViews" or CreateObject("roRegex", "^/Users/[^/]+/Views$", "").IsMatch(base) then
                return { Items: m.fx.views, TotalRecordCount: m.fx.views.Count() }
            end if
            if base <> "/Items" then return invalid
            if NxHasValue(NxList(m.fx.fail), q.ParentId) then return invalid
            all = []
            for each it in NxList(m.fx.items[q.ParentId])
                if it.Type = q.IncludeItemTypes then all.Push(it)
            end for
            start = q.StartIndex.ToInt()
            limit = q.Limit.ToInt()
            page = []
            for i = start to NxMinInt(start + limit, all.Count()) - 1
                page.Push(all[i])
            end for
            return { Items: page, TotalRecordCount: all.Count() }
        end function,
        getMany: function(paths as Object) as Object
            out = []
            for each p in paths
                out.Push(m.getJSON(p))
            end for
            return out
        end function
    }
end function
