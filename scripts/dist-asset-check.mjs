// Fails the build when a built page points at a local file that isn't in dist.
//
// The generated pages (the blog and the channel guide) are written after Vite,
// and they find the hashed stylesheet and script by looking at what Vite emitted.
// When that lookup went wrong once, it fell back to /styles.css, which does not
// exist in dist, and 23 pages shipped with no styles at all. Nothing failed.
// This check is what fails now.
//
// It reads every .html file under the output directory and checks the files a
// browser would fetch to draw the page: stylesheets, preloads, icons, scripts,
// images (src and srcset), video sources and posters. Links to other pages are
// left alone, because clean URLs and rewrites decide those, not the file tree.
//
//   node scripts/dist-asset-check.mjs            checks dist/
//   node scripts/dist-asset-check.mjs <dir>      checks another output directory

import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2] || "dist");
if (!existsSync(root)) {
  console.error(`dist-asset-check: ${root} does not exist. Run the build first.`);
  process.exit(1);
}

async function htmlFiles(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await htmlFiles(full)));
    else if (entry.name.endsWith(".html")) out.push(full);
  }
  return out;
}

const FETCHED_LINK_RELS = /\brel="(?:stylesheet|preload|modulepreload|icon|apple-touch-icon|manifest)"/;

function refsIn(html) {
  const refs = [];
  for (const m of html.matchAll(/<link\b[^>]*>/g)) {
    if (!FETCHED_LINK_RELS.test(m[0])) continue;
    const href = m[0].match(/\bhref="([^"]*)"/);
    if (href) refs.push(href[1]);
  }
  for (const m of html.matchAll(/<(?:script|img|source|video|audio|iframe)\b[^>]*>/g)) {
    for (const attr of ["src", "poster"]) {
      const v = m[0].match(new RegExp(`\\s${attr}="([^"]*)"`));
      if (v) refs.push(v[1]);
    }
    const srcset = m[0].match(/\ssrcset="([^"]*)"/);
    if (srcset) for (const part of srcset[1].split(",")) refs.push(part.trim().split(/\s+/)[0]);
  }
  return refs;
}

function isLocal(ref) {
  return ref && !/^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i.test(ref);
}

const missing = [];
let checked = 0;
for (const file of await htmlFiles(root)) {
  const html = await readFile(file, "utf8");
  for (const ref of refsIn(html)) {
    if (!isLocal(ref)) continue;
    const clean = decodeURI(ref.split(/[?#]/)[0]);
    const target = clean.startsWith("/") ? path.join(root, clean) : path.join(path.dirname(file), clean);
    checked++;
    if (!existsSync(target)) missing.push(`${path.relative(root, file)}: ${ref}`);
  }
}

if (missing.length) {
  console.error(`dist-asset-check: ${missing.length} reference(s) to files that are not in ${path.relative(process.cwd(), root) || root}:`);
  for (const m of missing.slice(0, 50)) console.error(`  ${m}`);
  if (missing.length > 50) console.error(`  ... and ${missing.length - 50} more`);
  process.exit(1);
}
console.log(`dist-asset-check: ${checked} local references, all present`);
