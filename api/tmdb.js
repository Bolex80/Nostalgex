/**
 * TMDB proxy for the Apple TV app.
 *
 * The App Store build ships without a TMDB key. It asks this function for one of
 * four read-only TMDB routes; the function adds the key from the Vercel env
 * (`TMDB_API_KEY`), forwards the request, and hands back TMDB's JSON and status.
 * Vercel's edge cache keeps a 200 for a day and serves it stale for a week while
 * refetching, so a title that many libraries share costs TMDB one request, not one
 * per Apple TV.
 *
 * Allowlist. Nothing else is forwarded:
 *   movie/{id}         with append_to_response=keywords
 *   tv/{id}            with append_to_response=keywords
 *   collection/{id}
 *   search/collection  with query (and an optional page)
 *
 * `X-Nostalgex-Client: tvos` is a cheap filter against stray browsers and crawlers,
 * not security. Nothing about a request is logged, ids included.
 */

const TMDB = 'https://api.themoviedb.org/3';
const CLIENT_HEADER = 'x-nostalgex-client';
const CLIENT_VALUE = 'tvos';
const CACHE_OK = 'public, s-maxage=86400, stale-while-revalidate=604800';
const NO_STORE = 'no-store';

const ID_ROUTE = /^(movie|tv|collection)\/(\d{1,10})$/;
const SEARCH_ROUTE = 'search/collection';
const QUERY_MAX = 200;
const PAGE_RE = /^[1-9]\d{0,3}$/;
const PAGE_MAX = 1000;

/**
 * The TMDB path and query string for a request, or null when the request is not on
 * the allowlist. The api_key is added by the handler, never here. Exported for the
 * smoke test.
 */
export function upstreamRequest(query) {
  const path = typeof query?.path === 'string' ? query.path : '';
  const params = new URLSearchParams();

  const idMatch = ID_ROUTE.exec(path);
  if (idMatch) {
    const [, kind, id] = idMatch;
    if (kind !== 'collection') params.set('append_to_response', 'keywords');
    return { path: `/${kind}/${id}`, params };
  }

  if (path === SEARCH_ROUTE) {
    const q = typeof query.query === 'string' ? query.query.trim() : '';
    if (!q || q.length > QUERY_MAX) return null;
    params.set('query', q);
    if (query.page !== undefined) {
      const page = typeof query.page === 'string' ? query.page : '';
      if (!PAGE_RE.test(page) || Number(page) > PAGE_MAX) return null;
      params.set('page', page);
    }
    return { path: `/${SEARCH_ROUTE}`, params };
  }

  return null;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (req.headers?.[CLIENT_HEADER] !== CLIENT_VALUE) {
    return res.status(403).json({ error: 'Client header required' });
  }

  const upstream = upstreamRequest(req.query || {});
  if (!upstream) {
    return res.status(400).json({ error: 'Unsupported path' });
  }

  const apiKey = process.env.TMDB_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'Server misconfigured' });
  }

  upstream.params.set('api_key', apiKey);

  let status;
  let data;
  try {
    const upstreamRes = await fetch(`${TMDB}${upstream.path}?${upstream.params}`, {
      headers: { Accept: 'application/json' },
    });
    status = upstreamRes.status;
    data = await upstreamRes.json();
  } catch {
    // Network failure, or TMDB answered with something that is not JSON (an HTML
    // error page during an outage). Either way the app should retry later, so
    // nothing is cached.
    res.setHeader('Cache-Control', NO_STORE);
    return res.status(502).json({ error: 'TMDB unavailable' });
  }

  // Only a 200 is worth keeping at the edge. A 404 for an id that TMDB later
  // creates, or a 429 while rate limited, should not be pinned for a day.
  res.setHeader('Cache-Control', status === 200 ? CACHE_OK : NO_STORE);
  return res.status(status).json(data);
}
