' Runs source/guide/SleepTimer.brs against upstream's SleepTimerLogic
' (Services/NowPlayingPanelLogic.swift): presets 15, 30, 60, a running
' timer kept among them, and its labels. And source/guide/NowPlayingLayout.brs
' against NowPlayingPanelLayout.programRows from the same file. Transcribed
' from the Swift (NowPlayingPanelLogicTests), not generated. Returns the
' failure count.

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

    ' programRows (#118), OPEN IN PLEX left out on the Roku.
    NxCheck(r, "rows: no subtitles, one audio track", NxPanelProgramRows(false, 1).Join(","), "captionsHeader,captions,audioHeader,audioTracks")
    NxCheck(r, "rows: no subtitles, no audio keeps cc", NxPanelProgramRows(false, 0).Join(","), "captionsHeader,captions,audioHeader,audioTracks")
    NxCheck(r, "rows: subtitles add their preferences", NxPanelProgramRows(true, 1).Join(","), "captionsHeader,captions,subtitleLanguage,autoSubtitles,audioHeader,audioTracks")
    NxCheck(r, "rows: two audio tracks add audio language", NxPanelProgramRows(false, 2).Join(","), "captionsHeader,captions,audioHeader,audioTracks,audioLanguage")
    NxCheck(r, "rows: everything, in order", NxPanelProgramRows(true, 3).Join(","), "captionsHeader,captions,subtitleLanguage,autoSubtitles,audioHeader,audioTracks,audioLanguage")

    print "sleep timer cases (upstream SleepTimerLogic, NowPlayingPanelLayout): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
