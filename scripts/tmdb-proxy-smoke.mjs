#!/usr/bin/env node
/**
 * Smoke test for api/tmdb.js. Stubs fetch, so nothing reaches TMDB.
 * Run: `npm run test:tmdb`.
 */
import handler, { upstreamRequest, corsHeaders } from "../api/tmdb.js";

let pass = 0;
const failures = [];
function check(name, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) pass++;
  else failures.push(`${name}: expected ${e}, got ${a}`);
}

/** Shape of an allowlist answer for comparison: path plus the query as a plain string. */
function shape(result) {
  return result ? { path: result.path, query: result.params.toString() } : null;
}

/** Canned TMDB response; records every upstream request. */
function stubTMDB(response) {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), headers: init.headers });
    if (response instanceof Error) throw response;
    return {
      status: response.status,
      json: async () => {
        if (response.nonJSON) throw new SyntaxError("Unexpected token <");
        return response.body ?? {};
      },
    };
  };
  return calls;
}

async function call({ method = "GET", query = {}, headers = { "x-nostalgex-client": "tvos" } } = {}) {
  let status = 0;
  let json = null;
  const sent = {};
  const res = {
    setHeader(key, value) { sent[key] = value; },
    status(code) { status = code; return this; },
    json(data) { json = data; return this; },
    end() { return this; },
  };
  await handler({ method, query, headers }, res);
  return { status, json, headers: sent };
}

process.env.TMDB_API_KEY = "test_key";

// ---- Allowlist ----
check("movie adds keywords", shape(upstreamRequest({ path: "movie/603" })), {
  path: "/movie/603", query: "append_to_response=keywords",
});
check("tv adds keywords", shape(upstreamRequest({ path: "tv/1399" })), {
  path: "/tv/1399", query: "append_to_response=keywords",
});
check("collection has no keywords", shape(upstreamRequest({ path: "collection/404609" })), {
  path: "/collection/404609", query: "",
});
check("search collection forwards query", shape(upstreamRequest({ path: "search/collection", query: " John Wick " })), {
  path: "/search/collection", query: "query=John+Wick",
});
check("search collection forwards page", shape(upstreamRequest({ path: "search/collection", query: "Alien", page: "2" })), {
  path: "/search/collection", query: "query=Alien&page=2",
});
check("search without query rejected", upstreamRequest({ path: "search/collection" }), null);
check("search with blank query rejected", upstreamRequest({ path: "search/collection", query: "   " }), null);
check("search with long query rejected", upstreamRequest({ path: "search/collection", query: "x".repeat(201) }), null);
check("search with bad page rejected", upstreamRequest({ path: "search/collection", query: "Alien", page: "0" }), null);
check("search with huge page rejected", upstreamRequest({ path: "search/collection", query: "Alien", page: "1001" }), null);
check("person rejected", upstreamRequest({ path: "person/1" }), null);
check("non-numeric id rejected", upstreamRequest({ path: "movie/abc" }), null);
check("sub-resource rejected", upstreamRequest({ path: "movie/603/credits" }), null);
check("traversal rejected", upstreamRequest({ path: "../movie/603" }), null);
check("leading slash rejected", upstreamRequest({ path: "/movie/603" }), null);
check("query injection rejected", upstreamRequest({ path: "movie/603?api_key=x" }), null);
check("oversized id rejected", upstreamRequest({ path: "movie/12345678901" }), null);
check("repeated path rejected", upstreamRequest({ path: ["movie/603", "tv/1"] }), null);
check("empty rejected", upstreamRequest({}), null);
check("undefined rejected", upstreamRequest(undefined), null);

// ---- Handler ----
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ method: "POST", query: { path: "movie/603" } });
  check("POST 405", r.status, 405);
  check("POST no upstream", calls.length, 0);
}
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "movie/603" }, headers: {} });
  check("missing client header 403", r.status, 403);
  check("missing client header no upstream", calls.length, 0);
}
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "movie/603" }, headers: { "x-nostalgex-client": "android" } });
  check("wrong client header 403", r.status, 403);
  check("wrong client header no upstream", calls.length, 0);
}
{
  const calls = stubTMDB({ status: 200, body: { id: 603 } });
  const r = await call({ query: { path: "movie/603" }, headers: { "x-nostalgex-client": "web" } });
  check("web client header 200", r.status, 200);
  check("web client one upstream call", calls.length, 1);
  check("web client cached at the edge", r.headers["Cache-Control"], "public, s-maxage=86400, stale-while-revalidate=604800");
}

// ---- CORS ----
for (const origin of ["https://www.nostalgex.app", "https://nostalgex.app", "http://localhost:5173"]) {
  check(`cors echoes ${origin}`, corsHeaders(origin)["Access-Control-Allow-Origin"], origin);
}
for (const origin of ["https://evil.example", "http://localhost:3000", "https://nostalgex.app.evil.example", "null", "", undefined]) {
  check(`cors refuses ${origin}`, corsHeaders(origin)["Access-Control-Allow-Origin"], undefined);
  check(`cors refuses ${origin} headers`, corsHeaders(origin)["Access-Control-Allow-Headers"], undefined);
}
check("cors vary always", corsHeaders(undefined).Vary, "Origin, X-Nostalgex-Client");
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ method: "OPTIONS", query: { path: "movie/603" }, headers: { origin: "http://localhost:5173" } });
  check("preflight 204", r.status, 204);
  check("preflight no upstream", calls.length, 0);
  check("preflight allow origin", r.headers["Access-Control-Allow-Origin"], "http://localhost:5173");
  check("preflight allow headers", r.headers["Access-Control-Allow-Headers"], "X-Nostalgex-Client");
  check("preflight allow methods", r.headers["Access-Control-Allow-Methods"], "GET, OPTIONS");
  check("preflight vary", r.headers.Vary, "Origin, X-Nostalgex-Client");
}
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ method: "OPTIONS", query: { path: "movie/603" }, headers: { origin: "https://evil.example" } });
  check("foreign preflight 204", r.status, 204);
  check("foreign preflight no allow origin", r.headers["Access-Control-Allow-Origin"], undefined);
  check("foreign preflight no upstream", calls.length, 0);
}
{
  stubTMDB({ status: 200, body: { id: 603 } });
  const r = await call({
    query: { path: "movie/603" },
    headers: { "x-nostalgex-client": "web", origin: "https://www.nostalgex.app" },
  });
  check("cors GET allow origin", r.headers["Access-Control-Allow-Origin"], "https://www.nostalgex.app");
  check("cors GET vary", r.headers.Vary, "Origin, X-Nostalgex-Client");
}
{
  stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "movie/603" }, headers: { origin: "http://localhost:5173" } });
  check("cors 403 still readable", r.headers["Access-Control-Allow-Origin"], "http://localhost:5173");
  check("cors 403 status", r.status, 403);
}
{
  stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "movie/603" }, headers: { "x-nostalgex-client": "tvos" } });
  check("tvos no origin no allow origin", r.headers["Access-Control-Allow-Origin"], undefined);
  check("tvos no origin still varies", r.headers.Vary, "Origin, X-Nostalgex-Client");
}
{
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "person/1" } });
  check("person 400", r.status, 400);
  check("person no upstream", calls.length, 0);
  check("person not cached", r.headers["Cache-Control"], undefined);
}
{
  delete process.env.TMDB_API_KEY;
  const calls = stubTMDB({ status: 200, body: {} });
  const r = await call({ query: { path: "movie/603" } });
  check("missing env 500", r.status, 500);
  check("missing env no upstream", calls.length, 0);
  process.env.TMDB_API_KEY = "test_key";
}
{
  const body = {
    id: 603,
    belongs_to_collection: { id: 2344, name: "The Matrix Collection" },
    keywords: { keywords: [{ id: 1, name: "artificial intelligence" }] },
  };
  const calls = stubTMDB({ status: 200, body });
  const r = await call({ query: { path: "movie/603" } });
  check("movie ok", r.status, 200);
  check("movie one upstream call", calls.length, 1);
  check("movie upstream url", calls[0].url, "https://api.themoviedb.org/3/movie/603?append_to_response=keywords&api_key=test_key");
  check("movie body passes through", r.json, body);
  check("movie cached at the edge", r.headers["Cache-Control"], "public, s-maxage=86400, stale-while-revalidate=604800");
}
{
  const calls = stubTMDB({ status: 200, body: { id: 404609, parts: [] } });
  const r = await call({ query: { path: "collection/404609" } });
  check("collection ok", r.status, 200);
  check("collection upstream url", calls[0].url, "https://api.themoviedb.org/3/collection/404609?api_key=test_key");
}
{
  const calls = stubTMDB({ status: 200, body: { results: [] } });
  await call({ query: { path: "search/collection", query: "John Wick", page: "2" } });
  check("search upstream url", calls[0].url, "https://api.themoviedb.org/3/search/collection?query=John+Wick&page=2&api_key=test_key");
}
{
  const calls = stubTMDB({ status: 200, body: {} });
  await call({ query: { path: "movie/603", api_key: "attacker", language: "fr" } });
  check("extra query params dropped", calls[0].url, "https://api.themoviedb.org/3/movie/603?append_to_response=keywords&api_key=test_key");
}
{
  stubTMDB({ status: 404, body: { status_code: 34, status_message: "The resource you requested could not be found." } });
  const r = await call({ query: { path: "movie/999999999" } });
  check("upstream 404 passes through", r.status, 404);
  check("upstream 404 not cached", r.headers["Cache-Control"], "no-store");
}
{
  stubTMDB({ status: 429, body: { status_code: 25 } });
  const r = await call({ query: { path: "tv/1399" } });
  check("upstream 429 passes through", r.status, 429);
  check("upstream 429 not cached", r.headers["Cache-Control"], "no-store");
}
{
  stubTMDB({ status: 502, nonJSON: true });
  const r = await call({ query: { path: "movie/603" } });
  check("upstream non-JSON 502", r.status, 502);
  check("upstream non-JSON not cached", r.headers["Cache-Control"], "no-store");
}
{
  stubTMDB(new Error("network down"));
  const r = await call({ query: { path: "movie/603" } });
  check("network error 502", r.status, 502);
  check("network error not cached", r.headers["Cache-Control"], "no-store");
}

if (failures.length) {
  console.error(`tmdb proxy smoke: ${failures.length} failed, ${pass} passed`);
  for (const f of failures) console.error("  - " + f);
  process.exit(1);
}
console.log(`tmdb proxy smoke: ${pass} passed`);
