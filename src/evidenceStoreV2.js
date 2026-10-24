// Pure, storage-parameterised localStorage wrapper for the evidence bundle
// this phase relays from the poker tab (task 2). Storage is passed in rather
// than reached for globally so this module is node -e-probable against a fake
// Storage object with no DOM.
//
// The "both origins" half of spec §6's recovery story: P1's own doc (task 8
// step 6) makes the receipt available to forward over the existing cross-origin
// bridge; THIS is where Buyin writes it to its own origin's localStorage on
// receipt, so a returning player is covered wherever they land.
//
// Keys are `vault2:evidence:${session}` -- the `vault2:` prefix keeps V2's
// storage textually distinct from anything V1 wrote, and lets listSessions
// enumerate only V2 envelopes.

const PREFIX = 'vault2:evidence:';

export function keyFor(session) {
  return `${PREFIX}${session}`;
}

// save(store, session, bundle): idempotent write. Repeats cost nothing --
// exactly vault:progress's own reasoning -- so the message handler calls this
// unconditionally on every vault:evidence-v2 that arrives.
export function save(store, session, bundle) {
  store.setItem(keyFor(session), JSON.stringify(bundle));
}

// load(store, session): the parsed envelope, or null if none / unparseable.
export function load(store, session) {
  const raw = store.getItem(keyFor(session));
  if (raw == null) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// listSessions(store): every parsed vault2:evidence:* envelope, as
// { session, bundle } pairs. Enumerates via Storage.key(i)/store.length --
// the plain, synchronous integer-index enumeration every localStorage
// implementation exposes (MDN "Storage: key() method" / "Storage: length
// property"), no polyfill needed. Used by task 7's recovery page.
export function listSessions(store) {
  const out = [];
  const n = store.length;
  for (let i = 0; i < n; i++) {
    const k = store.key(i);
    if (typeof k !== 'string' || !k.startsWith(PREFIX)) continue;
    const raw = store.getItem(k);
    if (raw == null) continue;
    try {
      out.push({ session: k.slice(PREFIX.length), bundle: JSON.parse(raw) });
    } catch {
      /* a corrupt envelope is skipped rather than crashing the whole list */
    }
  }
  return out;
}
