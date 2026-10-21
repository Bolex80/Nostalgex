#!/usr/bin/env node
/**
 * Ratings from other countries: scripts/rating-golden.json against
 * usContentRating in scripts/nostalgex-channel-filter.cjs, the web tuner's and
 * Docker's engine. Nostalgex/NostalgexTests/RatingGoldenTests.swift (Apple TV)
 * and roku/tests/RatingGoldenTests.brs (Roku) read the same file.
 *
 * Also checks that every label in the engine's tables has a golden case, so the
 * other two engines are held to it, and that VHS VAULT's 9 PM rule in
 * plex-tuner.html (getTimeFilteredPool) reads ratings through the normaliser.
 *
 * Run: `npm run test:ratings`
 */
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const CF = require("./nostalgex-channel-filter.cjs");
const root = new URL("../", import.meta.url);
const golden = JSON.parse(readFileSync(new URL("scripts/rating-golden.json", root), "utf8"));
const config = JSON.parse(readFileSync(new URL("channels.json", root), "utf8"));
const html = readFileSync(new URL("plex-tuner.html", root), "utf8");

const failures = [];
const show = (v) => JSON.stringify(v);

// 1. Every case.
for (const c of golden.cases) {
  const got = CF.usContentRating(c.raw, c.type);
  if (got !== c.us) failures.push(`${show(c.raw)} as ${c.type}: got ${show(got)}, want ${show(c.us)}`);
}

// 2. Every label in the tables has a case, for a film and for an episode.
const key = (raw) => (typeof raw === "string" ? raw.toUpperCase().replace(/\s+/g, "") : null);
const seen = new Set(golden.cases.map((c) => `${key(c.raw)}|${c.type}`));
const covered = (forms) => ["movie", "episode"].every((t) => forms.some((f) => seen.has(`${f}|${t}`)));
const { us, words, bare } = CF.ratingTables;
for (const label of us) if (!covered([label])) failures.push(`US label ${label} has no golden case for both types`);
for (const [country, table] of Object.entries(words)) {
  for (const label of Object.keys(table)) {
    if (!covered([`${country}-${label}`, `${country}/${label}`])) failures.push(`${country}-${label} has no golden case for both types`);
  }
}
for (const label of Object.keys(bare)) {
  if (!covered([label, `TV-${label}`])) failures.push(`bare ${label} has no golden case for both types`);
}

// 3. VHS VAULT holds a GB-18 film until 9 PM, as it does an R one.
function liftFunction(src, name) {
  const at = src.search(new RegExp(`function\\s+${name}\\s*\\(`));
  if (at < 0) throw new Error(`plex-tuner.html has no function ${name}`);
  let i = src.indexOf("{", src.indexOf(")", at));
  for (let depth = 0; ; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) break;
  }
  return src.slice(at, i + 1);
}
const getTimeFilteredPool = new Function(`${liftFunction(html, "getTimeFilteredPool")}\nreturn getTimeFilteredPool;`)();
function atLocalHour(hour, fn) {
  const RealDate = globalThis.Date;
  const ms = new RealDate(2026, 9, 21, hour, 30).getTime();
  globalThis.Date = class extends RealDate {
    constructor(...a) { if (a.length) super(...a); else super(ms); }
    static now() { return ms; }
  };
  try { return fn(); } finally { globalThis.Date = RealDate; }
}
const vault = config.channels.find((c) => c.name === "VHS VAULT");
if (!vault?.timeRestrictions?.blockRatings) {
  failures.push("VHS VAULT has no blockRatings in channels.json");
} else {
  const pool = [
    ["R", "r"], ["PG", "pg"], ["GB-18", "gb18"], ["GB-15", "gb15"], ["GB-PG", "gbpg"], ["FSK-16", "fsk16"], ["gb/12", "gb12"], ["", "none"],
  ].map(([contentRating, ratingKey]) => ({ ratingKey, contentRating, type: "movie" }));
  const keys = (arr) => arr.map((i) => i.ratingKey).join(",");
  const channel = { timeRestrictions: vault.timeRestrictions, itemPool: pool };
  const day = atLocalHour(20, () => keys(getTimeFilteredPool(channel)));
  const night = atLocalHour(21, () => keys(getTimeFilteredPool(channel)));
  if (day !== "pg,gbpg,gb12,none") failures.push(`VHS VAULT at 20:30 aired ${day}, want pg,gbpg,gb12,none`);
  if (night !== keys(pool)) failures.push(`VHS VAULT at 21:30 aired ${night}, want everything`);
}

if (failures.length) {
  console.error(`ratings: ${failures.length} failed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`ratings: ${golden.cases.length} golden cases, every table label covered, VHS VAULT holds GB-18 until 9 PM`);
