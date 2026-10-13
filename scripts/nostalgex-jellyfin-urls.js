// Jellyfin / Emby stream URLs for the web tuner.
//
// PARITY with tvOS
//   Nostalgex/Nostalgex/Services/JellyfinPlaybackResolver.swift  staticStreamURL
//   Nostalgex/Nostalgex/Services/JellyfinAPIService.swift        addingApiKey
//
// 1. Direct play asks for /Videos/{id}/stream.mp4, not /Videos/{id}/stream. Jellyfin 12.2
//    sets the Content-Type of a static stream from the FILE NAME, so an MP4 saved as .mkv
//    comes back video/x-matroska (and a .m4v as video/x-m4v, a .mov as video/quicktime).
//    The extension makes the server label the same bytes video/mp4. Only used for the
//    mp4/m4v/mov family; anything else keeps the extensionless URL.
// 2. Every hand-built HLS URL carries ApiKey beside api_key. Jellyfin 12.2 with legacy
//    authorization off (the default on a new install) answers 401 to api_key alone.
//    api_key stays for servers older than ApiKey. Emby 4.10 accepts both.
//
// Measured 2026-10-12 against local Jellyfin 12.2.0 and Emby 4.10.1.0.
//
// USAGE (browser: plain <script src="scripts/nostalgex-jellyfin-urls.js">,
// node: `import "./nostalgex-jellyfin-urls.js"`, then globalThis):
//
//   const JU = window.NostalgexJellyfinUrls;
//   JU.staticStreamUrl({ serverUrl, itemId, mediaSourceId, container, token, audioStreamIndex });
//   JU.withApiKey(url, token);

(function (global) {
  'use strict';

  const MP4_FAMILY = new Set(['mp4', 'm4v', 'mov']);

  function isMp4Family(container) {
    // Jellyfin can report a comma list straight from ffprobe ("mov,mp4,m4a,3gp,3g2,mj2").
    return String(container || '')
      .toLowerCase()
      .split(',')
      .some(c => MP4_FAMILY.has(c.trim()));
  }

  function staticStreamUrl(opts) {
    const { serverUrl, itemId, mediaSourceId, container, token, audioStreamIndex } = opts;
    const path = isMp4Family(container) ? 'stream.mp4' : 'stream';
    let url = `${serverUrl}/Videos/${itemId}/${path}`
      + `?Static=true&MediaSourceId=${encodeURIComponent(mediaSourceId)}&api_key=${token}`;
    if (audioStreamIndex !== undefined && audioStreamIndex !== null) {
      url += `&AudioStreamIndex=${audioStreamIndex}`;
    }
    return url;
  }

  function hasParam(url, name) {
    return new RegExp(`[?&]${name}=`).test(url);
  }

  function withApiKey(url, token) {
    let out = url;
    for (const name of ['api_key', 'ApiKey']) {
      if (!hasParam(out, name)) out += (out.includes('?') ? '&' : '?') + `${name}=${token}`;
    }
    return out;
  }

  const api = { isMp4Family, staticStreamUrl, withApiKey };

  global.NostalgexJellyfinUrls = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
