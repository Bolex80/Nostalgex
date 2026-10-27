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

    ' The settings' defaults (#64): AppState.swift reads FOREIGN AUDIO as on
    ' until it is chosen, fullscreen subtitles as off.
    NxCheck(r, "fresh install: foreign on", FormatJson(NxSubtitleSettingsFrom("", "").foreign), "true")
    NxCheck(r, "fresh install: always off", FormatJson(NxSubtitleSettingsFrom("", "").always), "false")
    NxCheck(r, "foreign chosen off is kept", FormatJson(NxSubtitleSettingsFrom("", "0").foreign), "false")
    NxCheck(r, "foreign chosen on", FormatJson(NxSubtitleSettingsFrom("", "1").foreign), "true")
    NxCheck(r, "always chosen on", FormatJson(NxSubtitleSettingsFrom("1", "").always), "true")

    ' SUBTITLE and AUDIO LANGUAGE (#62): upstream's presets, and a choice
    ' reduced to its language, as tracks here carry none of the region.
    presets = NxLanguagePresets()
    NxCheck(r, "presets: fifteen languages and the device", presets.Count().ToStr(), "16")
    NxCheck(r, "presets: the device first", presets[0].code + "=" + presets[0].label, "__system__=MATCH ROKU LANGUAGE")
    NxCheck(r, "label of a preset", NxLanguageLabel("pt-BR"), "PORTUGUESE (BRAZIL)")
    NxCheck(r, "label of an unknown code", NxLanguageLabel("fi"), "FI")
    ' shortLabel (#118), the Now Playing panel's value.
    NxCheck(r, "short label: the device is system", NxLanguageShortLabel("__system__"), "SYSTEM")
    NxCheck(r, "short label: a code in capitals", NxLanguageShortLabel("en") + " " + NxLanguageShortLabel("pt-BR") + " " + NxLanguageShortLabel("zh-Hans"), "EN PT-BR ZH-HANS")
    NxCheck(r, "preferred: the device", NxPreferredLanguageFrom("__system__", "fr_CA"), "fr")
    NxCheck(r, "preferred: a choice beats the device", NxPreferredLanguageFrom("de", "en_US"), "de")
    NxCheck(r, "preferred: region dropped", NxPreferredLanguageFrom("pt-BR", "en_US"), "pt")
    NxCheck(r, "preferred: script dropped", NxPreferredLanguageFrom("zh-Hant", "en_US"), "zh")
    NxCheck(r, "preferred: no locale is english", NxPreferredLanguageFrom("__system__", ""), "en")
    listed = [{ Track: "a1", Language: "eng" }, { Track: "a2", Language: "ger" }, { Track: "a3", Language: "deu" }]
    NxCheck(r, "audio track: the first in the language", NxToStr(NxAudioTrackForLanguage(listed, "de")), "a2")
    NxCheck(r, "audio track: english", NxToStr(NxAudioTrackForLanguage(listed, "en")), "a1")
    NxCheck(r, "audio track: none leaves the player's", NxToStr(NxAudioTrackForLanguage(listed, "ja") = invalid), "true")
    NxCheck(r, "audio track: portuguese (brazil) takes por", NxToStr(NxAudioTrackForLanguage([{ Track: "x", Language: "eng" }, { Track: "y", Language: "por" }], NxPreferredLanguageFrom("pt-BR", "en_US"))), "y")
    NxCheck(r, "audio track: untagged never matches", NxToStr(NxAudioTrackForLanguage([{ Track: "x", Language: "" }, { Track: "y" }], "en") = invalid), "true")

    ' pickLegibleOption (#63): a full track before a forced one.
    NxCheck(r, "pick: the full track over a forced one", NxSubPickIndex(["en", "en"], [true, false], "en").ToStr(), "1")
    NxCheck(r, "pick: a forced one when it's all there is", NxSubPickIndex(["en"], [true], "en").ToStr(), "0")
    NxCheck(r, "pick: forced in the language over another", NxSubPickIndex(["fr", "en"], [false, true], "en").ToStr(), "1")
    NxCheck(r, "pick: none in the language, the first", NxSubPickIndex(["fr", "de"], [false, false], "ja").ToStr(), "0")
    NxCheck(r, "pick: case of the tag", NxSubPickIndex(["EN"], [false], "en").ToStr(), "0")

    print "subtitle cases (upstream SubtitleSelectionLogicTests): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
