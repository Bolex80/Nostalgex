// TMDB enrichment for the web tuner: the same keywords, networks, production
// companies and franchise the Apple TV app reads, so enrichment-gated channels
// (TEEN MOVIES, MUSICALS, TRUE CRIME, SPY GAMES, BIOPICS, MIDNIGHT, TOON TOWN, ...)
// fill on the web the way they do on tvOS.
//
// Mirrors Nostalgex/Nostalgex/Services/EnrichmentService.swift:
//   1. dedupe the library to one work item per TMDB id (first item's media type wins)
//   2. read the shared Supabase cache (`media_enrichments`) for those ids
//   3. fetch the misses from TMDB through the site relay (api/tmdb.js)
//   4. upsert what was fetched back to Supabase with resolution=merge-duplicates
// and TMDBService.parseResponse for turning a TMDB document into a row.
//
// Two web-only additions:
//   - A per-browser cache in IndexedDB with a TTL, so a reload does not repeat the
//     Supabase read or the relay fetches.
//   - Only TMDB ids leave the browser. No IMDb ids, titles or server details. The
//     upsert carries the TMDB columns only, so it never touches OMDb columns an
//     Apple TV wrote.
//
// The attached record lives at `item.enrichment`, in the shape
// scripts/nostalgex-channel-filter.cjs `enrichedValue()` reads (camelCase, the
// Swift MediaEnrichment property names).
(function (global) {
  'use strict';

  const SUPABASE_CHUNK = 200;
  const RELAY_CONCURRENCY = 6;
  const CACHE_TTL_MS = 7 * 86400000;
  const MISS_TTL_MS = 86400000;
  const CLIENT_HEADER = 'X-Nostalgex-Client';
  const CLIENT_VALUE = 'web';
  const TMDB_COLUMNS = [
    'tmdb_id', 'media_type', 'keywords', 'networks', 'production_companies',
    'tmdb_genres', 'franchise_id', 'franchise_name', 'fetched_at',
  ];
  const DEFAULT_RELAY = 'https://nostalgex.app/api/tmdb';

  // ── Pure: shapes ───────────────────────────────────────────────────────────

  function names(list) {
    if (!Array.isArray(list)) return [];
    return list.map((x) => (x && typeof x.name === 'string' ? x.name : null)).filter((x) => x != null);
  }

  /**
   * TMDBService.parseResponse. Movies carry keywords under `keywords.keywords`,
   * TV under `keywords.results`. Franchise comes from `belongs_to_collection`
   * (movies only). OMDb fields stay null; the relay does not proxy OMDb.
   */
  function parseTMDBResponse(json, tmdbID, imdbID, mediaType, now = new Date()) {
    const doc = json && typeof json === 'object' ? json : {};
    const kwObj = doc.keywords && typeof doc.keywords === 'object' ? doc.keywords : null;
    const kwKey = mediaType === 'tv' ? 'results' : 'keywords';
    const collection = doc.belongs_to_collection && typeof doc.belongs_to_collection === 'object'
      ? doc.belongs_to_collection : null;
    const franchiseID = collection && Number.isInteger(collection.id) ? collection.id : null;
    const franchiseName = collection && typeof collection.name === 'string' ? collection.name : null;
    return {
      tmdbID: String(tmdbID),
      imdbID: imdbID ?? null,
      mediaType,
      keywords: kwObj ? names(kwObj[kwKey]) : [],
      networks: names(doc.networks),
      productionCompanies: names(doc.production_companies),
      tmdbGenres: names(doc.genres),
      imdbRating: null,
      imdbVotes: null,
      rottenTomatoesScore: null,
      metacriticScore: null,
      awards: null,
      franchiseID,
      franchiseName,
      fetchedAt: now.toISOString(),
    };
  }

  function stringList(v) {
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : [];
  }
  function numOrNull(v) {
    return typeof v === 'number' && Number.isFinite(v) ? v : null;
  }

  /** A Supabase row -> the attached record. Mirrors MediaEnrichment's resilient decoder. */
  function fromSupabaseRow(row) {
    if (!row || row.tmdb_id == null || typeof row.media_type !== 'string') return null;
    return {
      tmdbID: String(row.tmdb_id),
      imdbID: typeof row.imdb_id === 'string' ? row.imdb_id : null,
      mediaType: row.media_type,
      keywords: stringList(row.keywords),
      networks: stringList(row.networks),
      productionCompanies: stringList(row.production_companies),
      tmdbGenres: stringList(row.tmdb_genres),
      imdbRating: numOrNull(row.imdb_rating),
      imdbVotes: numOrNull(row.imdb_votes),
      rottenTomatoesScore: numOrNull(row.rt_score),
      metacriticScore: numOrNull(row.metacritic_score),
      awards: typeof row.awards === 'string' ? row.awards : null,
      franchiseID: numOrNull(row.franchise_id),
      franchiseName: typeof row.franchise_name === 'string' ? row.franchise_name : null,
      fetchedAt: typeof row.fetched_at === 'string' ? row.fetched_at : new Date().toISOString(),
    };
  }

  /** The upsert body for one record: TMDB columns only (see TMDB_COLUMNS). */
  function toSupabaseRow(e) {
    return {
      tmdb_id: e.tmdbID,
      media_type: e.mediaType,
      keywords: e.keywords,
      networks: e.networks,
      production_companies: e.productionCompanies,
      tmdb_genres: e.tmdbGenres,
      franchise_id: e.franchiseID,
      franchise_name: e.franchiseName,
      fetched_at: e.fetchedAt,
    };
  }

  /** One work item per TMDB id. Episodes are tv, everything else movie. First item wins. */
  function workItems(items) {
    const byID = new Map();
    for (const item of items || []) {
      if (!item || item.tmdbID == null || item.tmdbID === '') continue;
      const id = String(item.tmdbID);
      if (!/^\d{1,10}$/.test(id)) continue;
      if (!byID.has(id)) byID.set(id, { tmdbID: id, mediaType: item.type === 'episode' ? 'tv' : 'movie' });
    }
    return [...byID.values()];
  }

  function chunk(list, size) {
    const out = [];
    for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
    return out;
  }

  /** Sets `item.enrichment` on every item whose TMDB id has a record. Returns how many. */
  function attach(items, records) {
    let n = 0;
    for (const item of items || []) {
      if (!item || item.tmdbID == null) continue;
      const e = records.get(String(item.tmdbID));
      if (e) { item.enrichment = e; n++; }
    }
    return n;
  }

  async function mapWithConcurrency(list, limit, fn) {
    let next = 0;
    let active = 0;
    let peak = 0;
    async function worker() {
      while (next < list.length) {
        const i = next++;
        active++;
        if (active > peak) peak = active;
        try { await fn(list[i], i); } finally { active--; }
      }
    }
    const workers = [];
    for (let w = 0; w < Math.min(limit, list.length); w++) workers.push(worker());
    await Promise.all(workers);
    return peak;
  }

  // ── Network ────────────────────────────────────────────────────────────────

  function supabaseHeaders(anonKey) {
    return { apikey: anonKey, Authorization: `Bearer ${anonKey}`, 'Content-Type': 'application/json' };
  }

  /** SupabaseService.fetchEnrichments, in chunks of 200. A failed chunk is skipped, not fatal. */
  async function readSupabase(ids, cfg, fetchImpl, onChunk) {
    const out = [];
    const chunks = chunk(ids, cfg.chunkSize || SUPABASE_CHUNK);
    for (let i = 0; i < chunks.length; i++) {
      const url = `${cfg.supabaseURL}/rest/v1/media_enrichments?tmdb_id=in.(${chunks[i].join(',')})&select=*`;
      try {
        const res = await fetchImpl(url, { headers: supabaseHeaders(cfg.anonKey) });
        if (res.status !== 200) {
          console.warn(`[Enrichment] Supabase read failed: HTTP ${res.status}`);
        } else {
          const rows = await res.json();
          for (const row of Array.isArray(rows) ? rows : []) {
            const e = fromSupabaseRow(row);
            if (e) out.push(e);
          }
        }
      } catch (err) {
        console.warn('[Enrichment] Supabase read failed:', err && err.message);
      }
      if (onChunk) onChunk(i + 1, chunks.length);
    }
    return out;
  }

  /** SupabaseService.upsertEnrichments: chunks of 200, Prefer: resolution=merge-duplicates. */
  async function upsertSupabase(records, cfg, fetchImpl) {
    let written = 0;
    const url = `${cfg.supabaseURL}/rest/v1/media_enrichments?columns=${TMDB_COLUMNS.join(',')}`;
    for (const part of chunk(records, cfg.chunkSize || SUPABASE_CHUNK)) {
      try {
        const res = await fetchImpl(url, {
          method: 'POST',
          headers: { ...supabaseHeaders(cfg.anonKey), Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify(part.map(toSupabaseRow)),
        });
        if (res.status >= 300) console.warn(`[Enrichment] Supabase upsert failed: HTTP ${res.status}`);
        else written += part.length;
      } catch (err) {
        console.warn('[Enrichment] Supabase upsert failed:', err && err.message);
      }
    }
    return written;
  }

  /** One TMDB document through the relay. Returns { status, json }; network errors are status 0. */
  async function fetchRelay(work, cfg, fetchImpl) {
    const kind = work.mediaType === 'tv' ? 'tv' : 'movie';
    const url = `${cfg.relayURL}?path=${kind}/${work.tmdbID}`;
    try {
      const res = await fetchImpl(url, { headers: { Accept: 'application/json', [CLIENT_HEADER]: CLIENT_VALUE } });
      if (res.status !== 200) return { status: res.status, json: null };
      return { status: 200, json: await res.json() };
    } catch (err) {
      return { status: 0, json: null };
    }
  }

  // ── Local cache (IndexedDB) ────────────────────────────────────────────────
  // Rows: { tmdbID, savedAt, record | null }. A null record is a TMDB 404, kept for
  // MISS_TTL_MS so a title TMDB does not know is not asked for on every reload.

  function indexedDBCache(dbName = 'nostalgex-enrichment', storeName = 'rows') {
    let dbPromise = null;
    function open() {
      if (dbPromise) return dbPromise;
      dbPromise = new Promise((resolve, reject) => {
        try {
          const req = global.indexedDB.open(dbName, 1);
          req.onupgradeneeded = () => {
            const db = req.result;
            if (!db.objectStoreNames.contains(storeName)) db.createObjectStore(storeName, { keyPath: 'tmdbID' });
          };
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        } catch (err) { reject(err); }
      });
      return dbPromise;
    }
    return {
      async getMany(ids) {
        const out = new Map();
        try {
          const db = await open();
          await new Promise((resolve, reject) => {
            const tx = db.transaction(storeName, 'readonly');
            const store = tx.objectStore(storeName);
            for (const id of ids) {
              const r = store.get(id);
              r.onsuccess = () => { if (r.result) out.set(id, r.result); };
            }
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
          });
        } catch (err) {
          console.warn('[Enrichment] Local cache unavailable:', err && err.message);
        }
        return out;
      },
      async putMany(rows) {
        try {
          const db = await open();
          await new Promise((resolve, reject) => {
            const tx = db.transaction(storeName, 'readwrite');
            const store = tx.objectStore(storeName);
            for (const row of rows) store.put(row);
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
          });
        } catch (err) {
          console.warn('[Enrichment] Local cache write failed:', err && err.message);
        }
      },
    };
  }

  function memoryCache() {
    const m = new Map();
    return {
      rows: m,
      async getMany(ids) { const out = new Map(); for (const id of ids) if (m.has(id)) out.set(id, m.get(id)); return out; },
      async putMany(rows) { for (const r of rows) m.set(r.tmdbID, r); },
    };
  }

  // ── Config ─────────────────────────────────────────────────────────────────

  function metaContent(doc, name) {
    try {
      const el = doc && doc.querySelector(`meta[name="${name}"]`);
      const v = el ? String(el.getAttribute('content') || '').trim() : '';
      // An unset Vite env var leaves the %VITE_...% placeholder in the HTML.
      return v && !v.startsWith('%') ? v : '';
    } catch (err) {
      return '';
    }
  }

  /**
   * Supabase settings come from the build (Vite replaces %VITE_SUPABASE_URL% and
   * %VITE_SUPABASE_ANON_KEY% in plex-tuner.html). The relay is same-origin on the
   * site and its previews; on a local dev server it is nostalgex.app, unless
   * VITE_TMDB_RELAY_URL points somewhere else (a local relay harness).
   */
  function configFromPage(doc, loc) {
    const supabaseURL = metaContent(doc, 'nostalgex-supabase-url').replace(/\/+$/, '');
    const anonKey = metaContent(doc, 'nostalgex-supabase-anon-key');
    const relayOverride = metaContent(doc, 'nostalgex-tmdb-relay');
    const host = (loc && loc.hostname) || '';
    const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '';
    const relayURL = relayOverride || (isLocal ? DEFAULT_RELAY : '/api/tmdb');
    return { supabaseURL, anonKey, relayURL };
  }

  function missingConfiguration(cfg) {
    const missing = [];
    if (!cfg.relayURL) missing.push('tmdb relay');
    if (!cfg.supabaseURL) missing.push('supabase url');
    if (!cfg.anonKey) missing.push('anon key');
    return missing;
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  let loggedSkip = false;

  /**
   * Enrich `items` in place. Never throws. Calls `onCacheReady(records)` once the
   * local and Supabase caches have been read (before any relay fetch) when that
   * found anything, so the host can rebuild channels early, and resolves with the
   * full map when the relay fetches and the upsert are done.
   *
   * opts: { config, fetch, cache, now, concurrency, onProgress(done, total, phase),
   *         onCacheReady(records), isCancelled() }
   */
  async function enrichLibrary(items, opts = {}) {
    const cfg = opts.config || {};
    const stats = { ids: 0, local: 0, supabase: 0, fetched: 0, misses: 0, failed: 0, upserted: 0, peak: 0 };
    const records = new Map();
    const missing = missingConfiguration(cfg);
    if (missing.length) {
      if (!loggedSkip) {
        console.log(`[Enrichment] Off: missing ${missing.join(', ')}`);
        loggedSkip = true;
      }
      return { records, stats, skipped: true };
    }
    const fetchImpl = opts.fetch || global.fetch.bind(global);
    const cache = opts.cache || memoryCache();
    const nowMs = opts.now ? opts.now() : Date.now();
    const cancelled = opts.isCancelled || (() => false);
    const progress = opts.onProgress || (() => {});

    const work = workItems(items);
    stats.ids = work.length;
    if (!work.length) return { records, stats };

    // 1. Local cache.
    const local = await cache.getMany(work.map((w) => w.tmdbID));
    const needRemote = [];
    for (const w of work) {
      const row = local.get(w.tmdbID);
      const ttl = row && row.record ? CACHE_TTL_MS : MISS_TTL_MS;
      if (row && nowMs - row.savedAt < ttl) {
        if (row.record) { records.set(w.tmdbID, row.record); stats.local++; }
        else stats.misses++;
      } else {
        needRemote.push(w);
      }
    }

    // 2. Shared Supabase cache.
    const toStore = [];
    if (needRemote.length) {
      progress(0, needRemote.length, 'cache');
      const rows = await readSupabase(needRemote.map((w) => w.tmdbID), cfg, fetchImpl, (d, t) => {
        progress(d, t, 'cache');
      });
      for (const e of rows) {
        if (records.has(e.tmdbID)) continue;
        records.set(e.tmdbID, e);
        toStore.push({ tmdbID: e.tmdbID, savedAt: nowMs, record: e });
        stats.supabase++;
      }
    }
    if (toStore.length) await cache.putMany(toStore);
    attach(items, records);
    if (records.size && opts.onCacheReady && !cancelled()) opts.onCacheReady(records);

    // 3. Relay for whatever neither cache had.
    const toFetch = needRemote.filter((w) => !records.has(w.tmdbID));
    const fresh = [];
    const freshStore = [];
    if (toFetch.length && !cancelled()) {
      let done = 0;
      progress(0, toFetch.length, 'fetch');
      stats.peak = await mapWithConcurrency(toFetch, opts.concurrency || RELAY_CONCURRENCY, async (w) => {
        if (cancelled()) return;
        const { status, json } = await fetchRelay(w, cfg, fetchImpl);
        if (status === 200) {
          const e = parseTMDBResponse(json, w.tmdbID, null, w.mediaType, new Date(nowMs));
          records.set(w.tmdbID, e);
          fresh.push(e);
          freshStore.push({ tmdbID: w.tmdbID, savedAt: nowMs, record: e });
          stats.fetched++;
        } else if (status === 404) {
          freshStore.push({ tmdbID: w.tmdbID, savedAt: nowMs, record: null });
          stats.misses++;
        } else {
          stats.failed++;
        }
        done++;
        if (done % 10 === 0 || done === toFetch.length) progress(done, toFetch.length, 'fetch');
      });
    }

    // 4. Save what this browser fetched, locally and to the shared cache.
    if (freshStore.length) await cache.putMany(freshStore);
    if (fresh.length) stats.upserted = await upsertSupabase(fresh, cfg, fetchImpl);
    attach(items, records);
    console.log(`[Enrichment] ${stats.ids} TMDB ids: ${stats.local} local, ${stats.supabase} Supabase, `
      + `${stats.fetched} fetched, ${stats.misses} not on TMDB, ${stats.failed} failed, ${stats.upserted} saved`);
    return { records, stats };
  }

  const api = {
    SUPABASE_CHUNK,
    RELAY_CONCURRENCY,
    CACHE_TTL_MS,
    MISS_TTL_MS,
    TMDB_COLUMNS,
    parseTMDBResponse,
    fromSupabaseRow,
    toSupabaseRow,
    workItems,
    chunk,
    attach,
    mapWithConcurrency,
    readSupabase,
    upsertSupabase,
    fetchRelay,
    indexedDBCache,
    memoryCache,
    configFromPage,
    missingConfiguration,
    enrichLibrary,
  };
  global.NostalgexEnrichment = api;
})(typeof globalThis !== 'undefined' ? globalThis : window);
