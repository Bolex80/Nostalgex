#!/usr/bin/env node
/**
 * The web tuner's repair for a Plex response with bytes that are not UTF-8 (issue #125),
 * held to scripts/utf8-repair-golden.json, the same vectors the Apple TV's PlexUTF8Repair
 * is checked against (PlexUTF8RepairGoldenTests.swift). No network, no browser.
 * The page itself is `npm run test:plex-bad-byte`.
 * Run: `npm run test:utf8-repair`.
 */
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const root = new URL("../", import.meta.url);
const golden = JSON.parse(readFileSync(new URL("scripts/utf8-repair-golden.json", root), "utf8"));
const src = readFileSync(new URL("scripts/nostalgex-utf8-repair.js", root), "utf8");
const tuner = readFileSync(new URL("plex-tuner.html", root), "utf8");

const sandbox = { TextDecoder, console: { warn() {} } };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox);
const R = sandbox.NostalgexUTF8Repair;

let passed = 0;
const failures = [];
async function check(label, fn) {
  try { await fn(); passed += 1; } catch (err) { failures.push(`${label}\n    ${String(err.message).split("\n").join("\n    ")}`); }
}

for (const c of golden.cases) {
  await check(`golden: ${c.name}`, () => {
    const { text, repairedBytes } = R.decode(Uint8Array.from(Buffer.from(c.hex, "hex")));
    assert.equal(text, c.text);
    assert.equal(repairedBytes, c.repairedBytes);
  });
}

await check("json(): a Plex page with a lone 0xE9 keeps its accent (Response.json() does not)", async () => {
  const bytes = Buffer.concat([Buffer.from('{"title":"Caf'), Buffer.from([0xe9]), Buffer.from(' Society"}')]);
  assert.equal((await new Response(bytes).json()).title, "Caf� Society", "the plain read should show the bug");
  assert.equal((await R.json(new Response(bytes))).title, "Café Society");
});
await check("json(): a valid response is parsed untouched", async () => {
  const body = JSON.stringify({ title: "Amélie \u{1F600}" });
  assert.equal((await R.json(new Response(body))).title, "Amélie \u{1F600}");
});
await check("json(): a body that is not JSON still rejects", async () => {
  await assert.rejects(() => R.json(new Response("<html>")), { name: "SyntaxError" });
});
await check("json(): a test double with only json() falls back to it", async () => {
  assert.deepEqual(await R.json({ json: async () => ({ ok: 1 }) }), { ok: 1 });
});
await check("the repair never adds a quote, backslash or control character", () => {
  for (let b = 0x80; b <= 0xff; b++) {
    const { text } = R.decode(Uint8Array.from([0x22, b, 0x22]));
    assert.equal(/[\\\u0000-\u001f]/.test(text.slice(1, -1)), false, `byte 0x${b.toString(16)}`);
  }
});
await check("plex-tuner.html loads the repair and reads every Plex server page through it", () => {
  assert.equal(tuner.includes('<script src="scripts/nostalgex-utf8-repair.js"></script>'), true);
  assert.equal([...tuner.matchAll(/NostalgexUTF8Repair\.json\(/g)].length, 4, "expected the four Plex server reads");
  assert.equal(/await res\.json\(\);\s*const container/.test(tuner), false, "the section page is still read with res.json()");
  assert.equal(/await epRes\.json\(\)/.test(tuner), false, "allLeaves is still read with epRes.json()");
});

if (failures.length) {
  console.error(`utf8-repair smoke: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`utf8-repair smoke: ${passed} checks passed (${golden.cases.length} golden vectors)`);
