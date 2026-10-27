// Plex responses with a byte that is not UTF-8, repaired the way the Apple TV does.
//
// PARITY CONTRACT with tvOS
//   Nostalgex/Nostalgex/Services/PlexResponseDecoding.swift   (PlexUTF8Repair)
//   scripts/utf8-repair-golden.json                           (the shared vectors)
// Swift checks the vectors in PlexUTF8RepairGoldenTests, `npm run test:utf8-repair` checks them here.
// Change the rule in one engine without the other and one of those fails. The Roku port reads
// the same file.
//
// Plex copies a file or folder name into its JSON byte for byte. An unmatched item named in
// Latin-1 puts a lone 0xE9 into `title` or `summary`, and the response is no longer UTF-8.
// `Response.json()` decodes with replacement characters, so the library loads but "Café Society"
// reads "Caf� Society". The repair reads each byte that is not part of a well-formed UTF-8
// sequence (Unicode table 3-7) as Windows-1252, and decodes every well-formed sequence as it is.
// A valid response comes back untouched. A stray byte is always 0x80 or above, so the repair
// cannot add a quote, a backslash or a control character to the JSON around it.
//
// USAGE (browser: plain <script src="scripts/nostalgex-utf8-repair.js">, node: vm or require):
//   const R = globalThis.NostalgexUTF8Repair;
//   const data = await R.json(response);            // instead of response.json()
//   const { text, repairedBytes } = R.decode(bytes); // a Uint8Array
(function (global) {
  'use strict';

  // Windows-1252, 0x80 to 0x9F. 0xA0 to 0xFF match Latin-1. The five bytes Windows-1252 leaves
  // undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D) keep their Latin-1 code point, as browsers do.
  const HIGH = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ];

  function windows1252(byte) {
    return String.fromCharCode(byte >= 0x80 && byte <= 0x9F ? HIGH[byte - 0x80] : byte);
  }

  /** Length of the well-formed UTF-8 sequence that starts at `i` (Unicode table 3-7), or 0. */
  function sequenceLength(b, i) {
    const b0 = b[i];
    if (b0 < 0x80) return 1;
    const n = b.length;
    const cont = (k, low = 0x80, high = 0xBF) => i + k < n && b[i + k] >= low && b[i + k] <= high;
    if (b0 >= 0xC2 && b0 <= 0xDF) return cont(1) ? 2 : 0;
    if (b0 === 0xE0) return cont(1, 0xA0) && cont(2) ? 3 : 0;
    if ((b0 >= 0xE1 && b0 <= 0xEC) || b0 === 0xEE || b0 === 0xEF) return cont(1) && cont(2) ? 3 : 0;
    if (b0 === 0xED) return cont(1, 0x80, 0x9F) && cont(2) ? 3 : 0;
    if (b0 === 0xF0) return cont(1, 0x90) && cont(2) && cont(3) ? 4 : 0;
    if (b0 >= 0xF1 && b0 <= 0xF3) return cont(1) && cont(2) && cont(3) ? 4 : 0;
    if (b0 === 0xF4) return cont(1, 0x80, 0x8F) && cont(2) && cont(3) ? 4 : 0;
    return 0;
  }

  /**
   * `bytes` (a Uint8Array) as text. `repairedBytes` is 0 for a valid response, which is decoded
   * untouched (one leading byte order mark is dropped, as Response.json() does; a U+FEFF anywhere else is kept, even right after a repaired byte).
   */
  function decode(bytes) {
    try {
      return { text: new TextDecoder('utf-8', { fatal: true }).decode(bytes), repairedBytes: 0 };
    } catch (_) { /* not valid UTF-8: repair below */ }
    // ignoreBOM: every segment is decoded on its own, and a decoder that strips a BOM would drop
    // a U+FEFF that follows a repaired byte. Swift keeps it, so only the one at the very start of
    // the whole text goes (below), as Response.json() drops it.
    const lenient = new TextDecoder('utf-8', { ignoreBOM: true });
    let out = '';
    let repairedBytes = 0;
    let i = 0;
    let runStart = 0;
    while (i < bytes.length) {
      const length = sequenceLength(bytes, i);
      if (length > 0) { i += length; continue; }
      out += lenient.decode(bytes.subarray(runStart, i), { stream: false });
      out += windows1252(bytes[i]);
      repairedBytes += 1;
      i += 1;
      runStart = i;
    }
    out += lenient.decode(bytes.subarray(runStart), { stream: false });
    if (out.charCodeAt(0) === 0xFEFF) out = out.slice(1);
    return { text: out, repairedBytes };
  }

  /**
   * `response.json()` that survives a byte that is not UTF-8. A response object with no
   * arrayBuffer (a test double) falls back to its own json().
   */
  async function json(response, context) {
    if (!response || typeof response.arrayBuffer !== 'function') return response.json();
    const { text, repairedBytes } = decode(new Uint8Array(await response.arrayBuffer()));
    if (repairedBytes > 0) {
      console.warn(`[Nostalgex] PLEX UTF-8${context ? ' ' + context : ''}: repaired ${repairedBytes} byte(s) that were not UTF-8, read as Windows-1252`);
    }
    return JSON.parse(text);
  }

  global.NostalgexUTF8Repair = { decode, json, sequenceLength, windows1252 };
})(typeof globalThis !== 'undefined' ? globalThis : window);
