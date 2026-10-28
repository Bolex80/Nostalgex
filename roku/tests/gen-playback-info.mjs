// PLAYBACK INFORMATION vectors (issue #74): upstream's own
// scripts/nostalgex-playback-info.js run over codecs, sizes and sequences of
// attempts, so source/guide/PlaybackInfo.brs gives the web tuner's rows (and
// so the Apple TV's, which the web module mirrors). Called by
// tests/gen-vectors.mjs; read by tests/PlaybackInfoTests.brs.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export async function playbackInfoVectors(upstream) {
  await import(pathToFileURL(join(upstream, "scripts", "nostalgex-playback-info.js")).href);
  const PI = globalThis.NostalgexPlaybackInfo;
  if (!PI) throw new Error("upstream playback-info module did not load");

  const codecInputs = ["h264", "AVC", " avc1 ", "hevc", "H265", "hev1", "hvc1", "mpeg2video", "mpeg4", "av1", "vp9", "vc1",
    "aac", "AC3", "eac3", "dts", "dca", "truehd", "flac", "alac", "mp3", "opus", "vorbis", "pcm",
    "", null, "x264", "pcm_s16le", "dts-hd ma", "<script>", "h264 "];
  const codecs = [];
  for (const value of codecInputs) {
    for (const video of [true, false]) codecs.push({ value, video, label: PI.codecLabel(value, video) });
  }

  const sizeInputs = [[1920, 1080], [3840, 2160], [1279.6, 719.4], [0, 1080], [1920, 0], [65536, 65536], [65537, 100],
    [null, 1080], [1920, null], [-1, 5], [1, 1], [0.6, 0.6]];
  const sizes = sizeInputs.map(([w, h]) => ({ w, h, label: PI.sizeLabel(w, h) }));

  // Sequences. Each step's answer is kept: begin -> whether it was accepted,
  // ready -> true/false, rows -> the rows. "ready" names which attempt id it
  // carries: the latest, the one before, or none.
  const scripts = {
    "direct play, then ready": [
      { op: "begin", gen: 1, delivery: "directPlay", reason: "none" },
      { op: "rows", w: 1920, h: 1080 },
      { op: "ready", gen: 1, which: "latest" },
      { op: "rows", w: 1920, h: 1080 },
    ],
    "server stream chosen up front": [
      { op: "begin", gen: 1, delivery: "serverStream", reason: "serverStreamSelected" },
      { op: "ready", gen: 1, which: "latest" },
      { op: "rows", w: 3840, h: 2160 },
    ],
    "direct play fails, then the server stream": [
      { op: "begin", gen: 1, delivery: "directPlay", reason: "none" },
      { op: "ready", gen: 1, which: "latest" },
      { op: "invalidate" },
      { op: "rows", w: 1920, h: 1080 },
      { op: "begin", gen: 1, delivery: "serverStream", reason: "directPlayFailed" },
      { op: "ready", gen: 1, which: "previous" },
      { op: "rows", w: 1920, h: 1080 },
      { op: "ready", gen: 1, which: "latest" },
      { op: "rows", w: 1920, h: 1080 },
    ],
    "no picture, then the 1080p retry": [
      { op: "begin", gen: 4, delivery: "serverStream", reason: "serverStreamSelected" },
      { op: "begin", gen: 4, delivery: "serverStream", reason: "startupNoPicture", recovery: "compatibility1080p" },
      { op: "ready", gen: 4, which: "latest" },
      { op: "rows", w: 1920, h: 800 },
    ],
    "the recovery request stays once made": [
      { op: "begin", gen: 2, delivery: "serverStream", reason: "streamStalled", recovery: "compatibility1080p" },
      { op: "begin", gen: 2, delivery: "serverStream", reason: "playerRetry" },
      { op: "ready", gen: 2, which: "latest" },
      { op: "rows", w: 1280, h: 720 },
    ],
    "a stale generation is refused": [
      { op: "begin", gen: 3, delivery: "directPlay", reason: "none" },
      { op: "begin", gen: 2, delivery: "serverStream", reason: "directPlayFailed" },
      { op: "ready", gen: 2, which: "latest" },
      { op: "rows", w: 1920, h: 1080 },
      { op: "ready", gen: 3, which: "none" },
      { op: "ready", gen: 3, which: "latest" },
      { op: "rows", w: 1920, h: 1080 },
    ],
    "unknown words read as unknown": [
      { op: "begin", gen: 1, delivery: "sideways", reason: "gremlins", recovery: "everything" },
      { op: "ready", gen: 1, which: "latest" },
      { op: "rows", w: null, h: null },
    ],
    "nothing begun": [
      { op: "ready", gen: 1, which: "none" },
      { op: "rows", w: 1920, h: 1080 },
    ],
  };
  const creates = [
    { generation: 1, backend: "plex", qualityAtTune: "Server default", videoCodec: "hevc", audioCodec: "eac3" },
    { generation: 2, backend: "jellyfin", qualityAtTune: "Server default", videoCodec: "h264", audioCodec: "aac" },
    { generation: 3, backend: "emby", qualityAtTune: "Server default", videoCodec: "av1", audioCodec: "truehd" },
    { generation: 4, backend: "emby", qualityAtTune: "Server default", videoCodec: "mpeg2video", audioCodec: "ac3" },
    { generation: 1, backend: "kodi", qualityAtTune: "Turbo", videoCodec: "x264", audioCodec: "" },
  ];
  const sequences = [];
  for (const [name, steps] of Object.entries(scripts)) {
    for (const create of creates) {
      const info = PI.create(create);
      const ids = [];
      const answers = steps.map((s) => {
        if (s.op === "begin") {
          const id = info.beginAttempt(s.gen, s.delivery, s.reason, s.recovery ?? null);
          if (id != null) ids.push(id);
          return id != null;
        }
        if (s.op === "ready") {
          const id = s.which === "latest" ? ids.at(-1) : s.which === "previous" ? ids.at(-2) : null;
          return info.markReady(s.gen, id ?? null);
        }
        if (s.op === "invalidate") { info.invalidateAttempt(); return null; }
        return info.rows(s.w, s.h);
      });
      sequences.push({ name, create, steps, answers });
    }
  }
  // The evidence note isn't compared: the web's names the browser, the
  // Roku's the Roku player, as the Apple TV's names AVPlayer.
  return { codecs, sizes, sequences };
}
