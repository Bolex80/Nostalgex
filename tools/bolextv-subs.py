#!/usr/bin/env python3
"""BolexTV subtitle service.

Plex on this server answers /library/streams/<id> with 501, so the tuner cannot download a
subtitle at all. This service resolves the stream through Plex's own metadata and returns
WebVTT, which the page attaches to its <video> as a track.

Two kinds of subtitle stream exist and they are handled differently:
  * external - a sidecar file beside the video ("<name>.en.srt"). Plex gives it a /library/
               streams key but no index. Read straight off disk and converted in-process: instant.
  * embedded - inside the container. Plex gives it an index; ffmpeg extracts it, which is slower
               because ffmpeg has to walk the file to reach the track.

  GET /subs?rk=<ratingKey>&stream=<plexStreamId>&token=<plexToken>
  -> 200 text/vtt     the converted cues (cached under CACHE_DIR)
  -> 404              no such text subtitle stream, or the track is image-based (pgs/vobsub)
  -> 403              token rejected by Plex, or a path outside the media root
  -> 502              ffmpeg could not extract an embedded track

Only paths Plex itself reports for the item are ever read, and only under MEDIA_ROOT.
"""
import http.server
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PLEX = os.environ.get('PLEX_URL', 'http://192.168.2.30:32400').rstrip('/')
CACHE_DIR = os.environ.get('CACHE_DIR', '/srv/bolextv-subs/cache')
MEDIA_ROOT = os.environ.get('MEDIA_ROOT', '/mnt/tank-media/')
# Plex reports paths from inside its own container/VM ("/data/media/..."); on this host the same
# files live under /mnt/tank-media/multimedia/.
PLEX_PATH_PREFIX = os.environ.get('PLEX_PATH_PREFIX', '/data/media/')
HOST_PATH_PREFIX = os.environ.get('HOST_PATH_PREFIX', '/mnt/tank-media/multimedia/')
PORT = int(os.environ.get('PORT', '8099'))
# Text subtitle codecs that can become WebVTT. Image-based ones (pgs, vobsub, dvdsub) cannot.
TEXT_CODECS = {'srt', 'subrip', 'ass', 'ssa', 'mov_text', 'webvtt', 'vtt', 'text'}
SIDECAR_EXTS = ('.srt', '.ass', '.ssa', '.vtt')
LANG_ALIASES = {
    'eng': ('en', 'eng', 'english'),
    'spa': ('es', 'spa', 'spanish', 'espanol'),
    'por': ('pt', 'por', 'portuguese'),
    'fra': ('fr', 'fra', 'fre', 'french'),
    'deu': ('de', 'deu', 'ger', 'german'),
}


def plex_metadata(rating_key, token):
    url = f'{PLEX}/library/metadata/{urllib.parse.quote(str(rating_key))}'
    req = urllib.request.Request(url, headers={'X-Plex-Token': token, 'Accept': 'application/xml'})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def host_path(plex_path):
    """Plex's /data/media/... on this host is /mnt/tank-media/multimedia/..."""
    if plex_path.startswith(PLEX_PATH_PREFIX):
        return HOST_PATH_PREFIX + plex_path[len(PLEX_PATH_PREFIX):]
    return plex_path


def find_stream(xml_bytes, stream_id):
    """Locate a subtitle stream by Plex stream id.

    Returns {'kind': 'embedded'|'external', 'video': path, 'index': n|None, 'codec': str,
             'lang': str}, or None when the id is not a usable text subtitle. The index given to
    ffmpeg is the position among the *embedded* subtitle streams, because external ones are not
    in the file at all.
    """
    root = ET.fromstring(xml_bytes)
    video = next((part.get('file') for part in root.iter('Part') if part.get('file')), None)
    if not video:
        return None

    embedded_seen = 0
    for stream in root.iter('Stream'):
        if stream.get('streamType') != '3':
            continue
        has_index = stream.get('index') is not None
        kind = 'embedded' if has_index else ('external' if stream.get('key') else None)
        position = embedded_seen if kind == 'embedded' else None
        if kind == 'embedded':
            embedded_seen += 1
        if str(stream.get('id')) != str(stream_id):
            continue
        codec = (stream.get('codec') or '').lower()
        if not kind or codec not in TEXT_CODECS:
            return None
        return {'kind': kind, 'video': video, 'index': position, 'codec': codec,
                'lang': (stream.get('languageCode') or '').lower()}
    return None


def find_sidecar(video_path, lang):
    """The subtitle file that sits beside the video, preferring one in the wanted language."""
    folder = os.path.dirname(video_path)
    stem = os.path.splitext(os.path.basename(video_path))[0].lower()
    candidates = []
    for base in (folder, os.path.join(folder, 'Subs')):
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if not name.lower().endswith(SIDECAR_EXTS):
                continue
            if not name.lower().startswith(stem[:24]):
                continue
            candidates.append(os.path.join(base, name))
    if not candidates:
        return None
    for alias in LANG_ALIASES.get(lang, (lang,) if lang else ()):
        pattern = re.compile(r'[._\-\[ ]' + re.escape(alias) + r'([._\-\] ]|$)', re.I)
        for path in candidates:
            if pattern.search(os.path.basename(path)):
                return path
    return candidates[0]


def srt_to_vtt(text):
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    text = re.sub(r'^\d+[ \t]*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'(\d{2}:\d{2}:\d{2}),(\d{3})', r'\1.\2', text)
    return 'WEBVTT\n\n' + text.strip() + '\n'


def ass_time(stamp):
    """ASS 'H:MM:SS.cc' (centiseconds) -> WebVTT 'HH:MM:SS.mmm'."""
    h, m, rest = stamp.strip().split(':')
    sec, _, cs = rest.partition('.')
    return f'{int(h):02d}:{int(m):02d}:{int(sec):02d}.{int((cs or "0").ljust(2, "0")[:2]) * 10:03d}'


def ass_to_vtt(text):
    """Best-effort ASS/SSA to WebVTT: keep dialogue, drop the styling."""
    out = ['WEBVTT', '']
    for line in text.splitlines():
        if not line.startswith('Dialogue:'):
            continue
        fields = line.split(',', 9)
        if len(fields) < 10:
            continue
        try:
            start, end = ass_time(fields[1]), ass_time(fields[2])
        except (ValueError, IndexError):
            continue
        body = re.sub(r'\{[^}]*\}', '', fields[9]).replace('\\N', '\n').strip()
        if not body:
            continue
        out.append(f'{start} --> {end}')
        out.append(body)
        out.append('')
    return '\n'.join(out)


def read_sidecar(path, codec):
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read().lstrip('\ufeff')
    if codec in ('ass', 'ssa') or path.lower().endswith(('.ass', '.ssa')):
        return ass_to_vtt(text)
    if text.lstrip().upper().startswith('WEBVTT'):
        return text
    return srt_to_vtt(text)


def extract_embedded(video_path, position, codec, out_path):
    is_ass = codec in ('ass', 'ssa')
    tmp = out_path + '.ass' if is_ass else out_path
    fmt = 'ass' if is_ass else 'webvtt'
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', video_path,
                    '-map', f'0:s:{position}', '-f', fmt, tmp],
                   check=False, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        return None
    with open(tmp, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    if is_ass:
        os.unlink(tmp)
        return ass_to_vtt(text)
    return text if text.lstrip().startswith('WEBVTT') else srt_to_vtt(text)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = 'BolexTVSubs/1.1'

    def _send(self, code, body, ctype='text/plain; charset=utf-8'):
        data = body.encode('utf-8') if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == '/health':
            return self._send(200, 'ok')
        if parsed.path != '/subs':
            return self._send(404, 'not found')
        qs = urllib.parse.parse_qs(parsed.query)
        rk = (qs.get('rk') or [''])[0]
        stream = (qs.get('stream') or [''])[0]
        token = (qs.get('token') or [''])[0]
        if not (rk and stream and token):
            return self._send(400, 'rk, stream and token are required')

        cache_path = os.path.join(CACHE_DIR, f'{rk}-{stream}.vtt')
        if os.path.exists(cache_path):
            with open(cache_path, 'rb') as fh:
                return self._send(200, fh.read(), 'text/vtt; charset=utf-8')

        try:
            xml = plex_metadata(rk, token)
        except Exception as exc:                       # token wrong, Plex down
            return self._send(403, f'plex refused: {exc}')
        found = find_stream(xml, stream)
        if not found:
            return self._send(404, 'no text subtitle by that id')

        video = host_path(found['video'])
        if not os.path.realpath(video).startswith(os.path.realpath(MEDIA_ROOT)):
            return self._send(403, 'path outside the media root')
        if not os.path.exists(video):
            return self._send(404, 'media file missing')

        os.makedirs(CACHE_DIR, exist_ok=True)
        try:
            if found['kind'] == 'external':
                sidecar = find_sidecar(video, found['lang'])
                if not sidecar:
                    return self._send(404, 'sidecar file not found')
                vtt = read_sidecar(sidecar, found['codec'])
            else:
                vtt = extract_embedded(video, found['index'], found['codec'], cache_path)
        except Exception as exc:
            return self._send(502, f'extraction failed: {exc}')
        if not vtt or '-->' not in vtt:
            return self._send(404, 'subtitle could not be extracted')

        with open(cache_path, 'w', encoding='utf-8') as fh:
            fh.write(vtt)
        return self._send(200, vtt, 'text/vtt; charset=utf-8')

    def log_message(self, fmt, *args):
        sys.stderr.write('%s - %s\n' % (self.address_string(), fmt % args))


if __name__ == '__main__':
    os.makedirs(CACHE_DIR, exist_ok=True)
    httpd = http.server.ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print(f'subtitle service on :{PORT}, plex {PLEX}, cache {CACHE_DIR}', flush=True)
    httpd.serve_forever()
