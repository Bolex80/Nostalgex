#!/usr/bin/env node
/**
 * The schedule on the days the clocks change, on the web tuner and in the Docker image.
 *
 *   1. scripts/schedule-dst-golden.json's local midnights are the zones' real ones (Temporal).
 *   2. scripts/nostalgex-daily-manifest.js against those vectors, the ones
 *      NostalgexTests/ScheduleDSTGoldenTests.swift also runs, each in its own zone: the day's
 *      start, the next day's start and yesterday's key; a full day of schedule with no empty
 *      last hour and no hour run into tomorrow; and the day after reading the right yesterday.
 *   3. Negative control: the module with the old 86,400 s arithmetic fails exactly the days
 *      that aren't 24 hours long and the days after a short one, and nothing in a zone
 *      without daylight saving.
 *
 * No network. Run: `npm run test:schedule-dst`.
 */
import { readFileSync } from "node:fs";
import vm from "node:vm";

const root = new URL("../", import.meta.url);
const golden = JSON.parse(readFileSync(new URL("scripts/schedule-dst-golden.json", root), "utf8"));
const src = readFileSync(new URL("scripts/nostalgex-daily-manifest.js", root), "utf8");

let passed = 0;
const failures = [];
function check(label, ok, detail = "") {
  if (ok) passed += 1;
  else failures.push(`${label}${detail ? `\n    ${detail}` : ""}`);
}

const store = new Map();
const localStorage = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => { store.set(k, String(v)); },
  removeItem: (k) => { store.delete(k); },
  key: (i) => [...store.keys()][i] ?? null,
  get length() { return store.size; },
};
function load(source) {
  const ctx = { Date, TextEncoder, localStorage };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  return ctx.NostalgexDailyManifest;
}

const pool = (rows) => rows.map(([ratingKey, title, type, duration]) => ({ ratingKey, title, type, duration, addedAt: 0 }));
const small = { id: 201, name: "SMALL", itemPool: pool(golden.pools.small) };
const big = { id: 203, name: "BIG", itemPool: pool(golden.pools.big) };
const dayOf = (zone, date) => golden.days.find((d) => d.zone === zone && d.date === date);
const originalTZ = process.env.TZ;

/** The fill and yesterday vectors that fail for module `M`. */
function behaviourFailures(M) {
  const failed = [];
  for (const d of golden.days) {
    process.env.TZ = d.zone;
    store.clear();
    const blocks = M.getManifestBlocks(small, small.itemPool, d.at[2] * 1000, "dst");
    const contiguous = blocks.every((b, i) => i === 0 || b.startSec === blocks[i - 1].endSec);
    const ok = blocks.length > 0 && blocks[0].startSec === d.start && blocks.at(-1).endSec === d.nextStart && contiguous;
    if (!ok) failed.push(`fill ${d.zone} ${d.date}`);
  }
  for (const y of golden.yesterday) {
    process.env.TZ = y.zone;
    store.clear();
    const before = M.getManifestBlocks(big, big.itemPool, dayOf(y.zone, y.previous).at[2] * 1000, "dst");
    const after = M.getManifestBlocks(big, big.itemPool, dayOf(y.zone, y.date).at[2] * 1000, "dst");
    const aired = new Set(before.map((b) => b.item.ratingKey));
    if (after.some((b) => aired.has(b.item.ratingKey))) failed.push(`yesterday ${y.zone} ${y.date}`);
  }
  return failed;
}

// 1. The golden file's midnights are the real ones.
for (const d of golden.days) {
  const date = Temporal.PlainDate.from(d.date);
  const start = date.toZonedDateTime({ timeZone: d.zone }).epochMilliseconds / 1000;
  const next = date.add({ days: 1 }).toZonedDateTime({ timeZone: d.zone }).epochMilliseconds / 1000;
  check(`golden ${d.zone} ${d.date} matches the tz database`, start === d.start && next === d.nextStart,
    `file ${d.start}..${d.nextStart}, Temporal ${start}..${next}`);
}

// 2. The module.
const M = load(src);
for (const d of golden.days) {
  process.env.TZ = d.zone;
  for (const at of d.at) {
    const ms = at * 1000;
    const got = {
      date: M.localDayKey(ms),
      start: M.startOfLocalDayMs(ms) / 1000,
      nextStart: M.startOfNextLocalDayMs(ms) / 1000,
      previous: M.previousLocalDayKey(ms),
    };
    const want = { date: d.date, start: d.start, nextStart: d.nextStart, previous: d.previous };
    check(`days ${d.zone} ${d.date} at ${at}`, JSON.stringify(got) === JSON.stringify(want),
      `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
  }
}
const now = behaviourFailures(M);
check("fill and yesterday vectors all pass", now.length === 0, now.join(", "));
passed += golden.days.length + golden.yesterday.length - now.length - 1;

// 3. Negative control: the old arithmetic.
const oldSrc = src
  .replace("const dayEndSec = dayStartSec + localDayLengthSec(dayStartSec);", "const dayEndSec = dayStartSec + 86400;")
  .replace("const yesterdayKey = previousLocalDayKey(atMs);", "const yesterdayKey = localDayKey(Math.floor(startOfLocalDayMs(atMs) / 1000) * 1000 - 86400000);");
check("negative control patched both lines", oldSrc.includes("const dayEndSec = dayStartSec + 86400;") && oldSrc.includes("* 1000 - 86400000);")
  && !oldSrc.includes("localDayLengthSec(dayStartSec);") && !oldSrc.includes("previousLocalDayKey(atMs);"));
const expected = [
  ...golden.days.filter((d) => d.hours !== 24).map((d) => `fill ${d.zone} ${d.date}`),
  ...golden.yesterday.filter((y) => dayOf(y.zone, y.previous).hours < 24).map((y) => `yesterday ${y.zone} ${y.date}`),
].sort();
const old = behaviourFailures(load(oldSrc)).sort();
check("the old arithmetic fails exactly the short and long days and the day after a short one",
  JSON.stringify(old) === JSON.stringify(expected), `failed: ${old.join(", ")}\n    expected: ${expected.join(", ")}`);
const controls = ["America/Phoenix", "Asia/Kolkata", "UTC"];
check("the old arithmetic fails nothing in a zone without daylight saving", !old.some((f) => controls.some((z) => f.includes(z))));
check("the negative control has teeth", expected.length >= 20, `${expected.length} expected failures`);

if (originalTZ === undefined) delete process.env.TZ;
else process.env.TZ = originalTZ;

if (failures.length) {
  console.error(`schedule dst smoke: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`schedule dst smoke: ${passed} passed (${golden.days.length} days in ${new Set(golden.days.map((d) => d.zone)).size} zones, ` +
  `${golden.yesterday.length} day-after checks; the old arithmetic fails ${old.length}, none in a zone without daylight saving)`);
