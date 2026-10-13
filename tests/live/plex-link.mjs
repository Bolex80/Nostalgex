#!/usr/bin/env node
// Link this computer to Plex for the live checks: shows a plex.tv/link code,
// waits for it to be entered, and saves the token as PLEX_TOKEN in .env
// (git-ignored, mode 600). The token is never printed. Revoke it any time in
// Plex under Settings > Authorized Devices ("nostalgex-roku devtools").
import { https, readEnv, writeEnvKey } from "./plex-env.mjs";

const existing = readEnv().PLEX_TOKEN;
if (existing) {
  const me = await https("https://plex.tv/api/v2/user", { token: existing });
  if (me.status === 200) {
    console.log(`Already linked as ${me.json.username || me.json.title}.`);
    process.exit(0);
  }
  console.log("The saved token was rejected; linking again.");
}

const pin = await https("https://plex.tv/api/v2/pins", { method: "POST" });
if (pin.status < 200 || pin.status > 299) throw new Error(`plex.tv pins answered ${pin.status}`);
console.log(`Go to plex.tv/link and enter: ${String(pin.json.code).toUpperCase()}`);
console.log("Waiting up to 15 minutes...");

const deadline = Date.now() + 15 * 60 * 1000;
while (Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 2000));
  const check = await https(`https://plex.tv/api/v2/pins/${pin.json.id}`).catch(() => null);
  if (check?.status === 404) break;
  const token = check?.json?.authToken;
  if (token) {
    writeEnvKey("PLEX_TOKEN", token);
    const me = await https("https://plex.tv/api/v2/user", { token });
    console.log(`Linked as ${me.json?.username || me.json?.title || "Plex"}. Token saved to .env (mode 600).`);
    process.exit(0);
  }
}
console.log("The code expired. Run this again for a new one.");
process.exit(1);
