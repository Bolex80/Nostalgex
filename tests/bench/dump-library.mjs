#!/usr/bin/env node
// Save the signed-in Plex library, as upstream's loader reads it, with its
// shared-cache enrichment rows, for tests/bench/run.sh:
//
//   node tests/bench/dump-library.mjs     # writes out/bench/library.json
//
// The loader is lifted out of plex-tuner.html at the pinned commit, as
// tests/live/compare.mjs does. The file holds one person's library, so it
// stays in out/ (git-ignored).
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { readEnv, servers } from "../live/plex-env.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const clone = resolve(process.env.NOSTALGEX_DIR || join(repo, "..", "nostalgex"));
const pinned = readFileSync(join(repo, "data", "UPSTREAM"), "utf8").match(/^commit ([0-9a-f]{40})/m)[1];
const upstream = mkdtempSync(join(tmpdir(), "nostalgex-pin-"));
process.on("exit", () => rmSync(upstream, { recursive: true, force: true }));
execFileSync("git", ["clone", "-q", "--shared", "--no-checkout", clone, upstream]);
execFileSync("git", ["-C", upstream, "checkout", "-q", pinned]);
const require = createRequire(import.meta.url);

const html = readFileSync(join(upstream, "plex-tuner.html"), "utf8");
function lift(name) {
  const at = html.search(new RegExp(`(?:async\\s+)?function\\s+${name}\\s*\\(`));
  if (at < 0) throw new Error(`plex-tuner.html has no function ${name}`);
  let i = html.indexOf("(", at), depth = 0;
  for (; ; i++) { if (html[i] === "(") depth++; else if (html[i] === ")" && --depth === 0) break; }
  i = html.indexOf("{", i);
  for (depth = 0; ; i++) { if (html[i] === "{") depth++; else if (html[i] === "}" && --depth === 0) break; }
  return html.slice(at, i + 1) + "\n";
}
const pageSize = html.match(/const PLEX_PAGE_SIZE = (\d+);/)[1];
const loaderSource = [`const PLEX_PAGE_SIZE = ${pageSize};`,
  ...["plexLibraryFetchForServer", "fetchPlexSectionPaged", "scanOnePlexServer", "pickBestVersion", "resolutionHeight", "formatDuration"].map(lift),
  "globalThis.scanOnePlexServer = scanOnePlexServer;"].join("\n");
const CF = require(join(upstream, "scripts", "nostalgex-channel-filter.cjs"));
new Function(readFileSync(join(upstream, "scripts", "nostalgex-music-brainz.js"), "utf8"))();
const quiet = { ...console, log() {}, warn() {} };
const context = vm.createContext({
  fetch, console: quiet, AbortController, setTimeout, clearTimeout, URLSearchParams,
  discoveredGenres: {}, channelFilter: () => CF, NostalgexMusicBrainz: globalThis.NostalgexMusicBrainz,
});
context.globalThis = context;
vm.runInContext(loaderSource, context);
const LL = { state: {}, pulsePhase: async () => {}, setPhase: () => {} };

const env = readEnv();
let items = [];
for (const s of await servers(env.PLEX_TOKEN)) {
  items = items.concat(await context.scanOnePlexServer(s, LL, items.length, false));
}

// The shared cache's rows for the library's TMDB ids, as the TV reads them.
const rows = [];
const ids = [...new Set(items.map((it) => it.tmdbID).filter((v) => v != null))];
if (env.NOSTALGEX_SUPABASE_URL && env.NOSTALGEX_SUPABASE_ANON_KEY) {
  const h = { apikey: env.NOSTALGEX_SUPABASE_ANON_KEY, Authorization: `Bearer ${env.NOSTALGEX_SUPABASE_ANON_KEY}` };
  for (let i = 0; i < ids.length; i += 200) {
    const url = `${env.NOSTALGEX_SUPABASE_URL.replace(/\/$/, "")}/rest/v1/media_enrichments?tmdb_id=in.(${ids.slice(i, i + 200).join(",")})&select=*`;
    const res = await fetch(url, { headers: h });
    if (res.ok) rows.push(...(await res.json()));
  }
}

mkdirSync(join(repo, "out", "bench"), { recursive: true });
writeFileSync(join(repo, "out", "bench", "library.json"), JSON.stringify({ items, enrichmentRows: rows }), { mode: 0o600 });
console.log(`${items.length} items, ${rows.length} enrichment rows -> out/bench/library.json`);
