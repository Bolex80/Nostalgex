' Runs source/util/DailyRefresh.brs (#67) against upstream's
' startDailyRefresh: a check every 15 minutes, a refresh once both the last
' load and the last check are 6 hours old. Hand-written cases. Returns the
' failure count.

function NxRunDailyRefreshTests() as Integer
    r = { pass: 0, fail: 0 }
    h& = 3600
    now& = 1761480000
    NxCheck(r, "checks every 15 minutes", NxDailyRefreshCheckSec().ToStr(), "900")
    NxCheck(r, "refresh after 6 hours", NxDailyRefreshAfterSec().ToStr(), "21600")
    NxCheck(r, "loaded 5 h 59 m ago: not yet", FormatJson(NxDailyRefreshDue(now&, now& - 6 * h& + 60, 0)), "false")
    NxCheck(r, "loaded 6 h ago, never checked: due", FormatJson(NxDailyRefreshDue(now&, now& - 6 * h&, 0)), "true")
    NxCheck(r, "loaded a day ago, never checked: due", FormatJson(NxDailyRefreshDue(now&, now& - 24 * h&, 0)), "true")
    NxCheck(r, "load old, checked an hour ago: wait", FormatJson(NxDailyRefreshDue(now&, now& - 24 * h&, now& - h&)), "false")
    NxCheck(r, "load old, checked 6 h ago: due", FormatJson(NxDailyRefreshDue(now&, now& - 24 * h&, now& - 6 * h&)), "true")
    NxCheck(r, "loaded just now: not due", FormatJson(NxDailyRefreshDue(now&, now&, 0)), "false")
    print "daily refresh cases (upstream startDailyRefresh): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
