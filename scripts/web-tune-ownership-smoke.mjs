// Offline race tests execute the production resolver/player/subtitle functions.
// All network, media, timers and DOM operations are fixtures. Aborts are deliberately
// ignored by deferred fetches to prove ownership checks, not just cancellation.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const root = new URL('../', import.meta.url);
const tuner = readFileSync(new URL('plex-tuner.html', root), 'utf8');
const urls = readFileSync(new URL('scripts/nostalgex-jellyfin-urls.js', root), 'utf8');
function between(start, end) {
  const a = tuner.indexOf(start), b = tuner.indexOf(end, a);
  assert(a >= 0 && b > a, `production source anchors: ${start}`);
  return tuner.slice(a, b);
}
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
function fixture({ hls = false, backend = 'jellyfin', subtitles = false, reporting = false } = {}) {
  const requests = [], cleanups = [], failures = [], trackers = [], hlsInstances = [], sources = [], attached = [], revoked = [];
  const timers = new Map(), listeners = new Map(), gestureListeners = new Map();
  let seq = 0, timerSeq = 0, playCount = 0, fullscreen = true;
  const video = {
    paused: true, ended: false, currentTime: 0, style: {}, textTracks: [], error: null,
    _src: '', get src() { return this._src; }, set src(value) { this._src = value; sources.push(value); },
    get currentSrc() { return this._src; },
    playResult: null, play() { playCount++; this.paused = false; return this.playResult || Promise.resolve(); },
    pause() { this.paused = true; }, removeAttribute() { this._src = ''; }, load() {}, canPlayType() { return true; },
    addEventListener(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); },
    appendChild(track) { attached.push(track); this.textTracks.push(track.track); },
  };
  class Hls {
    static Events = { MANIFEST_PARSED: 'manifest', ERROR: 'error' };
    static ErrorTypes = { NETWORK_ERROR: 'network', MEDIA_ERROR: 'media' };
    static isSupported() { return hls; }
    constructor() { this.events = {}; this.destroyed = false; this.startLoads = 0; this.recoveries = 0; hlsInstances.push(this); }
    on(name, fn) { this.events[name] = fn; }
    loadSource(url) { this.src = url; sources.push(url); }
    attachMedia() {}
    destroy() { this.destroyed = true; }
    startLoad() { this.startLoads++; }
    recoverMediaError() { this.recoveries++; }
  }
  class FixtureURL extends URL {}
  FixtureURL.createObjectURL = blob => `blob:${blob.parts[0]}`;
  FixtureURL.revokeObjectURL = url => revoked.push(url);
  const element = { classList: { remove() {}, add() {} }, style: {} };
  const context = {
    console: { log() {}, warn() {}, error() {} }, URL: FixtureURL, URLSearchParams, AbortController,
    Blob: class { constructor(parts) { this.parts = parts; } }, crypto: { randomUUID: () => `generated-${++seq}` },
    currentChannel: null, mediaBackend: backend, plexServerUrl: 'https://fixture.invalid', plexToken: 'fixture-token', jellyfinUserId: 'fixture-user',
    jellyfinAuthHeader: () => `fixture-auth-${context.plexToken}`, getClientId: () => 'fixture-device',
    playbackTracker: null, currentPlayingItem: null, hlsInstance: null, syncPlexActivity: reporting,
    videoMuted: false, consecutivePlaybackFailures: 0,
    activeSubtitleTracks: [], activeSubtitleBlobUrls: [], subtitleRequestGeneration: 0, subtitleRequestController: null,
    subtitlesEnabled: subtitles, shouldAutoEnableSubs: () => false, pickSubtitle: subs => subs[0],
    pickAudioStream: () => null, isVideoFullscreen: () => fullscreen,
    buildSubtitleUrl: item => `https://fixture.invalid/subtitles/${item.ratingKey}`,
    clearVideoError() {}, showVideoError: error => failures.push(error), showPlaybackFailure: error => failures.push(error), classifyPlaybackFailure: details => details,
    document: {
      getElementById: id => id === 'plex-video' ? video : element,
      createElement() { return { track: {}, events: {}, removed: false, remove() { this.removed = true; }, addEventListener(name, fn) { this.events[name] = fn; } }; },
      addEventListener(name, fn) { if (!gestureListeners.has(name)) gestureListeners.set(name, new Set()); gestureListeners.get(name).add(fn); },
      removeEventListener(name, fn) { gestureListeners.get(name)?.delete(fn); },
    }, Hls,
    setTimeout(fn, delay) { const id = ++timerSeq; timers.set(id, { fn, delay }); return id; }, clearTimeout(id) { timers.delete(id); },
    makePlaybackTracker(item) { const tracker = { item, stops: 0, ready: 0, resumes: 0, pauses: 0, stop() { this.stops++; }, onReady() { this.ready++; }, onResume() { this.resumes++; }, onPause() { this.pauses++; } }; trackers.push(tracker); return tracker; },
    fetch(url, options = {}) {
      const parsed = new URL(url);
      if (parsed.pathname.endsWith('/ActiveEncodings') || parsed.pathname.endsWith('/universal/stop')) {
        cleanups.push({ url: parsed, options }); return Promise.resolve({ ok: true });
      }
      assert(parsed.pathname.includes('/PlaybackInfo') || parsed.pathname.startsWith('/subtitles/'), `unexpected fixture fetch: ${url}`);
      const wait = deferred(); requests.push({ url: parsed, options, ...wait }); return wait.promise;
    },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(urls
    + between('  let activeTranscodeSession = null;', "  let appState = 'connect'")
    + between('  function switchChannel(', '  async function getJellyfinTranscodeUrl(')
    + between('  async function getJellyfinTranscodeUrl(', '  // ── Playback tracking')
    + between('  let pendingPlayRetry = null;', '  function showNowPlaying(')
    + between('  function clearSubtitleTracks(', '  function setAudioLanguage(')
    + `\nfunction inspectOwnership() { return { activePlaybackRequest, activeTranscodeSession, pendingPlayRetry }; }`, context);
  let ended = 0;
  // Observe advancement without synthesizing another schedule; failure/timer handlers remain production.
  context.onItemEnded = () => { ended++; };
  function tune(item, channelId = 1) { context.currentChannel = channelId; return context.playCurrentItem(item, { id: channelId }); }
  function info(index, id, { body = null, ok = true } = {}) {
    requests[index].resolve({ ok, json: () => body ? body.promise : Promise.resolve({ PlaySessionId: `session-${id}`, MediaSources: [{ Id: id, TranscodingUrl: `/Videos/${id}/master.m3u8?PlaySessionId=session-${id}` }] }) });
  }
  return { context, video, requests, cleanups, failures, trackers, timers, listeners, hlsInstances, sources, attached, revoked, tune, info,
    setFullscreen(value) { fullscreen = value; }, get playCount() { return playCount; }, get ended() { return ended; } };
}
const transcode = id => ({ ratingKey: id, partKey: id, _forceTranscode: true, title: id });
const direct = (id, offset = 0) => ({ ratingKey: id, partKey: id, container: 'mp4', videoCodec: 'h264', audioCodec: 'aac', title: id, offsetSeconds: offset });
let count = 0;
async function test(name, run) { await run(); count++; console.log(`  ok ${name}`); }

await test('A -> B resolving B -> A cannot replace B, including loader/tracker/session', async () => {
  const f = fixture({ reporting: true });
  const a = f.tune(transcode('A'), 1), b = f.tune(transcode('B'), 2);
  assert.equal(f.requests[0].options.signal.aborted, true);
  f.info(1, 'B'); await b;
  f.info(0, 'A'); await a;
  assert.equal(f.context.currentPlayingItem.ratingKey, 'B');
  assert.match(f.video.src, /\/B\/master/);
  assert.deepEqual(f.trackers.map(t => t.item.ratingKey), ['B']);
  assert.equal(f.context.inspectOwnership().activeTranscodeSession.id, 'session-B');
  assert.deepEqual(f.cleanups.map(c => c.url.searchParams.get('playSessionId')), ['session-A']);
  assert.equal(f.cleanups[0].options.method, 'DELETE');
  f.context.stopVideo();
  assert.deepEqual(f.cleanups.map(c => c.url.searchParams.get('playSessionId')), ['session-A', 'session-B']);
});
await test('A -> B -> A rejects first A even when channel and item object match again', async () => {
  const f = fixture(); const sameA = transcode('A');
  const a1 = f.tune(sameA, 1), b = f.tune(transcode('B'), 2), a2 = f.tune(sameA, 1);
  f.info(2, 'A-new'); await a2;
  f.info(0, 'A-old'); await a1;
  f.info(1, 'B'); await b;
  assert.match(f.video.src, /A-new/);
  assert.equal(f.context.inspectOwnership().activeTranscodeSession.id, 'session-A-new');
  assert.deepEqual(f.cleanups.map(c => c.url.searchParams.get('playSessionId')), ['session-A-old', 'session-B']);
});
await test('response body delayed beyond disconnect is discarded and its exact old session released', async () => {
  const f = fixture(); const body = deferred(); const pending = f.tune(transcode('A'));
  f.info(0, 'A', { body }); await flush();
  f.context.stopVideo();
  f.context.mediaBackend = 'plex'; f.context.plexServerUrl = 'https://new.invalid'; f.context.plexToken = 'new-fixture-token';
  body.resolve({ PlaySessionId: 'old-session', MediaSources: [{ Id: 'A', TranscodingUrl: '/A.m3u8?PlaySessionId=old-session' }] });
  await pending;
  assert.equal(f.context.currentPlayingItem, null); assert.equal(f.video.src, '');
  assert.equal(f.cleanups[0].url.host, 'fixture.invalid');
  assert.equal(f.cleanups[0].url.searchParams.get('playSessionId'), 'old-session');
  assert.equal(f.cleanups[0].options.headers.Authorization, 'fixture-auth-fixture-token');
});
await test('aborted resolver rejection does not start a fallback or display a failure', async () => {
  const f = fixture(); const a = f.tune(transcode('A')); await f.tune(direct('B'), 2);
  const error = new Error('aborted'); error.name = 'AbortError'; f.requests[0].reject(error); await a;
  assert.equal(f.context.currentPlayingItem.ratingKey, 'B'); assert.equal(f.sources.length, 1);
  assert.equal(f.failures.length, 0); assert.equal(f.cleanups.length, 0);
});
await test('current resolver failure still uses its owned fallback and cleans it up', async () => {
  const f = fixture(); const a = f.tune(transcode('A')); f.requests[0].reject(new Error('fixture outage')); await a;
  assert.match(f.video.src, /master.m3u8/);
  const session = f.context.inspectOwnership().activeTranscodeSession;
  assert(session.id); f.context.stopVideo();
  assert.equal(f.cleanups[0].url.searchParams.get('playSessionId'), session.id);
});
await test('Plex cleanup is scoped to the outgoing item server and does not stop replacement session', async () => {
  const f = fixture({ backend: 'plex' });
  await f.tune({ ...transcode('A'), serverUrl: 'https://a.invalid', serverToken: 'a-fixture' });
  const old = f.context.inspectOwnership().activeTranscodeSession;
  await f.tune({ ...transcode('B'), serverUrl: 'https://b.invalid', serverToken: 'b-fixture' }, 2);
  const current = f.context.inspectOwnership().activeTranscodeSession;
  assert.notEqual(old.id, current.id); assert.equal(f.cleanups.length, 1);
  assert.equal(f.cleanups[0].url.host, 'a.invalid'); assert.equal(f.cleanups[0].url.searchParams.get('session'), old.id);
  assert.equal(current.stopped, undefined);
});
await test('queued native metadata and media callbacks cannot seek, play, report or skip the new item', async () => {
  const f = fixture({ reporting: true }); await f.tune(direct('A', 120));
  const oldMetadata = [...f.listeners.get('loadedmetadata')][0];
  const oldEvents = [f.video.onplaying, f.video.onpause, f.video.onended, f.video.onerror, f.video.onwaiting];
  f.video.onplaying(); const oldStall = [...f.timers.values()].find(t => t.delay === 8000).fn;
  await f.tune(direct('B', 30), 2);
  oldMetadata(); oldEvents.forEach(fn => fn()); oldStall();
  assert.equal(f.video.currentTime, 0); assert.equal(f.playCount, 0); assert.equal(f.ended, 0);
  assert.equal(f.trackers[1].ready, 0); assert.equal(f.trackers[1].pauses, 0);
  assert.equal(f.listeners.get('loadedmetadata').size, 1);
  [...f.listeners.get('loadedmetadata')][0](); assert.equal(f.video.currentTime, 30); assert.equal(f.playCount, 1);
});
await test('queued HLS errors and manifest events from destroyed loader cannot affect new loader', async () => {
  const f = fixture({ backend: 'plex', hls: true }); await f.tune(transcode('A'));
  const old = f.hlsInstances[0]; await f.tune(transcode('B'), 2);
  old.events.manifest();
  old.events.error(null, { fatal: true, details: 'manifestLoadError', type: 'network', response: { code: 404 } });
  old.events.error(null, { fatal: true, details: 'fragment', type: 'network' });
  assert.equal(old.destroyed, true); assert.equal(old.startLoads, 0); assert.equal(f.hlsInstances[1].destroyed, false);
  assert.equal(f.context.consecutivePlaybackFailures, 0); assert.equal(f.playCount, 0); assert.equal(f.failures.length, 0);
});
await test('old failure skip remains inert after returning to same channel and exact item', async () => {
  const f = fixture({ backend: 'plex' }); const item = transcode('A'); await f.tune(item);
  f.video.onerror(); const skip = [...f.timers.values()].find(t => t.delay === 5000).fn;
  await f.tune(transcode('B'), 2); await f.tune(item, 1); skip();
  assert.equal(f.ended, 0); assert.equal(f.context.currentPlayingItem, item);
});
await test('late autoplay rejection cannot arm a gesture retry for the next program', async () => {
  const f = fixture(); await f.tune(direct('A')); const rejectedPlay = deferred(); f.video.playResult = rejectedPlay.promise;
  [...f.listeners.get('loadedmetadata')][0](); await f.tune(direct('B'), 2);
  rejectedPlay.reject(new Error('fixture autoplay blocked')); await flush();
  assert.equal(f.context.inspectOwnership().pendingPlayRetry, null);
});
await test('subtitle A response ignored after B, including body await and stale track callbacks', async () => {
  const f = fixture({ subtitles: true });
  const a = { ...direct('A'), subtitles: [{ lang: 'en', index: 1 }] }, b = { ...direct('B'), subtitles: [{ lang: 'en', index: 1 }] };
  await f.tune(a); const body = deferred(); f.requests[0].resolve({ ok: true, text: () => body.promise }); await flush();
  await f.tune(b, 2); assert.equal(f.requests[0].options.signal.aborted, true);
  f.requests[1].resolve({ ok: true, text: async () => 'B-vtt' }); await flush();
  body.resolve('A-vtt'); await flush();
  assert.deepEqual(f.attached.map(t => t.src), ['blob:B-vtt']);
  const track = f.attached[0], delayedShow = [...f.timers.values()].find(t => t.delay === 300).fn;
  f.setFullscreen(false); f.context.clearSubtitleTracks(); track.events.load(); delayedShow();
  assert.notEqual(track.track.mode, 'showing'); assert.equal(track.removed, true);
  assert.deepEqual(f.revoked, ['blob:B-vtt']);
});
await test('same-item subtitle reload keeps only the latest preference request', async () => {
  const f = fixture({ subtitles: true }); const a = { ...direct('A'), subtitles: [{ lang: 'en', index: 1 }] };
  await f.tune(a); const newSub = f.context.loadSubtitleForCurrentItem(a);
  f.requests[1].resolve({ ok: true, text: async () => 'new-language' }); await newSub;
  f.requests[0].resolve({ ok: true, text: async () => 'old-language' }); await flush();
  assert.deepEqual(f.attached.map(t => t.src), ['blob:new-language']);
});
await test('connection token replacement without completed tune also invalidates late resolver', async () => {
  const f = fixture(); const a = f.tune(transcode('A')); f.context.plexToken = 'new-token'; f.info(0, 'A'); await a;
  assert.equal(f.context.currentPlayingItem, null); assert.equal(f.sources.length, 0);
  assert.equal(f.cleanups[0].url.searchParams.get('ApiKey'), 'fixture-token');
});
await test('late result sharing the active server session id cannot stop the current owner', async () => {
  const f = fixture(); const a = f.tune(transcode('A')), b = f.tune(transcode('B'), 2);
  f.info(1, 'shared'); await b; f.info(0, 'shared'); await a;
  assert.equal(f.cleanups.length, 0); assert.match(f.video.src, /shared/);
  f.context.stopVideo(); assert.equal(f.cleanups.length, 1);
});
await test('stale PlaybackInfo with no URL still releases its returned server session', async () => {
  const f = fixture(); const a = f.tune(transcode('A')); await f.tune(direct('B'), 2);
  f.requests[0].resolve({ ok: true, json: async () => ({ PlaySessionId: 'unused-session', MediaSources: [] }) }); await a;
  assert.equal(f.context.currentPlayingItem.ratingKey, 'B');
  assert.equal(f.cleanups[0].url.searchParams.get('playSessionId'), 'unused-session');
});
await test('selecting an empty channel retires outgoing playback and pending resolution', async () => {
  const f = fixture(); const a = f.tune(transcode('A'));
  f.context.CHANNELS = [{ id: 2, enabled: true, schedule: [] }];
  f.context.switchChannel(2); assert.equal(f.requests[0].options.signal.aborted, true);
  f.info(0, 'A'); await a;
  assert.equal(f.context.currentPlayingItem, null); assert.equal(f.video.src, '');
});
await test('Jellyfin user replacement invalidates a pending request even with the same token', async () => {
  const f = fixture(); const a = f.tune(transcode('A')); f.context.jellyfinUserId = 'next-user';
  f.info(0, 'A'); await a;
  assert.equal(f.context.currentPlayingItem, null); assert.equal(f.cleanups.length, 1);
});
console.log(`web tune ownership: ${count} production-function scenarios passed (offline)`);
