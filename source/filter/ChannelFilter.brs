' Channel pool filter, ported from Nostalgex.
'
' Copyright (c) 2024 Chad Mueller / Muell Haus Inc. (Nostalgex), MIT License.
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Source: upstream scripts/nostalgex-channel-filter.cjs, which upstream keeps
' in parity with the Apple TV's AppState+Channels.swift `filterItems`. Every
' rule, and the order the rules run in, is upstream's, checked against
' tests/vectors/filter.json. Don't change channel logic here; propose it upstream.
'
' One structural difference, for speed only: upstream lowercases a channel's
' rule lists and an item's fields on every call. Here NxFilterChannel and
' NxFilterItem do that once, because a Roku filters thousands of items into
' ~130 channels at startup.
'
' The clock is an argument. Upstream reads the wall clock for the current year
' and the releasedWithinMonths cutoff; here the caller passes a context from
' NxFilterClock (local calendar date, time of day and Unix time), so the same
' instant gives the same answer and the vectors can pin it.

' ── Inputs ──────────────────────────────────────────────────────────────────

' Local calendar context for "now", as upstream's `new Date()` sees it.
function NxFilterClock(nowSec = invalid as Dynamic) as Object
    dt = CreateObject("roDateTime")
    if nowSec <> invalid then dt.FromSeconds(nowSec)
    utc = dt.AsSeconds()
    dt.ToLocalTime()
    return {
        nowSec: utc,
        year: dt.GetYear(),
        month: dt.GetMonth(),
        day: dt.GetDayOfMonth(),
        secOfDay: dt.GetHours() * 3600 + dt.GetMinutes() * 60 + dt.GetSeconds()
    }
end function

' Exclusive rules as plex-tuner.html normalises them from channels.json.
function NxFilterExclusiveRules(rawRules as Dynamic) as Object
    out = []
    for each r in NxList(rawRules)
        ids = NxList(r.channelIDs)
        if ids.Count() = 0 and r.channelID <> invalid then ids = [r.channelID]
        out.Push({
            ids: ids,
            genresLower: NxLowerList(r.genres),
            titleContainsLower: NxLowerList(r.titleContains),
            editorialLower: NxLowerList(r.editorialTitles),
            manifestExclusive: NxTruthy(r.manifestExclusive)
        })
    end for
    return out
end function

' A channel { id, category, rules } with its rule lists pre-lowercased and its
' title patterns compiled.
function NxFilterChannel(channel as Object) as Object
    r = channel.rules
    if type(r) <> "roAssociativeArray" then r = {}
    genres = r.genres
    if type(genres) <> "roAssociativeArray" then genres = {}
    category = channel.category
    include = NxList(genres.include)
    c = {
        id: channel.id,
        r: r,
        isKids: category <> invalid and category = "kids",
        includeLower: NxLowerList(include),
        excludeLower: NxLowerList(genres.exclude),
        requireAllLower: NxLowerList(genres.requireAll),
        titleContainsRx: NxWordPatterns(r.titleContains),
        titleExcludesRx: NxWordPatterns(r.titleExcludes),
        episodeTitleRx: NxWordPatterns(r.episodeTitleContains),
        editorialLower: NxLowerList(r.editorialOverrides),
        studiosLower: NxLowerList(r.studios),
        prodCoLower: NxLowerList(r.productionCompanies),
        networksLower: NxLowerList(r.networks),
        keywordsLower: NxLowerList(r.keywords),
        keywordsExcludeLower: NxLowerList(r.keywordsExclude),
        keywordGenreGateLower: NxLowerList(r.keywordsRequireAnyGenre),
        keywordGatedLower: NxLowerList(r.keywordGatedGenres),
        contentRatings: NxList(r.contentRatings)
    }
    c.hasGenreInclude = include.Count() > 0
    c.hasStudioRule = c.studiosLower.Count() > 0
    c.isStudioChannel = c.hasStudioRule and not c.hasGenreInclude
    ' From the raw lists: an empty needle gets no pattern but still makes a rule.
    c.hasTitleRule = NxList(r.titleContains).Count() > 0
    c.hasEpisodeTitleRule = NxList(r.episodeTitleContains).Count() > 0
    c.hasProdCoRule = c.prodCoLower.Count() > 0
    c.hasKeywordRule = c.keywordsLower.Count() > 0
    c.hasNetworkRule = c.networksLower.Count() > 0
    c.isFamilySafe = c.isKids or NxHasExact(c.includeLower, "family")

    locks = NxGenreLocks()
    c.allowsAnimation = c.isStudioChannel or NxAnyIn(c.includeLower, locks.animation) or c.isKids or c.hasTitleRule
    c.allowsHorror = c.isStudioChannel or NxAnyIn(c.includeLower, locks.horror)
    c.allowsReality = c.isStudioChannel or NxAnyIn(c.includeLower, locks.reality)
    c.allowsDocumentary = c.isStudioChannel or NxAnyIn(c.includeLower, locks.documentary)
    c.allowsWar = c.isStudioChannel or NxAnyIn(c.includeLower, locks.war)
    c.allowsWestern = c.isStudioChannel or NxAnyIn(c.includeLower, locks.western)
    c.allowsTalkShow = c.isStudioChannel or NxAnyIn(c.includeLower, locks.talkShow)
    c.isExplicitReality = NxAnyIn(c.includeLower, locks.reality)
    c.isTitleCurated = c.hasTitleRule and not c.hasKeywordRule and not c.hasNetworkRule and not c.hasProdCoRule and not c.hasStudioRule

    dr = r.durationRange
    c.durMin = invalid
    c.durMax = invalid
    if type(dr) = "roAssociativeArray" then
        c.durMin = dr.min
        if c.durMin = invalid then c.durMin = dr.minMinutes
        c.durMax = dr.max
        if c.durMax = invalid then c.durMax = dr.maxMinutes
    end if
    return c
end function

' An item's lowercased and derived fields, computed once and kept on the item.
function NxFilterItem(item as Object) as Object
    p = item.nxFilter
    if p <> invalid then return p

    parts = []
    if NxTruthy(item.artist) then parts.Push(NxToStr(item.artist))
    if NxTruthy(item.title) then parts.Push(NxToStr(item.title))
    ' Mirrors Swift filterTitleHaystack: artist first, lowercased, " (YYYY)" stripped.
    ' (?![\s\S]) is the absolute end, as JS $ is; PCRE's $ also matches before a final newline.
    titleLower = NxRx("yearSuffix", " \(\d{4}\)(?![\s\S])").Replace(LCase(parts.Join(" ")), "")

    genres = []
    for each g in NxList(item.genres)
        genres.Push(LCase(NxToStr(g)))
    end for

    if type(item.tmdbKeywords) = "roArray" then
        keywords = NxLowerList(item.tmdbKeywords)
    else
        keywords = NxLowerList(NxEnriched(item, "keywords"))
    end if

    source = item.librarySource
    if not NxTruthy(source) then source = "movie"
    studioLower = ""
    if NxTruthy(item.studio) then studioLower = LCase(NxToStr(item.studio))
    companies = NxLowerList(NxEnriched(item, "productionCompanies"))
    prodCoHaystack = []
    prodCoHaystack.Append(companies)
    if NxTruthy(item.studio) then prodCoHaystack.Push(studioLower)
    mediaType = "movie"
    if item.type = "episode" then mediaType = "tv"
    manifestKey = invalid
    if NxTruthy(item.tmdbID) then manifestKey = mediaType + ":" + NxToStr(item.tmdbID)

    p = {
        titleLower: titleLower,
        genres: genres,
        episodeTitleLower: LCase(NxToStr(item.episodeTitle)),
        keywords: keywords,
        networks: NxLowerList(NxEnriched(item, "networks")),
        companies: companies,
        prodCoHaystack: prodCoHaystack,
        studioLower: studioLower,
        source: source,
        year: NxParseYear(item),
        manifestKey: manifestKey
    }
    item.nxFilter = p
    return p
end function

' ── The filter ──────────────────────────────────────────────────────────────

' Items that belong on the channel, as [{ item, via }]. `channel` is from
' NxFilterChannel; `manifest` is channels-memberships.json (or invalid);
' `exclusiveRules` is from NxFilterExclusiveRules; `clock` from NxFilterClock.
' Mirrors filterPool's item list. Its `shows` summary is a devtools aid and
' is not ported.
function NxFilterPool(items as Object, channel as Object, manifest as Dynamic, exclusiveRules as Object, clock as Object) as Object
    out = []
    for each it in items
        via = NxItemPasses(it, channel, manifest, exclusiveRules, clock)
        if via <> "" then out.Push({ item: it, via: via })
    end for
    return out
end function

' The matching rule ("rules", "manifest", "editorial", "title", "keyword",
' "network", "prodco"), or "" when the item doesn't belong. Mirrors itemPasses.
function NxItemPasses(item as Object, c as Object, manifest as Dynamic, exclusiveRules as Object, clock as Object) as String
    r = c.r
    p = NxFilterItem(item)
    titleLower = p.titleLower
    itemGenres = p.genres
    locks = NxGenreLocks()

    ' Matches the episode title, not the show: a Christmas special lives in
    ' "The One with the Holiday Armadillo", not in "Friends".
    matchesEpisodeTitleRule = c.hasEpisodeTitleRule and p.episodeTitleLower.Len() > 0 and NxAnyWord(p.episodeTitleLower, c.episodeTitleRx)
    matchesTitleRule = true
    if c.hasTitleRule then matchesTitleRule = NxAnyWord(titleLower, c.titleContainsRx)

    if NxTruthy(r.source) then
        if p.source <> r.source then return ""
    else if p.source = "musicVideo" then
        return ""
    end if

    if c.isFamilySafe and NxTruthy(item.contentRating) then
        if locks.adultRatings.DoesExist(NxToStr(item.contentRating)) then return ""
    end if

    if not c.allowsHorror and NxAnyIn(itemGenres, locks.horror) then return ""
    if not c.allowsReality and NxAnyIn(itemGenres, locks.reality) then return ""
    if not c.allowsAnimation and NxAnyIn(itemGenres, locks.animation) then return ""
    if not c.allowsDocumentary and NxAnyIn(itemGenres, locks.documentary) then return ""
    if not c.allowsWar and NxAnyIn(itemGenres, locks.war) then return ""
    if not c.allowsWestern and NxAnyIn(itemGenres, locks.western) then return ""
    if not c.allowsTalkShow and NxAnyIn(itemGenres, locks.talkShow) then return ""

    if c.isExplicitReality and not NxAnyIn(itemGenres, locks.reality) then return ""

    if NxHasExact(c.editorialLower, titleLower) then return "editorial"

    ' Manifest-level exclusivity: an item locked to one channel airs nowhere else.
    entry = invalid
    if manifest <> invalid and p.manifestKey <> invalid then
        if type(manifest.items) = "roAssociativeArray" then entry = manifest.items[p.manifestKey]
    end if
    if type(entry) = "roAssociativeArray" then
        if entry.exclusive <> invalid then
            if entry.exclusive <> c.id then return ""
        end if
    end if

    if NxManifestClaims(entry, c.id) then
        if NxTruthy(r.type) and item.type <> r.type then return ""
        if not NxPassesYearRange(item, r) then return ""
        if c.hasTitleRule and not matchesTitleRule then return ""
        ' A channel's own exclusions outrank a manifest claim; includes don't.
        if NxAnyWord(titleLower, c.titleExcludesRx) then return ""
        if NxAnySubstring(itemGenres, c.excludeLower) then return ""
        return "manifest"
    end if

    ' manifestOnly: membership comes solely from the manifest.
    if NxTruthy(r.manifestOnly) then return ""

    if NxAnyWord(titleLower, c.titleExcludesRx) then return ""

    ' Channel exclusivity: block items owned by another channel.
    for each rule in exclusiveRules
        if not NxHasValue(rule.ids, c.id) then
            if NxExclusiveRuleMatches(titleLower, itemGenres, rule) then return ""
            if rule.manifestExclusive and manifest <> invalid and p.manifestKey <> invalid and type(manifest.items) = "roAssociativeArray" then
                owner = manifest.items[p.manifestKey]
                for each id in rule.ids
                    if NxManifestClaims(owner, id) then return ""
                end for
            end if
        end if
    end for

    if NxTruthy(r.type) and item.type <> r.type then return ""

    if not NxPassesYearRange(item, r) then return ""

    if c.contentRatings.Count() > 0 then
        rating = ""
        if NxTruthy(item.contentRating) then rating = NxToStr(item.contentRating)
        if not (rating = "" and NxTruthy(r.allowUnrated)) then
            if not NxHasValue(c.contentRatings, rating) then return ""
        end if
    end if

    if NxIsNumber(item.duration) then
        if c.durMin <> invalid then
            if item.duration < c.durMin then return ""
        end if
        if c.durMax <> invalid then
            if item.duration > c.durMax then return ""
        end if
    end if

    itemYear = 0
    if p.year <> invalid then itemYear = p.year
    isNewRelease = itemYear >= clock.year - 1
    viewCount = NxNumberOr0(item.viewCount)
    if NxTruthy(r.watchedOnly) and viewCount < 1 and not isNewRelease then return ""
    if NxTruthy(r.unwatchedOnly) and (viewCount > 0 or isNewRelease) then return ""
    if NxTruthy(r.rewatched) and viewCount < 3 then return ""

    ' Episode-title channels are curated: the list is the allowlist.
    if c.hasEpisodeTitleRule and not matchesEpisodeTitleRule then return ""

    if NxAnySubstring(itemGenres, c.excludeLower) then return ""

    ' Soft exclude: unenriched items pass. Keywords match by exact equality.
    if c.keywordsExcludeLower.Count() > 0 and p.keywords.Count() > 0 then
        for each kw in c.keywordsExcludeLower
            if NxHasExact(p.keywords, kw) then return ""
        end for
    end if

    ' Enrichment gates. OMDb gates are HARD: a missing value rejects the item,
    ' as Swift's `guard let` does.
    if NxIsNumber(r.imdbRatingMin) then
        v = NxEnriched(item, "imdbRating")
        if not NxIsNumber(v) then return ""
        if v < r.imdbRatingMin then return ""
    end if
    if NxIsNumber(r.imdbVotesMin) then
        v = NxEnriched(item, "imdbVotes")
        if not NxIsNumber(v) then return ""
        if v < r.imdbVotesMin then return ""
    end if
    if NxIsNumber(r.rtScoreMin) then
        v = NxEnriched(item, "rottenTomatoesScore")
        if v = invalid then v = NxEnriched(item, "rtScore")
        if not NxIsNumber(v) then return ""
        if v < r.rtScoreMin then return ""
    end if
    if NxIsNumber(r.metacriticMin) then
        v = NxEnriched(item, "metacriticScore")
        if v = invalid then v = NxEnriched(item, "metacritic")
        if not NxIsNumber(v) then return ""
        if v < r.metacriticMin then return ""
    end if
    if NxTruthy(r.wonOscar) then
        awards = NxEnriched(item, "awards")
        if not NxIsString(awards) then return ""
        a = LCase(awards)
        if not (Instr(1, a, "won") > 0 and Instr(1, a, "oscar") > 0) then return ""
    end if

    ' addedWithinDays: an item with no addedAt (0) is rejected, as in Swift.
    if NxIsNumber(r.addedWithinDays) then
        if r.addedWithinDays > 0 then
            cutoff = clock.nowSec - r.addedWithinDays * 86400#
            if NxNumberOr0(item.addedAt) < cutoff then return ""
        end if
    end if

    ' releasedWithinMonths: month precision from originallyAvailableAt, else a
    ' year approximation.
    if NxIsNumber(r.releasedWithinMonths) then
        if r.releasedWithinMonths > 0 then
            months = r.releasedWithinMonths
            hit = invalid
            if NxIsString(item.originallyAvailableAt) then
                hit = NxRx("isoDate", "^(\d{4})-(\d{2})-(\d{2})").Match(item.originallyAvailableAt)
            end if
            if hit <> invalid and hit.Count() = 4 then
                if NxReleasedBefore(hit[1].ToInt(), hit[2].ToInt(), hit[3].ToInt(), months, clock) then return ""
            else if p.year <> invalid then
                yearsBack = Int((months + 11) / 12) - 1
                if p.year < clock.year - yearsBack then return ""
            end if
        end if
    end if

    ' ratingMin: the Plex rating or the user rating clears the bar.
    if NxIsNumber(r.ratingMin) then
        if NxNumberOr0(item.rating) < r.ratingMin and NxNumberOr0(item.userRating) < r.ratingMin then return ""
    end if

    matchesGenre = c.hasGenreInclude and NxAnySubstring(itemGenres, c.includeLower)
    for each need in c.requireAllLower
        if not NxAnySubstring(itemGenres, [need]) then return ""
    end for

    ' Plex studio first, then TMDB production companies and networks.
    matchesStudio = false
    if c.hasStudioRule then
        if p.studioLower <> "" and NxContainsAny(p.studioLower, c.studiosLower) then
            matchesStudio = true
        else if NxAnyContainsAny(p.companies, c.studiosLower) then
            matchesStudio = true
        else if NxAnyContainsAny(p.networks, c.studiosLower) then
            matchesStudio = true
        end if
    end if

    matchesProdCo = c.hasProdCoRule and p.prodCoHaystack.Count() > 0 and NxAnyContainsAny(p.prodCoHaystack, c.prodCoLower)

    if c.isTitleCurated then
        ' The title list is the allowlist (e.g. ADULT CARTOONS).
        if not matchesTitleRule then return ""
        return "rules"
    end if

    ' Keywords are additive: they broaden membership, never gate it.
    matchesKeyword = false
    if c.hasKeywordRule and p.keywords.Count() > 0 then
        kwHit = false
        for each kw in c.keywordsLower
            if NxHasExact(p.keywords, kw) then
                kwHit = true
                exit for
            end if
        end for
        if kwHit then
            matchesKeyword = c.keywordGenreGateLower.Count() = 0 or NxAnySubstring(itemGenres, c.keywordGenreGateLower)
        end if
    end if

    matchesNetwork = c.hasNetworkRule and p.networks.Count() > 0 and NxAnyContainsAny(p.networks, c.networksLower)

    if c.hasTitleRule or c.hasStudioRule or c.hasGenreInclude or c.hasProdCoRule or c.hasKeywordRule or c.hasNetworkRule then
        if c.hasTitleRule and matchesTitleRule then return "title"
        if matchesKeyword then return "keyword"
        if matchesNetwork then return "network"
        if matchesProdCo then return "prodco"
        if c.hasStudioRule and c.hasGenreInclude then
            if not matchesStudio or not matchesGenre then return ""
        else if c.hasStudioRule then
            if not matchesStudio then return ""
        else if c.hasGenreInclude then
            if not matchesGenre then return ""
            ' Broad genres also need a keyword. Exact match, so gating "Music"
            ' leaves "Musical" alone.
            if c.keywordGatedLower.Count() > 0 and not matchesKeyword then
                for each g in c.keywordGatedLower
                    if NxHasExact(itemGenres, g) then return ""
                end for
            end if
        else
            return ""
        end if
        return "rules"
    end if

    return "rules"
end function

' ── Rule helpers ────────────────────────────────────────────────────────────

function NxManifestClaims(entry as Dynamic, channelId as Dynamic) as Boolean
    if type(entry) <> "roAssociativeArray" then return false
    return NxHasValue(NxList(entry.channels), channelId)
end function

' Mirrors ExclusiveRule.matches: editorial title, title substring, genre substring.
function NxExclusiveRuleMatches(titleLower as String, itemGenres as Object, rule as Object) as Boolean
    if NxHasExact(rule.editorialLower, titleLower) then return true
    if NxContainsAny(titleLower, rule.titleContainsLower) then return true
    if rule.genresLower.Count() > 0 and NxAnySubstring(itemGenres, rule.genresLower) then return true
    return false
end function

function NxPassesYearRange(item as Object, r as Object) as Boolean
    yr = r.yearRange
    if type(yr) <> "roAssociativeArray" then return true
    year = NxReleaseYear(item)
    if year = invalid then return true
    if yr.min <> invalid then
        if year < yr.min then return false
    end if
    if yr.max <> invalid then
        if year > yr.max then return false
    end if
    return true
end function

' Plex `year`, parsed like JS parseInt; invalid when there is none.
function NxParseYear(item as Object) as Dynamic
    y = item.year
    if y = invalid then return invalid
    if NxIsNumber(y) then return y
    if not NxIsString(y) then return invalid
    if y = "" then return invalid
    hit = NxRx("leadingInt", "^\s*([+-]?\d+)").Match(y)
    if hit.Count() < 2 then return invalid
    return hit[1].ToInt()
end function

' Mirrors Swift itemReleaseYear: `year`, else the year of originallyAvailableAt.
function NxReleaseYear(item as Object) as Dynamic
    y = NxFilterItem(item).year
    if y <> invalid then return y
    if NxIsString(item.originallyAvailableAt) then
        hit = NxRx("isoYear", "^(\d{4})-\d{2}-\d{2}").Match(item.originallyAvailableAt)
        if hit.Count() = 2 then return hit[1].ToInt()
    end if
    return invalid
end function

' Upstream: new Date(y, mo - 1, d) < (now with setMonth(getMonth() - months)),
' both in local time. JS rolls an out-of-range day or month forward (Mar 31
' minus one month is "Feb 31", which is Mar 3), which day serials reproduce.
function NxReleasedBefore(y as Integer, mo as Integer, d as Integer, months as Integer, clock as Object) as Boolean
    released = NxDaySerial(y, mo - 1, d) * 86400&
    cutoff = NxDaySerial(clock.year, clock.month - 1 - months, clock.day) * 86400& + clock.secOfDay
    return released < cutoff
end function

' Days since 1970-01-01 for a JS-style (year, zero-based month, day), any of
' which may be out of range. Hinnant's days_from_civil.
function NxDaySerial(y as Integer, monthIndex as Integer, d as Integer) as LongInteger
    yy = y + NxFloorDiv(monthIndex, 12)
    mm = monthIndex - NxFloorDiv(monthIndex, 12) * 12 + 1
    if mm <= 2 then yy = yy - 1
    era = NxFloorDiv(yy, 400)
    yoe = yy - era * 400
    mp = mm + 9
    if mm > 2 then mp = mm - 3
    doy = Int((153 * mp + 2) / 5)
    doe = yoe * 365 + Int(yoe / 4) - Int(yoe / 100) + doy
    serial& = era
    return serial& * 146097 + doe - 719468 + d - 1
end function

function NxFloorDiv(a as Integer, b as Integer) as Integer
    return Int(a / b) ' Int() floors, and / is float division
end function

' The genre locks and adult ratings, built once per thread.
function NxGenreLocks() as Object
    g = GetGlobalAA()
    if g.nxGenreLocks = invalid then
        g.nxGenreLocks = {
            horror: NxSet(["horror"]),
            reality: NxSet(["reality", "game show", "game-show", "reality-tv"]),
            animation: NxSet(["animation", "animated", "cartoon"]),
            documentary: NxSet(["documentary", "docuseries"]),
            war: NxSet(["war", "war & politics"]),
            western: NxSet(["western"]),
            talkShow: NxSet(["talk show", "talk", "news"]),
            adultRatings: NxSet(["R", "NC-17", "TV-MA", "18", "18+", "X", "NR"])
        }
    end if
    return g.nxGenreLocks
end function

' Regexes, compiled once per thread.
function NxRx(name as String, pattern as String) as Object
    g = GetGlobalAA()
    if g.nxRx = invalid then g.nxRx = {}
    rx = g.nxRx[name]
    if rx = invalid then
        rx = CreateObject("roRegex", pattern, "")
        g.nxRx[name] = rx
    end if
    return rx
end function

' `\bneedle\b` patterns over lowercased text, as upstream's titleContainsWord.
' An empty needle never matches, so it gets no pattern.
function NxWordPatterns(list as Dynamic) as Object
    out = []
    for each t in NxList(list)
        n = LCase(NxToStr(t))
        if n <> "" then
            escaped = ""
            for i = 1 to n.Len()
                ch = Mid(n, i, 1)
                if Instr(1, ".*+?^${}()|[]\", ch) > 0 then escaped = escaped + "\"
                escaped = escaped + ch
            end for
            out.Push(CreateObject("roRegex", "\b" + escaped + "\b", ""))
        end if
    end for
    return out
end function

function NxAnyWord(haystack as String, patterns as Object) as Boolean
    for each rx in patterns
        if rx.IsMatch(haystack) then return true
    end for
    return false
end function

' ── Small helpers ───────────────────────────────────────────────────────────

' Upstream's enrichedValue: under item.enrichment, else flat on the item.
function NxEnriched(item as Object, key as String) as Dynamic
    e = item.enrichment
    if type(e) = "roAssociativeArray" then
        if e[key] <> invalid then return e[key]
    end if
    return item[key]
end function

function NxLowerList(v as Dynamic) as Object
    out = []
    for each x in NxList(v)
        out.Push(LCase(NxToStr(x)))
    end for
    return out
end function

function NxSet(list as Object) as Object
    s = {}
    s.SetModeCaseSensitive()
    for each x in list
        s[x] = true
    end for
    return s
end function

' Some element of `list` is a key of `set` (case-sensitive).
function NxAnyIn(list as Object, set as Object) as Boolean
    for each x in list
        if set.DoesExist(x) then return true
    end for
    return false
end function

function NxHasExact(list as Object, s as String) as Boolean
    for each x in list
        if x = s then return true
    end for
    return false
end function

' Some haystack in `list` contains some needle in `needles`, as upstream's
' `itemGenres.some((g) => needles.some((n) => g.includes(n)))`.
function NxAnySubstring(list as Object, needles as Object) as Boolean
    for each h in list
        if NxContainsAny(h, needles) then return true
    end for
    return false
end function

function NxAnyContainsAny(list as Object, needles as Object) as Boolean
    return NxAnySubstring(list, needles)
end function

function NxContainsAny(haystack as String, needles as Object) as Boolean
    for each n in needles
        if n = "" or Instr(1, haystack, n) > 0 then return true
    end for
    return false
end function

' Plex GUIDs: `tmdb://456`, or agent URLs containing `tmdb://456`. Takes the
' Plex metadata AA; returns the TMDB id as an Integer, or invalid.
'
' Plex sends both `guid` (a string) and `Guid` (a list), so each is read by
' its exact key. tests/vectors/filter.json has both key orders, which fail on a
' device where the two collide.
function NxParseTmdbIdFromPlex(raw as Object, isEpisode = false as Boolean) as Dynamic
    candidates = []
    if type(raw["Guid"]) = "roArray" then
        for each g in raw["Guid"]
            if type(g) = "roAssociativeArray" then candidates.Push(g.id) else candidates.Push(invalid)
        end for
    end if
    if NxTruthy(raw["guid"]) then candidates.Push(raw["guid"])
    if isEpisode and NxTruthy(raw.grandparentGuid) then candidates.Push(raw.grandparentGuid)
    if isEpisode and NxTruthy(raw.parentGuid) then candidates.Push(raw.parentGuid)
    rx = NxRx("tmdbGuid", "tmdb://(\d+)")
    for each id in candidates
        hit = rx.Match(NxToStr(id))
        if hit.Count() = 2 then return hit[1].ToInt()
    end for
    return invalid
end function
