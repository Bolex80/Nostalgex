' Franchise channel grouping, ported from Nostalgex.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: upstream scripts/nostalgex-franchise-builder.js, the web port of the
' Apple TV's FranchiseChannelBuilder.swift, over the shared dictionary
' data/franchises.json. Every rule, and the order the rules run in, is
' upstream's, checked against upstream's own golden file (vendored unchanged as
' tests/vectors/franchise-golden.json) and tests/vectors/franchise.json. Don't
' change grouping logic here; propose it upstream.
'
' Differences that don't change results:
'
' - NxFranchiseDefinitions works out each definition's title keys once. Upstream
'   recomputes them for every item, and a Roku has thousands of episodes.
'   NxFranchiseBuild also remembers the dictionary match, and the found
'   franchise match, per TV title, because every episode of a show has the
'   same title and neither match depends on anything else.
' - NxFranchiseTitleKey takes two regex replacements for an ASCII title,
'   which give the key the character walk gives, without the walk.
' - Text is walked a code point at a time. Upstream walks grapheme clusters;
'   NxFranchiseGraphemes joins combining marks onto the character before them,
'   which is the same split for any title Plex is likely to hold.
' - Upstream judges letters and numbers with \p{Alphabetic} and \p{N}, which
'   roRegex doesn't support. NxFranchiseCharClass has the ranges written out
'   for Latin, Greek, Cyrillic, kana, CJK punctuation and full-width forms;
'   other scripts count as letters apart from their common punctuation.
'   Upstream already approximates Swift here.
' - Names sort by code point, as upstream's compareStrings does, without its
'   NFC step. Plex hands out NFC titles.
' - Lowercasing is NxFranchiseLower, not LCase. On the TV, LCase leaves
'   full-width letters and Roman numerals alone and maps Έ to ҽ (seen on Roku
'   OS 15 and 16), where JS toLowerCase lowers all three. NxFranchiseLower has
'   JS's mappings written out for Latin, Greek (final sigma included),
'   Cyrillic, Armenian, Roman numerals, circled and full-width letters.
'
' What the Roku lacks: TMDB enrichment. Without `item.enrichment` a film has no
' collection id, so only the dictionary's titles and tokens place it, as on the
' web tuner before enrichment loads.

function NxFranchiseDefaultMinimumFilms() as Integer
    return 3
end function

' ── Unicode helpers ─────────────────────────────────────────────────────────

' 0 for anything else, 1 for a letter (\p{Alphabetic}), 2 for a number (\p{N}).
function NxFranchiseCharClass(cp as Integer) as Integer
    if cp < 128 then
        if cp >= 48 and cp <= 57 then return 2
        if (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) then return 1
        return 0
    end if
    if cp < 192 then
        if cp = 170 or cp = 181 or cp = 186 then return 1
        if cp = 178 or cp = 179 or cp = 185 or (cp >= 188 and cp <= 190) then return 2
        return 0
    end if
    if cp <= 591 then
        if cp = 215 or cp = 247 then return 0
        return 1
    end if
    if cp <= 705 then return 1
    if cp < 880 then
        if (cp >= 710 and cp <= 721) or (cp >= 736 and cp <= 740) or cp = 748 or cp = 750 or cp = 837 then return 1
        return 0
    end if
    if cp <= 1023 then
        if cp = 884 or cp = 885 or cp = 888 or cp = 889 or cp = 894 or cp = 900 or cp = 901 or cp = 903 or cp = 1014 then return 0
        if cp >= 896 and cp <= 899 then return 0
        return 1
    end if
    if cp <= 1327 then
        if cp >= 1154 and cp <= 1161 then return 0
        return 1
    end if
    ' Hebrew and Arabic punctuation and digits.
    if cp >= 1470 and cp <= 1475 and cp <> 1471 and cp <> 1473 and cp <> 1474 then return 0
    if cp = 1478 or cp = 1523 or cp = 1524 or cp = 1548 or cp = 1563 or cp = 1567 or cp = 1748 then return 0
    if cp >= 1545 and cp <= 1547 then return 0
    if (cp >= 1632 and cp <= 1641) or (cp >= 1776 and cp <= 1785) or (cp >= 2406 and cp <= 2415) then return 2
    if cp >= 1642 and cp <= 1645 then return 0
    if cp = 2404 or cp = 2405 then return 0
    ' General punctuation, super- and subscripts, currency, letterlike symbols.
    if cp >= 8192 and cp <= 8303 then return 0
    if cp >= 8304 and cp <= 8348 then
        if cp = 8305 or cp = 8319 or (cp >= 8336 and cp <= 8348) then return 1
        if cp = 8304 or (cp >= 8308 and cp <= 8313) or (cp >= 8320 and cp <= 8329) then return 2
        return 0
    end if
    if cp >= 8352 and cp <= 8399 then return 0
    if cp >= 8400 and cp <= 8447 then return 0
    if cp >= 8448 and cp <= 8527 then
        if cp = 8450 or cp = 8455 or (cp >= 8458 and cp <= 8467) or cp = 8469 then return 1
        if (cp >= 8473 and cp <= 8477) or cp = 8484 or cp = 8486 or cp = 8488 then return 1
        if (cp >= 8490 and cp <= 8493) or (cp >= 8495 and cp <= 8505) or (cp >= 8508 and cp <= 8511) then return 1
        if (cp >= 8517 and cp <= 8521) or cp = 8526 then return 1
        return 0
    end if
    if cp >= 8528 and cp <= 8585 then return 2
    if cp >= 8586 and cp <= 9311 then return 0
    if cp >= 9312 and cp <= 9471 then
        if cp >= 9372 and cp <= 9449 then return 1
        return 2
    end if
    if cp >= 9472 and cp <= 11263 then
        if cp >= 10102 and cp <= 10131 then return 2
        if cp = 11517 then return 2
        return 0
    end if
    if cp >= 11776 and cp <= 11903 then return 0
    ' CJK punctuation and kana.
    if cp >= 12288 and cp <= 12351 then
        if cp = 12295 or (cp >= 12321 and cp <= 12329) or (cp >= 12344 and cp <= 12346) then return 2
        if cp = 12293 or cp = 12294 or (cp >= 12337 and cp <= 12341) or cp = 12347 or cp = 12348 then return 1
        return 0
    end if
    if cp >= 12353 and cp <= 12543 then
        if (cp >= 12441 and cp <= 12444) or cp = 12448 or cp = 12539 then return 0
        return 1
    end if
    ' Full-width and half-width forms.
    if cp >= 65040 and cp <= 65135 then return 0
    if cp >= 65280 and cp <= 65519 then
        if cp >= 65296 and cp <= 65305 then return 2
        if (cp >= 65313 and cp <= 65338) or (cp >= 65345 and cp <= 65370) then return 1
        if cp >= 65382 and cp <= 65500 then return 1
        return 0
    end if
    ' Surrogates (if a runtime exposes them), and emoji and symbols beyond the BMP.
    if cp >= 55296 and cp <= 57343 then return 0
    if cp >= 126976 then return 0
    return 1
end function

' A mark that upstream's grapheme split keeps on the character before it.
function NxFranchiseIsJoiner(cp as Integer) as Boolean
    if cp < 768 then return false
    if cp <= 879 then return true
    if cp >= 1155 and cp <= 1161 then return true
    if cp >= 1425 and cp <= 1479 then return cp <> 1470 and cp <> 1472 and cp <> 1475 and cp <> 1478
    if (cp >= 1552 and cp <= 1562) or (cp >= 1611 and cp <= 1631) or cp = 1648 then return true
    if cp = 3633 or (cp >= 3636 and cp <= 3642) or (cp >= 3655 and cp <= 3662) then return true
    if (cp >= 6832 and cp <= 6911) or (cp >= 7616 and cp <= 7679) then return true
    if cp = 8205 or (cp >= 8400 and cp <= 8447) then return true
    if cp = 12441 or cp = 12442 then return true
    if (cp >= 65024 and cp <= 65039) or (cp >= 65056 and cp <= 65071) then return true
    return false
end function

' Grapheme clusters, the stand-in for upstream's Intl.Segmenter.
function NxFranchiseGraphemes(s as String) as Object
    out = []
    for i = 1 to s.Len()
        ch = Mid(s, i, 1)
        if out.Count() > 0 and NxFranchiseIsJoiner(Asc(ch)) then
            out[out.Count() - 1] = out[out.Count() - 1] + ch
        else
            out.Push(ch)
        end if
    end for
    return out
end function

' Upstream's isLetterOrNumber, judged on the first code point.
function NxFranchiseIsLetterOrNumber(ch as String) as Boolean
    if ch = "" then return false
    return NxFranchiseCharClass(Asc(ch)) <> 0
end function

' Code-point order: upstream's compareStrings.
function NxFranchiseCompare(a as String, b as String) as Integer
    na = a.Len()
    nb = b.Len()
    n = na
    if nb < n then n = nb
    for i = 1 to n
        d = Asc(Mid(a, i, 1)) - Asc(Mid(b, i, 1))
        if d < 0 then return -1
        if d > 0 then return 1
    end for
    if na = nb then return 0
    if na < nb then return -1
    return 1
end function

' ── Lowercasing ─────────────────────────────────────────────────────────────

' JS toLowerCase for the scripts titles use. ASCII-only text takes LCase,
' which is right for ASCII on every Roku.
function NxFranchiseLower(s as String) as String
    g = GetGlobalAA()
    if g.nxNonAscii = invalid then g.nxNonAscii = CreateObject("roRegex", "[^\x00-\x7F]", "")
    if not g.nxNonAscii.IsMatch(s) then return LCase(s)
    n = s.Len()
    out = ""
    for i = 1 to n
        cp = Asc(Mid(s, i, 1))
        if cp = 931 then
            ' Σ is ς at the end of a word: after a letter, before no letter.
            prevLetter = false
            if i > 1 then prevLetter = NxFranchiseCharClass(Asc(Mid(s, i - 1, 1))) = 1
            nextLetter = false
            if i < n then nextLetter = NxFranchiseCharClass(Asc(Mid(s, i + 1, 1))) = 1
            if prevLetter and not nextLetter then out = out + Chr(962) else out = out + Chr(963)
        else if cp = 304 then
            out = out + "i" + Chr(775) ' İ: i and a combining dot, as JS gives
        else
            out = out + Chr(NxFranchiseLowerCp(cp))
        end if
    end for
    return out
end function

function NxFranchiseLowerCp(cp as Integer) as Integer
    if cp < 128 then
        if cp >= 65 and cp <= 90 then return cp + 32
        return cp
    end if
    if cp < 256 then
        if cp >= 192 and cp <= 222 and cp <> 215 then return cp + 32
        return cp
    end if
    if cp < 384 then ' Latin Extended-A
        if cp = 376 then return 255
        if (cp >= 313 and cp <= 328) or (cp >= 377 and cp <= 382) then
            if cp mod 2 = 1 then return cp + 1
            return cp
        end if
        if cp = 305 or cp = 312 or cp = 329 or cp = 383 then return cp
        if cp mod 2 = 0 then return cp + 1
        return cp
    end if
    if cp >= 880 and cp < 1024 then ' Greek
        if cp = 902 then return 940
        if cp >= 904 and cp <= 906 then return cp + 37
        if cp = 908 then return 972
        if cp = 910 or cp = 911 then return cp + 63
        if (cp >= 913 and cp <= 929) or (cp >= 931 and cp <= 939) then return cp + 32
        if cp = 880 or cp = 882 or cp = 886 then return cp + 1
        if cp = 895 then return 1011
        if cp = 975 then return 983
        if cp >= 984 and cp <= 1007 and cp mod 2 = 0 then return cp + 1
        if cp = 1012 then return 952
        if cp = 1015 or cp = 1018 then return cp + 1
        if cp = 1017 then return 1010
        if cp >= 1021 then return cp - 130
        return cp
    end if
    if cp >= 1024 and cp < 1328 then ' Cyrillic
        if cp <= 1039 then return cp + 80
        if cp <= 1071 then return cp + 32
        if cp < 1120 then return cp
        if cp = 1216 then return 1231
        if cp >= 1217 and cp <= 1230 then
            if cp mod 2 = 1 then return cp + 1
            return cp
        end if
        if (cp >= 1120 and cp <= 1153) or (cp >= 1162 and cp <= 1215) or (cp >= 1232 and cp <= 1327) then
            if cp mod 2 = 0 then return cp + 1
        end if
        return cp
    end if
    if cp >= 1329 and cp <= 1366 then return cp + 48 ' Armenian
    if cp >= 7680 and cp <= 7935 then ' Latin Extended Additional
        if cp = 7838 then return 223
        if (cp <= 7829 or cp >= 7840) and cp mod 2 = 0 then return cp + 1
        return cp
    end if
    if cp >= 8544 and cp <= 8559 then return cp + 16 ' Roman numerals
    if cp >= 9398 and cp <= 9423 then return cp + 26 ' circled letters
    if cp >= 65313 and cp <= 65338 then return cp + 32 ' full-width letters
    return cp
end function

' ── Title normalization ─────────────────────────────────────────────────────

' Lowercased, with any trailing " (YYYY)" dropped. Upstream's normalizedTitle.
function NxFranchiseNormalizedTitle(raw as Dynamic) as String
    s = NxFranchiseLower(NxToStr(raw))
    n = s.Len()
    if n >= 7 and Mid(s, n - 6, 2) = " (" and Right(s, 1) = ")" then
        for i = n - 4 to n - 1
            if NxFranchiseCharClass(Asc(Mid(s, i, 1))) <> 2 then return s
        end for
        return Left(s, n - 7)
    end if
    return s
end function

' Key for exact title lists: normalized, then every run of punctuation and
' whitespace one space; apostrophes never split a word. Upstream's
' explicitTitleKey.
function NxFranchiseTitleKey(raw as Dynamic) as String
    s = NxFranchiseNormalizedTitle(raw)
    g = GetGlobalAA()
    if g.nxNonAscii = invalid then g.nxNonAscii = CreateObject("roRegex", "[^\x00-\x7F]", "")
    if not g.nxNonAscii.IsMatch(s) then
        ' ASCII, already lowercased: letters and digits are [a-z0-9], an
        ' apostrophe goes, and any other run is one space, none at the ends.
        s = NxRx("franchiseApostrophe", "'").ReplaceAll(s, "")
        return NxRx("franchiseSeparators", "[^a-z0-9]+").ReplaceAll(s, " ").Trim()
    end if
    out = ""
    pendingSpace = false
    for each ch in NxFranchiseGraphemes(s)
        if NxFranchiseIsLetterOrNumber(ch) then
            if pendingSpace and out <> "" then out = out + " "
            pendingSpace = false
            out = out + ch
        else if ch = "'" or ch = Chr(8217) then
            ' an apostrophe joins
        else
            pendingSpace = true
        end if
    end for
    return out
end function

' Word-boundary containment, both inputs lowercased. Upstream's
' titleContainsToken: "star wars" matches "Star Wars Rebels", "men" doesn't
' match "Mentalist".
function NxFranchiseContainsToken(titleLower as String, tokenLower as String) as Boolean
    if tokenLower = "" then return false
    from = 1
    while true
        at = Instr(from, titleLower, tokenLower)
        if at = 0 then return false
        leftOK = true
        ' The grapheme before: back over joiners to the character they sit on.
        k = at - 1
        while k >= 1 and NxFranchiseIsJoiner(Asc(Mid(titleLower, k, 1)))
            k = k - 1
        end while
        if k >= 1 then leftOK = not NxFranchiseIsLetterOrNumber(Mid(titleLower, k, 1))
        after = at + tokenLower.Len()
        rightOK = true
        if after <= titleLower.Len() then rightOK = not NxFranchiseIsLetterOrNumber(Mid(titleLower, after, 1))
        if leftOK and rightOK then return true
        from = at + 1
    end while
    return false
end function

' "John Wick Collection" -> "John Wick". Upstream's cleanFranchiseName.
function NxFranchiseCleanName(raw as Dynamic) as String
    name = NxToStr(raw)
    suffix = " collection"
    if Len(name) >= Len(suffix) and NxFranchiseLower(Right(name, Len(suffix))) = suffix then name = Left(name, Len(name) - Len(suffix))
    return name.Trim()
end function

' "Spider-Man (MCU)" -> "Spider-Man": trailing parentheticals, never the whole
' name. Upstream's stripParentheticalSuffix.
function NxFranchiseStripParenthetical(raw as Dynamic) as String
    s = NxToStr(raw).Trim()
    while Right(s, 1) = ")"
        openAt = 0
        for i = s.Len() to 1 step -1
            if Mid(s, i, 1) = "(" then
                openAt = i
                exit for
            end if
        end for
        if openAt <= 1 then exit while
        s = Left(s, openAt - 1).Trim()
    end while
    return s
end function

' Found franchises with the same merge key are one channel. Upstream's
' franchiseMergeKey.
function NxFranchiseMergeKey(raw as Dynamic) as String
    key = NxFranchiseTitleKey(NxFranchiseCleanName(NxFranchiseStripParenthetical(NxFranchiseCleanName(raw))))
    if Left(key, 4) = "the " then key = Mid(key, 5)
    return key
end function

' ── Dictionary ──────────────────────────────────────────────────────────────

' JS's intOrNull: an integer, or a string of digits, else invalid.
function NxFranchiseInt(v as Dynamic) as Dynamic
    if NxIsNumber(v) then
        t = type(v)
        if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            if v <> Int(v) then return invalid
            return Int(v)
        end if
        return v
    end if
    if NxIsString(v) then
        s = v.Trim()
        if NxRx("franchiseInt", "^-?\d+$").IsMatch(s) then return s.ToInt()
    end if
    return invalid
end function

' JS's `=== true`: only a real true.
function NxFranchiseIsTrue(v as Dynamic) as Boolean
    if type(v) = "Boolean" or type(v) = "roBoolean" then return v
    return false
end function

function NxFranchiseStrings(v as Dynamic) as Object
    out = []
    for each s in NxList(v)
        if NxIsString(s) then out.Push(s)
    end for
    return out
end function

' The franchises.json document or its `franchises` array, with the same
' defaults as upstream's normalizeDefinitions. Each definition also carries its
' title keys, worked out once (filmKeys, tvKeys).
function NxFranchiseDefinitions(doc as Dynamic) as Object
    list = []
    if type(doc) = "roArray" then
        list = doc
    else if type(doc) = "roAssociativeArray" then
        list = NxList(doc.franchises)
    end if
    out = []
    for each d in list
        if type(d) = "roAssociativeArray" then
            if NxIsString(d.canonicalName) then
                ids = []
                for each x in NxList(d.tmdbCollectionIDs)
                    n = NxFranchiseInt(x)
                    if n <> invalid then ids.Push(n)
                end for
                def = {
                    canonicalName: d.canonicalName,
                    stockChannelID: NxFranchiseInt(d.stockChannelID),
                    tmdbCollectionIDs: ids,
                    nameMatchTokens: NxFranchiseStrings(d.nameMatchTokens),
                    tvShowTitles: NxFranchiseStrings(d.tvShowTitles),
                    filmTitles: NxFranchiseStrings(d.filmTitles),
                    studioRuled: NxFranchiseIsTrue(d.studioRuled),
                    defaultOn: NxFranchiseIsTrue(d.defaultOn)
                }
                def.filmKeys = NxFranchiseKeySet(def.filmTitles)
                def.tvKeys = NxFranchiseKeySet(def.tvShowTitles)
                out.Push(def)
            end if
        end if
    end for
    return out
end function

function NxFranchiseKeySet(titles as Object) as Object
    s = {}
    s.SetModeCaseSensitive()
    for each t in titles
        s[NxFranchiseTitleKey(t)] = true
    end for
    return s
end function

' Upstream's defaultOnIDs, as an array of stable ids in dictionary order.
function NxFranchiseDefaultOnIDs(defs as Object) as Object
    out = []
    for each d in defs
        if d.defaultOn then out.Push("dict:" + d.canonicalName)
    end for
    return out
end function

' Upstream's isOn: an explicit choice wins, else the default. enabledIDs and
' disabledIDs are sets (case-sensitive AAs) or invalid.
function NxFranchiseIsOn(id as String, enabledIDs as Dynamic, disabledIDs as Dynamic, defs as Object) as Boolean
    if enabledIDs <> invalid then
        if enabledIDs.DoesExist(id) then return true
    end if
    if disabledIDs <> invalid then
        if disabledIDs.DoesExist(id) then return false
    end if
    return NxHasValue(NxFranchiseDefaultOnIDs(defs), id)
end function

function NxFranchiseCollectionMap(defs as Object) as Object
    out = {}
    for each d in defs
        if not d.studioRuled then
            for each id in d.tmdbCollectionIDs
                out[id.ToStr()] = d
            end for
        end if
    end for
    return out
end function

' The shared film and TV matcher: an exact hit on the explicit list wins across
' every definition before any token is tried. keysField is "filmKeys" or
' "tvKeys". Upstream's dictionaryMatchTitle.
function NxFranchiseMatchTitle(title as Dynamic, keysField as String, defs as Object, includeStudioRuled as Boolean) as Dynamic
    key = NxFranchiseTitleKey(title)
    for each d in defs
        if includeStudioRuled or not d.studioRuled then
            if d[keysField].DoesExist(key) then return d
        end if
    end for
    titleLower = NxFranchiseNormalizedTitle(title)
    for each d in defs
        if not d.studioRuled then
            for each tok in d.nameMatchTokens
                if NxFranchiseContainsToken(titleLower, tok) then return d
            end for
        end if
    end for
    return invalid
end function

' The dictionary franchise a film title belongs to, or invalid. Upstream's
' dictionaryMatchForFilmTitle.
function NxFranchiseMatchFilm(title as Dynamic, defs as Object) as Dynamic
    return NxFranchiseMatchTitle(title, "filmKeys", defs, false)
end function

' item.enrichment's { franchiseID, franchiseName }, as upstream's readEnrichment.
function NxFranchiseEnrichment(item as Object) as Object
    e = item.enrichment
    if type(e) <> "roAssociativeArray" then return { fid: invalid, name: invalid }
    name = invalid
    if NxIsString(e.franchiseName) then name = e.franchiseName
    return { fid: NxFranchiseInt(e.franchiseID), name: name }
end function

function NxFranchiseIntSet(list as Dynamic) as Object
    s = {}
    for each x in NxList(list)
        n = NxFranchiseInt(x)
        if n <> invalid then s[n.ToStr()] = true
    end for
    return s
end function

' ── Build ───────────────────────────────────────────────────────────────────

' Upstream's build. opts: movies, tvItems (titles are SHOW titles), defs (from
' NxFranchiseDefinitions), availableStockChannelIDs, minimumFilms (optional).
' Returns groupings { name, stableID, placement: { type: "stock", channelID }
' or { type: "dynamic" }, movies, tvItems, mergedFranchiseIDs, fromDictionary },
' holding the caller's own items in input order.
function NxFranchiseBuild(opts as Object) as Object
    movies = NxList(opts.movies)
    tvItems = NxList(opts.tvItems)
    defs = NxList(opts.defs)
    available = NxFranchiseIntSet(opts.availableStockChannelIDs)
    minimumFilms = NxFranchiseDefaultMinimumFilms()
    if NxIsNumber(opts.minimumFilms) then
        if opts.minimumFilms = Int(opts.minimumFilms) then minimumFilms = Int(opts.minimumFilms)
    end if

    byCollectionID = NxFranchiseCollectionMap(defs)
    ' Buckets in creation order: upstream's Map keeps insertion order.
    buckets = {}
    buckets.SetModeCaseSensitive()
    order = []

    ' 1. Movies, placed once each: dictionary by collection id, dictionary by
    '    title (explicit beats token), auto-found by collection id, else
    '    skipped. Auto-found films wait until every collection has a name.
    autoFoundNames = {}
    autoFoundFilms = []
    for each movie in movies
        en = NxFranchiseEnrichment(movie)
        fid = en.fid
        def = invalid
        if fid <> invalid then def = byCollectionID[fid.ToStr()]
        if def <> invalid then
            b = NxFranchiseBucket(buckets, order, "dict:" + def.canonicalName, def.canonicalName, def)
            b.movies.Push(movie)
            NxFranchiseAddID(b, fid)
        else
            titleDef = NxFranchiseMatchTitle(movie.title, "filmKeys", defs, false)
            if titleDef <> invalid then
                b = NxFranchiseBucket(buckets, order, "dict:" + titleDef.canonicalName, titleDef.canonicalName, titleDef)
                b.movies.Push(movie)
            else if fid <> invalid then
                if not autoFoundNames.DoesExist(fid.ToStr()) and en.name <> invalid then
                    autoFoundNames[fid.ToStr()] = UCase(NxFranchiseCleanName(en.name))
                end if
                autoFoundFilms.Push({ movie: movie, fid: fid })
            end if
        end if
    end for

    ' A collection whose films never carried a name is dropped. Named ones with
    ' the same merge key share a bucket.
    for each f in autoFoundFilms
        name = autoFoundNames[f.fid.ToStr()]
        if name <> invalid and name <> "" then
            mk = NxFranchiseMergeKey(name)
            key = "found:#" + f.fid.ToStr()
            if mk <> "" then key = "found:" + mk
            b = NxFranchiseBucket(buckets, order, key, "", invalid)
            b.movies.Push(f.movie)
            NxFranchiseAddID(b, f.fid)
        end if
    end for
    ' Named after the lowest collection id; a merged bucket drops its suffix.
    for each key in order
        b = buckets[key]
        if b.definition = invalid then
            name = autoFoundNames[NxFranchiseMinID(b).ToStr()]
            if b.franchiseIDs.Count() > 1 then name = NxFranchiseStripParenthetical(name)
            b.name = name
        end if
    end for

    ' Found buckets in ascending collection id, the order TV tries them in.
    ' Ties keep creation order, as JS's stable sort does.
    found = []
    for each key in order
        b = buckets[key]
        if b.definition = invalid then
            entry = { key: key, low: NxFranchiseMinID(b), nameLower: NxFranchiseLower(b.name) }
            k = found.Count()
            while k > 0 and found[k - 1].low > entry.low
                k = k - 1
            end while
            found = NxFranchiseInsert(found, k, entry)
        end if
    end for

    ' 2. TV: dictionary (explicit titles, studio-ruled included, then tokens),
    '    else a found franchise whose name the show title contains.
    tvMatch = {}
    tvMatch.SetModeCaseSensitive()
    tvFound = {}
    tvFound.SetModeCaseSensitive()
    for each tv in tvItems
        title = NxToStr(tv.title)
        if tvMatch.DoesExist(title) then
            def = tvMatch[title]
        else
            def = NxFranchiseMatchTitle(tv.title, "tvKeys", defs, true)
            if def = invalid then def = false
            tvMatch[title] = def
        end if
        if type(def) = "roAssociativeArray" then
            b = NxFranchiseBucket(buckets, order, "dict:" + def.canonicalName, def.canonicalName, def)
            b.tvItems.Push(tv)
        else
            if tvFound.DoesExist(title) then
                foundKey = tvFound[title]
            else
                foundKey = ""
                titleLower = NxFranchiseNormalizedTitle(tv.title)
                for each fk in found
                    if NxFranchiseContainsToken(titleLower, fk.nameLower) then
                        foundKey = fk.key
                        exit for
                    end if
                end for
                tvFound[title] = foundKey
            end if
            if foundKey <> "" then buckets[foundKey].tvItems.Push(tv)
        end if
    end for

    ' 3. Resolve: a stock fold needs one item and no films; a dynamic channel
    '    needs minimumFilms films.
    groupings = []
    for each key in order
        b = buckets[key]
        ids = NxFranchiseSortedIDs(b)
        def = b.definition
        fromDictionary = def <> invalid
        g = invalid
        stock = false
        if fromDictionary then
            if def.stockChannelID <> invalid then stock = available.DoesExist(def.stockChannelID.ToStr())
        end if
        if stock then
            if b.movies.Count() + b.tvItems.Count() >= 1 then
                g = NxFranchiseGrouping(def.canonicalName, { type: "stock", channelID: def.stockChannelID }, b, ids, true)
            end if
        else if b.movies.Count() >= minimumFilms then
            g = NxFranchiseGrouping(b.name, { type: "dynamic" }, b, ids, fromDictionary)
        end if
        if g <> invalid then
            ' Stable insertion: stock folds by channel, then dynamic by name,
            ' then stableID.
            k = groupings.Count()
            while k > 0 and NxFranchiseOrder(groupings[k - 1], g) > 0
                k = k - 1
            end while
            groupings = NxFranchiseInsert(groupings, k, g)
        end if
    end for
    return groupings
end function

function NxFranchiseBucket(buckets as Object, order as Object, key as String, name as String, def as Dynamic) as Object
    b = buckets[key]
    if b = invalid then
        ids = {}
        b = { name: name, definition: def, movies: [], tvItems: [], franchiseIDs: ids }
        buckets[key] = b
        order.Push(key)
    end if
    return b
end function

sub NxFranchiseAddID(b as Object, fid as Integer)
    b.franchiseIDs[fid.ToStr()] = fid
end sub

function NxFranchiseSortedIDs(b as Object) as Object
    out = []
    for each k in b.franchiseIDs
        v = b.franchiseIDs[k]
        i = out.Count()
        while i > 0 and out[i - 1] > v
            i = i - 1
        end while
        out = NxFranchiseInsert(out, i, v)
    end for
    return out
end function

function NxFranchiseMinID(b as Object) as Dynamic
    ids = NxFranchiseSortedIDs(b)
    if ids.Count() = 0 then return invalid
    return ids[0]
end function

function NxFranchiseInsert(list as Object, at as Integer, v as Dynamic) as Object
    out = []
    for i = 0 to list.Count() - 1
        if i = at then out.Push(v)
        out.Push(list[i])
    end for
    if at >= list.Count() then out.Push(v)
    return out
end function

' Upstream's grouping comparator: negative when a sorts first.
function NxFranchiseOrder(a as Object, b as Object) as Integer
    aStock = a.placement.type = "stock"
    bStock = b.placement.type = "stock"
    if aStock and bStock then
        d = a.placement.channelID - b.placement.channelID
        if d < 0 then return -1
        if d > 0 then return 1
        return 0
    end if
    if aStock <> bStock then
        if aStock then return -1
        return 1
    end if
    c = NxFranchiseCompare(a.name, b.name)
    if c <> 0 then return c
    return NxFranchiseCompare(a.stableID, b.stableID)
end function

function NxFranchiseGrouping(name as String, placement as Object, b as Object, ids as Object, fromDictionary as Boolean) as Object
    stableID = "dict:" + name
    if not fromDictionary then
        low = 0
        if ids.Count() > 0 then low = ids[0]
        stableID = "tmdb:" + low.ToStr()
    end if
    return {
        name: name,
        stableID: stableID,
        placement: placement,
        movies: b.movies,
        tvItems: b.tvItems,
        mergedFranchiseIDs: ids,
        fromDictionary: fromDictionary
    }
end function

' The stock channel a server collection maps to: the lowest stock channel that
' two or more members reach through a dictionary collection id, or invalid.
' Upstream's stockChannelForCollectionItems.
function NxFranchiseCollectionStockChannel(items as Object, defs as Object, availableStockChannelIDs as Dynamic) as Dynamic
    available = NxFranchiseIntSet(availableStockChannelIDs)
    byCollectionID = NxFranchiseCollectionMap(defs)
    hits = {}
    for each item in NxList(items)
        fid = NxFranchiseEnrichment(item).fid
        if fid <> invalid then
            def = byCollectionID[fid.ToStr()]
            if def <> invalid then
                if def.stockChannelID <> invalid then
                    ch = def.stockChannelID
                    if available.DoesExist(ch.ToStr()) then
                        n = hits[ch.ToStr()]
                        if n = invalid then n = { id: ch, count: 0 }
                        n.count = n.count + 1
                        hits[ch.ToStr()] = n
                    end if
                end if
            end if
        end if
    end for
    best = invalid
    for each k in hits
        h = hits[k]
        if h.count >= 2 then
            if best = invalid then
                best = h.id
            else if h.id < best then
                best = h.id
            end if
        end if
    end for
    return best
end function
