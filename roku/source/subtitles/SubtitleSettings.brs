' The subtitle settings, kept on the TV, and the Roku side of matching
' languages.
'
' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

' { always, foreign }: upstream's subtitlesInFullscreenEnabled, off until
' chosen, and autoSubtitlesForForeignAudioEnabled, on until chosen
' (AppState.swift: `?? true`), so a fresh install reads FOREIGN AUDIO.
function NxSubtitleSettings() as Object
    reg = NxRegSection("player")
    return NxSubtitleSettingsFrom(reg.Read("subsAlways"), reg.Read("subsForeign"))
end function

' From the saved values, "" when never saved.
function NxSubtitleSettingsFrom(always as String, foreign as String) as Object
    return { always: always = "1", foreign: foreign <> "0" }
end function

' Only a flag that changed is written, as upstream writes one key per
' setting: the CC toggle saves ALWAYS and leaves FOREIGN AUDIO unchosen, so
' its default still applies.
sub NxSaveSubtitleSettings(s as Object)
    reg = NxRegSection("player")
    was = NxSubtitleSettings()
    if s.always <> was.always then reg.Write("subsAlways", NxFlag(s.always))
    if s.foreign <> was.foreign then reg.Write("subsForeign", NxFlag(s.foreign))
    reg.Flush()
end sub

function NxFlag(on as Boolean) as String
    if on then return "1"
    return "0"
end function

' Upstream's SubtitleLanguagePreset.all (Models/SubtitleLanguagePreset.swift),
' the list both language settings offer, with the Roku's name for "follow the
' device".
function NxLanguagePresets() as Object
    return [
        { code: "__system__", label: "MATCH ROKU LANGUAGE" }
        { code: "en", label: "ENGLISH" }
        { code: "es", label: "SPANISH" }
        { code: "fr", label: "FRENCH" }
        { code: "de", label: "GERMAN" }
        { code: "it", label: "ITALIAN" }
        { code: "pt-BR", label: "PORTUGUESE (BRAZIL)" }
        { code: "ja", label: "JAPANESE" }
        { code: "ko", label: "KOREAN" }
        { code: "zh-Hans", label: "CHINESE (SIMPLIFIED)" }
        { code: "zh-Hant", label: "CHINESE (TRADITIONAL)" }
        { code: "ru", label: "RUSSIAN" }
        { code: "ar", label: "ARABIC" }
        { code: "nl", label: "DUTCH" }
        { code: "pl", label: "POLISH" }
        { code: "sv", label: "SWEDISH" }
    ]
end function

' displayLabel(for:): the preset's label, else the code in capitals.
function NxLanguageLabel(code as String) as String
    for each p in NxLanguagePresets()
        if p.code = code then return p.label
    end for
    return UCase(code)
end function

' SUBTITLE LANGUAGE ("subsLanguage") or AUDIO LANGUAGE ("audioLanguage") as
' saved, "__system__" until chosen, as upstream's
' loadPreferredSubtitleLanguageInitial and loadPreferredAudioLanguageInitial.
function NxSavedLanguage(key as String) as String
    v = CreateObject("roRegistrySection", "player").Read(key)
    if v = "" then return "__system__"
    return v
end function

sub NxSaveLanguage(key as String, code as String)
    reg = CreateObject("roRegistrySection", "player")
    reg.Write(key, code)
    reg.Flush()
end sub

' The language a setting asks for, as tracks here are compared: Roku hands a
' track's language over without a region (NxSubComparableTag), so the
' setting is reduced to its language too, and PORTUGUESE (BRAZIL) matches a
' Portuguese track. "__system__" is the TV's locale.
function NxPreferredLanguageFrom(code as String, localeId as String) as String
    primary = NxSubPrimary(NxSubResolvedLanguage(code, localeId))
    if primary = invalid then return "en"
    return primary
end function

' upstream's resolvedPreferredSubtitleLanguageCode. Plex still sends the
' subtitle track the Plex account has selected: this picks among the tracks
' the player lists, and asks nothing of Plex.
function NxSubPreferredLanguage() as String
    return NxPreferredLanguageFrom(NxSavedLanguage("subsLanguage"), CreateObject("roDeviceInfo").GetCurrentLocale())
end function

' upstream's resolvedPreferredAudioLanguageCode.
function NxAudioPreferredLanguage() as String
    return NxPreferredLanguageFrom(NxSavedLanguage("audioLanguage"), CreateObject("roDeviceInfo").GetCurrentLocale())
end function

' The player's track for `lang` among `listed` (availableAudioTracks), as
' upstream's applyAudioTrackSelection picks with preferredTrackIndex: the
' first in that language. invalid when none is, which leaves the player's
' own choice where upstream takes the first track.
function NxAudioTrackForLanguage(listed as Object, lang as String) as Dynamic
    for each t in listed
        tag = NxSubComparableTag(t.Language)
        if tag <> invalid and NxSubMatches(tag, lang) then return t.Track
    end for
    return invalid
end function

' Roku reports a track's language as the stream gives it: Plex's HLS says
' "eng", where AVFoundation hands upstream "en". Two-letter codes for the
' three-letter ones of upstream's language list; others pass through.
function NxSubComparableTag(lang as Dynamic) as Dynamic
    if lang = invalid then return invalid
    t = LCase(NxToStr(lang)).Trim()
    if t = "" then return invalid
    iso2 = { eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de", ita: "it", por: "pt", jpn: "ja", kor: "ko", chi: "zh", zho: "zh", rus: "ru", ara: "ar", dut: "nl", nld: "nl", pol: "pl", swe: "sv" }
    if iso2.DoesExist(t) then return iso2[t]
    return t
end function
