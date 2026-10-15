' Runs source/subtitles/SubtitleSelection.brs against the cases in upstream's
' NostalgexTests/SubtitleSelectionLogicTests.swift, copied one for one: Swift
' can't run here, so these are transcribed, not generated. Returns the
' failure count.

function NxRunSubtitleTests() as Integer
    r = { pass: 0, fail: 0 }

    NxCheck(r, "resolved explicit", NxSubResolvedLanguage("fr", "en_US"), "fr")
    NxCheck(r, "resolved system de", NxSubResolvedLanguage("__system__", "de_DE"), "de")
    NxCheck(r, "resolved system ja", NxSubResolvedLanguage("__system__", "ja_JP"), "ja")

    NxCheck(r, "tag extended", NxToStr(NxSubLanguageTag("en-US", "fr_FR")), "en-us")
    NxCheck(r, "tag locale", NxToStr(NxSubLanguageTag(invalid, "es_ES")), "es")
    NxCheck(r, "tag underscore", NxToStr(NxSubLanguageTag(invalid, "pt_BR")), "pt")

    NxCheck(r, "index exact", NxSubPreferredTrackIndex(["en", "es"], "en").ToStr(), "0")
    NxCheck(r, "index region", NxSubPreferredTrackIndex(["es", "en-us"], "en").ToStr(), "1")
    NxCheck(r, "index fallback", NxSubPreferredTrackIndex(["de", "fr"], "ja").ToStr(), "0")
    NxCheck(r, "index nil", NxSubPreferredTrackIndex([invalid, "fr"], "en").ToStr(), "0")

    NxCheck(r, "auto foreign only", NxSubShouldAutoEnable(["fr"], "en").ToStr(), "true")
    NxCheck(r, "auto match present", NxSubShouldAutoEnable(["fr", "en"], "en").ToStr(), "false")
    NxCheck(r, "auto region match", NxSubShouldAutoEnable(["en-us"], "en").ToStr(), "false")
    NxCheck(r, "auto empty", NxSubShouldAutoEnable([], "en").ToStr(), "false")
    NxCheck(r, "auto nil", NxSubShouldAutoEnable([invalid], "en").ToStr(), "false")
    NxCheck(r, "auto und", NxSubShouldAutoEnable(["und"], "en").ToStr(), "false")
    NxCheck(r, "auto und mixed", NxSubShouldAutoEnable(["fr", "und"], "en").ToStr(), "false")
    NxCheck(r, "auto case", NxSubShouldAutoEnable(["EN"], "en").ToStr(), "false")
    NxCheck(r, "auto many foreign", NxSubShouldAutoEnable(["fr", "de", "ja"], "en").ToStr(), "true")

    print "subtitle cases (upstream SubtitleSelectionLogicTests): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
