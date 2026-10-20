#!/usr/bin/env node
// QR code vectors for source/util/QrCode.brs, from a reference encoder: the
// `qrcode` package's matrices at level M, byte mode, for each text under each
// of the eight masks. A decoder (`jsqr`) reads
// each matrix back, so a vector is a code a phone can scan.
//
//   npm install --prefix "$dir" qrcode@1.5.4 jsqr@1.4.0
//   QR_REF_DIR="$dir" node tests/gen-qr.mjs     # writes tests/vectors/qr.json
//
// Not part of gen-vectors.mjs: nothing here comes from upstream, and the
// encoder only changes when this port does.
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.env.QR_REF_DIR;
if (!dir) throw new Error("set QR_REF_DIR to a directory with qrcode@1.5.4 and jsqr@1.4.0 installed");
const require = createRequire(join(dir, "node_modules", "x.js"));
const QR = require("qrcode");
const jsQR = require("jsqr");

const texts = [
  "https://www.plex.tv/link/",
  "https://www.plex.tv/link/?pin=ABCD",
  "https://www.plex.tv/link/?pin=Z9Q2",
  "A",
  "0123456789abcdef",
  // Version 7 and up carry version bits; 10 has a 16-bit count.
  "https://www.plex.tv/link/?pin=ABCD&padding=" + "x".repeat(100),
  "w".repeat(110),
  "y".repeat(150),
  "z".repeat(213),
];

// Renders a matrix with a 4-module quiet zone at 4 px a module and decodes it.
function decodes(rows, want) {
  const scale = 4, quiet = 4, n = rows.length + quiet * 2, px = n * scale;
  const img = new Uint8ClampedArray(px * px * 4).fill(255);
  rows.forEach((row, y) => [...row].forEach((c, x) => {
    if (c !== "1") return;
    for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) {
      const o = (((y + quiet) * scale + dy) * px + (x + quiet) * scale + dx) * 4;
      img[o] = img[o + 1] = img[o + 2] = 0;
    }
  }));
  const got = jsQR(img, px, px);
  return got !== null && got.data === want;
}

const cases = texts.map((text) => {
  const segs = [{ data: Buffer.from(text, "latin1"), mode: "byte" }];
  const masks = [];
  for (let mask = 0; mask < 8; mask++) {
    const q = QR.create(segs, { errorCorrectionLevel: "M", maskPattern: mask });
    const size = q.modules.size;
    const rows = Array.from({ length: size }, (_, y) =>
      Array.from({ length: size }, (_, x) => (q.modules.get(y, x) ? "1" : "0")).join(""));
    if (!decodes(rows, text)) throw new Error(`reference code for ${JSON.stringify(text)} mask ${mask} doesn't decode`);
    masks.push(rows);
  }
  return { text, version: QR.create(segs, { errorCorrectionLevel: "M" }).version, masks };
});

const out = new URL("./vectors/qr.json", import.meta.url);
writeFileSync(out, JSON.stringify({ generator: "qrcode@1.5.4, checked with jsqr@1.4.0", cases }, null, 1) + "\n");
console.log(`wrote ${out.pathname}: ${cases.length} texts, versions ${cases.map((c) => c.version).join(",")}`);
