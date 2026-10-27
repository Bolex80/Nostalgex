// STREAM QUALITY: how much a server is asked to send, the web port of the Apple TV's setting.
//
// PARITY CONTRACT with tvOS
//   Nostalgex/Nostalgex/Models/StreamQuality.swift   (the five levels and their numbers)
//   scripts/stream-quality-golden.json               (the shared table)
// Swift checks the table in StreamQualityGoldenTests, `npm run test:stream-quality` checks it
// here. Change a level in one engine without the other and one of those fails. The Roku port
// (#65) reads the same file.
//
// THE ONE DIFFERENCE FROM THE APPLE TV, on purpose. The web has always asked for the top
// (Jellyfin and Emby: a 120 Mbps ceiling; Plex: no ceiling at all, the server decides), so AUTO
// and MAXIMUM here leave every request exactly as it was. Only HIGH, MEDIUM and LOW add a
// ceiling. The Apple TV's AUTO and MAXIMUM ask for 4K at 40 Mbps and differ only in its
// remote direct-play ceiling, which the web has no way to tell is needed (a browser cannot say
// whether a server is on the LAN). Playback is the product, so no request a viewer already
// plays with changes until they pick a level.
//
// WHAT A CAPPED LEVEL CHANGES, per request:
//   Plex          the transcode URL gains maxVideoBitrate, videoQuality, videoResolution and
//                 autoAdjustQuality=0, the same four the Apple TV sends.
//   Jellyfin/Emby PlaybackInfo's MaxStreamingBitrate (device profile and body) is the level's
//                 bits per second, and the fallback HLS URL gains VideoBitrate and MaxWidth.
//   Direct play   a file whose known bitrate is above the level's ceiling is transcoded
//                 instead, wherever the server is. An unknown bitrate direct plays, as on the
//                 Apple TV.
// It is read when a programme starts, so it applies to every channel from the next programme.
(function (global) {
  'use strict';

  const STORAGE_KEY = 'nostalgex_stream_quality';
  const DEFAULT_ID = 'auto';
  // What the web asked Jellyfin and Emby for before this setting existed.
  const LEGACY_MEDIA_BROWSER_BPS = 120000000;

  // The Apple TV's table (StreamQuality.swift). Kbps is Plex's maxVideoBitrate unit.
  const LEVELS = [
    { id: 'auto',    name: 'Auto',    maxBitrateKbps: 40000, width: 3840, height: 2160, videoQualityIndex: 100 },
    { id: 'maximum', name: 'Maximum', maxBitrateKbps: 40000, width: 3840, height: 2160, videoQualityIndex: 100 },
    { id: 'high',    name: 'High',    maxBitrateKbps: 12000, width: 1920, height: 1080, videoQualityIndex: 90 },
    { id: 'medium',  name: 'Medium',  maxBitrateKbps: 4000,  width: 1280, height: 720,  videoQualityIndex: 75 },
    { id: 'low',     name: 'Low',     maxBitrateKbps: 1500,  width: 854,  height: 480,  videoQualityIndex: 60 },
  ];
  const CAPPED = new Set(['high', 'medium', 'low']);

  function level(id) {
    return LEVELS.find((l) => l.id === id) || LEVELS[0];
  }

  /** A short label for a chip or a row: AUTO, MAXIMUM, HIGH 1080P, MEDIUM 720P, LOW 480P. */
  function chipLabel(id) {
    const l = level(id);
    return CAPPED.has(l.id) ? `${l.name} ${l.height}p`.toUpperCase() : l.name.toUpperCase();
  }

  /** The second line of a row: what the level asks the server for. */
  function detail(id) {
    const l = level(id);
    if (CAPPED.has(l.id)) return `${l.height}p, ${l.maxBitrateKbps / 1000} Mbps.`;
    return l.id === 'auto' ? 'No ceiling from here. The server decides.' : 'No ceiling. For fast local networks.';
  }

  /** The saved choice, or AUTO. `storage` is localStorage (anything that throws gives AUTO). */
  function current(storage) {
    try {
      const raw = (storage || global.localStorage).getItem(STORAGE_KEY);
      return LEVELS.some((l) => l.id === raw) ? raw : DEFAULT_ID;
    } catch (_) {
      return DEFAULT_ID;
    }
  }

  function save(id, storage) {
    if (!LEVELS.some((l) => l.id === id)) return false;
    try {
      (storage || global.localStorage).setItem(STORAGE_KEY, id);
      return true;
    } catch (_) {
      return false;
    }
  }

  function isCapped(id) {
    return CAPPED.has(id);
  }

  /** The Plex transcode URL's quality parameters, with a leading &. Empty for AUTO and MAXIMUM. */
  function plexTranscodeQuery(id) {
    if (!isCapped(id)) return '';
    const l = level(id);
    return `&maxVideoBitrate=${l.maxBitrateKbps}&videoQuality=${l.videoQualityIndex}`
      + `&videoResolution=${l.width}x${l.height}&autoAdjustQuality=0`;
  }

  /** Jellyfin and Emby MaxStreamingBitrate, in bits per second. */
  function mediaBrowserMaxBitrate(id) {
    return isCapped(id) ? level(id).maxBitrateKbps * 1000 : LEGACY_MEDIA_BROWSER_BPS;
  }

  /** Extra options for NostalgexJellyfinUrls.fallbackHlsUrl. Empty for AUTO and MAXIMUM. */
  function mediaBrowserFallbackOptions(id) {
    if (!isCapped(id)) return {};
    const l = level(id);
    return { maxWidth: l.width, videoBitrate: l.maxBitrateKbps * 1000 };
  }

  /**
   * False when the level's ceiling is below the file's known bitrate (kbps), so the programme
   * goes through the server's transcoder. True for AUTO, MAXIMUM, and a bitrate nobody knows.
   */
  function directPlayAllowed(id, bitrateKbps) {
    if (!isCapped(id)) return true;
    const kbps = Number(bitrateKbps);
    if (!Number.isFinite(kbps) || kbps <= 0) return true;
    return kbps <= level(id).maxBitrateKbps;
  }

  /** The Playback Information row. AUTO and MAXIMUM keep the label of what the web always asked. */
  function infoLabel(id, backend) {
    if (isCapped(id)) {
      const l = level(id);
      return `${l.name} (${l.height}p, ${l.maxBitrateKbps / 1000} Mbps)`;
    }
    if (backend === 'jellyfin' || backend === 'emby') return 'Up to 120 Mbps';
    if (backend === 'plex') return 'Server default';
    return 'Unknown';
  }

  global.NostalgexStreamQuality = {
    STORAGE_KEY, DEFAULT_ID, LEVELS, level, chipLabel, detail, current, save, isCapped,
    plexTranscodeQuery, mediaBrowserMaxBitrate, mediaBrowserFallbackOptions, directPlayAllowed, infoLabel,
  };
})(typeof globalThis !== 'undefined' ? globalThis : window);
