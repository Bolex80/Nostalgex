' Runs source/util/RescanInfo.brs and source/util/PlaybackVerdict.brs: the
' RESCAN LIBRARY row's lines (#66). The summary cases are transcribed from
' upstream's LibraryDiagnosticsTests.swift, the verdict wording from
' PlaybackFailure.diagnosticSummary; not generated. Returns the failure count.

function NxRunRescanTests() as Integer
    r = { pass: 0, fail: 0 }

    ' ── LibraryDiagnosticsTests ──
    NxCheck(r, "empty library", NxLibrarySummaryText(NxLibraryCounts([])), "No titles loaded. The scan came back empty.")
    NxCheck(r, "never loaded", NxLibrarySummaryText(invalid), "No titles loaded. The scan came back empty.")
    items = [NxRescanItem("movie", "Jaws"), NxRescanItem("movie", "Alien"), NxRescanItem("episode", "Suits"), NxRescanItem("episode", "Suits"), NxRescanItem("episode", "Lost")]
    NxCheck(r, "counts movies, episodes and shows", NxLibrarySummaryText(NxLibraryCounts(items)), "5 titles · 2 movies · 3 episodes from 2 shows · 100% with genres · 100% matched to TMDB")
    tiny = NxLibrarySummaryText(NxLibraryCounts([NxRescanItem("movie", "Blood Diamond"), NxRescanItem("movie", "Shin Godzilla")]))
    NxCheck(r, "a tiny count is visible", Left(tiny, 8), "2 titles")
    bare = []
    for i = 0 to 3
        it = NxRescanItem("movie", "M" + i.ToStr())
        it.genres = []
        it.tmdbID = invalid
        bare.Push(it)
    end for
    NxCheck(r, "flags unscraped metadata", NxLibrarySummaryText(NxLibraryCounts(bare)), "4 titles · 4 movies · 0% with genres · 0% matched to TMDB")
    many = []
    for i = 0 to 2628
        kind = "episode"
        if i < 349 then kind = "movie"
        many.Push(NxRescanItem(kind, "T" + (i mod 80).ToStr()))
    end for
    NxCheck(r, "thousands are grouped", Left(NxLibrarySummaryText(NxLibraryCounts(many)), 12), "2,629 titles")
    NxCheck(r, "pct 1 of 3", NxPercentOf(1, 3).ToStr(), "33")
    NxCheck(r, "pct 2 of 3", NxPercentOf(2, 3).ToStr(), "67")
    NxCheck(r, "pct of none", NxPercentOf(0, 0).ToStr(), "0")
    NxCheck(r, "grouped 999", NxGroupedInt(999), "999")
    NxCheck(r, "grouped 1000000", NxGroupedInt(1000000), "1,000,000")
    NxCheck(r, "shows by exact title", NxLibraryCounts([NxRescanItem("episode", "Lost"), NxRescanItem("episode", "LOST")]).shows.ToStr(), "2")

    ' ── libraryLastUpdatedText (RelativeDateTimeFormatter, full, numeric) ──
    NxCheck(r, "ago 0", NxRelativeAgo(0), "in 0 seconds")
    NxCheck(r, "ago 1 s", NxRelativeAgo(1), "1 second ago")
    NxCheck(r, "ago 59 s", NxRelativeAgo(59), "59 seconds ago")
    NxCheck(r, "ago 60 s", NxRelativeAgo(60), "1 minute ago")
    NxCheck(r, "ago 2 h", NxRelativeAgo(7300), "2 hours ago")
    NxCheck(r, "ago 1 day", NxRelativeAgo(86400), "1 day ago")
    NxCheck(r, "ago 2 weeks", NxRelativeAgo(15 * 86400), "2 weeks ago")
    NxCheck(r, "ago 3 months", NxRelativeAgo(95 * 86400), "3 months ago")
    NxCheck(r, "future", NxRelativeAgo(-120), "in 2 minutes")

    lines = NxRescanLines(invalid, "Emby", "", 1000)
    NxCheck(r, "row before a load", lines.Join("|"), "No titles loaded. The scan came back empty.|Last updated Never. Pull a fresh copy of your Emby library after adding content")
    held = { counts: NxLibraryCounts(items), at: 1000 }
    lines = NxRescanLines(held, "Plex", "Oct 25 19:30 Plex unreachable: " + Chr(34) + "Jaws" + Chr(34) + ", Can't reach your server", 1000 + 180)
    NxCheck(r, "row with a failure", lines.Join("|"), "5 titles · 2 movies · 3 episodes from 2 shows · 100% with genres · 100% matched to TMDB|Last updated 3 minutes ago. Pull a fresh copy of your Plex library after adding content|Last playback failure: Oct 25 19:30 Plex unreachable: " + Chr(34) + "Jaws" + Chr(34) + ", Can't reach your server")

    ' ── PlaybackFailure.diagnosticSummary ──
    NxCheck(r, "summary refused", NxFailureSummary("serverRefused", "Plex", 500, invalid), "Plex HTTP 500, refused before video")
    NxCheck(r, "summary missing", NxFailureSummary("fileMissing", "Emby", 404, invalid), "Emby HTTP 404, file not on disk")
    NxCheck(r, "summary auth", NxFailureSummary("notAuthorised", "Jellyfin", 401, invalid), "Jellyfin rejected credentials")
    NxCheck(r, "summary slow", NxFailureSummary("serverTooSlow", "Plex", 0, invalid), "Plex below real time on the capped stream")
    NxCheck(r, "summary unreachable", NxFailureSummary("serverUnreachable", "Emby", 0, invalid), "Emby unreachable")
    NxCheck(r, "summary decode", NxFailureSummary("deviceCannotRender", "Plex", 0, "hevc"), "device could not decode hevc")
    NxCheck(r, "summary decode, no codec", NxFailureSummary("deviceCannotRender", "Plex", 0, invalid), "device could not decode the stream")
    NxCheck(r, "summary no source", NxFailureSummary("noPlayableSource", "Emby", 0, invalid), "Emby returned no stream URL")
    NxCheck(r, "summary unknown", NxFailureSummary("unknown", "Plex", 0, invalid), "Plex failed with no usable signal")

    ' A whole line, from giveUp's event, with the stamp's text cut off (it is
    ' the TV's local time).
    e = { server: "Emby", event: "error", rung: "server", errorCode: -2, category: "", probe: 1, codec: invalid }
    card = NxPlaybackFailure(e)
    line = NxPlaybackVerdictLine(e, card, false, "The Matrix", 0)
    NxCheck(r, "verdict line", Mid(line, Instr(1, line, " Emby")), " Emby unreachable: " + Chr(34) + "The Matrix" + Chr(34) + ", Can't reach your server")
    line = NxPlaybackVerdictLine(e, card, true, "", 0)
    NxCheck(r, "verdict line, channel stopped", Mid(line, Instr(1, line, " channel")), " channel stopped after " + NxFailureRunLimit().ToStr() + " failures in a row; last: Emby unreachable: " + Chr(34) + "?" + Chr(34) + ", Nothing on this channel will play right now")
    NxCheck(r, "stamp shape", FormatJson(NxRescanStampShape(NxVerdictStamp(1761420600))), "true")
    for each text in [line, NxRescanLines(held, "Plex", "", 2000).Join(" ")]
        NxCheck(r, "no em dash", Instr(1, text, Chr(8212)).ToStr(), "0")
    end for

    print "rescan cases (upstream LibraryDiagnostics, PlaybackDiagnostics): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxRescanItem(kind as String, title as String) as Object
    return { type: kind, title: title, genres: ["Comedy"], tmdbID: "123" }
end function

' "Oct 25 19:30": a month, a day, a 24-hour time.
function NxRescanStampShape(s as String) as Boolean
    re = CreateObject("roRegex", "^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{1,2} [0-2][0-9]:[0-5][0-9]$", "")
    return re.IsMatch(s)
end function
