// Franchise vectors beyond upstream's golden file: the text edges the port
// handles differently in kind (code points instead of grapheme clusters,
// written-out letter ranges instead of \p{Alphabetic}), and auto-found names
// that only sort or upper-case right by code point. Every answer comes from
// upstream's scripts/nostalgex-franchise-builder.js. Upstream's own golden
// file is vendored unchanged as tests/vectors/franchise-golden.json.
// Called by tests/gen-vectors.mjs, which owns the output.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const titles = [
  "", "Amélie", "AMÉLIE (2001)", "Amélie", "Pokémon: Best Wishes!", "Léon: The Professional",
  "Ōkami", "ΤΈΛΟΣ", "Брат 2", "千と千尋の神隠し", "ラーメン・ガール", "Ｓｔａｒ Ｗａｒｓ", "x² Squared",
  "Café — Noir", "Amélie (２００１)", "Rocky (19)", "Rocky(2001)", "Rocky (2001) ", "Hello World",
  "Mr.Robot", "Up!", "(500) Days of Summer", "Bob's Burgers", "‘Allo ‘Allo!", "M*A*S*H",
  "Æon Flux", "Straße", "Ⅻ Monkeys", "Nº 1", "½ Price", "¿Qué?", "Señor × Señora", "Daredevil (2015) (2015)",
  // Case mapping the TV's LCase gets wrong or might: Greek with medial and
  // final sigma, Latin Extended-A (both pairings), Cyrillic, Armenian,
  // circled letters, Ÿ, ẞ and İ.
  "ΟΔΥΣΣΕΙΑ", "Ο ΆΝΘΡΩΠΟΣ ΣΤΗ ΓΗ", "ΣΑΣ", "ŁÓDŹ ŚWIĘTA", "ČEŠKÁ ŽENA", "ĽUBOŠ", "ŸVES", "İSTANBUL",
  "ЁЛКИ", "ЇЖАК Є", "ҐРУНТ", "ԱՐԱՐԱՏ", "ⒸⒾⓉⓎ", "GROẞ", "ĞÜZEL", "ØRSTED", "ĦAMRUN", "ŊUŊ",
];

const tokens = [
  ["star wars rebels", "star wars"], ["the mentalist", "men"], ["amélie", "am"], ["café", "caf"],
  ["amélie", "ame"], ["pokémon go", "pokémon"], ["x-men: first class", "x-men"], ["x-men", "men"],
  ["star wars", ""], ["a star wars story", "star wars"], ["star warsy", "star wars"], ["ラーメン・ガール", "ラーメン"],
  ["брат 2", "брат"], ["ébrat", "brat"], ["1brat", "brat"], ["brat²", "brat"], ["brat…", "brat"],
  ["the matrix the matrix", "matrix"], ["matrixx matrix", "matrix"], ["star", "star wars"],
];

const names = [
  "The Matrix Collection", "Pokémon Collection", "Alien (Original) (1979) Collection", "(Untitled)",
  "Star Trek: The Original Series Collection", "THE AVENGERS COLLECTION", "Theater Camp", "Spider-Man (MCU)",
  "(MCU)", "A (b) (c)", "A (b) c", "  X  ", "John Wick Collection", "Collection", " collection",
  "JOHN WICK COLLECTION", "The ", "The", "Thé Room Collection",
];

const film = (id, title, fid, name) =>
  fid === undefined ? { id, title } : { id, title, enrichment: { franchiseID: fid, franchiseName: name } };

// Auto-found channels named and sorted by upstream's rules: non-ASCII names
// upper-cased, code-point order (É after Z), ties broken by stable id.
const cases = [
  {
    name: "auto-found-names-sort-by-code-point",
    availableStockChannelIDs: [],
    movies: [
      ...[1, 2, 3].map((n) => film(`z${n}`, `Zorro ${n}`, 9001, "Zorro Collection")),
      ...[1, 2, 3].map((n) => film(`e${n}`, `Émile ${n}`, 9002, "Émile Collection")),
      ...[1, 2, 3].map((n) => film(`a${n}`, `Ålien ${n}`, 9003, "Ålien Collection")),
      ...[1, 2, 3].map((n) => film(`p${n}`, `Pokémon ${n}`, 9004, "Pokémon Collection")),
      ...[1, 2, 3].map((n) => film(`b${n}`, `bambi ${n}`, 9005, "bambi collection")),
    ],
    tvItems: [
      { id: "t1", title: "Pokémon Journeys" },
      { id: "t2", title: "Zorro (1957)" },
      { id: "t3", title: "Émile et Moi" },
      { id: "t4", title: "Pokémonster" },
    ],
  },
  {
    name: "same-name-ties-break-by-stable-id",
    availableStockChannelIDs: [],
    movies: [
      ...[1, 2, 3].map((n) => film(`x${n}`, `Twin A ${n}`, 7002, "Twins Collection")),
      ...[1, 2, 3].map((n) => film(`y${n}`, `Twin B ${n}`, 7001, "Twins (Remake) Collection")),
      ...[1, 2, 3].map((n) => film(`w${n}`, `Other ${n}`, 7003, "Twins: Again")),
      film("u1", "Unnamed 1", 7004), film("u2", "Unnamed 2", 7004), film("u3", "Unnamed 3", 7004),
    ],
    tvItems: [{ id: "t1", title: "Twins" }, { id: "t2", title: "Twins: Again" }],
  },
  {
    name: "dictionary-and-found-mixed-with-episodes",
    availableStockChannelIDs: [100, 102],
    movies: [
      film("sw1", "Star Wars", 10, "Star Wars Collection"),
      film("hp1", "Harry Potter and the Philosopher's Stone", 1241, "Harry Potter Collection"),
      ...[1, 2, 3].map((n) => film(`r${n}`, `Rocky ${n}`, 1575, "Rocky Collection")),
      film("rog", "Rogue One: A Star Wars Story (2016)"),
      film("nn", "No Collection", null),
    ],
    tvItems: [
      ...[1, 2, 3].map((n) => ({ id: `m${n}`, title: "The Mandalorian", episodeTitle: `Chapter ${n}` })),
      { id: "rk", title: "Rocky and Bullwinkle" },
      { id: "sw", title: "STAR WARS: VISIONS (2021)" },
    ],
  },
];

const folds = [
  { items: [film("a", "A", 10), film("b", "B", 10), film("c", "C", 1241), film("d", "D", 1241)], availableStockChannelIDs: [100, 102] },
  { items: [film("a", "A", 10), film("b", "B", 10), film("c", "C", 1241), film("d", "D", 1241)], availableStockChannelIDs: [102] },
  { items: [film("a", "A", 10), film("b", "B", "10")], availableStockChannelIDs: ["100"] },
  { items: [{ id: "a", title: "A" }, film("b", "B", null)], availableStockChannelIDs: [100] },
];

export function franchiseVectors(upstream) {
  const source = readFileSync(join(upstream, "scripts", "nostalgex-franchise-builder.js"), "utf8");
  new Function(source)();
  const FB = globalThis.NostalgexFranchiseBuilder;
  const dictionary = JSON.parse(readFileSync(join(upstream, "franchises.json"), "utf8"));
  const project = (gs) => gs.map((g) => ({
    name: g.name, stableID: g.stableID, placement: g.placement,
    movies: g.movies.map((x) => x.id), tvItems: g.tvItems.map((x) => x.id),
    mergedFranchiseIDs: g.mergedFranchiseIDs, fromDictionary: g.fromDictionary,
  }));
  return {
    text: titles.map((t) => ({ title: t, normalized: FB.normalizedTitle(t), key: FB.explicitTitleKey(t) })),
    tokens: tokens.map(([title, token]) => ({ title, token, out: FB.titleContainsToken(title, token) })),
    names: names.map((n) => ({
      name: n, clean: FB.cleanFranchiseName(n), strip: FB.stripParentheticalSuffix(n), merge: FB.franchiseMergeKey(n),
    })),
    defaultOn: [...FB.defaultOnIDs(dictionary)],
    cases: cases.map((c) => ({ ...c, expected: project(FB.build({ ...c, definitions: dictionary })) })),
    collectionFolds: folds.map((f) => ({
      ...f, stockChannelID: FB.stockChannelForCollectionItems({ ...f, definitions: dictionary }),
    })),
  };
}
