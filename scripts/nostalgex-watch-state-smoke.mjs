#!/usr/bin/env node
/**
 * Report Playback must never leave a program in Continue Watching. Checks
 * scripts/nostalgex-watch-state.js against the golden vectors the Apple TV app's
 * WatchStateGuardTests also read (scripts/watch-cleanup-golden.json), then drives the
 * Plex and Jellyfin/Emby guards through a recording fetch and checks the exact calls.
 *
 * Run: `npm run test:watch-state`
 */
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { deepStrictEqual, strictEqual, ok } from "node:assert/strict";
import "./nostalgex-watch-state.js";

const WS = globalThis.NostalgexWatchState;
const here = dirname(fileURLToPath(import.meta.url));
const golden = JSON.parse(readFileSync(resolve(here, "watch-cleanup-golden.json"), "utf8"));

let passed = 0;
const failures = [];
async function check(label, fn) {
  try {
    await fn();
    passed += 1;
  } catch (err) {
    failures.push(`${label}\n    ${String(err.message).split("\n").join("\n    ")}`);
  }
}

// ── Golden decision table, shared with Swift ──
for (const c of golden.cases) {
  await check(`golden: ${c.name}`, () => {
    const steps = c.backend === "plex" ? WS.plexPlan(c.prior, c.counted) : WS.mediaServerPlan(c.prior, c.counted);
    deepStrictEqual(steps.map(WS.describe), c.steps);
  });
}

// ── Recording fetch ──
function recorder(routes) {
  const calls = [];
  const served = {};
  const fetchImpl = async (url, init) => {
    const u = new URL(url);
    const method = (init && init.method) || "GET";
    calls.push({ method, path: u.pathname, query: Object.fromEntries(u.searchParams), body: init && init.body ? JSON.parse(init.body) : null, headers: (init && init.headers) || {} });
    const list = routes[`${method} ${u.pathname}`];
    if (!list) return { status: 200, json: async () => ({}) };
    const i = Math.min(served[`${method} ${u.pathname}`] || 0, list.length - 1);
    served[`${method} ${u.pathname}`] = i + 1;
    const [status, body] = list[i];
    return { status, json: async () => body };
  };
  return { calls, fetchImpl };
}
const meta = (o) => ({ MediaContainer: { Metadata: [o] } });
const row = (items) => ({ MediaContainer: { Metadata: items } });
const cleanupPaths = ["/:/unscrobble", "/:/progress", "/actions/removeFromContinueWatching"];

async function plexSession(routes, counted) {
  const r = recorder(routes);
  const guard = WS.plexGuard({ serverUrl: "http://plex.test", authQuery: "X-Plex-Token=tok", fetchImpl: r.fetchImpl });
  const queue = WS.createReportQueue();
  let prior;
  queue.enqueue(async () => { prior = await guard.capture("41418"); });
  queue.enqueue(() => r.fetchImpl(guard.timelineUrl("41418", "playing", 1500000, 5976930, "s"), { method: "PUT" }));
  queue.enqueue(() => r.fetchImpl(guard.timelineUrl("41418", "stopped", 1620000, 5976930, "s"), { method: "PUT" }));
  queue.enqueue(() => guard.restore("41418", prior, counted));
  await queue.drain();
  return r.calls;
}

await check("plex: surf an unwatched film -> one unscrobble, after the last report", async () => {
  const calls = await plexSession({ "GET /library/metadata/41418": [[200, meta({ ratingKey: "41418", type: "movie" })]] }, false);
  strictEqual(calls[0].path, "/library/metadata/41418");
  const cleanup = calls.filter((c) => cleanupPaths.includes(c.path));
  deepStrictEqual(cleanup.map((c) => c.path), ["/:/unscrobble"]);
  deepStrictEqual(cleanup[0].query, { key: "41418", identifier: "com.plexapp.plugins.library", "X-Plex-Token": "tok" });
  strictEqual(calls[calls.length - 1].path, "/:/unscrobble");
});

await check("plex: prior resume point -> progress back to it", async () => {
  const calls = await plexSession({ "GET /library/metadata/41418": [[200, meta({ ratingKey: "41418", type: "movie", viewOffset: 600000 })]] }, false);
  const cleanup = calls.filter((c) => cleanupPaths.includes(c.path));
  strictEqual(cleanup.length, 1);
  strictEqual(cleanup[0].method, "PUT");
  strictEqual(cleanup[0].path, "/:/progress");
  strictEqual(cleanup[0].query.time, "600000");
  strictEqual(cleanup[0].query.state, "stopped");
});

await check("plex: watched film -> removeFromContinueWatching only", async () => {
  const calls = await plexSession({ "GET /library/metadata/41418": [[200, meta({ ratingKey: "41418", type: "movie", viewCount: 2 })]] }, false);
  const cleanup = calls.filter((c) => cleanupPaths.includes(c.path));
  deepStrictEqual(cleanup.map((c) => `${c.method} ${c.path} ${c.query.ratingKey}`), ["PUT /actions/removeFromContinueWatching 41418"]);
});

await check("plex: metadata read fails -> removeFromContinueWatching only, never unscrobble", async () => {
  const calls = await plexSession({ "GET /library/metadata/41418": [[500, null]] }, false);
  const cleanup = calls.filter((c) => cleanupPaths.includes(c.path));
  deepStrictEqual(cleanup.map((c) => c.path), ["/actions/removeFromContinueWatching"]);
});

await check("plex: counted episode, show not in Continue Watching -> remove the next-up entry", async () => {
  const r = recorder({
    "GET /library/metadata/48281": [[200, meta({ ratingKey: "48281", type: "episode", grandparentRatingKey: "48279" })]],
    "GET /hubs/continueWatching/items": [
      [200, row([{ ratingKey: "900", type: "episode", grandparentRatingKey: "777" }])],
      [200, row([{ ratingKey: "900", type: "episode", grandparentRatingKey: "777" }, { ratingKey: "48283", type: "episode", grandparentRatingKey: "48279" }])],
    ],
  });
  const guard = WS.plexGuard({ serverUrl: "http://plex.test", authQuery: "X-Plex-Token=tok", fetchImpl: r.fetchImpl });
  const prior = await guard.capture("48281");
  strictEqual(prior.showKey, "48279");
  strictEqual(prior.showInContinueWatching, false);
  strictEqual(new URL(guard.scrobbleUrl("48281")).searchParams.get("key"), "48281");
  await guard.restore("48281", prior, true);
  const removals = r.calls.filter((c) => c.path === "/actions/removeFromContinueWatching");
  deepStrictEqual(removals.map((c) => c.query.ratingKey), ["48283"]);
});

await check("plex: counted episode, show already in Continue Watching -> nothing removed", async () => {
  const r = recorder({
    "GET /library/metadata/48281": [[200, meta({ ratingKey: "48281", type: "episode", grandparentRatingKey: "48279" })]],
    "GET /hubs/continueWatching/items": [[200, row([{ ratingKey: "48280", type: "episode", grandparentRatingKey: "48279" }])]],
  });
  const guard = WS.plexGuard({ serverUrl: "http://plex.test", authQuery: "", fetchImpl: r.fetchImpl });
  const prior = await guard.capture("48281");
  await guard.restore("48281", prior, true);
  strictEqual(r.calls.filter((c) => cleanupPaths.includes(c.path)).length, 0);
});

// ── Jellyfin / Emby ──
async function msRestore(prior, counted) {
  const r = recorder({});
  const guard = WS.mediaServerGuard({ serverUrl: "http://jf.test", userId: "u1", authHeader: () => 'MediaBrowser Token="t"', fetchImpl: r.fetchImpl });
  await guard.restore("i1", prior, counted);
  return r.calls;
}
const untouched = { resumePosition: 0, playCount: 0, played: false, lastPlayedDate: null, showKey: null, showInContinueWatching: false };

await check("jellyfin/emby: capture reads UserData", async () => {
  const r = recorder({ "GET /Users/u1/Items/i1": [[200, { UserData: { PlaybackPositionTicks: 6000000000, PlayCount: 2, Played: true, LastPlayedDate: "2026-10-11T18:03:04.0000000Z" } }]] });
  const guard = WS.mediaServerGuard({ serverUrl: "http://jf.test", userId: "u1", authHeader: "MediaBrowser Token=\"t\"", fetchImpl: r.fetchImpl });
  deepStrictEqual(await guard.capture("i1"), { resumePosition: 6000000000, playCount: 2, played: true, lastPlayedDate: "2026-10-11T18:03:04.0000000Z", showKey: null, showInContinueWatching: false });
  strictEqual(r.calls[0].headers.Authorization, 'MediaBrowser Token="t"');
});

await check("jellyfin/emby: untouched item -> DELETE PlayedItems", async () => {
  const calls = await msRestore(untouched, false);
  deepStrictEqual(calls.map((c) => `${c.method} ${c.path}`), ["DELETE /Users/u1/PlayedItems/i1"]);
});

await check("jellyfin/emby: prior resume point -> POST UserData with the prior values", async () => {
  const calls = await msRestore({ ...untouched, resumePosition: 6000000000, playCount: 1, lastPlayedDate: "2026-10-01T00:00:00Z" }, false);
  strictEqual(calls.length, 1);
  strictEqual(`${calls[0].method} ${calls[0].path}`, "POST /Users/u1/Items/i1/UserData");
  deepStrictEqual(calls[0].body, { PlaybackPositionTicks: 6000000000, PlayCount: 1, Played: false, LastPlayedDate: "2026-10-01T00:00:00Z" });
  strictEqual(calls[0].headers["Content-Type"], "application/json");
});

await check("jellyfin/emby: counted watch -> played once, no resume point", async () => {
  const calls = await msRestore(untouched, true);
  deepStrictEqual(calls[0].body, { PlaybackPositionTicks: 0, PlayCount: 1, Played: true });
});

await check("jellyfin/emby: unreadable prior -> only clear the resume point", async () => {
  const calls = await msRestore(null, false);
  deepStrictEqual(calls[0].body, { PlaybackPositionTicks: 0 });
});

// ── Ordering ──
await check("queue: a slow report still finishes before the cleanup queued after it", async () => {
  const q = WS.createReportQueue();
  const order = [];
  q.enqueue(() => new Promise((res) => setTimeout(() => { order.push("report"); res(); }, 20)));
  q.enqueue(async () => { order.push("cleanup"); });
  q.enqueue(async () => { throw new Error("a failed call never stalls the queue"); });
  q.enqueue(async () => { order.push("next"); });
  await q.drain();
  deepStrictEqual(order, ["report", "cleanup", "next"]);
  ok(true);
});

const total = passed + failures.length;
if (failures.length) {
  console.error(`watch state: ${failures.length} of ${total} FAILED`);
  for (const f of failures) console.error(`  x ${f}`);
  process.exit(1);
}
console.log(`watch state: ${total} checks passed (${golden.cases.length} golden cases)`);
