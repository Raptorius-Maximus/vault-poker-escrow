import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

// Serves public/ on :8790, nothing else -- no API, no proxy, no writes.
//
// Bound to all interfaces, not just loopback -- explicitly requested, to
// let a phone on the same wifi reach it, the same trust model the poker
// relay already uses for its own "same wifi" link (see that project's
// HANDOFF.md). This does NOT hand out any more than that: Vault holds no
// key material of its own (that stays in the connecting wallet app, on
// whatever device is doing the connecting) and makes no writes -- static
// files only. Widening this is a real, deliberate change from the
// original "loopback only, single machine" design; it trades a small
// amount of LAN-visibility for phone reachability, nothing more.
const PORT = 8790;
const HOST = '0.0.0.0';
const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), 'public');

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };

/*
 * Caching.
 *
 * This sent no Cache-Control at all, which is not "no caching" -- with no
 * header a browser applies its own heuristic and may hold a copy for as long
 * as it likes. Harmless on a LAN, where the only visitors were the two people
 * who could also be told to hard-refresh. On a public URL it means a player
 * silently running last week's code with no way for anyone to know, and the
 * bug is invisible from here because the developer's own browser fetched the
 * new version.
 *
 * `no-cache` does not mean "do not store" -- it means "ask before reusing".
 * Paired with an ETag the browser sends what it has, and an unchanged file
 * comes back as an empty 304 rather than 650KB. So repeat loads stay cheap
 * and a stale bundle becomes impossible rather than merely unlikely.
 *
 * The tag is mtime and size rather than a content hash: it changes exactly
 * when a rebuild writes the file, costs one stat instead of hashing 650KB on
 * every request, and this server has no build step to hang a real hash off.
 * Weak (`W/`) because it identifies a version, not a byte-exact encoding.
 */
const etagFor = (info) => `W/"${info.mtimeMs.toString(36)}-${info.size.toString(36)}"`;

const server = createServer(async (req, res) => {
  const urlPath = req.url.split('?')[0];
  const path = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = normalize(join(ROOT, path));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  try {
    const info = await stat(filePath);
    if (!info.isFile()) throw new Error('not a file');
    const etag = etagFor(info);

    const headers = {
      'Content-Type': TYPES[extname(filePath)] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache',
      ETag: etag,
    };

    // The browser already has this exact version -- say so and send nothing.
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, headers).end();
      return;
    }

    const body = await readFile(filePath);
    res.writeHead(200, headers);
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Vault serving on http://${HOST}:${PORT}`);
});
