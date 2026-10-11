// Report Playback without filling Continue Watching: the web port of the tvOS guard.
//
// PARITY CONTRACT with tvOS
//   Nostalgex/Nostalgex/Services/WatchStateGuard.swift   (WatchCleanupPlan, request shapes)
//   Nostalgex/Nostalgex/Services/PlaybackTracker.swift   (when capture and cleanup run)
//
// Both read scripts/watch-cleanup-golden.json: WatchStateGuardTests on the Swift side,
// `npm run test:watch-state` here. Change a rule in one engine without the other and
// one of those tests fails.
//
// The rule: Report Playback keeps Now Playing and real watches flowing to the user's
// server, but a program the tuner played must never be left in Continue Watching (Plex),
// Resume (Jellyfin, Emby) or On Deck. Before the first report we read what the server
// held for the item; when the session ends we put that back. Measured against Plex,
// Emby 4.10 and Jellyfin 12.2 on 2026-10-11 (Nostalgex/docs/plex-session-reporting.md).
//
// USAGE (browser: plain <script src="scripts/nostalgex-watch-state.js">,
// node: `import "./nostalgex-watch-state.js"`, then globalThis):
//
//   const WS = window.NostalgexWatchState;
//   const guard = WS.plexGuard({ serverUrl, authQuery: 'X-Plex-Token=...', fetchImpl: fetch });
//   WS.sharedQueue.enqueue(async () => { prior = await guard.capture(ratingKey); });
//   ...reports, all through WS.sharedQueue...
//   WS.sharedQueue.enqueue(() => guard.restore(ratingKey, prior, counted));

(function (global) {
  'use strict';

  const LIBRARY = 'com.plexapp.plugins.library';

  // ── The decision (must match WatchCleanupPlan in Swift) ──
  // prior: { resumePosition, playCount, played, lastPlayedDate, showKey, showInContinueWatching }
  // or null when the read failed. resumePosition is Plex ms or Jellyfin/Emby 100ns ticks.

  function plexPlan(prior, counted) {
    if (counted) {
      // The scrobble cleared the item's own resume point; an episode scrobble adds the
      // next episode to Continue Watching. Remove that unless the show was already there.
      if (!prior || !prior.showKey || prior.showInContinueWatching) return [];
      return [{ kind: 'removeShowFromContinueWatching', show: prior.showKey }];
    }
    if (!prior) return [{ kind: 'removeFromContinueWatching' }];
    if (prior.resumePosition > 0) return [{ kind: 'progress', time: prior.resumePosition }];
    if (prior.playCount === 0 && !prior.played) return [{ kind: 'unscrobble' }];
    return [{ kind: 'removeFromContinueWatching' }];
  }

  function mediaServerPlan(prior, counted) {
    if (!prior) return [{ kind: 'userData', position: 0 }];
    if (counted) return [{ kind: 'userData', position: 0, playCount: prior.playCount + 1, played: true }];
    if (prior.resumePosition === 0 && prior.playCount === 0 && !prior.played) return [{ kind: 'markUnplayed' }];
    const step = { kind: 'userData', position: prior.resumePosition, playCount: prior.playCount, played: prior.played };
    if (prior.lastPlayedDate) step.lastPlayedDate = prior.lastPlayedDate;
    return [step];
  }

  /** Compact form used by scripts/watch-cleanup-golden.json. */
  function describe(step) {
    switch (step.kind) {
      case 'unscrobble': return 'unscrobble';
      case 'progress': return `progress ${step.time}`;
      case 'removeFromContinueWatching': return 'removeFromContinueWatching';
      case 'removeShowFromContinueWatching': return `removeShowFromContinueWatching ${step.show}`;
      case 'markUnplayed': return 'markUnplayed';
      case 'userData': {
        const parts = [`userData position=${step.position}`];
        if (step.playCount != null) parts.push(`playCount=${step.playCount}`);
        if (step.played != null) parts.push(`played=${step.played}`);
        if (step.lastPlayedDate) parts.push(`lastPlayedDate=${step.lastPlayedDate}`);
        return parts.join(' ');
      }
      default: return step.kind;
    }
  }

  // ── Ordering ──
  // Plex writes a resume point on every timeline report, so a cleanup that lands before
  // the last report is undone by it. Every report and cleanup goes through one queue.
  function createReportQueue() {
    let tail = Promise.resolve();
    return {
      enqueue(op) {
        tail = tail.then(op).catch(() => {});
        return tail;
      },
      drain() { return tail; },
    };
  }

  async function send(fetchImpl, method, url, opts) {
    const o = opts || {};
    try {
      const res = await fetchImpl(url, {
        method,
        headers: Object.assign({ Accept: 'application/json' }, o.headers || {}),
        body: o.body,
        keepalive: !!o.keepalive,
      });
      let json = null;
      if (o.json) { try { json = await res.json(); } catch (_) { json = null; } }
      return { status: res.status, json };
    } catch (_) {
      return null;
    }
  }

  // ── Plex ──
  function plexGuard({ serverUrl, authQuery, fetchImpl }) {
    const f = fetchImpl || global.fetch.bind(global);
    const url = (path, params) => {
      const q = new URLSearchParams(params || {}).toString();
      return `${serverUrl}${path}?${q}${q && authQuery ? '&' : ''}${authQuery || ''}`;
    };
    const ok = r => r && r.status >= 200 && r.status < 300;

    async function continueWatching() {
      const r = await send(f, 'GET', url('/hubs/continueWatching/items', { count: '200' }), { json: true });
      if (!ok(r) || !r.json || !r.json.MediaContainer) return null;
      return r.json.MediaContainer.Metadata || [];
    }

    function stepUrl(step, rk) {
      switch (step.kind) {
        case 'unscrobble': return ['GET', url('/:/unscrobble', { key: rk, identifier: LIBRARY })];
        case 'progress': return ['PUT', url('/:/progress', { key: rk, identifier: LIBRARY, time: String(step.time), state: 'stopped' })];
        case 'removeFromContinueWatching': return ['PUT', url('/actions/removeFromContinueWatching', { ratingKey: rk })];
        default: return null;
      }
    }

    return {
      url,
      /** `key` is the bare rating key; /library/metadata/{rk} is answered with 404. */
      scrobbleUrl: rk => url('/:/scrobble', { key: rk, identifier: LIBRARY }),
      timelineUrl: (rk, state, timeMs, durationMs, sessionId) => url('/:/timeline', {
        ratingKey: rk, key: `/library/metadata/${rk}`, state, time: String(timeMs),
        duration: String(durationMs), 'X-Plex-Session-Identifier': sessionId,
      }),
      async capture(rk) {
        const r = await send(f, 'GET', url(`/library/metadata/${encodeURIComponent(rk)}`), { json: true });
        const meta = ok(r) && r.json && r.json.MediaContainer && (r.json.MediaContainer.Metadata || [])[0];
        if (!meta) return null;
        const prior = {
          resumePosition: meta.viewOffset || 0,
          playCount: meta.viewCount || 0,
          played: (meta.viewCount || 0) > 0,
          lastPlayedDate: null,
          showKey: null,
          showInContinueWatching: false,
        };
        if (meta.type === 'episode' && meta.grandparentRatingKey) {
          const show = String(meta.grandparentRatingKey);
          prior.showKey = show;
          const row = await continueWatching();
          // Unreadable row: assume the show was there, so we never remove a real entry.
          prior.showInContinueWatching = row
            ? row.some(e => String(e.grandparentRatingKey) === show || String(e.ratingKey) === show)
            : true;
        }
        return prior;
      },
      async restore(rk, prior, counted, opts) {
        const keepalive = !!(opts && opts.keepalive);
        for (const step of plexPlan(prior, counted)) {
          if (step.kind === 'removeShowFromContinueWatching') {
            const row = (await continueWatching()) || [];
            for (const e of row.filter(x => String(x.grandparentRatingKey) === step.show)) {
              const r = await send(f, 'PUT', url('/actions/removeFromContinueWatching', { ratingKey: String(e.ratingKey) }), { keepalive });
              console.log('[Tracker] cleanup', rk, 'removeFromContinueWatching next-up', e.ratingKey, r ? r.status : 'failed');
            }
            continue;
          }
          const req = stepUrl(step, rk);
          if (!req) continue;
          const r = await send(f, req[0], req[1], { keepalive });
          console.log('[Tracker] cleanup', rk, describe(step), r ? r.status : 'failed');
        }
      },
    };
  }

  // ── Jellyfin / Emby ── (both answer the /Users/{id}/... routes)
  function mediaServerGuard({ serverUrl, userId, authHeader, fetchImpl }) {
    const f = fetchImpl || global.fetch.bind(global);
    const base = `${serverUrl}/Users/${encodeURIComponent(userId)}`;
    const headers = () => ({ Authorization: typeof authHeader === 'function' ? authHeader() : authHeader });
    const ok = r => r && r.status >= 200 && r.status < 300;

    function stepRequest(step, id) {
      const item = encodeURIComponent(id);
      if (step.kind === 'markUnplayed') return ['DELETE', `${base}/PlayedItems/${item}`, null];
      if (step.kind === 'userData') {
        const body = { PlaybackPositionTicks: step.position };
        if (step.playCount != null) body.PlayCount = step.playCount;
        if (step.played != null) body.Played = step.played;
        if (step.lastPlayedDate) body.LastPlayedDate = step.lastPlayedDate;
        return ['POST', `${base}/Items/${item}/UserData`, JSON.stringify(body)];
      }
      return null;
    }

    return {
      markPlayedUrl: id => `${base}/PlayedItems/${encodeURIComponent(id)}`,
      async capture(id) {
        const r = await send(f, 'GET', `${base}/Items/${encodeURIComponent(id)}`, { json: true, headers: headers() });
        const data = ok(r) && r.json && r.json.UserData;
        if (!data) return null;
        return {
          resumePosition: data.PlaybackPositionTicks || 0,
          playCount: data.PlayCount || 0,
          played: !!data.Played,
          lastPlayedDate: data.LastPlayedDate || null,
          showKey: null,
          showInContinueWatching: false,
        };
      },
      async restore(id, prior, counted, opts) {
        const keepalive = !!(opts && opts.keepalive);
        for (const step of mediaServerPlan(prior, counted)) {
          const req = stepRequest(step, id);
          if (!req) continue;
          const h = headers();
          if (req[2]) h['Content-Type'] = 'application/json';
          const r = await send(f, req[0], req[1], { headers: h, body: req[2] || undefined, keepalive });
          console.log('[Tracker] cleanup', id, describe(step), r ? r.status : 'failed');
        }
      },
    };
  }

  const api = {
    plexPlan,
    mediaServerPlan,
    describe,
    createReportQueue,
    sharedQueue: createReportQueue(),
    plexGuard,
    mediaServerGuard,
  };

  global.NostalgexWatchState = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
