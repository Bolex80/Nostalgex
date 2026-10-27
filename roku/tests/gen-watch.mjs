// Report Playback vectors: upstream's own scripts/nostalgex-watch-state.js run
// over sequences, so the port's pulse backoff and cleanup plans answer exactly
// as the web tuner's (and so the Apple TV's, which shares
// scripts/watch-cleanup-golden.json with it). Called by tests/gen-vectors.mjs.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export async function watchVectors(upstream) {
  await import(pathToFileURL(join(upstream, "scripts", "nostalgex-watch-state.js")).href);
  const W = globalThis.NostalgexWatchState;
  if (!W) throw new Error("upstream watch-state module did not load");

  // Backoff: each script is a list of "pulse" (ask allowPulse) and "ok"/"fail"
  // (record); the answers to each pulse are kept.
  const scripts = {
    "answered pulses all go": ["pulse", "ok", "pulse", "ok", "pulse"],
    "one failure skips one pulse": ["pulse", "fail", "pulse", "pulse", "pulse"],
    "failures double the skip": ["fail", "pulse", "pulse", "fail", "pulse", "pulse", "pulse", "fail", "pulse", "pulse", "pulse", "pulse", "pulse"],
    "an answer resets it": ["fail", "fail", "fail", "ok", "pulse", "fail", "pulse", "pulse"],
    "the skip stops at 30": [...Array(8).fill("fail"), ...Array(32).fill("pulse")],
  };
  const backoff = Object.entries(scripts).map(([name, steps]) => {
    const b = W.createPulseBackoff();
    const answers = [];
    for (const s of steps) {
      if (s === "pulse") answers.push(b.allowPulse());
      else b.record(s === "ok");
    }
    return { name, steps, answers };
  });

  // Plans for priors the golden file doesn't hold.
  const priors = [
    null,
    { resumePosition: 0, playCount: 0, played: false, lastPlayedDate: null, showKey: null, showInContinueWatching: false },
    { resumePosition: 0, playCount: 0, played: true, lastPlayedDate: null, showKey: null, showInContinueWatching: false },
    { resumePosition: 0, playCount: 3, played: true, lastPlayedDate: "2026-01-02T03:04:05.0000000Z", showKey: null, showInContinueWatching: false },
    { resumePosition: 123456789, playCount: 0, played: false, lastPlayedDate: null, showKey: null, showInContinueWatching: false },
    { resumePosition: 0, playCount: 0, played: false, lastPlayedDate: null, showKey: "77", showInContinueWatching: true },
    { resumePosition: 0, playCount: 0, played: false, lastPlayedDate: null, showKey: "77", showInContinueWatching: false },
  ];
  const plans = [];
  for (const prior of priors) {
    for (const counted of [false, true]) {
      plans.push({ backend: "plex", prior, counted, steps: W.plexPlan(prior, counted).map(W.describe) });
      plans.push({ backend: "mediaServer", prior, counted, steps: W.mediaServerPlan(prior, counted).map(W.describe) });
    }
  }
  return { backoff, plans };
}
