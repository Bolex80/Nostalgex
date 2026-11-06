#!/usr/bin/env node
/**
 * Measure proposed channels against the REAL Plex library, using the repo's own filter.
 * Read-only: Plex GETs only, nothing written to the server.
 *
 *   node research/measure-channels.mjs [ids...]     (default: the 8 new channels)
 */
import { createRequire } from "node:module";
import { readFile, writeFile } from "node:fs/promises";
const require = createRequire(import.meta.url);
const CF = require("../scripts/nostalgex-channel-filter.cjs");

const TOKEN = (await readFile("/home/alex/hermes_data/credentials/plex.token", "utf8")).trim();
const BASE = "http://192.168.2.30:32400";
const CACHE = new URL("./library-cache.json", import.meta.url);

async function plex(path) {
  const r = await fetch(`${BASE}${path}&X-Plex-Token=${TOKEN}`, {
    headers: { Accept: "application/json" },
  });
  if (!r.ok) throw new Error(`${path} -> ${r.status}`);
  return r.json();
}

function toItem(m, kind) {
  const genres = (m.Genre || []).map((g) => g.tag);
  return {
    type: kind,
    title: m.title,
    // the filter matches artist+title; for an episode the "artist" is the show name
    artist: kind === "episode" ? m.grandparentTitle || "" : "",
    genres,
    year: m.year,
    originallyAvailableAt: m.originallyAvailableAt,
    contentRating: m.contentRating,
    studio: m.studio || "",
    network: m.network || m.studio || "",
    rating: m.rating || m.audienceRating || 0,
    userRating: m.userRating || 0,
    viewCount: m.viewCount || 0,
    duration: Math.round((m.duration || 0) / 60000),
    summary: m.summary || "",
    addedAt: m.addedAt || 0,
  };
}

let items;
try {
  items = JSON.parse(await readFile(CACHE, "utf8"));
  console.log(`cache: ${items.length} items`);
} catch {
  items = [];
  for (const section of [1, 3, 4, 10]) {
    const d = await plex(`/library/sections/${section}/all?type=1`);
    const ms = d.MediaContainer.Metadata || [];
    console.log(`movies section ${section}: ${ms.length}`);
    for (const m of ms) items.push(toItem(m, "movie"));
  }
  for (const section of [2, 8]) {
    const d = await plex(`/library/sections/${section}/all?type=4`);
    const ms = d.MediaContainer.Metadata || [];
    console.log(`episodes section ${section}: ${ms.length}`);
    for (const m of ms) items.push(toItem(m, "episode"));
  }
  await writeFile(CACHE, JSON.stringify(items));
}

const channels = JSON.parse(await readFile(new URL("../channels.json", import.meta.url), "utf8"));
const exclusiveRules = channels.exclusiveRules || [];
const wanted = process.argv.slice(2).map(Number);
const targets = channels.channels.filter((c) =>
  wanted.length ? wanted.includes(c.id) : c.id >= 500 && c.id <= 507);

for (const ch of targets) {
  const result = CF.filterPool(items, ch, { exclusiveRules });
  const pool = result.items || result;
  const shows = new Map();
  for (const it of pool) {
    const key = ch.rules.type === "episode" ? it.artist : it.title;
    shows.set(key, (shows.get(key) || 0) + 1);
  }
  const top = [...shows.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12);
  console.log(
    `\nCH${ch.number} ${ch.name} (id ${ch.id})  ->  ${pool.length} items, ${shows.size} distinct titles`,
  );
  console.log("   " + (top.map(([t, n]) => `${t} (${n})`).join(" · ") || "NOTHING MATCHES"));
}
