#!/usr/bin/env node
/**
 * The web tuner never asks Jellyfin or Emby to put a subtitle into the video, and only picks
 * subtitle tracks it can show. Points 8 and 9 in scripts/nostalgex-jellyfin-urls.js.
 *
 * Runs the page's own getJellyfinTranscodeUrl and pickSubtitle, cut out of plex-tuner.html,
 * against a fake server, so the PlaybackInfo body checked here is the one the page sends.
 *
 * Measured 2026-10-19 against Jellyfin 12.2.0 and Emby 4.10.1.0: with the old body (empty
 * SubtitleProfiles, no SubtitleStreamIndex) Jellyfin burned every default or forced subtitle
 * track into a libx264 re-encode and Emby every forced one; with this body every case copied
 * the video. A PGS or VobSub track fetched as WebVTT came back 400 (Jellyfin) or empty (Emby).
 *
 * Run: `npm run test:jellyfin-subtitles`. Point TUNER / URLS at other files for a negative control.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const tunerPath = process.env.TUNER || path.join(root, "plex-tuner.html");
const urlsPath = process.env.URLS || path.join(root, "scripts/nostalgex-jellyfin-urls.js");
const tuner = fs.readFileSync(tunerPath, "utf8");
await import(pathToFileURL(urlsPath).href);
const JU = globalThis.NostalgexJellyfinUrls;

let passed = 0;
const failures = [];
async function check(label, fn) {
  try {
    await fn();
    passed += 1;
  } catch (e) {
    failures.push(`${label}: ${e.message}`);
  }
}
function assert(ok, msg) {
  if (!ok) throw new Error(msg);
}

// Cut a top-level-in-script function out of the page by matching braces, skipping strings,
// template literals and comments.
function extractFunction(src, name) {
  const start = src.search(new RegExp(`(async\\s+)?function\\s+${name}\\s*\\(`));
  if (start < 0) throw new Error(`${name} not found in ${path.basename(tunerPath)}`);
  let i = src.indexOf("{", src.indexOf(")", start));
  let depth = 0;
  const stack = [];
  for (; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    const mode = stack[stack.length - 1];
    if (mode === "line") { if (c === "\n") stack.pop(); continue; }
    if (mode === "block") { if (c === "*" && n === "/") { stack.pop(); i++; } continue; }
    if (mode === "'" || mode === '"') { if (c === "\\") i++; else if (c === mode) stack.pop(); continue; }
    if (mode === "`") {
      if (c === "\\") i++;
      else if (c === "`") stack.pop();
      else if (c === "$" && n === "{") { stack.push("${"); depth++; i++; }
      continue;
    }
    if (c === "/" && n === "/") { stack.push("line"); i++; continue; }
    if (c === "/" && n === "*") { stack.push("block"); i++; continue; }
    if (c === "'" || c === '"' || c === "`") { stack.push(c); continue; }
    if (c === "{") depth++;
    if (c === "}") {
      depth--;
      if (mode === "${") stack.pop();
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  throw new Error(`${name}: unbalanced braces`);
}

// ---- the module ----

const profiles = JU.subtitleProfiles ? JU.subtitleProfiles() : [];
await check("subtitle profiles cover the formats both servers name", () => {
  const formats = new Set(profiles.map(p => String(p.Format).toLowerCase()));
  for (const f of ["srt", "subrip", "ass", "ssa", "mov_text", "webvtt", "pgssub", "dvdsub", "dvbsub"]) {
    assert(formats.has(f), `missing ${f}`);
  }
});
await check("every subtitle profile is External, none Encode or Hls", () => {
  assert(profiles.length > 0, "no profiles");
  for (const p of profiles) assert(p.Method === "External", `${p.Format} is ${p.Method}`);
});
await check("no subtitle stream is -1", () => assert(JU.NO_SUBTITLE_STREAM === -1, `got ${JU.NO_SUBTITLE_STREAM}`));
await check("text subtitle codecs are text, any case", () => {
  for (const c of ["subrip", "SRT", "ass", "ssa", "mov_text", "webvtt"]) assert(JU.isTextSubtitle(c), c);
});
await check("image subtitle codecs are not text", () => {
  for (const c of ["PGSSUB", "pgs", "DVDSUB", "dvbsub", "hdmv_pgs_subtitle", "dvd_subtitle", "", null, undefined]) {
    assert(!(JU.isTextSubtitle && JU.isTextSubtitle(c)), String(c));
  }
});

// ---- the page's PlaybackInfo body ----

async function pageBody(backend, retry) {
  const sent = [];
  const ctx = {
    NostalgexJellyfinUrls: JU,
    URL,
    console: { warn() {}, log() {} },
    pickAudioStream: () => null,
    ownsPlaybackRequest: () => true,
    fetch: async (url, init) => {
      sent.push({ url, body: JSON.parse(init.body) });
      return {
        ok: true,
        json: async () => ({
          PlaySessionId: "ps1",
          MediaSources: [{ Id: "ms1", TranscodingUrl: "/videos/i1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1&ApiKey=TOK" }],
        }),
      };
    },
  };
  vm.createContext(ctx);
  vm.runInContext(`${extractFunction(tuner, "getJellyfinTranscodeUrl")}; this.getJellyfinTranscodeUrl = getJellyfinTranscodeUrl;`, ctx);
  const request = {
    backend, serverUrl: "http://192.168.1.50:8096", token: "TOK", deviceId: "dev", userId: "u1",
    authorization: "MediaBrowser Token=\"TOK\"", controller: new AbortController(),
  };
  const out = await ctx.getJellyfinTranscodeUrl({ ratingKey: "i1", partKey: "ms1", offsetSeconds: 600, _retryHls: retry }, request);
  assert(sent.length === 1, `expected one PlaybackInfo POST, saw ${sent.length}`);
  return { body: sent[0].body, url: sent[0].url, out };
}

for (const backend of ["jellyfin", "emby"]) {
  for (const retry of [false, true]) {
    const label = `${backend}${retry ? " retry" : ""}`;
    await check(`${label}: PlaybackInfo asks for no subtitle stream`, async () => {
      const { body } = await pageBody(backend, retry);
      assert(body.SubtitleStreamIndex === -1, `SubtitleStreamIndex is ${JSON.stringify(body.SubtitleStreamIndex)}`);
      assert(body.MediaSourceId === "ms1", "-1 only counts with a matching MediaSourceId");
    });
    await check(`${label}: PlaybackInfo lists every subtitle format as External`, async () => {
      const { body } = await pageBody(backend, retry);
      const sp = body.DeviceProfile.SubtitleProfiles;
      assert(Array.isArray(sp) && sp.length > 0, "SubtitleProfiles is empty");
      assert(JSON.stringify(sp) === JSON.stringify(profiles), "SubtitleProfiles differ from the module's");
    });
  }
}
await check("the rest of the body is unchanged: H.264 in TS, start time, Emby retry flags", async () => {
  const j = (await pageBody("jellyfin", false)).body;
  const e = (await pageBody("emby", true)).body;
  assert(j.DeviceProfile.TranscodingProfiles[0].Container === "ts", "transcode container");
  assert(j.DeviceProfile.TranscodingProfiles[0].VideoCodec === "h264", "transcode video codec");
  assert(j.StartTimeTicks === 6000000000, `StartTimeTicks ${j.StartTimeTicks}`);
  assert(j.EnableDirectPlay === undefined, "Jellyfin first try has no retry flags");
  assert(e.EnableDirectPlay === false && e.EnableDirectStream === false, "Emby retry flags");
});
await check("the stream URL is the server's TranscodingUrl, unchanged apart from api keys", async () => {
  const { out } = await pageBody("jellyfin", false);
  assert(out.url.startsWith("http://192.168.1.50:8096/videos/i1/master.m3u8?MediaSourceId=ms1"), out.url);
  assert(!/SubtitleStreamIndex|SubtitleMethod/.test(out.url), out.url);
});

// ---- the page's subtitle pick ----

function pagePick(subs, preferred = "en") {
  const ctx = { NostalgexJellyfinUrls: JU, resolveSubtitleLanguage: () => preferred };
  vm.createContext(ctx);
  const table = /const ISO6391_TO_6392 = \{[\s\S]*?\};/.exec(tuner);
  vm.runInContext(`${table ? table[0] : ""} ${extractFunction(tuner, "langMatches")}; ${extractFunction(tuner, "pickSubtitle")}; this.pick = pickSubtitle;`, ctx);
  return ctx.pick(subs);
}
const pgs = { index: 2, lang: "eng", forced: false, codec: "pgssub" };
const srt = { index: 3, lang: "eng", forced: false, codec: "subrip" };
const forcedPgs = { index: 5, lang: "eng", forced: true, codec: "pgssub" };
const forcedSrt = { index: 6, lang: "eng", forced: true, codec: "subrip" };
const vob = { index: 2, lang: "eng", forced: false, codec: "dvdsub" };

await check("Blu-ray layout: an English SRT wins over the English PGS listed first", () => {
  const p = pagePick([pgs, srt, forcedPgs]);
  assert(p && p.index === 3, `picked ${JSON.stringify(p)}`);
});
await check("image tracks only: nothing is picked, rather than an empty WebVTT", () => {
  assert(pagePick([pgs, forcedPgs, vob]) === null, "picked an image track");
});
await check("forced text track is still the fallback", () => {
  const p = pagePick([pgs, forcedSrt]);
  assert(p && p.index === 6, `picked ${JSON.stringify(p)}`);
});
await check("wrong language is still never picked", () => {
  assert(pagePick([{ index: 2, lang: "spa", forced: false, codec: "subrip" }]) === null, "picked Spanish");
});
await check("no tracks, or not an array: nothing", () => {
  assert(pagePick([]) === null && pagePick(undefined) === null, "picked something");
});

if (failures.length) {
  console.error(`jellyfin-subtitles: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error("  " + f);
  process.exit(1);
}
console.log(`jellyfin-subtitles: ${passed} passed`);
