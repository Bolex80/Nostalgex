#!/usr/bin/env node
/**
 * Jellyfin / Emby stream URLs the web tuner builds. Same rules as the Apple TV app's
 * JellyfinPlaybackResolver.staticStreamURL and JellyfinAPIService.addingApiKey.
 *
 * Run: `npm run test:jellyfin-urls`
 */
import { strictEqual } from "node:assert/strict";
import "./nostalgex-jellyfin-urls.js";

const JU = globalThis.NostalgexJellyfinUrls;
const S = "http://192.168.1.50:8096";

let passed = 0;
const failures = [];
function check(label, fn) {
  try {
    fn();
    passed += 1;
  } catch (e) {
    failures.push(`${label}: ${e.message}`);
  }
}

const direct = (container, extra = {}) =>
  JU.staticStreamUrl({ serverUrl: S, itemId: "abc", mediaSourceId: "ms 1", container, token: "TOK", ...extra });

for (const c of ["mp4", "m4v", "mov", "MP4", "mov,mp4,m4a,3gp,3g2,mj2"]) {
  check(`direct play ${c} asks for stream.mp4`, () =>
    strictEqual(direct(c), `${S}/Videos/abc/stream.mp4?Static=true&MediaSourceId=ms%201&api_key=TOK`));
}
for (const c of ["webm", "mkv", "", null, undefined]) {
  check(`direct play ${c} keeps the extensionless stream`, () =>
    strictEqual(direct(c), `${S}/Videos/abc/stream?Static=true&MediaSourceId=ms%201&api_key=TOK`));
}
check("audio stream index is appended", () =>
  strictEqual(direct("mp4", { audioStreamIndex: 2 }), `${S}/Videos/abc/stream.mp4?Static=true&MediaSourceId=ms%201&api_key=TOK&AudioStreamIndex=2`));
check("audio stream index 0 is kept", () =>
  strictEqual(direct("mp4", { audioStreamIndex: 0 }).endsWith("&AudioStreamIndex=0"), true));
check("null audio stream index is left off", () =>
  strictEqual(direct("mp4", { audioStreamIndex: null }).includes("AudioStreamIndex"), false));

check("hand-built HLS gets ApiKey beside api_key", () =>
  strictEqual(JU.withApiKey(`${S}/Videos/abc/master.m3u8?MediaSourceId=abc&api_key=TOK`, "TOK"),
    `${S}/Videos/abc/master.m3u8?MediaSourceId=abc&api_key=TOK&ApiKey=TOK`));
check("TranscodingUrl that already has ApiKey gains api_key only", () =>
  strictEqual(JU.withApiKey(`${S}/videos/abc/master.m3u8?PlaySessionId=p&ApiKey=TOK`, "TOK"),
    `${S}/videos/abc/master.m3u8?PlaySessionId=p&ApiKey=TOK&api_key=TOK`));
check("both present: unchanged", () =>
  strictEqual(JU.withApiKey(`${S}/x?api_key=A&ApiKey=A`, "TOK"), `${S}/x?api_key=A&ApiKey=A`));
check("no query string yet", () =>
  strictEqual(JU.withApiKey(`${S}/x`, "TOK"), `${S}/x?api_key=TOK&ApiKey=TOK`));
check("a param that merely ends in api_key does not count", () =>
  strictEqual(JU.withApiKey(`${S}/x?not_api_key=1`, "TOK"), `${S}/x?not_api_key=1&api_key=TOK&ApiKey=TOK`));

if (failures.length) {
  console.error(`jellyfin-urls: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error("  " + f);
  process.exit(1);
}
console.log(`jellyfin-urls: ${passed} passed`);
