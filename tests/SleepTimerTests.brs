' Runs source/guide/SleepTimer.brs against upstream's SleepTimerLogic
' (Services/NowPlayingPanelLogic.swift): presets 15, 30, 60, a running
' timer kept among them, and its labels. Transcribed from the Swift, not
' generated. Returns the failure count.

function NxRunSleepTimerTests() as Integer
    r = { pass: 0, fail: 0 }

    NxCheck(r, "offered none", FormatJson(NxSleepOffered(0)), "[15,30,60]")
    NxCheck(r, "offered preset", FormatJson(NxSleepOffered(30)), "[15,30,60]")
    NxCheck(r, "offered 45 kept", FormatJson(NxSleepOffered(45)), "[15,30,45,60]")
    NxCheck(r, "offered 90 kept", FormatJson(NxSleepOffered(90)), "[15,30,60,90]")
    NxCheck(r, "offered 5 kept", FormatJson(NxSleepOffered(5)), "[5,15,30,60]")

    NxCheck(r, "label off", NxSleepLabel(0), "OFF")
    NxCheck(r, "label 30", NxSleepLabel(30), "30 MIN")
    NxCheck(r, "label 60", NxSleepLabel(60), "1 HR")
    NxCheck(r, "label 90", NxSleepLabel(90), "1 HR 30 MIN")
    NxCheck(r, "label 120", NxSleepLabel(120), "2 HR")

    NxCheck(r, "countdown 0", NxSleepCountdown(0), "0:00")
    NxCheck(r, "countdown 65", NxSleepCountdown(65), "1:05")
    NxCheck(r, "countdown 1799", NxSleepCountdown(1799), "29:59")
    NxCheck(r, "countdown 3600", NxSleepCountdown(3600), "1:00:00")
    NxCheck(r, "countdown 3725", NxSleepCountdown(3725), "1:02:05")
    NxCheck(r, "countdown negative", NxSleepCountdown(-4), "0:00")

    print "sleep timer cases (upstream SleepTimerLogic): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
