#!/usr/bin/env node
/**
 * STREAM QUALITY, the web port of the Apple TV's StreamQuality (issue #123): the table is held
 * to scripts/stream-quality-golden.json, the same file StreamQualityGoldenTests.swift reads,
 * and the request builders to what the web asked before the setting existed. No network, no
 * browser. The real page is `npm run test:stream-quality:browser`.
 * Run: `npm run test:stream-quality`.
 */
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const root = new URL("../", import.meta.url);
const golden = JSON.parse(readFileSync(new URL("scripts/stream-quality-golden.json", root), "utf8"));
const read = (p) => readFileSync(new URL(p, root), "utf8");

const sandbox = { console };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const f of ["scripts/nostalgex-stream-quality.js", "scripts/nostalgex-jellyfin-urls.js", "scripts/nostalgex-playback-info.js"]) vm.runInContext(read(f), sandbox);
const SQ = sandbox.NostalgexStreamQuality;
const URLS = sandbox.NostalgexJellyfinUrls;
const PI = sandbox.NostalgexPlaybackInfo;

let passed = 0;
const failures = [];
function check(label, fn) {
  try { fn(); passed += 1; } catch (err) { failures.push(`${label}\n    ${String(err.message).split("\n").join("\n    ")}`); }
}
const plain = (v) => JSON.parse(JSON.stringify(v));

check("the table is the Apple TV's: same ids, order and numbers", () => {
  assert.deepEqual(plain(SQ.LEVELS.map((l) => ({ id: l.id, displayName: l.name, maxBitrateKbps: l.maxBitrateKbps, width: l.width, height: l.height, videoQualityIndex: l.videoQualityIndex }))), golden.levels);
});
check("the storage key and the default are the Apple TV's", () => {
  assert.equal(SQ.STORAGE_KEY, golden.storageKey);
  assert.equal(SQ.DEFAULT_ID, golden.default);
});

const store = (initial) => { const m = new Map(initial ? [[SQ.STORAGE_KEY, initial]] : []); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)) }; };
check("a new install, an unknown value and a storage that throws are all AUTO", () => {
  assert.equal(SQ.current(store()), "auto");
  assert.equal(SQ.current(store("ultra")), "auto");
  assert.equal(SQ.current({ getItem() { throw new Error("blocked"); } }), "auto");
});
check("a choice is saved and read back; an unknown level is refused", () => {
  const s = store();
  assert.equal(SQ.save("low", s), true);
  assert.equal(SQ.current(s), "low");
  assert.equal(SQ.save("ultra", s), false);
  assert.equal(SQ.current(s), "low");
  assert.equal(SQ.save("high", { setItem() { throw new Error("blocked"); } }), false);
});

check("AUTO and MAXIMUM change nothing: no Plex parameters, 120 Mbps, no fallback options, any file direct plays", () => {
  for (const id of ["auto", "maximum"]) {
    assert.equal(SQ.isCapped(id), false);
    assert.equal(SQ.plexTranscodeQuery(id), "");
    assert.equal(SQ.mediaBrowserMaxBitrate(id), 120000000);
    assert.deepEqual(plain(SQ.mediaBrowserFallbackOptions(id)), {});
    assert.equal(SQ.directPlayAllowed(id, 200000), true);
  }
});
check("HIGH, MEDIUM and LOW ask for their numbers", () => {
  assert.equal(SQ.plexTranscodeQuery("high"), "&maxVideoBitrate=12000&videoQuality=90&videoResolution=1920x1080&autoAdjustQuality=0");
  assert.equal(SQ.plexTranscodeQuery("medium"), "&maxVideoBitrate=4000&videoQuality=75&videoResolution=1280x720&autoAdjustQuality=0");
  assert.equal(SQ.plexTranscodeQuery("low"), "&maxVideoBitrate=1500&videoQuality=60&videoResolution=854x480&autoAdjustQuality=0");
  assert.equal(SQ.mediaBrowserMaxBitrate("medium"), 4000000);
  assert.deepEqual(plain(SQ.mediaBrowserFallbackOptions("low")), { maxWidth: 854, videoBitrate: 1500000 });
});
check("direct play: above the ceiling transcodes, at or below plays, unknown plays", () => {
  assert.equal(SQ.directPlayAllowed("medium", 4000), true);
  assert.equal(SQ.directPlayAllowed("medium", 4001), false);
  assert.equal(SQ.directPlayAllowed("low", 20000), false);
  for (const unknown of [undefined, null, 0, NaN, "x"]) assert.equal(SQ.directPlayAllowed("low", unknown), true);
});

const opts = { serverUrl: "http://s", itemId: "i", mediaSourceId: "m", token: "t", deviceId: "d", playSessionId: "p" };
check("the Jellyfin fallback URL is byte for byte what it was when no level is passed", () => {
  assert.equal(URLS.fallbackHlsUrl(opts),
    "http://s/Videos/i/master.m3u8?MediaSourceId=m&api_key=t&VideoCodec=h264&AudioCodec=aac&MaxWidth=3840&SegmentContainer=ts&DeviceId=d&PlaySessionId=p&ApiKey=t");
});
check("a capped level adds VideoBitrate and its own MaxWidth to the fallback URL", () => {
  const url = URLS.fallbackHlsUrl({ ...opts, ...SQ.mediaBrowserFallbackOptions("medium") });
  assert.equal(url, "http://s/Videos/i/master.m3u8?MediaSourceId=m&api_key=t&VideoCodec=h264&AudioCodec=aac&MaxWidth=1280&VideoBitrate=4000000&SegmentContainer=ts&DeviceId=d&PlaySessionId=p&ApiKey=t");
});

check("Playback Information keeps today's labels at AUTO and MAXIMUM and names a capped level", () => {
  for (const id of ["auto", "maximum", undefined]) {
    assert.equal(PI.webQualityLabel("plex", id), "Server default");
    assert.equal(PI.webQualityLabel("jellyfin", id), "Up to 120 Mbps");
    assert.equal(PI.webQualityLabel("emby", id), "Up to 120 Mbps");
  }
  assert.equal(PI.webQualityLabel("plex", "high"), "High (1080p, 12 Mbps)");
  assert.equal(PI.webQualityLabel("jellyfin", "medium"), "Medium (720p, 4 Mbps)");
  assert.equal(PI.webQualityLabel("emby", "low"), "Low (480p, 1.5 Mbps)");
  for (const id of ["high", "medium", "low"]) {
    const info = PI.create({ generation: 1, backend: "plex", qualityAtTune: PI.webQualityLabel("plex", id) });
    assert.equal(info.rows().find((r) => r.id === "quality").value, PI.webQualityLabel("plex", id));
  }
});

const tuner = read("plex-tuner.html");
check("plex-tuner.html loads the module and no request keeps a fixed 120 Mbps", () => {
  assert.equal(tuner.includes('<script src="scripts/nostalgex-stream-quality.js"></script>'), true);
  assert.equal(/MaxStreamingBitrate: 120000000/.test(tuner), false, "a fixed 120 Mbps is still in the page");
  assert.equal([...tuner.matchAll(/NostalgexStreamQuality\.mediaBrowserMaxBitrate\(/g)].length, 2, "device profile and body");
  assert.equal(tuner.includes("NostalgexStreamQuality.plexTranscodeQuery("), true);
  assert.equal([...tuner.matchAll(/NostalgexStreamQuality\.directPlayAllowed\(/g)].length, 2, "Jellyfin/Emby and Plex direct play");
});
check("the rail, the drawer, the picker and Settings all have the control", () => {
  for (const id of ["tb-quality", "tb-quality-val", "dw-quality-val", "quality-dialog", "quality-rows", "cfg-quality-chips"]) {
    assert.equal(tuner.includes(`id="${id}"`), true, id);
  }
});

if (failures.length) {
  console.error(`stream-quality smoke: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`stream-quality smoke: ${passed} checks passed (${golden.levels.length} golden levels)`);
