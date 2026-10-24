# Phase 1 — protocol substrate (poker repo)

## Goal

Give the poker client every artefact a later dispute needs to exist and be
byte-correct, with **no chain interaction anywhere in this phase**: a
monotone, wire-correct hand number with an explicit button; a signed,
hash-chained action per bet with the exact post-clamp amount the engine
applied; a both-signed hand-start marker built from all 52 shares and both
`hello` card keys; both-signed receipts exchanged at every hand boundary
including the mandatory `(0,0)` and `final`; write-ahead persistence for the
signed action tip with a refuse-to-resume guard; and keccak-challenge DLEQ
proofs for every postable share. At the phase boundary, two `Game` instances
wired through `src/test/e2e.test.ts`'s `connect()`/`pump()` harness (or an
equivalent extended for the new artefacts) play a full hand and produce a
receipt, a marker, and a signed action chain, each independently
recomputable and verifiable off the emitted bytes — no contract, no RPC, no
`prototypes/dispute-gas/` gas measurement involved. `npm test` (`vitest run`
per `package.json`) is the only executable proof this phase offers, and it
must exit 0.

## Inputs from previous phase

The scaffold, not a prior phase — P1 is first in the drafting wave after
`artifact-formats.md`. Verifiable claims this phase depends on:

- `artifact-formats.md` is normative for every signed byte (tag/domain
  registry §2, receipt §3, marker §4, signed action §5, Merkle §7, DLEQ §8) —
  read in full 2026-08-17, cited by section throughout.
- `decisions.md` D1 (formats doc owns every field), D2 (secp256k1 session
  keys, registration is P2's), D3 (keccak-challenge DLEQ for chain-verifiable
  shares, sha512 stays for wire-only proofs), D7 (canonical post-clamp
  amounts, write-ahead), D14 (load-bearing rule list), D15 (durations are
  P2/P7 concerns, not P1's), **D16** (added to the ledger after this
  document's first draft — cross-repo byte parity is proven by one
  committed vector file, not by two independent readings of the same
  prose; P1 owns the generator, task 10 below).
- `fixtures-index.md`'s client-side row (bottom of file): F12.3 canonical
  amounts, F14.3 write-ahead ordering, D14 load-bearing rules — "enumerated
  in P1/P6 docs", which this document does in task 9.
- Spec `2026-08-16-v2-cash-settlement-consolidated.md` §9 items 1, 6, 9, 16,
  18, 19 — read in full 2026-08-17; item numbers verified against the actual
  file (the brief's "16" is item 16, "Actions are unsigned"; item 18,
  "`Game.act()` signs nothing and sends the raw pre-clamp amount", is the one
  that pins the canonical-amount fix precisely and is cited alongside it).

## Files touched

**Created:**
- `src/core/signing.ts` — session keypair generation, the universal-binding
  preimage builder (`contract ‖ chainid ‖ session` per formats §1), raw
  keccak-digest sign/verify, and the byte-order fix noted in task 1.
- `src/core/merkle.ts` — position-bound leaf hashing and sorted-pair tree
  (formats §7) for the 52-card deck and share trees.
- `src/core/dleqKeccak.ts` — keccak-challenge DLEQ prover (formats §8),
  separate from `proofs.ts`'s sha512 prover, which stays untouched.
- `src/core/receipt.ts` — receipt preimage/hash builder (formats §3) and the
  wei/chip unit converter (`weiPerChip`, `chipsToWei` — B1, fix round 1;
  receipt fields are wei, marker `sb`/`bb` and action `amount` are chips).
- `src/core/marker.ts` — marker preimage/hash builder (formats §4).
- `src/core/signedAction.ts` — signed-action preimage/hash builder and chain
  helpers (formats §5).
- `src/test/signing.test.ts`, `src/test/merkle.test.ts`,
  `src/test/dleq-keccak.test.ts`, `src/test/receipt.test.ts`,
  `src/test/marker.test.ts`, `src/test/signed-action.test.ts`,
  `src/test/write-ahead.test.ts`, `src/test/hand-number.test.ts` — new test
  files, named after the module or behaviour under test per the existing
  `<topic>.test.ts` convention (`src/test/vault-button.test.ts`,
  `vault-persistence.test.ts`, etc.).
- `src/vectors/gen.mts`, `src/vectors/p1-vectors.json`,
  `src/vectors/Vectors.sol` — task 10's committed vector generator and its
  two committed outputs, per D16 (pattern:
  `prototypes/dispute-gas/gen/gen.mts` in the vault repo).

**Modified:**
- `src/core/protocol.ts` — extend `Msg` with `receipt` and `marker`
  variants; extend the `act` variant with `hand`, `seq`, the canonical
  `amount`, `prev`, and `sig`.
- `src/core/game.ts` — remove the `hand % 2` button computation (line 119);
  take button as an explicit constructor argument; compute all 52 shares and
  build/sign the marker at shuffle end; sign each outgoing action with the
  post-clamp committed total (not the raw `amount` argument to `act()`);
  maintain the action-hash chain with `prev₀ = markerHash`; gate `beginDeal`
  on both-signed receipt N−1 existing.
- `src/worker.ts` — extend the `init` message to carry the session private
  key material and `contract`/`chainid`/`session` binding values; extend the
  `In` union and `post()` events for marker/receipt construction and the new
  write-ahead persistence handoff (task 7).
- `src/useGame.ts` — hand-number recovery (task 4); session keypair
  generation/storage (task 1); marker and receipt exchange, persistence, and
  the `(0,0)`/`final` rules (tasks 5, 8); write-ahead persistence in the
  worker's `onmessage` handler, ahead of the existing
  `transportRef.current?.send(m.msg)` forward (task 7); reuse of
  `vaultInfoRef.current.{contractAddress,chainId}` (already populated by the
  existing Buyin `postMessage` handshake, line ~958) as the binding values,
  and reuse of `vaultResultHash`'s `keccak256(toBytes(roomId))` as the
  `session` id (extracted to a shared helper, `sessionIdFor`, to avoid a
  second definition of the same formula).

**Deleted:** none.

## Tasks

**Task order, stated once, authoritatively:** Tasks 4 and 5 forward-reference
task 8's receipt-store outputs (`loadNewestReceipt`, `latestReceiptHash`).
Rather than stubbing interfaces here for task 8 to fill in later, **Task 8
dispatches before Tasks 4 and 5.** Full suggested order: **1, 2, 3, 8, 4, 5,
6, 7, 9, 10** — 1/2/3 are independent foundations and can dispatch in any
order relative to each other or in parallel; 8 comes next because 4 and 5
need its outputs; 6 and 7 need 5 (the marker) and 1 (signing); 9 audits 6
and 7's output, so it comes after both; 10 (the vector generator, added by
D16 — see below) needs every builder module from 1, 2, 3, 5, 6, and 8 to
already exist, so it dispatches last.

**Phase-base SHA (D17):** `poker@d66a68a` — the scaffold's own last-VERIFIED
checkpoint (README.md's Status section). Any isolation/no-touch gate in this
document that needs a diff base uses `git diff d66a68a..HEAD -- <paths>`,
never bare `git diff --stat`, per D17. Dispatch-time SHA (recorded 2026-08-17): **poker@d66a68a**. Record if moved by the time tasks 1-10 are dispatched — this value is a
snapshot, not a promise that no other commit landed first.

### Task 1 — session-key signing primitives

**Goal:** a small, framework-free module other tasks build on: keypair
generation, the universal-binding preimage builder, and raw-digest signing
that produces the wire's `r ‖ s ‖ v` byte order.

**Files:** create `src/core/signing.ts`, `src/test/signing.test.ts`.

**Steps:**
1. Keygen: `secp256k1.utils.randomSecretKey()` (probed 2026-08-17 against
   `@noble/curves@2.3.0`, already a poker dependency —
   `secp256k1.getPublicKey(priv, false)` for the uncompressed public key).
2. Preimage builder: `bindPreimage(tag: number, domain: string, contract:
   Hex20, chainId: bigint, session: Hex32, ...fields: Uint8Array[])` →
   `tag(1) ‖ domain(ascii) ‖ contract(20) ‖ chainid(32) ‖ session(32) ‖
   ...fields`, all big-endian fixed-width per formats §1 (`abi.encodePacked`
   semantics, no length prefixes). Export small helpers for uint64/uint32/
   uint256/uint8 big-endian encoding — nothing here should hand-roll padding
   inline in a caller.
3. `hash(preimage) = keccak256(preimage)` via `@noble/hashes/sha3.js`'s
   `keccak_256` — confirmed 2026-08-17: `@noble/hashes@2.3.0` is already a
   poker dependency (`package.json`) and its `sha3.js` entry point exports
   `keccak_256` (also the function `prototypes/dispute-gas/gen/gen.mts`
   uses in the vault repo, for the same hash, over the same domain-tagged
   preimage shape — a standalone Node script there, not evidence about
   Vite's resolver, but the dependency and export are the fact this step
   actually rests on).
4. **Byte-order footgun, load-bearing for every downstream signature:**
   probed 2026-08-17 — `secp256k1.sign(digest, priv, { format: 'recovered'
   })` returns 65 bytes as **`v(1) ‖ r(32) ‖ s(32)`** (recovery byte
   *first*), not the wire's `r ‖ s ‖ v`. `Channel.sol`'s `_recover`
   (`contracts/src/Channel.sol:177-190`, vault repo) reads `r = sig[0:32]`,
   `s = sig[32:64]`, `v = sig[64]`, accepting `v ∈ {0,1,27,28}` (adds 27 if
   `v<27`) and requiring low-s. `sign(...)` with `{format:'recovered'}`
   already returns low-s (`lowS` defaults to `true` in noble's ECDSA —
   confirmed in `node_modules/@noble/curves/abstract/weierstrass.d.ts`).
   `signRaw(digest, priv)` in this module must therefore slice the 65-byte
   output as `[v, ...rs] = sig` and reassemble `Uint8Array([...rs, v])`
   before returning. Get this wrong and every signature this phase produces
   fails the wallet-style recovery P2 implements from AF-2's note (raw
   digest, no EIP-191 prefix, but same `r‖s‖v` shape).
5. `verifyRaw(digest, sig65, pubkeyUncompressed)` for symmetry and tests.

**Verification probe:** `npx vitest run src/test/signing.test.ts` — assert
(a) `bindPreimage` output for a known tag/domain/contract/chainid/session/
field tuple is byte-for-byte **equal to the corresponding entry in the
committed `src/vectors/p1-vectors.json`** (D16 — this replaces this task's
originally-planned hand-built-literal comparison; the committed vector is
now the single source of truth, not a value re-typed into this test). **This
assertion cannot land until task 10's generator has produced
`p1-vectors.json`** — per the Task order note, task 10 dispatches last, so
land this task's structural checks (b)-(d) first, standalone and already
passing, and add assertion (a) as a small follow-up diff once task 10 lands
rather than blocking this task's own dispatch on a later one; (b) a
round-trip sign→verify succeeds; (c) the produced 65-byte signature's last
byte is `0x00`, `0x01`, `0x1b`, or `0x1c` (never anything else — catches a
regression of the byte-reorder fix); (d) `s ≤ N/2` on every signature
produced across 50 random digests (low-s holds without extra work).

**Dispatch:** agent (workhorse, medium).

---

### Task 2 — Merkle tree module

**Goal:** position-bound leaf hashing and the sorted-pair tree formats §7
specifies, shared by the marker (deck/share roots) and later P3's on-chain
verifier's off-chain proof-generation twin.

**Files:** create `src/core/merkle.ts`, `src/test/merkle.test.ts`.

**Steps:**
1. `shareLeaf(pos: number, shareEnc: Uint8Array): Uint8Array` = `keccak256(
   0x05 ‖ "vault/shareleaf/v1" ‖ uint8(pos) ‖ shareEnc(32))`.
2. `deckLeaf(pos: number, c1Enc: Uint8Array, c2Enc: Uint8Array): Uint8Array`
   = `keccak256(0x06 ‖ "vault/deckleaf/v1" ‖ uint8(pos) ‖ c1Enc(32) ‖
   c2Enc(32))`.
3. `node(a: Uint8Array, b: Uint8Array): Uint8Array` = sorted-pair
   `keccak256(min(a,b) ‖ max(a,b))`, byte-lexicographic comparison (equals
   numeric order on `bytes32` — formats §7 states this explicitly; the
   comparator is a plain byte-array compare, nothing curve-specific).
4. `buildTree(leaves: Uint8Array[]): { root: Uint8Array; layers:
   Uint8Array[][] }` — 52 leaves in, odd node at a level pairs with itself
   (formats §7, "the prototype's rule, kept" — matches
   `prototypes/dispute-gas/gen/gen.mts` lines ~298-320 in the vault repo).
5. `proveInclusion(layers, index): Uint8Array[]` — 6-hash proof for 52
   leaves; `verifyInclusion(leaf, proof, index, root): boolean` for the test
   and for reuse by later phases' off-chain tooling.

**Verification probe:** `npx vitest run src/test/merkle.test.ts` — build a
52-leaf tree from known `(pos, bytes)` pairs, assert every leaf's proof
verifies against the root, assert two leaves at different positions with
identical `shareEnc` produce different leaves (the position-bound property
formats §7 exists for), and assert the same construction with the
prototype's *unbound* `keccak(shareEnc)` leaf shape produces a different
root (documents the delta from `artifact-formats.md` §10 rather than
silently matching it). **Per D16, add a further assertion once task 10
lands** (same landing note as task 1's probe: dispatch this task's
structural checks first, add the vector check as a follow-up): the deck
tree and the share tree this task builds from task 10's fixed deterministic
inputs produce roots, and a sampled inclusion proof, byte-for-byte equal to
`src/vectors/p1-vectors.json`'s Merkle section — the committed vectors are
the source of truth for "both Merkle trees with proofs" D16 requires, not a
value re-derived independently in this test.

**Dispatch:** agent (workhorse, low).

---

### Task 3 — keccak-challenge DLEQ prover

**Goal:** the chain-verifiable DLEQ variant formats §8 specifies, for every
postable share. The existing `proveDleq`/`verifyDleq` in `src/core/
proofs.ts` (sha512 Fiat-Shamir, used for the wire-only proofs in
`Session.makeShares`) stay untouched per D3 — this is new, separate code.

**Files:** create `src/core/dleqKeccak.ts`, `src/test/dleq-keccak.test.ts`.

**Steps:**
1. Mirror `prototypes/dispute-gas/gen/gen.mts`'s `keccakChallenge` (vault
   repo, lines ~197-208): `payload = cardPkEnc ‖ c1Enc ‖ shareEnc ‖ t1Enc ‖
   t2Enc` (5×32 bytes); `h1 = keccak256(0x01 ‖ "vault/dleq/keccak-v1" ‖
   payload)`; `h2 = keccak256(0x02 ‖ "vault/dleq/keccak-v1" ‖ payload)`;
   `c = (h1·2²⁵⁶ + h2) mod L` where `L` is `src/core/group.ts`'s exported
   `ORDER` (ristretto255 group order — same constant the prototype computes
   independently; reusing `group.ts`'s is a correctness win, not just style).
2. `proveDleqKeccak(secret, pub, base2, point2): { c: bigint; s: bigint }` —
   same `t1 = G·k`, `t2 = base2·k`, `s = k + c·secret mod L` structure as
   `proofs.ts`'s `proveDleq`, challenge computed via step 1 instead of
   `hashToScalars`.
3. `verifyDleqKeccak(pub, base2, point2, c, s): boolean` — recompute `t1 =
   G·s − pub·c`, `t2 = base2·s − point2·c`, recheck the challenge.
4. §8 note: this is the same challenge formula `formats §10`'s prototype
   deltas list does **not** flag as changing (only the action domain, `prev₀`,
   and Merkle leaves are listed as deltas) — so this module's output should
   be checkable against the prototype's own logic structurally, not just
   against the formats doc's prose.

**Verification probe:** `npx vitest run src/test/dleq-keccak.test.ts` —
generate a random `(secret, pub=G·secret, base2, point2=base2·secret)`,
assert `verifyDleqKeccak` accepts the honest proof and rejects `s+1` (this
structural check needs no committed vector and dispatches with this task,
standalone). **Per D16, once task 10 lands** (follow-up diff, same pattern
as tasks 1 and 2): assert `(c, s)` for task 10's fixed, deterministic
`(cardPkEnc, c1Enc, shareEnc, t1Enc, t2Enc)` tuple is byte/value-equal to
`src/vectors/p1-vectors.json`'s DLEQ section — this replaces the originally
planned "computed independently in the test via raw `keccak_256` calls"
approach (still true that noble computes the numbers; D16's point is that
the computation happens once, in the generator, and is committed rather
than re-run inside every consuming test).

**Dispatch:** agent (workhorse, medium).

---

### Task 4 — hand-number recovery and the explicit button

**Goal:** fix spec §9 items 1 and 9. Hand number stops being `handRef.current`
alone (local, reset to 0 on `onPeerRestart`, `useGame.ts:1393`, never bound
into anything); the button stops being `hand % 2 === 0` (`game.ts:119`,
which silently posts the wrong blinds the moment the two engines' hand
counters diverge — the exact bug §9.9 names).

**Files:** modify `src/core/game.ts` (constructor signature, remove line
119's parity computation), `src/useGame.ts` (`handRef` sourcing,
`spawnWorker`'s `hand` argument, `startFresh`, `onPeerRestart`'s
`handRef.current = 0` reset), `src/worker.ts` (`init` message gains an
explicit `button` field alongside the existing `hand`).

**Steps:**
1. Recovery order per spec §9.1: on (re)connect, read the newest stored
   receipt (`(hand, subseq)` via task 8's `loadNewestReceipt()` — per the
   Task order note above, task 8 dispatches before this task, so that
   function already exists) — strongest source, "cannot be lied to about
   it" since both signatures are on it. Falling back to the
   marker floor is explicitly **out of scope for P1** (needs the on-chain
   read P6 adds); P1 implements only the local-storage leg of the recovery
   order and the refuse-to-resume guard for the case neither exists.
2. Refuse-to-resume guard: a client with no stored receipt for this session
   must not accept a hand number from its peer — "not lower than what I have
   already signed" with nothing signed means accept nothing, per §9.1's
   closing paragraph. Extend this same guard to the signed-action tip (task
   7's write-ahead store) per spec §6's amendment: "a client that cannot see
   what it last signed refuses to sign actions for that hand at all."
3. Button: add a required `button: Seat` parameter to `Game`'s constructor,
   remove the `hand % 2` line. Source of truth for what value to pass is the
   **marker** once task 5 exists (the marker carries `button` explicitly,
   both-signed) — until then, and for hands before any marker exists (there
   is none for hand 0, whose only artefact is receipt `(0,0)`), alternate
   from a value transmitted the same way blinds' `level` already is
   (`useGame.ts:1569`, `{ t: 'newhand', level: next }`): add `button` to that
   same message, computed by whoever deals from the last value both sides
   agree on. This is flagged as an **open question** below rather than
   silently decided, because "carried explicitly" admits more than one wire
   shape and the marker (task 5) is the one both-signed source of truth —
   the `newhand` field is a bridge for hands the marker exchange hasn't
   covered yet.
4. Update every call site that constructs `Game` directly and will break on
   a new required constructor argument — confirmed 2026-08-17 via `grep -n
   "new Game(" src/test/*.test.ts`: `e2e.test.ts` (`connect()` and three
   further inline constructions, lines 19-20, 199-200, 229-230, 286-287),
   `ordering.test.ts` (`pair()` plus two more direct constructions, lines
   29, 155, 161), and `live.test.ts` (line 53, part of a live-running
   suite). `launch-flow.test.ts` and `mobile.test.ts` do **not** construct
   `Game` (they are source-text-regex tests over other files) and need no
   change here — re-grep before touching `game.ts`'s signature regardless,
   since this list is a snapshot, not a substitute for checking.

**Verification probe:** `npx vitest run src/test/hand-number.test.ts` — (a)
two engines whose local hand counters are artificially desynced (one at 3,
one at 5) still post the SAME button once both read it from the same
explicit source, where the old code would post different blinds; (b) a
fresh client with empty storage refuses to resume a session it has no
receipt for. Then `npx vitest run src/test/e2e.test.ts src/test/ordering.test.ts
src/test/live.test.ts src/test/vault-button.test.ts` — existing suites still
pass with the new constructor signature (regression gate on `Game`'s public
API change, covering every file confirmed above to construct `Game`
directly).

**Dispatch:** agent (workhorse, high).

---

### Task 5 — hand-start marker: construction, signing, exchange, persistence

**Goal:** formats §4, D6, D14's "marker-pk hello-match refusal". All 52
shares computed at shuffle end; both `shareRoot`s and the `deckRoot` via
task 2's `merkle.ts`; both `cardPk`s from the `hello` exchange; button and
blinds; both-signed; persisted. **No posting, no deal gate against a chain
confirmation** — that read requires chain awareness this phase does not
have (spec §9.8), and is P6's job per the README's sequencing row.

**Files:** modify `src/core/protocol.ts` (new `marker` `Msg` variant),
`src/core/game.ts` (build at shuffle end — the natural point, since
`Session.deck` is fixed and `makeShares` is already callable for any
position set at that moment), `src/useGame.ts` (both-sign exchange,
persistence), create `src/core/marker.ts`.

**Steps:**
1. `src/core/marker.ts`: `buildMarkerPreimage({contract, chainId, session,
   hand, receiptHash, deckRoot, hostShareRoot, guestShareRoot, hostCardPk,
   guestCardPk, button, sb, bb})` using task 1's `bindPreimage` with tag
   `0x02`, domain `vault/marker/v2`, field order exactly as formats §4 lists
   it. `markerHash = keccak256(preimage)`. **`sb`/`bb` are chips (B1, fix
   round 1)** — the same values `betting.ts`'s `startHand` already takes
   (`this.sb`/`this.bb` in `game.ts`, sourced from `BIG_BLIND`/
   `SMALL_BLIND`/`blindsFor`), passed straight through with no conversion.
   This is deliberately the **other** unit domain from task 8's receipt: the
   marker anchors chip-space replay (P3's `BettingReplay` seeds from these
   fields plus a chips view), and only the receipt converts to wei.
2. In `Game`, right after `acceptShuffle`/the host's second shuffle (i.e.
   the moment `this.deck` is final for the hand, before `beginDeal`'s
   `makeShares(theirHolePositions)` call): call `session.makeShares([0..51])`
   once, cache the 52 items (this **replaces** the on-demand
   `makeShares(positions)` calls at deal/street-advance time for the purpose
   of the marker's `shareRoot` — the existing calls for actually revealing
   cards to the peer stay as they are, since revealing early would leak
   information; the marker only needs the roots, not the shares themselves,
   until a dispute). Build `deckLeaf`/`shareLeaf` per position via
   `merkle.ts`, get `deckRoot`/`hostShareRoot`.
3. `hostCardPk`/`guestCardPk` are `Session.key.public` (own) and
   `Session.peerPk` (peer's) — both already ristretto `Pt` values held by
   `Session` since `acceptHello`; encode via `group.ts`'s `toHex`/wire form.
4. **D14 load-bearing rule:** "An honest client signs the marker only after
   the shuffle proofs verify AND both cardPks match the hello it received."
   Both are already guaranteed by the point this code runs (shuffle
   verification throws before this point on failure; `peerPk` is set only in
   `acceptHello` from the wire `hello.pk`) — the load-bearing part is
   **asserting it explicitly** rather than relying on control flow, so a
   future refactor can't silently drop the ordering. Add the explicit check
   with a **distinct marker (M5, fix round 1 — one string per D14 rule, not
   a shared count, since P6 also lands "load-bearing — do not relax"
   comments for its own two D14 rules and a summed grep across shared
   files cannot tell P1's comments from P6's):** `// load-bearing — do not
   relax (D14: marker-pk hello-match)`.
5. Exchange: host signs and sends `{t:'marker', ...fields, hostSig}`; guest
   verifies the fields it can check locally (its own `shareRoot`/`cardPk`
   match what it computed), signs, sends back `{t:'marker', ...fields,
   guestSig}` (or a compact "I attest, here's my sig over your hash"
   response — mirror the existing shuffle exchange's send-verify-send
   shape in `Session.shuffle`/`acceptShuffle` rather than inventing a new
   pattern). Persist the both-signed marker (task 8's storage module) before
   dealing.
6. `receiptHash` field: the highest-subseq receipt hash at hand N−1, via
   task 8's `latestReceiptHash()` — per the Task order note above, task 8
   dispatches before this task, so the function already exists. For hand 1
   this resolves to receipt `(0,0)`'s hash.

**Verification probe:** `npx vitest run src/test/marker.test.ts` — two
engines complete a shuffle, both independently compute the same
`deckRoot`/`hostShareRoot`/`guestShareRoot`/`markerHash`; a marker whose
`cardPk` doesn't match the `hello` is refused (throws) before signing; the
persisted marker round-trips through the storage module unchanged.

**Dispatch:** agent (session-tier, high) — new subsystem, three D14
load-bearing rules touch it, and P2/P6 verify these bytes on chain, so a
silent field-order or encoding mistake here is invisible until P6.

---

### Task 6 — signed action chain, canonical post-clamp amount

**Goal:** spec §9.18/§9.16, formats §5, D7. `Game.act()` currently signs
nothing and sends the raw pre-clamp `amount` (`game.ts:285-290`); the client
must sign the amount `applyAction` (`betting.ts:127-183`) actually applied.

**Files:** modify `src/core/protocol.ts` (`act` variant gains `hand`, `seq`,
canonical `amount`, `prev`, `sig`), `src/core/game.ts` (`act()`,
`applyPeerAction()`), create `src/core/signedAction.ts`.

**Steps:**
1. `src/core/signedAction.ts`: `buildActionPreimage({contract, chainId,
   session, hand, seq, action, amount, prev})` via task 1's `bindPreimage`,
   tag `0x03`, domain `vault/act/v2`, exactly formats §5's field order.
   `actionHash = keccak256(preimage)`. **`amount` is chips (B1, fix round
   1)** — the exact post-clamp value `betting.ts` produces (step 2 below),
   with no conversion; only task 8's receipt fields are wei.
2. **Canonical amount, without touching `betting.ts`:** `applyAction`
   mutates `st.committed[seat]` to the clamped total in place
   (`betting.ts:155-158`, the `target` variable). `Game.act()` can read
   `this.betting.committed['me']` **after** calling `applyAction` to get the
   exact clamped total for a `'bet'` action; `amount = 0` for
   `fold`/`check`/`call` per formats §5 ("MUST be 0"). This needs no change
   to `betting.ts` at all — the clamp already happens there, and its result
   is already stored in state the caller can read straight back.
3. `seq` increments per hand (reset each hand, alongside `prev₀ =
   markerHash` from task 5); `prev` for `seq > 0` is the previous action's
   own `actionHash`. Track this as hand-scoped state on `Game` (it already
   resets naturally, since `Game`'s `betting` is rebuilt each hand via
   `startHand`).
4. Sign with the actor's session key only — **never derive the signer from
   `seq` parity** (formats §5's explicit warning, corrected by AF-2: the
   button acts first preflop and last postflop, so the same seat can act at
   consecutive seqs across a street boundary). The signer is simply "the
   side that called `act()` locally" (host or guest, whichever `role` this
   `Game` instance is) — there is no ambiguity to resolve here, since each
   `Game` only ever signs its own local actions and verifies the peer's on
   receipt; this note exists so nobody "simplifies" it into a parity check
   later.
5. `applyPeerAction` verifies the incoming `sig` against the peer's session
   public key (registration itself is P2's; P1 verifies against the
   locally-held peer session pubkey exchanged the same way `hello`'s card
   pubkey is exchanged — add a session-key `hello`-equivalent field or reuse
   `hello` itself, since both are per-match, exchanged-once values; **flagged
   as an open question below** — reusing `hello` couples card-key and
   session-key exchange into one message, which is convenient but conflates
   two independently-lived keys per spec §6's "neither rule may be
   harmonised with the other").

**Verification probe:** `npx vitest run src/test/signed-action.test.ts` —
(a) F12.3's construction: a raw bet of 200 clamped to 120 by `applyAction`
signs `amount=120`, and replaying the signed chain against a fresh
`applyAction` call with the same starting state reproduces exactly 120,
never 200; (b) fold/check/call always sign `amount=0` even when a stray
caller passes a nonzero `amount` argument; (c) `prev₀` on the first action
of a hand equals that hand's `markerHash` (depends on task 5); (d) two
actions at the same `(hand, seq, prev)` differing only in `action`/`amount`
are flagged as equivocation candidates by a pure `isEquivocationPair`
helper this task also exports (D8/D12's `test_F13_4` groundwork, consumed
by P3 — P1 only needs the pure predicate to exist and be tested, not a
contract).

**Dispatch:** agent (session-tier, high) — D7/D14, money-adjacent (P3/P4
enforce these bytes on chain; a clamp-parity bug here is invisible until a
real dispute).

---

### Task 7 — write-ahead persistence for the signed action tip

**Goal:** spec §6's amendment and D7/D14: persist a signed action **before**
transmitting it; a restored client never re-signs at or below its persisted
tip and sends-or-files the persisted action itself; cleared storage refuses
further signing for that hand.

**Files:** modify `src/useGame.ts` (the worker's `onmessage` handler,
currently `w.onmessage = (e) => { ...; if (m.ev === 'send')
transportRef.current?.send(m.msg); ... }`, `useGame.ts:1092-1106`), create
`src/core/actionStore.ts` (pure, storage-parameterised — mirrors
`saveVaultSigs`/`loadVaultSigs`'s `Pick<Storage,'setItem'|'getItem'>`
pattern in `useGame.ts:266-293`), `src/test/write-ahead.test.ts`.

**Steps:**
1. **Why this can't live in the worker:** confirmed 2026-08-17 against MDN
   ("Web Workers API: Functions and classes available to workers") —
   dedicated Web Workers have no `window.localStorage`/`sessionStorage`
   (DOM-tied APIs; IndexedDB and the File System API are what workers do
   get). `Game.act()` and the signing in task 6 run inside `worker.ts`, so
   persistence must happen on the **main thread**, in the synchronous gap
   between the worker's `postMessage({ev:'send', msg})` arriving and
   `useGame.ts` forwarding it to the transport. That gap is one synchronous
   `onmessage` callback — no `await` sits between "worker signed it" and
   "main thread can persist it", so ordering is enforceable without a race.
2. `actionStore.ts`: `saveActionTip(store, sessionId, hand, action:
   SignedAction): void`, `loadActionTip(store, sessionId, hand):
   SignedAction | null`, keyed `vault:action:${sessionId}:${hand}` (mirrors
   `vaultSigsKey`'s `vault:sigs:${roomId}` naming in `useGame.ts:262-264`).
3. In `w.onmessage`: before the existing `if (m.ev === 'send')
   transportRef.current?.send(m.msg)`, check whether `m.msg.t === 'act'`
   (or `'marker'`/`'receipt'` — the same write-ahead discipline applies to
   all three per D7's "persist before transmit, no exceptions"); if so, call
   `saveActionTip`/the equivalent persistence for that artefact type
   synchronously first, **then** forward to the transport. **This ordering
   is the first of P1's three D14 load-bearing rules — mark the persist-
   before-forward call site itself with its own distinct marker (M5, fix
   round 1): `// load-bearing — do not relax (D14: write-ahead signing)`,
   here, not only at step 5's refusal check below; an implementer reading
   step-by-step hits this call site first and the rule is exactly as
   load-bearing here as it is there.**
4. On restore (session/tab reload mid-hand): if `loadActionTip` returns a
   tip for the current hand, the client must not let `Game.act()` produce a
   new signature for that `seq` — it re-sends the persisted bytes instead
   ("sends-or-files the persisted action itself", spec §6, "a
   persisted-but-unsent tip is still that player's move; re-deciding it is
   equivocation"). Implement as a guard in the `act()` wiring: if a tip
   exists for the seq about to be signed, skip signing and re-transmit the
   stored bytes.
5. Refuse-to-sign-on-cleared-storage: if `Game.act()` is about to sign
   `seq=0` for a hand and no marker/receipt trail exists locally for that
   session (task 4's guard, extended here to the action tip specifically per
   spec §6: "a client that cannot see what it last signed refuses to sign
   actions for that hand at all"), throw rather than sign — this is the
   third of P1's three D14 load-bearing rules (write-ahead itself, and this
   refusal, are two; task 5 carries the marker-pk one). Its own distinct
   marker (M5, fix round 1): `// load-bearing — do not relax (D14:
   refuse-on-cleared-storage)` — a different string from step 3's, so the
   two rules' comments are individually greppable rather than only
   countable as a total.

**Verification probe:** `npx vitest run src/test/write-ahead.test.ts` — (a)
a fake `Storage` (mirroring `vault-persistence.test.ts`'s `fakeStorage()`)
receives the action's bytes before a stub transport's `send` is called,
asserted by recording call order in an array, not just call counts; (b) a
"restored" client with a stored tip that calls `act()` for that same seq
again does not produce a second, distinct signature — it returns the stored
one; (c) a client with an empty store refuses to sign `seq=0` for a hand it
has no marker/receipt trail for.

**Dispatch:** agent (session-tier, high) — this is the rule D8's
equivocation-burn proof depends on (§5.1: "This burn is proof of misconduct
only because §6 requires write-ahead signing"); a bug here doesn't just
break a test, it breaks the soundness argument P3 relies on.

---

### Task 8 — receipt wire message, hand-boundary exchange, persistence

**Goal:** spec §9.6 ("no receipt message in the protocol at all") and §1.1:
new `Msg` variant, exchange at every hand boundary, mandatory `(0,0)` before
hand 1, `final` on stop, persistence in `localStorage` (moved off
`sessionStorage`, spec §6/Q13) under both origins.

**Files:** modify `src/core/protocol.ts` (`receipt` `Msg` variant),
`src/useGame.ts` (`beginMatch`/`nextHand`/the stop-and-sign-final path,
persistence), create `src/core/receipt.ts`, `src/test/receipt.test.ts`.

**Steps:**
1. **Unit domains, stated explicitly (B1, fix round 1):** `hostStack`,
   `guestStack`, `hostDeposit`, `guestDeposit` are **wei** (`uint256`),
   never the engine's chip counts. This is the one place wei appears in
   this phase's artefacts — the marker's `sb`/`bb` (task 5) and the signed
   action's `amount` (task 6) are both **chips**, matching `betting.ts`'s
   native unit, because replay (P3's `BettingReplay`) runs in chip-space
   against the marker's blinds. Receipt is the seam between the two spaces
   (B1: "this is the seam D1 exists for"), so it is the only artefact that
   converts.
2. `src/core/receipt.ts`: `buildReceiptPreimage({contract, chainId, session,
   hand, subseq, hostStack, guestStack, hostDeposit, guestDeposit, final})`
   via task 1's `bindPreimage`, tag `0x01`, domain `vault/receipt/v2`,
   formats §3's field order, all five stack/deposit-shaped fields taken as
   **wei already** — this function does not convert, it only builds the
   preimage from wei inputs its caller supplies. `receiptHash =
   keccak256(preimage)`.
3. **The converter, and where the rate comes from:** `weiPerChip(depositWei:
   bigint, startingChips: number): bigint` in `src/core/receipt.ts`,
   computing `depositWei / BigInt(startingChips)` — fixed once, at `(0,0)`,
   per B1's ruling, never recomputed. A second helper,
   `chipsToWei(chips: number, rate: bigint): bigint`, converts the engine's
   live chip-space stacks to wei at every later receipt using that same
   fixed rate. **The rate needs a real `depositWei` figure, which this
   phase does not have** — spec §9.8 already excludes chain awareness from
   P1's scope, and no existing `postMessage` field from Buyin surfaces a
   wei deposit amount today (confirmed 2026-08-17: `vaultInfoRef` carries
   only `contractAddress`/`chainId`/`host`/`guest`, per the grep at
   `useGame.ts:958`; no deposit figure). This phase's `(0,0)` signing
   therefore waits on `hostDeposit`/`guestDeposit` being supplied the same
   way `vaultInfoRef.contractAddress`/`chainId` already gate other signing
   (see Recovery) — a real wei figure is P2/P6's chain-read to add; until
   it exists, task 10's own vectors (and any local/non-Vault play) use a
   fixed deterministic placeholder `depositWei` so the receipt's shape and
   the rate arithmetic are exercised and byte-checked now, without
   pretending this phase can read a chain balance it cannot reach.
4. `(0,0)` before hand 1: gate `beginMatch`'s deal (the existing
   `startedRef.current = true` path, `useGame.ts:1160-1188`) on a both-signed
   receipt `(0,0)` existing first, with `hostDeposit`/`guestDeposit` = the
   real (or, absent chain awareness, placeholder — step 3) wei figures, and
   `hostStack`/`guestStack` = those same values converted at rate `1` (by
   construction, `(0,0)`'s own stacks equal its own deposits — formats §3:
   "receipt `(0,0)`... carries both signatures" and "records the opening
   stacks and the opening deposits", which are the same numbers at hand 0).
   `weiPerChip` is computed from this receipt's `hostDeposit` and the
   engine's starting chip count (`startStack(config)`) and held for every
   later receipt in this match.
5. Exchange at every hand boundary: extend `nextHand()`
   (`useGame.ts:1554-1571`) to require both-signed receipt N (or N,1 for a
   rebuy boundary — rebuy wiring itself is P2/P5's, but the `subseq` field
   exists here so P1's format doesn't need revisiting later) before
   `startFresh` proceeds. This is the client-only half of §3's "no hand is
   dealt while the previous hand's receipt is unsigned" rule; the on-chain
   marker-confirmation gate (D6) is explicitly P6's.
6. `final`: extend the existing stop/leave UI path to sign a receipt with
   `final=0x01`, and make `nextHand()`/`beginMatch()` refuse to proceed once
   a `final` has been signed locally (spec §1.1: "the client refuses to deal
   another hand after signing one"). `final` receipts convert the same way
   as any other (step 3's fixed rate) — `final` does not change the unit
   domain, only the flag.
7. Persistence: `localStorage`, not `sessionStorage` — cite MDN
   ("Window: localStorage property" / "Window: sessionStorage property"):
   `localStorage` persists with no expiration until explicitly cleared,
   scoped per origin; `sessionStorage` is cleared when the tab/window's
   session ends. This is exactly Q13's complaint (`saveVaultSigs`/
   `loadVaultSigs` currently take `sessionStorage` as their default caller
   in `useGame.ts:847,1051,1501` — task 8 does not change those call sites'
   *purpose* (they persist the vault settlement signatures, a different
   artefact), but the new receipt store must default to `localStorage` from
   the start, and existing `sessionStorage` call sites are noted as a
   pre-existing, separate concern, not silently "fixed" here without being
   asked).
8. Both origins: poker's own `localStorage` write is straightforward
   (mirrors task 7's store shape). The buyin-origin copy is **out of scope
   for this poker-repo phase** — P1's job is to make the receipt available to
   forward, via the existing cross-origin bridge (`useGame.ts`'s periodic
   `postMessage` to `vaultWindowRef`, `useGame.ts:~780-813`, which already
   carries `pokerUrl`/`connected`/etc. to Buyin): add the latest receipt to
   that same payload. P2 (vault repo) is responsible for Buyin actually
   writing it to its own `localStorage` on receipt.

**Verification probe:** `npx vitest run src/test/receipt.test.ts` — (a) no
hand deals before a both-signed `(0,0)` exists (assert via the existing
`connect()`-style harness, extended); (b) a `final`-signed client refuses a
subsequent `nextHand()` call; (c) `loadNewestReceipt` after a simulated
reload returns the highest `(hand, subseq)` pair persisted, ordered
correctly (a `(3,1)` receipt beats `(3,0)` and `(2,5)`); (d) **unit-domain
check (B1):** every persisted/exchanged receipt's `hostStack`/`guestStack`/
`hostDeposit`/`guestDeposit` are `bigint` wei values consistent with
`(0,0)`'s fixed `weiPerChip` rate — a receipt built from a chip-space stack
of `150` at a rate of `10^15` wei/chip round-trips to exactly
`150n * 10n**15n`, never a raw chip integer leaking into a wei field.

**Dispatch:** agent (workhorse, high).

---

### Task 9 — cross-cutting fixtures and D14 comment audit

**Goal:** D12's named fixtures this phase is responsible for, plus a
mechanical audit that every D14 load-bearing rule this phase carries has its
required comment.

**Files:** modify/extend `src/test/signed-action.test.ts` (F12.3),
`src/test/write-ahead.test.ts` (F14.3), create
`src/test/load-bearing-audit.test.ts` (or fold into a top-level check — see
step 3).

**Steps:**
1. **F12.3 — `test_F12_3_clamp_parity`** (fixtures-index.md row, "(+ P1
   client signing tests)"): honest wire chain with a clamped bet (raw 200 →
   clamped 120): canonical amounts replay exactly. Already covered by task
   6's probe (b); this step names it with the fixture's canonical test name
   so P3's re-derivation (D12: "test tasks re-derive this class from the
   parking doc") finds it under the expected name.
2. **F14.3 — `test_F14_3_pair_in_window_only`'s client half**: "write-ahead
   ordering (persist-then-send, never re-sign ≤ tip, send-or-file tip on
   restore)" per the fixtures-index's closing note. Name task 7's probe
   sub-cases to match: `persists before transmitting`, `never re-signs at or
   below the persisted tip`, `re-sends the persisted tip on restore` as
   three explicit `it(...)` blocks (not folded into one assertion), so a
   future diff against the parking doc's finding 3/4a can match them
   one-to-one.
3. **D14 comment audit (M5, fix round 1 — grep each distinct marker, never
   a summed count):** a small test (or a `grep`-based check run as part of
   the test file, since vitest can shell out or `readFileSync` the source
   files it's checking) that greps for each of P1's three specific D14
   markers **individually, by its exact distinct string**, not for the
   shared prefix `load-bearing — do not relax` counted in aggregate — a
   count-based check cannot tell P1's comments from P6's, since P6 lands
   its own two D14 rules' comments under the same prefix, possibly in the
   same files (`useGame.ts` in particular, touched by both phases):
   - `load-bearing — do not relax (D14: marker-pk hello-match)` in
     `src/core/marker.ts` — task 5 step 4.
   - `load-bearing — do not relax (D14: write-ahead signing)` in
     `src/useGame.ts` or `src/core/actionStore.ts` — task 7 step 3.
   - `load-bearing — do not relax (D14: refuse-on-cleared-storage)` in
     `src/useGame.ts` or `src/core/actionStore.ts` — task 7 step 5.

   Each check is "does this exact string appear at least once, anywhere in
   the poker repo" — a plain `grep -rl` — never a total occurrence count.
   **`src/core/signedAction.ts` carries no D14 rule and is deliberately not
   in this list** — canonical-amount signing (task 6) is D7's rule, not one
   of D14's five, and giving it a load-bearing comment here would assert a
   rule this document never named.
4. Re-derive the fixture class from the parking doc per D12's instruction
   ("test tasks re-derive this class from the parking doc") for anything
   P1-shaped: `grep "### Findings" docs/superpowers/parking/
   v2-cash-game-settlement.md` from "## Tenth cold check" onward (vault
   repo), confirm no client-signing-shaped finding is missing from
   `fixtures-index.md`'s two P1 rows. If the re-derivation finds one, that
   is a plan finding for `review-findings.md`, not a silent addition here.

**Verification probe:** `npx vitest run src/test/signed-action.test.ts
src/test/write-ahead.test.ts` — the named fixtures exist as `it(...)` blocks
with exactly the fixture names from `fixtures-index.md`. D14 audit (M5): run
each of the following three individually — `grep -rl "load-bearing — do not
relax (D14: marker-pk hello-match)" src/core/marker.ts`, `grep -rl
"load-bearing — do not relax (D14: write-ahead signing)" src/useGame.ts
src/core/actionStore.ts`, `grep -rl "load-bearing — do not relax (D14:
refuse-on-cleared-storage)" src/useGame.ts src/core/actionStore.ts` — YES =
each of the three returns at least one matching file. This is three
independent presence checks, not one summed count, so it cannot collide
with P6's own two D14 markers (`hole shares born only by a completing
action`, `deal gate pause`) landing in the same shared files under the same
prefix. `src/core/signedAction.ts` is deliberately excluded from every
check here, matching step 3's note above.

**Dispatch:** agent (workhorse, high).

---

### Task 10 — canonical vector generator and cross-repo sync

**Added by D16, after this document's first draft** — "P1↔P2 revision round
injects this (wave-1 drafters were briefed before D16 existed)." This is
task 10 of 10, the tripwire task-count boundary this document's drafting
brief set; recorded here rather than split, since every step below is one
coherent deliverable (one generator, one set of committed outputs) and
splitting it would only separate steps that need to run together.

**Goal:** prove cross-repo byte parity with one committed artefact instead
of two independent readings of `artifact-formats.md`'s prose. Supersedes
this document's original tasks 1-3 plan of "compute expected hashes in-test
with noble" — the computation still uses noble, but runs once, in this
generator, and is committed rather than re-derived inside every consuming
test (D16's own wording).

**Files:** create `src/vectors/gen.mts`, `src/vectors/p1-vectors.json`
(committed), `src/vectors/Vectors.sol` (committed); modify
`src/test/signing.test.ts`, `src/test/merkle.test.ts`,
`src/test/dleq-keccak.test.ts` (land the vector-equality assertions tasks
1-3 deferred); modify `package.json` (a `gen:vectors` script).

**Steps:**
1. **Fixed, deterministic inputs only** — hardcoded private keys, scalars,
   and positions, never `crypto.getRandomValues()`/`group.ts`'s
   `randScalar()`. This is the whole point (D16: "deterministic fixed
   keys"): the same run must always emit the same bytes, or `sha256sum`
   parity with the vault repo's synced copy is unenforceable. Mirror
   `prototypes/dispute-gas/gen/gen.mts`'s approach (vault repo) rather than
   inventing a new one.
2. Emit receipt vectors: several `(hand, subseq, hostStack, guestStack,
   hostDeposit, guestDeposit, final)` tuples through task 8's
   `buildReceiptPreimage`/`receiptHash`, each signed with task 1's
   `signRaw` under a fixed test keypair.
3. Emit marker vectors via task 5's `buildMarkerPreimage`; action-chain
   vectors via task 6's `buildActionPreimage`, including at least one
   clamped-amount case (raw bet 200 → canonical 120 — doubles as committed
   ground truth for F12.3, task 9 step 1); DLEQ vectors via task 3's
   `proveDleqKeccak`/`verifyDleqKeccak`; two Merkle trees (deck and share)
   with a handful of inclusion proofs via task 2's `merkle.ts`.
4. Write `src/vectors/p1-vectors.json` — every value above as hex-string
   JSON — and `src/vectors/Vectors.sol`, a Solidity rendering (constants or
   a library, pattern: the `.sol` output `gen.mts` already produces in the
   vault repo, confirmed 2026-08-17 via
   `prototypes/dispute-gas/README.md:30`'s documented invocation: `node
   --experimental-strip-types gen/gen.mts > test/Vectors.sol`). Use the same
   `node --experimental-strip-types` invocation here — confirmed 2026-08-17
   against this machine's `node --version` (v22.12.0) and the vault repo's
   own documented command; neither repo has `tsx`/`ts-node` as a dependency
   (checked both `package.json`s), so `--experimental-strip-types` is the
   real, already-working mechanism, not a guess.
5. Add `"gen:vectors": "node --experimental-strip-types src/vectors/gen.mts"`
   to `package.json`'s `scripts` (the script itself writes both output
   files rather than relying on shell redirection, so one invocation
   produces both — simpler than splitting stdout across two commands as the
   vault prototype's single-file-output form does).
6. Retrofit tasks 1, 2, and 3's test files: add the vector-equality
   assertions those tasks' verification probes described as "follow-up,
   once task 10 lands" — this is that landing.
7. **Ownership boundary (D18, fix round 1):** the sync — copying
   `p1-vectors.json`/`Vectors.sol` into the vault repo and gating on
   `sha256sum` equality there — is **P2's**, not P1's. P1's own
   responsibility is narrower but not merely "commit and record a hash": it
   is (i) committing both files, (ii) recording their `sha256sum` in this
   task's commit message, and (iii) **self-verifying that recording is
   still accurate as a gate P1 itself runs** (step-8 below) — never treating
   "the hash is recorded somewhere" as sufficient on its own. P1 does not
   modify the vault repo, per this phase's side-effect boundary.
8. **P1's own D18 gate, three parts, all hard-fail (never a fallback
   pass):**
   - `sha256sum -c` self-check: write the two recorded lines from step 7's
     commit message to a `.sha256` file and run `sha256sum -c` against the
     committed files — YES only if both report `OK`. A missing file or a
     mismatch is a **gate FAILURE**, not a "still passes, vectors will sync
     later" — there is no such wording in this document to delete, and none
     should be added.
   - Reference check: `grep -l "p1-vectors.json" src/test/signing.test.ts
     src/test/merkle.test.ts src/test/dleq-keccak.test.ts` — YES only if
     all three files match, proving each one actually imports/reads the
     committed vector rather than carrying a structurally-similar hardcoded
     literal that happens to agree with it today.
   - Mutation probe: flip one byte in a copy of `src/vectors/p1-vectors.json`
     used only for this check (never the committed file — restore or
     discard the copy immediately after), rerun `npx vitest run
     src/test/signing.test.ts src/test/merkle.test.ts
     src/test/dleq-keccak.test.ts` against the mutated copy — YES only if
     at least one assertion in each of the three files fails. A pass here
     would mean the byte-equality assertions are vacuous (checking
     something other than the file's actual content), which is exactly
     what D18 exists to catch.

**Verification probe:** run `node --experimental-strip-types
src/vectors/gen.mts` twice into two temp files and `diff` them — YES = empty
diff (determinism, the property step 1 exists for). `npx vitest run
src/test/signing.test.ts src/test/merkle.test.ts
src/test/dleq-keccak.test.ts` — YES = exit 0, including the new
vector-equality assertions from step 6. Then step 8's three-part gate,
each independently YES/NO and each a hard blocker on its own — no
partial-credit combination of the three counts as phase-green.

**Dispatch:** agent (workhorse, high) — mechanical once tasks 1, 2, 3, 5, 6,
and 8's builder functions exist (this task calls them, it does not
reimplement their logic), but touches every artefact type and is the one
place cross-repo parity either holds or silently doesn't.

## Phase-boundary verification

Gate type: **technical-auto** — every probe below is a literal command.

1. **YES/NO — full suite green.** Run `npm test` (package.json's `test`
   script, confirmed 2026-08-17: `"test": "vitest run"`). YES = exit code 0.
   Baseline, confirmed by an executed `npm test` run 2026-08-17: **278
   passing, 23 files, exit 0.** The phase is green if the post-phase run
   exits 0 with a passing count **≥ 278** (the delta being this phase's own
   new tests across tasks 1-10).
2. **YES/NO — new modules exist and are typed.** `npx tsc --noEmit -p
   .` (probe its existence first: `cat package.json` shows `typescript` as
   a devDependency and `tsc` is available via `npx`; confirm a `tsconfig.json`
   exists at repo root before relying on this — `ls tsconfig.json`). YES =
   exit 0, no new type errors from the six new `src/core/*.ts` files or the
   `Msg`/`Game` signature changes.
3. **YES/NO — golden-vector tests are real, not vacuous (P1-1, fix round
   1 — running `vitest` alone is not this gate).** Three parts, all
   required:
   - `npx vitest run src/test/signing.test.ts src/test/merkle.test.ts
     src/test/dleq-keccak.test.ts src/test/receipt.test.ts
     src/test/marker.test.ts src/test/signed-action.test.ts
     src/test/write-ahead.test.ts src/test/hand-number.test.ts` — YES = all
     exit 0, no skipped tests.
   - `grep -l "p1-vectors.json" src/test/signing.test.ts
     src/test/merkle.test.ts src/test/dleq-keccak.test.ts` — YES = all three
     files match (each one actually references the committed vector file,
     not a coincidentally-agreeing hardcoded literal).
   - Mutation probe (same check as task 10 step 8's, restated here as the
     phase-boundary's own gate rather than assumed inherited): flip one
     byte in a scratch copy of `p1-vectors.json`, rerun those three test
     files against it, confirm at least one assertion in each fails, then
     discard the mutated copy. YES only if all three fail on the mutation —
     a pass here means the check is vacuous.
3a. **YES/NO — D18 vector self-consistency (B4, fix round 1).** `sha256sum
   -c` against the hashes task 10 recorded in its own commit message,
   run against the actually-committed `src/vectors/p1-vectors.json` and
   `src/vectors/Vectors.sol` — YES only if both report `OK`. A missing
   file or a hash mismatch is a **gate FAILURE**, never a fallback pass —
   there is no "vectors will sync later, proceed anyway" path in this
   document, per D18.
4. **YES/NO — no task in this document instructs a chain interaction
   (P1-3, fix round 1 — reframed from a git-diff grep, which cannot prove
   this: a chain command run out-of-band during execution leaves no diff
   artifact to grep against).** This is a property of the plan text itself,
   checked by construction: `grep -niE "forge (test|script|create)|
   hardhat|RPC_URL|--broadcast|vm\\.(envUint|rpcUrl)" phase-1-protocol-
   substrate.md` against this document — YES only if every match found is
   inside a *citation* (a probed fact about another repo, e.g. task 10 step
   4's reference to the vault prototype's own `.sol`-rendering command) and
   never inside an instruction this document's own Steps tell an
   implementing agent to run. None of this document's ten tasks' Steps
   sections currently instruct `forge`, `hardhat`, an RPC call, or a
   broadcast — this phase's only executable commands are `npm test`,
   `npx vitest run ...`, `npx tsc --noEmit`, `node --experimental-strip-
   types src/vectors/gen.mts`, and read-only `grep`/`sha256sum`/`diff`
   probes, all local and offline.
5. **YES/NO — D14 audit passes (M5).** Task 9 step 3's three individual
   distinct-marker greps (`marker-pk hello-match`, `write-ahead signing`,
   `refuse-on-cleared-storage`) each return at least one matching file —
   three separate YES/NO checks, not one summed count.

## Outputs to next phase

**To P2 (money-frame, vault repo) — verifiable claims it can cite:**
- `src/core/receipt.ts`'s `buildReceiptPreimage`/`receiptHash` and
  `src/core/marker.ts`'s `buildMarkerPreimage`/`markerHash` are the exact
  byte layouts `Channel.sol`'s verifier must reproduce — formats §3/§4,
  unchanged from this document's task 1 preimage builder.
- `src/core/signing.ts`'s byte-reorder fix (task 1 step 4) is the shape
  P2's new raw-digest recovery routine (AF-2: "not a reuse of `_recover`")
  must accept — 65 bytes `r ‖ s ‖ v`, low-s, no EIP-191 prefix.
- Test evidence: `src/test/receipt.test.ts`, `src/test/marker.test.ts`,
  `src/test/signing.test.ts` passing is the client-side half of formats
  §3/§4/§1's contract; P2's contract-side tests are the other half and are
  not this phase's job to write.
- The `(0,0)` mandatory-receipt gate (task 8 step 2) exists client-side;
  P2's settlement logic can assume a well-behaved client never dealt without
  one, but must not assume the contract can *verify* that fact without a
  filing (P3's job).
- **Per D16:** `src/vectors/p1-vectors.json` and `src/vectors/Vectors.sol`
  (task 10) are the committed source of truth for every artefact this phase
  defines. P2 copies both into the vault repo and gates its own forge
  suites on `sha256sum` equality against the poker repo's copy — task 10's
  commit message carries the hashes P2 checks against; P2 does not
  re-derive the vectors independently.
- **Per B1 (fix round 1):** P2's own fields were already wei; this phase's
  addition is that `src/core/receipt.ts`'s `hostStack`/`guestStack`/
  `hostDeposit`/`guestDeposit` are wei too, so `Channel.sol`'s side needs no
  new unit handling — P2 should add only a one-line note confirming this
  where its own receipt-consuming code is documented, not a conversion.

**To P3 (disputes-evidence, vault repo) — per B1's ruling on chip/wei space:**
- P3's `BettingReplay` seeds from **chip-space**: the marker's `sb`/`bb`
  (task 5, unconverted chips) plus a chips view of the receipt-baseline
  stacks (the inverse of task 8's `chipsToWei` — P3 divides back by the
  same `(0,0)`-fixed `weiPerChip` rate task 8 computes and a marker/receipt
  pair together carry enough information to recover). The settlement
  overlay P3 computes from a replayed hand converts back to **wei** via
  that same fixed rate before touching `Channel.sol`'s payout arithmetic.
  P1 does not implement this reverse conversion (no replay exists in this
  phase) — task 8 step 3's `weiPerChip`/`chipsToWei` are the two functions
  P3 needs; a rate-inversion helper (`weiToChips`) is P3's to add if the
  forward pair does not already suffice for its direction.
- Per D18, P3 consumes P2's already-landed copy of the vectors (not P1's
  directly) and re-runs `sha256sum -c` against it as its own gate.

**To P6 (client-chain, poker repo) — precise handoff:**
- `src/core/marker.ts` builds and both-signs the marker; P6 adds the
  **posting** transaction and the **deal-gate read** (waiting on-chain
  confirmation) — this phase deliberately stops at "both-signed and
  persisted."
- `src/core/dleqKeccak.ts`'s `proveDleqKeccak` is ready for P6 to call when
  posting shares in a dispute; P1 does not call it outside tests (no share
  is posted in this phase).
- Two of D14's five load-bearing rules are P6's to carry, not P1's: "hole
  shares born only by a completing action" (a posting-timing rule, not a
  construction one) and "deal gate pause" (needs the chain read P1 doesn't
  have). This document's task 9 audits only the three P1 does carry
  (write-ahead, refuse-on-cleared-storage, marker-pk hello-match refusal) —
  flagged explicitly so the arc-end review doesn't expect five comments from
  this phase's diff.
- `handRef`/button recovery (task 4) currently implements only the
  local-storage leg of spec §9.1's two-source recovery order; the marker-
  floor leg needs P6's chain read. Task 4's refuse-to-resume guard is
  therefore **more conservative than the spec's final state** — a client
  with no local receipt refuses to resume even when a marker floor exists
  on chain that could have recovered it. This is safe (never resumes on
  wrong information) but will make P6's job include *loosening* this guard,
  not just adding a chain read to it.

## Open questions

1. **Button's wire source before a marker exists.** Task 4 step 3 proposes
   adding `button` to the existing `newhand` message as a bridge for hand 1
   (which has no prior marker). Default: implement it that way. Overrule:
   whoever drafts P6, if the marker-first-hand ordering ends up making the
   bridge unnecessary (e.g. if a marker is required to exist even for hand
   1 before any card deals, in which case `newhand`'s `button` field is
   redundant and should be removed rather than shipped).
2. **Session-key exchange message.** Task 6 step 5 flags reusing `hello` to
   also carry the session public key, versus a separate exchange. Default:
   reuse `hello` (fewer round trips, and both are per-match, exchanged-once
   values) but keep the two keys as visibly separate fields (`cardPk`,
   `sessionPk`) rather than merging their *lifetimes* — spec §6's "neither
   rule may be harmonised" is about persistence/destruction rules, not about
   how many wire messages carry the keys. Overrule: P2, if registration
   (which needs the session key at `open`/`join`, before any `hello` is
   possible) makes `hello` too late in the sequence — in that case the
   session key must be known and registered before the match's first
   `hello`, and this phase's exchange becomes redundant confirmation rather
   than the first exchange.
3. **Session-key persistence format pending P6's encryption.** D2 assigns
   "P1 uses the keypair locally," "P6 adds §6's encrypted persistence."
   Default: P1 persists the session private key unencrypted in
   `localStorage` (keyed by session id, mirroring task 7/8's stores), with a
   `// TODO(P6): encrypt under a wallet-derived key, spec §6` comment at the
   write site — session-key survival across a reload is needed for write-
   ahead continuity within this phase's own scope (the same key must keep
   signing across a reload for the chain to stay verifiable), but the
   hardening is explicitly deferred. Overrule: if leaving a real secp256k1
   private key in plaintext `localStorage` for even the pre-P6 window is
   judged unacceptable, P1's fallback is keeping the session key in memory
   only (regenerated per tab load) and accepting that a mid-match reload
   loses the ability to sign further actions until P6 ships — worse
   ergonomics, no plaintext-key exposure. Whoever runs P1 should raise this
   rather than silently picking the plaintext path if it feels wrong in
   review.

## Recovery

- **`Game`'s constructor signature change breaks call sites silently.**
  Task 4 adds a required `button` argument; any test or call site
  constructing `Game` positionally (not all do — some use named config)
  will pass the wrong thing to the wrong parameter without a type error if
  the new parameter's type coincides with an existing one's. Mitigation:
  task 4's step 4 explicitly greps `new Game(` across `src/test/` before
  touching the signature; recovery if missed is a fast, loud test failure
  (wrong button → wrong blinds → an existing `posts blinds and gives the
  button first action preflop` assertion in `e2e.test.ts` fails
  immediately), not a silent bug.
- **Worker respawn loses in-flight signing state.** `spawnWorker`
  terminates and recreates the worker every hand (`useGame.ts:1077`,
  `workerRef.current?.terminate()`). Task 6/7's hand-scoped chain state
  (`seq`, `prev`) must be reconstructed from the marker (task 5) on each new
  worker's `init`, not assumed to survive in worker memory — this is
  already the natural design (each hand's chain starts fresh at `prev₀ =
  markerHash`), but a recovery path exists if it is not: reread the
  persisted marker (task 7's store) and rebuild `seq`/`prev` from the
  action tip rather than from worker memory.
- **`vaultInfoRef` not yet populated when the first artefact needs
  signing.** `contractAddress`/`chainId` arrive via the existing Buyin
  `postMessage` handshake (`useGame.ts:958`), asynchronously, and the
  existing `vaultMaybeSign` already guards on `!info.contractAddress ||
  info.chainId == null`. Task 1/5/6/8's signing calls need the same guard —
  if a receipt/marker/action needs signing before Buyin has said hello, the
  correct behaviour is to hold the artefact unsigned and retry once
  `vaultInfoRef` populates (mirroring the existing pattern), not to sign
  with placeholder values. If this stalls play in the non-Vault (`vaultOn
  === false`) path, the recovery is a fixed local `contract`/`chainid` for
  that path only — flagged here rather than assumed, since P1 has not
  established what "no vault" mode should bind artefacts to.
- **The vector generator (task 10) is deterministic by construction, and a
  regression here is silent otherwise.** If a future edit to any of the six
  builder modules reintroduces nondeterminism (a stray `randScalar()` or
  `crypto.getRandomValues()` call where a fixed test key belongs), the
  generator will emit different bytes on every run, `sha256sum` equality
  with the vault repo's synced copy will drift, and nothing in `npm test`
  alone catches it. Recovery: task 10's own probe (run the generator twice,
  diff the output) is the check that exists specifically for this; it
  should run in CI alongside `npm test`, not just once at drafting time.
- **`depositWei` has no real source until P2/P6 land a chain read (B1).**
  Task 8 step 3's `weiPerChip` rate needs an actual wei figure this phase
  cannot read; if `(0,0)` signing is reached with only a placeholder value
  (the same guard pattern as `vaultInfoRef`, two bullets up), every receipt
  in that match carries a rate nobody outside a test can verify against a
  real deposit. This is safe as long as the placeholder path never runs in
  a real Vault-connected match — enforced by the same `vaultOn`/
  `vaultFunded` guards `beginMatch` already has (`useGame.ts:1160-1188`);
  it is not safe if a future edit lets `(0,0)` sign before a real deposit
  figure exists in the Vault-connected path. Recovery if that happens: the
  same refuse-and-retry pattern as the `vaultInfoRef` bullet, not a silent
  fallback to `rate = 1`.
