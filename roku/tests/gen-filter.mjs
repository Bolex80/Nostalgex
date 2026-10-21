// Filter golden vectors, from upstream's scripts/nostalgex-channel-filter.cjs.
// Called by tests/gen-vectors.mjs, which owns the output and --check.
//
// Every real channel in channels.json, plus synthetic ones lifted from
// upstream's filter smoke test, is run against a generated library under two
// pinned clocks. The library is built from the channels themselves: for each
// channel one item made to match it, one near miss that breaks a single rule,
// and items the real membership manifest claims for it. Generic and edge-case
// items fill out the rest.
//
// The filter reads the wall clock (`new Date()`) for the current year and the
// releasedWithinMonths cutoff, so the caller must pin Date before running it.
//
// Clock B also runs as an Emby library (`backend`), the only input besides the
// clock that changes a result: an Emby Dolby Vision profile 5 file goes on no
// channel. Every other item answers the same on any backend.
import { createRequire } from "node:module";
import { join } from "node:path";

// mulberry32: a small deterministic PRNG for building the library.
function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// The clocks the vectors run under, as UTC instants evaluated with TZ=UTC.
// B is local midnight exactly, on a 31st, six months after a 30-day month:
// JS setMonth rolls 2027-03-31 back to "2026-09-31", which is 2026-10-01.
export const CLOCKS = [
  { name: "A", iso: "2026-10-12T15:30:00Z", backend: "plex" },
  { name: "B", iso: "2027-03-31T00:00:00Z", backend: "emby" },
];

export function clockContext(iso) {
  const d = new Date(iso);
  return {
    nowSec: Math.floor(d.getTime() / 1000),
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
    secOfDay: d.getUTCHours() * 3600 + d.getUTCMinutes() * 60 + d.getUTCSeconds(),
  };
}

// Synthetic channels, one per behaviour upstream's smoke test pins down.
const SYNTHETIC = [
  { id: 212, rules: { genres: { include: ["Drama"] }, imdbRatingMin: 6.5, imdbVotesMin: 5000 } },
  { id: 214, rules: { genres: { include: ["Drama"] }, imdbVotesMin: 30000 } },
  { id: 67, rules: { genres: { include: ["Drama"] }, ratingMin: 8.2, durationRange: { min: 60 } } },
  { id: 49, rules: { genres: { include: ["Drama"] }, releasedWithinMonths: 6, durationRange: { min: 60 } } },
  { id: 950, rules: { genres: { include: ["Comedy"] }, releasedWithinMonths: 13 } },
  { id: 951, rules: { genres: { include: ["Comedy"] }, releasedWithinMonths: 1 } },
  { id: 900, rules: { genres: { include: ["Comedy"] }, keywords: ["road trip"] } },
  { id: 901, rules: { genres: { include: ["Comedy"] }, keywords: ["wedding"], keywordsRequireAnyGenre: ["Romance"] } },
  { id: 902, rules: { genres: { include: ["Music", "Musical"] }, keywords: ["broadway"], keywordGatedGenres: ["Music"] } },
  { id: 903, rules: { genres: { include: ["Drama"] }, keywordsExclude: ["anime"] } },
  { id: 120, rules: { networks: ["HBO"] } },
  { id: 1, rules: { type: "movie", rewatched: true } },
  { id: 92, rules: { genres: { include: ["Drama"] }, yearRange: { min: 1980, max: 1989 } } },
  { id: 904, rules: { genres: { include: ["Drama"] }, contentRatings: ["PG", "PG-13"], allowUnrated: true } },
  { id: 905, rules: { genres: { include: ["Drama"] } } },
  { id: 906, rules: { manifestOnly: true, genres: { include: ["Comedy"] } } },
  { id: 908, rules: { type: "episode", titleContains: ["Bluey"], genres: { include: ["Animation"] } } },
  { id: 909, rules: { genres: { include: ["Drama"] }, titleExcludes: ["war"] } },
  { id: 910, rules: { source: "musicVideo", titleContains: ["Nirvana"] } },
  { id: 911, rules: { genres: { include: ["Science Fiction"], exclude: ["Animation", "Family", "Kids"] } } },
  { id: 912, rules: { watchedOnly: true } },
  { id: 913, rules: { unwatchedOnly: true } },
  { id: 914, rules: { rtScoreMin: 90, metacriticMin: 80 } },
  { id: 915, rules: { wonOscar: true } },
  { id: 916, rules: { addedWithinDays: 30 } },
  { id: 917, rules: { durationRange: { minMinutes: 20, maxMinutes: 40 } } },
  { id: 918, category: "kids", rules: { genres: { include: ["Comedy"] } } },
  { id: 919, rules: { studios: ["Pixar"] } },
  { id: 920, rules: { studios: ["Disney"], genres: { include: ["Adventure"] } } },
  { id: 921, rules: { productionCompanies: ["A24"] } },
  { id: 922, rules: { genres: { include: ["Drama"], requireAll: ["Crime", "Thriller"] } } },
  { id: 923, rules: { editorialOverrides: ["Die Hard"], genres: { include: ["Family"] } } },
  { id: 924, rules: { type: "episode", episodeTitleContains: ["Christmas", "Holiday"] } },
  // Episode rules of upstream 2d1e237: summary words, seasonal title words in an
  // air window (one wrapping the new year), title vetoes, and no type rule, so a
  // film's own title takes the same path.
  { id: 930, rules: { episodeSummaryContains: ["christmas"], episodeTitleExcludes: ["scary"] } },
  { id: 931, rules: { type: "episode", episodeSeasonalTitleContains: ["holiday", "jingle"], episodeAirWindow: { from: "11-15", to: "12-31" } } },
  { id: 932, rules: { episodeSeasonalTitleContains: ["frost"], episodeAirWindow: { from: "12-20", to: "01-10" }, episodeTitleContains: ["snowman"] } },
  { id: 933, rules: { episodeTitleContains: ["turkey"], episodeAirWindow: { from: "bad", to: "11-30" }, episodeSeasonalTitleContains: ["feast"], contentRatings: ["TV-PG", "TV-G"] } },
  // matchTmdbGenres: TMDB genres join the server's for includes, excludes and locks.
  { id: 934, rules: { matchTmdbGenres: true, genres: { include: ["Romance"], exclude: ["Horror"] } } },
  { id: 935, rules: { matchTmdbGenres: true, genres: { include: ["Drama"] }, keywords: ["christmas"], keywordsRequireAnyGenre: ["TV Movie"] } },
  { id: 925, rules: { genres: { include: ["Reality"] } } },
  { id: 926, rules: { yearRange: { min: 2000 } } },
  { id: 927, rules: {} },
  { id: 928 },
];

const LOCK_GENRES = ["Horror", "Reality", "Game Show", "Animation", "Animated", "Cartoon", "Documentary",
  "Docuseries", "Sport", "Music", "Musical", "War", "War & Politics", "Western", "Talk Show", "News",
  "History", "Family", "Kids", "Holiday", "Christmas"];
const RATINGS = ["G", "PG", "PG-13", "R", "NC-17", "TV-Y", "TV-G", "TV-PG", "TV-14", "TV-MA", "NR", "", "18+"];

export function filterVectors(upstream) {
  const require = createRequire(import.meta.url);
  const CF = require(join(upstream, "scripts", "nostalgex-channel-filter.cjs"));
  const config = require(join(upstream, "channels.json"));
  const manifest = require(join(upstream, "channels-memberships.json"));
  // Exclusive rules exactly as plex-tuner.html normalises them on load.
  const exclusiveRules = (config.exclusiveRules || []).map((r) => ({
    channelIDs: r.channelIDs || (r.channelID != null ? [r.channelID] : []),
    genres: r.genres || [],
    titleContains: r.titleContains || [],
    editorialTitles: r.editorialTitles || [],
    manifestExclusive: !!r.manifestExclusive,
    type: r.type || null,
    source: r.source || null,
  }));
  const real = config.channels.map((c) => ({ id: c.id, category: c.category, rules: c.rules }));
  const channels = [...real, ...SYNTHETIC];

  // Vocabulary from every channel, so random items land on real rules.
  const vocab = { genres: new Set(LOCK_GENRES), titles: new Set(), studios: new Set(), networks: new Set(),
    companies: new Set(), keywords: new Set(), excludes: new Set() };
  for (const { rules: r = {} } of channels) {
    for (const g of [...(r.genres?.include || []), ...(r.genres?.exclude || []), ...(r.genres?.requireAll || [])]) vocab.genres.add(g);
    for (const t of [...(r.titleContains || []), ...(r.editorialOverrides || [])]) vocab.titles.add(t);
    for (const s of r.studios || []) vocab.studios.add(s);
    for (const n of r.networks || []) vocab.networks.add(n);
    for (const p of r.productionCompanies || []) vocab.companies.add(p);
    for (const k of [...(r.keywords || []), ...(r.keywordsExclude || [])]) vocab.keywords.add(k);
    for (const t of r.titleExcludes || []) vocab.excludes.add(t);
  }
  for (const rule of exclusiveRules) for (const t of [...rule.titleContains, ...rule.editorialTitles]) vocab.titles.add(t);
  const V = Object.fromEntries(Object.entries(vocab).map(([k, s]) => [k, [...s].sort()]));

  const rand = prng(0x5eed);
  const pick = (arr) => arr[Math.floor(rand() * arr.length)];
  const chance = (p) => rand() < p;
  const items = [];
  let nextKey = 1000;
  const add = (it) => {
    const item = { ratingKey: String(nextKey++), type: "movie", title: "Untitled", genres: [], duration: 100, ...it };
    for (const k of Object.keys(item)) if (item[k] === undefined) delete item[k];
    items.push(item);
    return item;
  };

  // Built to match a channel: every rule it has, satisfied.
  function matching(c) {
    const r = c.rules || {};
    const episodic = CF.hasEpisodeRules(r);
    const it = { type: r.type || (episodic ? "episode" : "movie") };
    const include = r.genres?.include || [];
    it.genres = [...new Set([...(include.length ? [include[0]] : []), ...(r.genres?.requireAll || [])])];
    // A matchTmdbGenres channel's include reached through TMDB genres alone.
    if (r.matchTmdbGenres && include.length) { it.genres = it.genres.filter((g) => g !== include[0]); it.tmdbGenres = [include[0]]; }
    if (r.keywordsRequireAnyGenre?.length) it.genres.push(r.keywordsRequireAnyGenre[0]);
    if (r.titleContains?.length) it.title = `${pick(r.titleContains)}`;
    else if (r.editorialOverrides?.length) it.title = r.editorialOverrides[0];
    else it.title = `Feature ${nextKey}`;
    if (r.episodeTitleContains?.length) it.episodeTitle = `A Very ${r.episodeTitleContains[0]} Special`;
    else if (r.episodeSeasonalTitleContains?.length) {
      it.type = "episode";
      it.episodeTitle = `The ${pick(r.episodeSeasonalTitleContains)} Show`;
      it.originallyAvailableAt = `1999-${r.episodeAirWindow?.to || "12-01"}`;
    } else if (r.episodeSummaryContains?.length) {
      it.episodeTitle = "Pilot";
      it.summary = `Everyone gathers for ${pick(r.episodeSummaryContains)} at the house.`;
    }
    if (episodic && it.type !== "episode") it.title = it.episodeTitle || it.title;
    if (r.studios?.length) it.studio = `${r.studios[0]} Pictures`;
    if (r.networks?.length) it.networks = [r.networks[0]];
    if (r.productionCompanies?.length) it.productionCompanies = [r.productionCompanies[0]];
    if (r.keywords?.length) it.tmdbKeywords = [pick(r.keywords)];
    if (r.yearRange) it.year = r.yearRange.min != null ? r.yearRange.min + 1 : r.yearRange.max - 1;
    else it.year = 1990 + Math.floor(rand() * 30);
    if (r.contentRatings?.length) it.contentRating = r.contentRatings[0];
    else it.contentRating = c.category === "kids" ? "PG" : pick(RATINGS);
    const dr = r.durationRange;
    if (dr) it.duration = (dr.min ?? dr.minMinutes ?? 0) + 5;
    if (r.ratingMin != null) it.rating = r.ratingMin + 0.1;
    if (r.imdbRatingMin != null) it.imdbRating = r.imdbRatingMin + 0.5;
    if (r.imdbVotesMin != null) it.imdbVotes = r.imdbVotesMin;
    if (r.rewatched) it.viewCount = 3;
    if (r.source) it.librarySource = r.source;
    if (r.source === "musicVideo") it.artist = r.titleContains?.[0];
    if (r.addedWithinDays) it.addedAt = "recent";
    if (r.releasedWithinMonths) it.originallyAvailableAt = "recent";
    return it;
  }

  // One rule broken, cycling through the kinds of break.
  const BREAKS = [
    (it, r) => { if (r.yearRange) it.year = (r.yearRange.min ?? 2100) - 1; else it.year = String(it.year); },
    (it, r) => { if (r.ratingMin != null) it.rating = r.ratingMin - 0.1; else it.rating = 9.5; },
    (it, r) => { it.contentRating = r.contentRatings?.length ? "TV-MA" : "R"; },
    (it, r) => { it.genres = [...it.genres, r.genres?.exclude?.[0] || "Horror"]; },
    (it, r) => { it.title = `${it.title} ${r.titleExcludes?.[0] || "War"} Story`; },
    (it, r) => { it.genres = [...it.genres, pick(["Reality", "Animation", "Documentary", "Western", "Talk Show", "War"])]; },
    (it, r) => { it.tmdbKeywords = [r.keywordsExclude?.[0] || "anime"]; },
    (it, r) => { it.duration = r.durationRange ? (r.durationRange.min ?? 20) - 1 : 0; },
    (it, r) => { it.type = it.type === "movie" ? "episode" : "movie"; },
    (it, r) => { it.librarySource = r.source ? "movie" : "musicVideo"; },
    (it, r) => { it.year = null; it.originallyAvailableAt = "1975-06-01"; },
    (it, r) => { it.title = `${String(it.title).toUpperCase()} (1999)`; },
    (it, r) => { if (r.keywords?.length) { it.genres = ["Horror"]; } else { it.genres = []; } },
    (it, r) => { it.viewCount = r.rewatched ? 2 : 1; },
    (it, r) => { it.studio = undefined; it.networks = undefined; it.productionCompanies = undefined; },
    (it, r) => { it.episodeTitle = `${it.episodeTitle || "Pilot"} ${r.episodeTitleExcludes?.[0] || "Scary"}`; it.title = `${it.title} Scary`; },
    (it, r) => { it.originallyAvailableAt = "2001-07-04"; it.summary = "A trip to the lake."; },
    (it, r) => { it.tmdbGenres = ["Horror", ...(it.tmdbGenres || [])]; },
    (it, r) => { it.doviProfile = 5; },
  ];

  channels.forEach((c, n) => {
    const r = c.rules || {};
    add(matching(c));
    const miss = matching(c);
    BREAKS[n % BREAKS.length](miss, r);
    add(miss);
    // Real manifest claims for this channel, up to two, with genres that
    // sometimes trip its exclusions.
    let claims = 0;
    for (const [key, entry] of Object.entries(manifest.items)) {
      if (claims >= 2) break;
      if (!entry.channels.includes(c.id)) continue;
      const [mediaType, tmdb] = key.split(":");
      // The second claim breaks the channel's title rules, which a claim must
      // still obey: an excluded word, or a title off its titleContains list.
      let title = entry.name;
      if (claims === 1 && r.titleExcludes?.length) title = `${title} ${r.titleExcludes[0]}`;
      else if (claims === 1 && r.titleContains?.length) title = "Claimed Elsewhere";
      add({
        type: mediaType === "tv" ? "episode" : "movie",
        title,
        tmdbID: Number(tmdb),
        genres: claims === 1 && r.genres?.exclude?.length ? [r.genres.exclude[0]] : [pick(V.genres)],
        year: 1985 + Math.floor(rand() * 40),
        contentRating: pick(RATINGS),
      });
      claims++;
    }
  });

  // Exclusive manifest entries, both on and off their owning channel.
  for (const [key, entry] of Object.entries(manifest.items).filter(([, e]) => e.exclusive != null).slice(0, 6)) {
    const [mediaType, tmdb] = key.split(":");
    add({ type: mediaType === "tv" ? "episode" : "movie", title: entry.name, tmdbID: Number(tmdb), genres: ["Comedy"], year: 2001 });
  }

  // Random items over the whole vocabulary.
  for (let i = 0; i < 80; i++) {
    const it = {
      type: chance(0.4) ? "episode" : "movie",
      title: chance(0.5) ? pick(V.titles) : `Random ${i}`,
      genres: Array.from({ length: 1 + Math.floor(rand() * 3) }, () => pick(V.genres)),
      year: chance(0.9) ? 1950 + Math.floor(rand() * 77) : undefined,
      contentRating: pick(RATINGS),
      duration: [7, 22, 44, 58, 95, 120, 180][Math.floor(rand() * 7)],
      rating: chance(0.7) ? Math.round(rand() * 100) / 10 : undefined,
      userRating: chance(0.2) ? Math.round(rand() * 100) / 10 : undefined,
      viewCount: Math.floor(rand() * 5),
    };
    if (chance(0.3)) it.studio = pick(V.studios);
    if (chance(0.25)) it.networks = [pick(V.networks)];
    if (chance(0.2)) it.productionCompanies = [pick(V.companies)];
    if (chance(0.4)) it.tmdbKeywords = [pick(V.keywords), pick(V.keywords)];
    if (chance(0.2)) it.title = `${it.title} ${pick(V.excludes)}`;
    if (it.type === "episode" && chance(0.3)) it.episodeTitle = pick(["The Christmas Party", "Holiday Armadillo", "Pilot", "Thanksgiving", "Jingle Hell", "Merry Scary", "Roman Holiday", "Frosty Mornings"]);
    if (chance(0.3)) it.summary = pick(["Christmas comes early.", "A Thanksgiving dinner goes wrong.", "The gang goes on holiday.", "Nothing much happens.", ""]);
    if (it.type === "episode" && chance(0.4)) it.originallyAvailableAt = pick(["1994-12-15", "1996-11-21", "2003-09-02", "2010-01-05", "1999-12-31", "2015-02-17", "1999-11-15"]);
    if (chance(0.25)) it.tmdbGenres = [pick(V.genres), pick(["TV Movie", "Romance", "Horror", "Animation", "Family"])];
    if (chance(0.15)) it.doviProfile = pick([5, 8, 7, null]);
    add(it);
  }

  // Edge cases the generated items might not reach.
  add({ title: "Smells Like Teen Spirit", artist: "Nirvana", librarySource: "musicVideo", genres: [] });
  add({ title: "Die Hard", genres: ["Action"], contentRating: "R", year: 1988 });
  add({ title: "A Christmas Story", genres: ["Comedy"], year: 1983 });
  add({ title: "Elf (2003)", genres: ["Comedy", "Family"], year: 2003, contentRating: "PG" });
  add({ title: "The Warden", genres: ["Drama"], year: 1990 });
  add({ title: "AMÉLIE", genres: ["Comedy", "Romance"], year: 2001, contentRating: "R" });
  add({ title: "Bluey (2018)", type: "episode", genres: ["Comedy"], year: 2018 });
  add({ title: "Nested", genres: ["Drama"], enrichment: { imdbRating: 7, imdbVotes: 6000, keywords: ["Anime"], networks: ["HBO Max"] } });
  add({ title: "Flat", genres: ["Drama"], imdbRating: 6.5, imdbVotes: 5000, rtScore: 95, metacriticScore: 85, awards: "Won 2 Oscars. 10 wins" });
  add({ title: "Nominated", genres: ["Drama"], awards: "Nominated for 1 Oscar" });
  add({ title: "No Genres" });
  add({ title: "String Year", genres: ["Drama"], year: "1985" });
  add({ title: "Bad Year", genres: ["Drama"], year: "unknown", originallyAvailableAt: "1985-02-03" });
  add({ title: "Month Zero", genres: ["Comedy"], originallyAvailableAt: "2026-00-15" });
  add({ title: "Unrated", genres: ["Drama"], contentRating: "" });
  add({ title: "Romantic Wedding", genres: ["Romantic Comedy"], tmdbKeywords: ["Wedding"] });
  add({ title: "Road Movie", genres: ["Drama"], tmdbKeywords: ["road trip movie"] });
  // Upstream 2d1e237 and 5d6d65f: own titles, summaries, air windows, TMDB genres,
  // scoped locks and Emby Dolby Vision profile 5.
  add({ title: "A Charlie Brown Christmas", type: "movie", genres: ["Animation", "Family"], year: 1965, contentRating: "G", duration: 25 });
  add({ title: "Santa Clarita Diet", type: "episode", episodeTitle: "Moral Gray Area", genres: ["Comedy", "Horror"], librarySource: "tv", year: 2017 });
  add({ title: "Friends", type: "episode", episodeTitle: "The One with Phoebe's Dad", summary: "Phoebe goes to meet her father at Christmas.", genres: ["Comedy"], contentRating: "TV-PG", duration: 22, originallyAvailableAt: "1995-12-14" });
  add({ title: "Emily in Paris", type: "episode", episodeTitle: "Roman Holiday", summary: "A vacation in Rome.", genres: ["Comedy", "Drama"], contentRating: "TV-MA", duration: 30, originallyAvailableAt: "2023-09-01" });
  add({ title: "Window Edge", type: "episode", episodeTitle: "Holiday Frost", genres: ["Comedy"], contentRating: "TV-G", duration: 22, originallyAvailableAt: "2001-01-10T00:00:00Z" });
  add({ title: "Window Short", type: "episode", episodeTitle: "Holiday Frost", genres: ["Comedy"], contentRating: "TV-G", duration: 22, originallyAvailableAt: "2001-1-10" });
  add({ title: "The Princess Switch", genres: ["Comedy", "Family"], year: 2018, contentRating: "TV-G", tmdbGenres: ["Romance", "TV Movie"], tmdbKeywords: ["christmas"] });
  add({ title: "Nested Genres", genres: ["Drama"], year: 2010, enrichment: { tmdbGenres: ["Romance", "TV Movie"], keywords: ["christmas"] } });
  add({ title: "Lab Clip Comedy", genres: ["Comedy", "Action"], year: 2003, contentRating: "PG", doviProfile: 5 });
  add({ title: "Lab Clip Show", type: "episode", episodeTitle: "Pilot", genres: ["Comedy", "Action"], year: 2003, contentRating: "TV-PG", duration: 25, doviProfile: 5 });
  add({ title: "Lab Clip Eight", genres: ["Comedy", "Action"], year: 2003, contentRating: "PG", doviProfile: 8 });
  // Ratings from other countries (upstream GitHub #41): every channel reads them
  // as US labels, a film label on a film and a TV label on an episode.
  add({ title: "Wallace & Gromit: The Curse of the Were-Rabbit", genres: ["Animation", "Family", "Comedy"], year: 2005, contentRating: "GB-U" });
  add({ title: "Paddington", genres: ["Family", "Comedy", "Adventure"], year: 2014, contentRating: "GB-PG" });
  add({ title: "Harry Potter and the Goblet of Fire", genres: ["Adventure", "Fantasy", "Family"], year: 2005, contentRating: "GB-12A" });
  add({ title: "Danger Mouse", type: "episode", episodeTitle: "Rogue Robots", genres: ["Animation", "Kids", "Comedy"], year: 1981, contentRating: "GB-U", duration: 22 });
  add({ title: "Even Stevens", type: "episode", episodeTitle: "Pilot", genres: ["Comedy", "Family"], studio: "Disney Channel", year: 2000, contentRating: "GB-U", duration: 22 });
  add({ title: "Merlin", type: "episode", episodeTitle: "The Dragon's Call", genres: ["Drama", "Family", "Fantasy"], year: 2008, contentRating: "TV-12A", duration: 44 });
  add({ title: "Skins", type: "episode", episodeTitle: "Tony", genres: ["Drama", "Comedy"], year: 2007, contentRating: "gb/15", duration: 44 });
  add({ title: "Illumination Test Film", genres: ["Comedy", "Family"], studio: "Illumination Entertainment", year: 2020, contentRating: "GB-18" });
  add({ title: "Despicable Me", genres: ["Animation", "Family", "Comedy"], studio: "Illumination Entertainment", year: 2010, contentRating: "FSK-0" });
  add({ title: "Superbad", genres: ["Comedy"], year: 2007, contentRating: "GB-15" });
  add({ title: "The Wolf of Wall Street", genres: ["Comedy", "Crime", "Drama"], year: 2013, contentRating: "FSK 16" });
  add({ title: "Black Christmas", genres: ["Horror", "Holiday"], year: 1974, contentRating: "IE-18" });
  add({ title: "Home Alone", genres: ["Comedy", "Family", "Holiday"], year: 1990, contentRating: "AU-PG" });
  add({ title: "Scream", genres: ["Horror", "Mystery"], year: 1996, contentRating: "NZ-R18" });
  add({ title: "Bluey", type: "episode", episodeTitle: "Christmas Swim", genres: ["Animation", "Kids"], year: 2021, contentRating: "AU-P", duration: 8 });

  // Dates relative to each clock are resolved per clock; the item list itself
  // must be one fixed list, so relative markers become per-clock fields.
  const results = {};
  const contexts = Object.fromEntries(CLOCKS.map((c) => [c.name, clockContext(c.iso)]));
  // Fix relative fields against clock A once: "recent" means 10 days before A,
  // which is not recent at B, so B exercises the rejecting side.
  const a = contexts.A;
  for (const it of items) {
    if (it.addedAt === "recent") it.addedAt = a.nowSec - 10 * 86400;
    if (it.originallyAvailableAt === "recent") it.originallyAvailableAt = "2026-08-20";
  }
  // Boundary items for releasedWithinMonths at both clocks.
  for (const date of ["2026-04-12", "2026-04-13", "2026-04-11", "2026-09-30", "2026-10-01", "2026-10-02", "2026-03-01", "2026-02-28"]) {
    add({ title: `Released ${date}`, genres: ["Drama", "Comedy"], duration: 90, year: 2026, originallyAvailableAt: date });
  }
  for (const days of [29, 30, 31]) add({ title: `Added ${days}d`, genres: ["Drama"], addedAt: a.nowSec - days * 86400 });

  for (const clock of CLOCKS) {
    const ctx = contexts[clock.name];
    results[clock.name] = withClock(clock.iso, () => {
      // One string per channel, aligned with `channels` (synthetic ids reuse real ones).
      return channels.map((c) => CF.filterPool(items, c, { manifest, exclusiveRules, nowSec: ctx.nowSec, backend: clock.backend })
        .items.map((i) => `${i.ratingKey}:${i.poolVia}`).join(","));
    });
  }

  // parseTmdbIdFromPlex: the Plex shapes it has to read.
  const tmdb = [
    [{ Guid: [{ id: "imdb://tt0111161" }, { id: "tmdb://278" }] }, false],
    [{ guid: "com.plexapp.agents.themoviedb://603?lang=en" }, false],
    [{ guid: "plex://movie/5d776825880197001ec967c5" }, false],
    [{ guid: "plex://episode/1", grandparentGuid: "tmdb://1396", parentGuid: "tmdb://3572" }, true],
    [{ guid: "plex://episode/1", grandparentGuid: "tmdb://1396" }, false],
    [{ Guid: [], guid: "tmdb://00042" }, false],
    [{}, false],
    // What includeGuids=1 returns, in both key orders: `guid` and `Guid` must
    // stay two keys on the device, or one hides the other. `bothCases` marks
    // them for the interpreter, whose ParseJson folds key case.
    [{ guid: "plex://movie/5d776825880197001ec967c5", Guid: [{ id: "imdb://tt0133093" }, { id: "tmdb://603" }] }, false, true],
    [{ Guid: [{ id: "imdb://tt0133093" }, { id: "tmdb://603" }], guid: "plex://movie/5d776825880197001ec967c5" }, false, true],
  ].map(([raw, isEpisode, bothCases]) => ({ raw, isEpisode, ...(bothCases && { bothCases }), out: CF.parseTmdbIdFromPlex(raw, isEpisode) }));

  return {
    clocks: CLOCKS.map((c) => ({ ...c, ...contexts[c.name] })),
    exclusiveRules,
    channels,
    items,
    results,
    parseTmdbIdFromPlex: tmdb,
  };
}

// Run fn with the wall clock pinned to iso. Only the argument-less forms read
// the clock; the filter builds dates no other way.
function withClock(iso, fn) {
  const RealDate = globalThis.Date;
  const fixed = new RealDate(iso).getTime();
  class PinnedDate extends RealDate {
    constructor(...args) {
      if (args.length === 0) super(fixed);
      else super(...args);
    }
    static now() { return fixed; }
  }
  globalThis.Date = PinnedDate;
  try {
    return fn();
  } finally {
    globalThis.Date = RealDate;
  }
}
