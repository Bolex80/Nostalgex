' Runs source/guide/DeepLink.brs: what a launch or roInput deep link names.
' Hand-written cases; deep links are the Roku's own, with nothing upstream to
' match. Returns the failure count.

function NxRunDeepLinkTests() as Integer
    r = { pass: 0, fail: 0 }

    NxCheck(r, "no args", FormatJson(NxDeepLinkFrom(invalid)), "null")
    NxCheck(r, "plain launch", FormatJson(NxDeepLinkFrom({ source: "homescreen" })), "null")
    NxCheck(r, "no mediaType", FormatJson(NxDeepLinkFrom({ contentId: "7" })), "null")
    NxCheck(r, "empty contentId", FormatJson(NxDeepLinkFrom({ contentId: " ", mediaType: "live" })), "null")
    link = NxDeepLinkFrom({ contentId: " 7 ", mediaType: "live", source: "external-control" })
    NxCheck(r, "link", FormatJson(link), "{""contentId"":""7"",""mediaType"":""live""}")

    channels = [
        { id: 1, number: 1, name: "ONE" },
        { id: 9, number: 7, name: "SEVEN" },
        { id: 7, number: 12, name: "TWELVE" },
        { id: 900001, number: 300, name: "FRANCHISE" },
    ]
    NxCheck(r, "id before number", NxDeepLinkChannel(channels, link).ToStr(), "2")
    NxCheck(r, "by number", NxDeepLinkChannel(channels, { contentId: "300", mediaType: "live" }).ToStr(), "3")
    NxCheck(r, "by franchise id", NxDeepLinkChannel(channels, { contentId: "900001", mediaType: "movie" }).ToStr(), "3")
    NxCheck(r, "unknown", NxDeepLinkChannel(channels, { contentId: "abc", mediaType: "live" }).ToStr(), "-1")
    NxCheck(r, "no channels", NxDeepLinkChannel(invalid, link).ToStr(), "-1")
    NxCheck(r, "no link", NxDeepLinkChannel(channels, invalid).ToStr(), "-1")
    NxCheck(r, "unset field", NxDeepLinkChannel(channels, {}).ToStr(), "-1")

    print "deep link cases: "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
