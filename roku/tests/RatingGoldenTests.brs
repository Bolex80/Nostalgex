' Runs upstream's scripts/rating-golden.json (copied unchanged to
' tests/vectors/), the cases its Swift RatingGoldenTests and web
' nostalgex-rating-smoke.mjs both read: a raw rating, an item type and the US
' label the channel rules must read for it (GitHub #41). null is no rating.
' Returns the failure count.

function NxRunRatingGoldenTests(goldenPath as String) as Integer
    golden = ParseJson(ReadAsciiFile(goldenPath))
    if golden = invalid then
        print "FAIL cannot read "; goldenPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    for each c in golden.cases
        got = NxUsContentRating(c.raw, c.type)
        NxCheck(r, "rating " + FormatJson(c.raw) + " as " + c.type, FormatJson(got), FormatJson(c.us))
    end for
    print "rating golden cases (upstream rating-golden.json):"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
