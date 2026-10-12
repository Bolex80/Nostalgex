// Default genre gate for "more like this" claims.
//
// TMDB recommendations / similar titles and whole-collection sweeps drift out
// of a channel's genre (Carry On on WESTERNS, every James Bond film on CRIME
// FLICKS, MYSTERY and SCI-FI). So every recommendation / similar / both claim
// and every collection member must also fit the channel's own
// `rules.genres.include` from channels.json. Exemplars and hand-curated claims
// are never gated.
//
// channels.json genre names are Plex-flavoured; the title side is TMDB's genre
// list, which differs (TV uses "Sci-Fi & Fantasy", "Action & Adventure",
// "War & Politics"; TMDB has no "Holiday" or "Sport" genre at all). Each TMDB
// genre expands to the Plex names it covers, then matches the way the runtime
// filter does: substring, case-insensitive (nostalgex-channel-filter.cjs).

const TMDB_GENRE_ALIASES = {
  "action & adventure": ["action & adventure", "action", "adventure"],
  "sci-fi & fantasy": ["sci-fi & fantasy", "science fiction", "sci-fi", "fantasy"],
  "science fiction": ["science fiction", "sci-fi"],
  "war & politics": ["war & politics", "war", "politics"],
  kids: ["kids", "children"],
  reality: ["reality", "reality-tv"],
  talk: ["talk", "talk show"],
};

// Every genre name TMDB can emit (movie + TV lists), expanded.
const TMDB_GENRES = [
  "action", "adventure", "animation", "comedy", "crime", "documentary", "drama",
  "family", "fantasy", "history", "horror", "music", "mystery", "romance",
  "science fiction", "thriller", "tv movie", "war", "western",
  "action & adventure", "kids", "news", "reality", "sci-fi & fantasy", "soap",
  "talk", "war & politics",
];

export function expandTmdbGenres(genres) {
  const out = new Set();
  for (const g of genres || []) {
    const k = String(g).toLowerCase();
    for (const a of TMDB_GENRE_ALIASES[k] || [k]) out.add(a);
  }
  return [...out];
}

const ALL_TMDB_NAMES = expandTmdbGenres(TMDB_GENRES);

// The channel's genres.include names TMDB can actually produce. An include
// TMDB never emits ("Holiday", "Christmas", "Sports") can't be checked, so a
// channel whose whole include list is like that gets no default gate.
export function gateableIncludes(rules) {
  const inc = (rules?.genres?.include || []).map((g) => String(g).toLowerCase());
  return inc.filter((m) => ALL_TMDB_NAMES.some((a) => a.includes(m)));
}

// null when the title passes (or the channel has nothing gateable), else a reason.
export function ruleGenreReason(tmdbGenres, includes) {
  if (!includes?.length) return null;
  const names = expandTmdbGenres(tmdbGenres);
  if (names.some((a) => includes.some((m) => a.includes(m)))) return null;
  return `genres ${(tmdbGenres || []).join("/") || "none"} miss channel rule ${includes.join("/")}`;
}

// Manifest sources the default gate applies to.
export const GATED_SOURCES = new Set(["recommendation", "similar", "both", "collection-via", "collection"]);
