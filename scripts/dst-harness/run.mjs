#!/usr/bin/env node
/**
 * Daylight-saving harness: what each surface's schedule does on the days the clocks change.
 *
 * Runs the web tuner's engine as the page runs it (scripts/nostalgex-daily-manifest.js plus
 * plex-tuner.html's own buildChannelSchedule, in a VM with a pinned clock and an in-memory
 * localStorage), once per zone in scripts/dst-harness/input.json, with process.env.TZ set to
 * that zone. Nostalgex/NostalgexTests/DSTHarnessTests.swift runs the Apple TV engine over the
 * same plan and writes the same shape, so the two can be compared sample by sample.
 *
 * The truth for "when does this local day start" comes from Temporal, not from either engine.
 *
 *   node scripts/dst-harness/run.mjs                          web tuner only; writes out/plan.json + out/js.json
 *   node scripts/dst-harness/run.mjs --swift out/swift.json   also reads the Apple TV run and compares
 *   node scripts/dst-harness/run.mjs --label after            names the output out/js-after.json
 *   node scripts/dst-harness/run.mjs --diff a.json b.json     which days' blocks differ between two runs
 *
 * Apple TV side (needs out/plan.json from a run of this script first):
 *   TEST_RUNNER_DST_HARNESS_PLAN=<abs>/out/plan.json TEST_RUNNER_DST_HARNESS_OUT=<abs>/out/swift.json \
 *     xcodebuild test ... -only-testing:NostalgexTests/DSTHarnessTests
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import vm from "node:vm";

const here = new URL("./", import.meta.url);
const root = new URL("../../", import.meta.url);
const outDir = new URL("out/", here);
mkdirSync(outDir, { recursive: true });

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };

if (args[0] === "--diff") {
  diffRuns(JSON.parse(readFileSync(args[1], "utf8")), JSON.parse(readFileSync(args[2], "utf8")));
  process.exit(0);
}

const input = JSON.parse(readFileSync(new URL("input.json", here), "utf8"));
const label = opt("--label");
const swiftPath = opt("--swift");

// ── The plan: which instants to pack and sample, from Temporal ──────────────────────────
const plan = { zones: {} };
for (const [zone, changes] of Object.entries(input.zones)) {
  plan.zones[zone] = {};
  for (const change of changes) {
    const c = Temporal.PlainDate.from(change);
    const days = [];
    for (let k = -input.daysBefore; k <= input.daysAfter; k++) {
      const d = c.add({ days: k });
      const start = d.toZonedDateTime({ timeZone: zone });
      const next = d.add({ days: 1 }).toZonedDateTime({ timeZone: zone });
      const noon = d.toZonedDateTime({ timeZone: zone, plainTime: "12:00" });
      days.push({
        date: d.toString(),
        noon: noon.epochMilliseconds / 1000,
        trueStart: start.epochMilliseconds / 1000,
        trueNext: next.epochMilliseconds / 1000,
      });
    }
    const from = c.add({ days: -1 }).toZonedDateTime({ timeZone: zone }).epochMilliseconds / 1000;
    const to = c.add({ days: 2 }).toZonedDateTime({ timeZone: zone }).epochMilliseconds / 1000;
    const samples = [];
    for (let t = from; t < to; t += input.sampleStepSeconds) samples.push(t);
    plan.zones[zone][change] = { days, samples };
  }
}
plan.channels = input.channels;
writeFileSync(new URL("plan.json", outDir), JSON.stringify(plan));

// ── The web tuner engine, as the page runs it ──────────────────────────────────────────
const dmSrc = readFileSync(new URL("scripts/nostalgex-daily-manifest.js", root), "utf8");
const tuner = readFileSync(new URL("plex-tuner.html", root), "utf8");
function pageSlice(startMarker, endMarker) {
  const a = tuner.indexOf(startMarker);
  const b = tuner.indexOf(endMarker, a + 1);
  if (a < 0 || b < 0) throw new Error(`plex-tuner.html moved: ${startMarker}`);
  return tuner.slice(a, b);
}
const buildSrc = pageSlice("  function buildChannelSchedule(channel) {", "  function rebuildAllSchedules()");
const fmtSrc = pageSlice("  function formatTime(seconds) {", "\n  }\n") + "\n  }\n";

function makeWeb() {
  const store = new Map();
  const RealDate = Date;
  const ctx = { console, TextEncoder, now: 0 };
  ctx.localStorage = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => { store.set(k, String(v)); },
    removeItem: (k) => { store.delete(k); },
    key: (i) => [...store.keys()][i] ?? null,
    get length() { return store.size; },
  };
  ctx.Date = class extends RealDate {
    constructor(...a) { super(...(a.length ? a : [ctx.now])); }
    static now() { return ctx.now; }
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(dmSrc, ctx);
  vm.runInContext(`${fmtSrc}\n${buildSrc}
    function getTimeFilteredPool(ch) { return ch.itemPool; }
    function manifestServerKey() { return 'harness'; }
    this.web = { buildChannelSchedule };`, ctx);
  return ctx;
}

/** What the web guide row draws at `t + 3600`: renderGrid lays today's blocks end to end by width. */
function webGuideAt(blocks, t) {
  const ws = Math.floor(t / 1800) * 1800;
  const we = ws + 7200;
  const target = t + 3600 - ws;
  let x = 0;
  for (const b of blocks) {
    if (b.endSec <= ws) continue;
    if (b.startSec >= we) break;
    const w = Math.min(b.endSec, we) - Math.max(b.startSec, ws);
    if (target >= x && target < x + w) return b.item.ratingKey;
    x += w;
  }
  return null;
}

function runWeb() {
  const result = { engine: "web", zones: {} };
  const originalTZ = process.env.TZ;
  for (const [zone, scenarios] of Object.entries(plan.zones)) {
    process.env.TZ = zone;
    result.zones[zone] = {};
    for (const [change, p] of Object.entries(scenarios)) {
      const ctx = makeWeb();
      const DM = ctx.NostalgexDailyManifest;
      const channels = input.channels.map((c) => ({
        id: c.id, name: c.name, isPremiereChannel: false,
        itemPool: c.pool.map((i) => ({ ...i, addedAt: 0 })),
      }));
      const days = [];
      for (const d of p.days) {
        ctx.now = d.noon * 1000;
        const row = {
          date: d.date,
          dayKey: DM.localDayKey(d.noon * 1000),
          dayStart: DM.startOfLocalDayMs(d.noon * 1000) / 1000,
          dayNumber: DM.localDayNumber(d.noon * 1000),
          ch: {},
        };
        for (const ch of channels) {
          row.ch[ch.id] = DM.getManifestBlocks(ch, ch.itemPool, d.noon * 1000, "harness")
            .map((b) => [b.item.ratingKey, b.startSec, b.endSec]);
        }
        days.push(row);
      }
      const samples = [];
      for (const t of p.samples) {
        ctx.now = t * 1000;
        const row = { t, ch: {} };
        for (const ch of channels) {
          ctx.web.buildChannelSchedule(ch);
          const s0 = ch.schedule && ch.schedule[0];
          const blocks = ch._manifestBlocks || [];
          const exact = blocks.find((b) => t >= b.startSec && t < b.endSec);
          let chosen = null;
          if (s0) {
            const start = t - (s0.offsetSeconds || 0);
            chosen = blocks.find((b) => b.item.ratingKey === s0.ratingKey && Math.abs(b.startSec - start) <= 1) || null;
          }
          row.ch[ch.id] = {
            now: chosen ? [chosen.item.ratingKey, chosen.startSec, chosen.endSec] : null,
            next: ch.schedule && ch.schedule[1] ? ch.schedule[1].ratingKey : null,
            fallback: !exact,
            offset: s0 ? s0.offsetSeconds : null,
            itemSec: s0 ? s0.duration * 60 : null,
            guide60: webGuideAt(blocks, t),
          };
        }
        samples.push(row);
      }
      result.zones[zone][change] = { days, samples };
    }
  }
  if (originalTZ === undefined) delete process.env.TZ; else process.env.TZ = originalTZ;
  return result;
}

// ── Measures ──────────────────────────────────────────────────────────────────────────
const CH = Object.fromEntries(input.channels.map((c) => [c.id, c.name]));
const mins = (s) => Math.round(s / 60);

function dayMeasures(run, zone, change) {
  const p = plan.zones[zone][change];
  const r = run.zones[zone][change];
  return r.days.map((d, i) => {
    const truth = p.days[i];
    const prev = i > 0 ? r.days[i - 1] : null;
    const out = { date: d.date, dayNumber: d.dayNumber, sameDayNumberAsYesterday: !!prev && prev.dayNumber === d.dayNumber, ch: {} };
    for (const id of Object.keys(d.ch)) {
      const blocks = d.ch[id];
      const keys = blocks.map((b) => b[0]);
      const prevKeys = prev ? prev.ch[id].map((b) => b[0]) : null;
      const prevSet = new Set(prevKeys || []);
      out.ch[id] = {
        startMin: blocks.length ? mins(blocks[0][1] - truth.trueStart) : null,
        // Negative: the day's last block ends before the next local midnight (a hole).
        endMin: blocks.length ? mins(blocks[blocks.length - 1][2] - truth.trueNext) : null,
        repeats: prevKeys ? new Set(keys.filter((k) => prevSet.has(k))).size : null,
        seamDup: !!prevKeys && prevKeys.length > 0 && keys[0] === prevKeys[prevKeys.length - 1],
        identical: !!prevKeys && JSON.stringify(keys) === JSON.stringify(prevKeys),
      };
    }
    return out;
  });
}

/** Five-minute samples split into the day before, the change day and the day after. */
function sampleMeasures(run, zone, change) {
  const p = plan.zones[zone][change];
  const r = run.zones[zone][change];
  const ci = p.days.findIndex((d) => d.date === change);
  const windows = [
    ["before", p.days[ci - 1].trueStart, p.days[ci].trueStart],
    ["change", p.days[ci].trueStart, p.days[ci + 1].trueStart],
    ["after", p.days[ci + 1].trueStart, p.days[ci + 2].trueStart],
  ];
  const byT = new Map(r.samples.map((s) => [s.t, s]));
  const step = input.sampleStepSeconds;
  const out = {};
  for (const [name, a, b] of windows) {
    out[name] = {};
    for (const id of Object.keys(CH)) {
      const m = { nothingOn: 0, pastEnd: 0, overlap: 0, guideWrong: 0, guideWrongAt: [] };
      for (const s of r.samples) {
        if (s.t < a || s.t >= b) continue;
        const c = s.ch[id];
        if (!c.now) m.nothingOn += step;
        if (c.fallback === true) m.pastEnd += step;           // web: no block covers now, it reuses the last one
        if (c.firstNow !== undefined && c.now && c.firstNow !== c.now[0]) m.overlap += step; // Apple TV: two blocks claim now
        const later = byT.get(s.t + 3600);
        if (later) {
          const promised = c.guide60;
          const aired = later.ch[id].now ? later.ch[id].now[0] : null;
          if (promised !== aired) {
            m.guideWrong += step;
            if (m.guideWrongAt.length < 3) m.guideWrongAt.push(s.t + 3600);
          }
        }
      }
      for (const k of ["nothingOn", "pastEnd", "overlap", "guideWrong"]) m[k] = mins(m[k]);
      out[name][id] = m;
    }
  }
  return out;
}

function agreement(a, b, zone, change) {
  const ra = a.zones[zone][change], rb = b.zones[zone][change];
  let dayDiffs = 0;
  ra.days.forEach((d, i) => { if (JSON.stringify(d.ch) !== JSON.stringify(rb.days[i].ch) || d.dayKey !== rb.days[i].dayKey) dayDiffs++; });
  let nowDiff = 0;
  const firstDiff = [];
  ra.samples.forEach((s, i) => {
    for (const id of Object.keys(s.ch)) {
      const x = s.ch[id].now ? s.ch[id].now[0] : null;
      const y = rb.samples[i].ch[id].now ? rb.samples[i].ch[id].now[0] : null;
      if (x !== y) { nowDiff += input.sampleStepSeconds; if (firstDiff.length < 2) firstDiff.push(`${CH[id]}@${fmt(zone, s.t)}`); }
    }
  });
  return { dayDiffs, nowDiffMin: mins(nowDiff), firstDiff };
}

function fmt(zone, t) {
  return new Date(t * 1000).toLocaleString("en-GB", { timeZone: zone, month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false });
}

function report(run) {
  const lines = [`\n=== ${run.engine.toUpperCase()} ===`];
  for (const [zone, scenarios] of Object.entries(run.zones)) {
    for (const change of Object.keys(scenarios)) {
      const p = plan.zones[zone][change];
      const ci = p.days.findIndex((d) => d.date === change);
      const len = (p.days[ci].trueNext - p.days[ci].trueStart) / 3600;
      lines.push(`\n${zone} ${change} (day is ${len} h)${input.controls.includes(zone) ? " [control]" : ""}`);
      const dm = dayMeasures(run, zone, change);
      for (const d of dm.slice(input.daysBefore - 1)) {
        const parts = Object.entries(d.ch).map(([id, c]) =>
          `${CH[id]} start ${c.startMin >= 0 ? "+" : ""}${c.startMin}m end ${c.endMin >= 0 ? "+" : ""}${c.endMin}m` +
          (CH[id] === "BIG" ? ` repeats ${c.repeats}` : "") + (c.seamDup ? " SEAM-DUP" : "") + (c.identical ? " SAME-AS-YESTERDAY" : ""));
        lines.push(`  ${d.date}${d.date === change ? "*" : " "} day#${d.dayNumber}${d.sameDayNumberAsYesterday ? " (SAME day# as yesterday)" : ""} | ${parts.join(" | ")}`);
      }
      const sm = sampleMeasures(run, zone, change);
      for (const w of ["before", "change", "after"]) {
        const parts = Object.entries(sm[w]).map(([id, m]) => {
          const bits = [];
          if (m.nothingOn) bits.push(`nothing on ${m.nothingOn}m`);
          if (m.pastEnd) bits.push(`past last block ${m.pastEnd}m`);
          if (m.overlap) bits.push(`two blocks claim now ${m.overlap}m`);
          if (m.guideWrong) bits.push(`guide wrong ${m.guideWrong}m (${m.guideWrongAt.map((t) => fmt(zone, t)).join(", ")})`);
          return `${CH[id]}: ${bits.join(", ") || "ok"}`;
        });
        lines.push(`  ${w.padEnd(6)} ${parts.join(" | ")}`);
      }
    }
  }
  return lines.join("\n");
}

function diffRuns(a, b) {
  for (const zone of Object.keys(a.zones)) {
    for (const change of Object.keys(a.zones[zone])) {
      const da = a.zones[zone][change].days, db = b.zones[zone][change].days;
      const changed = da.filter((d, i) => JSON.stringify(d.ch) !== JSON.stringify(db[i].ch)).map((d) => d.date);
      const sa = a.zones[zone][change].samples, sb = b.zones[zone][change].samples;
      let nowChanged = 0;
      sa.forEach((s, i) => { for (const id of Object.keys(s.ch)) if (JSON.stringify(s.ch[id].now) !== JSON.stringify(sb[i].ch[id].now)) nowChanged++; });
      console.log(`${zone.padEnd(20)} ${change}: days with different blocks: ${changed.length ? changed.join(", ") : "none"}; samples with a different now: ${nowChanged}`);
    }
  }
}

// ── Run ───────────────────────────────────────────────────────────────────────────────
const web = runWeb();
writeFileSync(new URL(`js${label ? "-" + label : ""}.json`, outDir), JSON.stringify(web));
console.log(report(web));

if (swiftPath && existsSync(swiftPath)) {
  const swift = JSON.parse(readFileSync(swiftPath, "utf8"));
  swift.engine = "apple tv";
  console.log(report(swift));
  console.log("\n=== APPLE TV vs WEB (same zone, same instants) ===");
  for (const [zone, scenarios] of Object.entries(plan.zones)) {
    for (const change of Object.keys(scenarios)) {
      const g = agreement(swift, web, zone, change);
      console.log(`${zone.padEnd(20)} ${change}: days whose blocks differ ${g.dayDiffs}; minutes where now playing differs ${g.nowDiffMin}${g.firstDiff.length ? " (first: " + g.firstDiff.join(", ") + ")" : ""}`);
    }
  }
}
