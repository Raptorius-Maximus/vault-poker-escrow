# Phase 5 — buyin-ui (vault repo, plain JS)

## Goal

Extend Buyin — the existing local escrow UI at `src/main.js` / `public/` —
to run V2 cash sessions **alongside** V1, without touching a single V1 file
(D11/D13). Concretely: a declared-depth "set the table" handshake with the
bond shown next to its consequence before either deposit (spec §2/§2.1); a
session-key registration flow driven by a wallet `personal_sign` (formats
§6); deposit/rebuy with the "not chips yet" explanation surfaced (spec §3);
an "open a dispute" button that auto-files every §5.2 duty it can reach the
moment the window is open (spec §5.1: "no expertise required"); a status
display of the window's two phases with real timestamps; settlement-outcome
copy for the states AF-4 actually rules on (zero-filings full refund;
per-duty bond fate), with the richer §5.3 rows behind `TBD-P3-ROWS` and the
phase-2 continuation behind `TBD-P4-CONTINUATION`; a bare-address recovery
page (spec §6); pull-payment `withdraw()`; and a gas-reserve warning (spec
§8.6).

**This phase's real ceiling, stated plainly:** P2 ships the money frame this
UI drives, but P3 (dispute evidence) and P4 (phase-2 continuation) have not
shipped — their contract surfaces still `revert NotYetBuilt()`. P6 (poker
repo) has not shipped either — nothing on the poker side yet sends this
phase's new postMessage types. So this phase builds every screen the pinned
interfaces support today, wires the seam P6 will fill in, and makes the gaps
visible and graceful rather than pretending they're closed. The
phase-boundary floor (below) is scoped to what P2 alone makes true.

## Inputs from previous phase

**From P2 (money-frame, checked, in revision) — cited, not re-derived:**

- The Session interface exactly as artifact-formats §9 pins it:
  `open(session, opponent, maxHost, maxGuest, sessionKey, walletSig) payable`,
  `join(session, sessionKey, walletSig) payable`, `cancelOpen(session)`,
  `deposit(session) payable` — plus P2's additive
  `fileMarkerWithReceipt(...)` (not a breaking change to the pinned shapes).
- **The bond formula, decision 1, verbatim**, including its worked case
  (`M_host=1500, M_guest=500 → bondHost=1650, bondGuest=1100`):

      ceilDiv(a, b) = (a + b - 1) / b
      avgCeil       = ceilDiv(M_host + M_guest, 2)
      base_i        = max(avgCeil, M_i)
      bond_i        = ceilDiv(11 * base_i, 10)

- **The two-transaction good ending (decision 4)**: file a `final` receipt
  via `fileReceipt`, then call `resolve()` — P2's own flagged deviation from
  V1's single-call `closeCooperative`. This phase's task 6 drives both.
- **The dispute-filing interface (artifact-formats §9)**: `openDispute`,
  `fileReceipt`, `fileMarker`/`fileMarkerWithReceipt`, `fileActions`,
  `postShares`, `phase2Act`, `resolve`, `withdraw`. Per P2's decision 10,
  `fileActions`/`postShares`/`phase2Act`, and `resolve`'s marked-live-hand
  branch, revert the named custom error `NotYetBuilt()` until P3 replaces
  the stub bodies — the exact signatures do not change under P3, so this
  phase's calls against them are forward-compatible, not throwaway.
- **AF-4's ruling (`review-findings.md`)**, the only dispute *outcomes* this
  phase can honestly render: zero filings at `markedHand == 0` → full refund
  including both bonds (never-started semantics); one or more filings at
  `markedHand == 0` → per-duty bond fate (filer's own bond returns, a
  full-window-absent counterparty's bond burns) — **never** a both-burn.
  Everything reachable once `markedHand > 0` is P3/P4's `NotYetBuilt()`
  territory (`TBD-P3-ROWS`).
- **No deployed address yet.** D11/D13: deployment is P7-only. This phase
  builds against the compiled ABI shape the pinned interfaces above commit
  to; the literal, field-exact ABI is reconciled against
  `contracts/out/ChannelV2.sol/ChannelV2.json` once P2 lands for real (P2 is
  "in revision" as of this doc's drafting — `README.md`'s Status block).
- **P2's read surface is not fully pinned.** P2's task 1 step 3 declares a
  growing `Session` struct ("a struct is fine") without stating whether the
  storage mapping is `public`, and without naming individual getters for
  `window`/`bank`/`grace` (stored `immutable`) or `credits` (a public
  mapping per P2 task 6 step 1 — that one *is* named `public`
  explicitly). **This phase assumes the V1 precedent carries over**: V1's
  `mapping(bytes32 => Session) public sessions` (`Channel.sol:45`) and
  `uint256 public immutable defaultWindow` (`Channel.sol:44`) are exactly
  the pattern D15 already commits to needing externally ("P7's deploy
  prints which duration set each instance carries"). Marked
  **`TBD-P2-GETTER-ABI`** everywhere this phase reads a P2 storage field —
  resolved mechanically, not by guessing, once `contracts/out/ChannelV2.sol/
  ChannelV2.json` exists (task 1 step 1).

**From P1 (protocol substrate, poker repo, checker-revision in flight) —
cited, not re-derived:**

- `src/core/signing.ts` (session keypair; the address form is what crosses
  to Buyin, the private key never does — D2), `src/core/receipt.ts`,
  `src/core/marker.ts`, `src/core/signedAction.ts` (the three artefact
  builders formats §3/§4/§5 pin), `src/core/actionStore.ts` (write-ahead
  persistence, keyed `vault:action:${sessionId}:${hand}`) and the
  equivalent receipt/marker persistence task 8 builds (key pattern not
  pinned in P1's doc; not needed here — see below), `src/core/dleqKeccak.ts`
  (share proofs for `postShares`).
- **P1's own doc already names the seam this phase must extend**: task 8
  step 6, verbatim — "The buyin-origin copy is out of scope for this
  poker-repo phase — P1's job is to make the receipt available to forward,
  via the existing cross-origin bridge (`useGame.ts`'s periodic `postMessage`
  to `vaultWindowRef` …); add the latest receipt to that same payload. P2
  \[sic — the vault-repo UI work, this phase\] is responsible for Buyin
  actually writing it to its own `localStorage` on receipt." This phase
  (task 2) is where that responsibility lands.
- **P1 does not pin the exact wire shape of the forwarded bundle** (it only
  commits to "the latest receipt" riding the existing periodic payload).
  This phase therefore *defines* the wire shape it needs (task 2) and marks
  it **`TBD-P1-EVIDENCE-SHAPE`** — P6 (poker repo, which actually writes the
  sending side) either matches it or amends it; this is not this phase's
  interface to unilaterally freeze on the poker side.
- **The `vaultInfoRef`/`vault:hello` handshake this phase extends**:
  `poker/src/useGame.ts:949-972` (the `vault:hello` listener),
  `poker/src/useGame.ts:958` (`vaultInfoRef.current = { contractAddress,
  chainId, host, guest }`, the line the phase-5 dispatch brief named
  specifically). All 8 real message types, grepped 2026-08-17
  (`grep -n "vault:" poker/src/useGame.ts poker/src/ui/App.tsx`,
  `src/main.js`): `vault:hello` (Buyin→poker), `vault:opponent`,
  `vault:progress`, `vault:sent`, `vault:peer-sent`, `vault:confirmed`,
  `vault:focus-poker`, `vault:result`. **Not all eight resend on a cycle**:
  only `vault:hello`, `vault:opponent`, `vault:progress`, and `vault:result`
  fire repeatedly, tied to the ~4s hello cycle or a repeat-safe idempotent
  send; `vault:sent`, `vault:peer-sent`, `vault:confirmed`, and
  `vault:focus-poker` are genuinely one-shot, fired once per real event
  (a transaction broadcasting, confirming, or a focus request), because
  re-sending them on a timer would misrepresent a past event as still
  happening. (`OVERVIEW.md:166-167`'s "anything sent once is a bug waiting
  to happen" reads as a blanket claim about all of these; it is inherited
  drift from that document, not re-asserted as fact here.) This phase's two
  new message types (task 2) are designed by analogy to the four that
  *do* resend — specifically `vault:opponent` (a value the receiver may not
  have had yet, safe to overwrite idempotently, per-hello) and
  `vault:progress` (a status snapshot, safe to overwrite) — since a session
  key and an evidence bundle are both standing state, not one-shot events,
  and both should self-heal the same way a missed `vault:opponent` does.

**Live source read for this doc**: `src/main.js` (1413 lines — the whole V1
app: connect, open/join, active/dispute, close, plus every UX lesson in its
comments), `src/abi.js`, `src/deployments.js`, `build.mjs`, `server.mjs`,
`public/index.html`, `contracts/src/Channel.sol` (191 lines, V1, for the
`_recover`/pull-payment/getter conventions this phase mirrors),
`OVERVIEW.md` (hosting, postMessage catalogue, the two shipped-bug
writeups), `docs/arc-history.md` (V1's shipped-bug paragraph). `viem@2.55.13`
(`node_modules/viem`) confirmed 2026-08-17 to export `encodePacked`
(`_esm/index.js:62`; string values become raw UTF-8 bytes with no length
prefix — `_esm/utils/abi/encodePacked.js`, matching `abi.encodePacked`
semantics exactly, which is what formats §1's preimages need) and
`walletClient.signMessage({account, message:{raw: digest}})` performing
`personal_sign` with the EIP-191 wrap applied to the raw digest
(`_esm/actions/wallet/signMessage.js:5,50-68` — matches formats §1's
wallet-signed-artefact convention exactly). `viem/chains` exports `foundry`
(chain id 31337) at `_esm/chains/index.js:229`, needed for the local-anvil
floor probe. `~/.foundry/bin/anvil` confirmed present and running
(`anvil --version` → `1.7.1`, 2026-08-17).

**No JS test framework exists in this repo.** `package.json`'s only scripts
are `build` (esbuild) and `start` (the static server) — no `vitest`, no
`jest`, no DOM-testing library. Per this phase's own scope rule, this is not
silently invented: verification below is build-green (`npm run build`),
grep-based structural probes over the built source, small `node -e` scripts
exercising this phase's pure (non-DOM) modules directly, and an
**operator-run two-tab local-anvil smoke** as the phase-boundary floor.
Recorded as Open question 4.

## Files touched

**Created:**
- `public/v2.html` — new entry point for V2 sessions (copies V1's inline
  `<style>` block verbatim rather than sharing it — this app has no CSS
  module system, and a shared stylesheet would let a V1 style edit silently
  ripple into V2 or vice versa).
- `public/v2-recover.html` — the bare-address recovery page (task 7).
- `src/mainV2.js` — the V2 app's state/render loop, mirroring `src/main.js`'s
  shape (no framework, one file, module-level state) but for V2 sessions
  only.
- `src/mainV2Recover.js` — small entry for the recovery page (task 7).
- `src/abiV2.js` — `ChannelV2`'s ABI, hand-mirrored per `src/abi.js`'s
  convention. The read-surface functions are `TBD-P2-GETTER-ABI` until
  reconciled against the compiled contract (task 1 step 1).
- `src/deploymentsV2.js` — empty (`{}`) until P7's Base Sepolia deploy,
  mirroring `src/deployments.js`'s shape; the operator adds a local `31337`
  entry by hand for this phase's own floor probe (never committed as a real
  deployment record).
- `src/bondV2.js` — pure reimplementation of P2 decision 1's bond formula
  in JS `BigInt`, so the UI can show the bond before any transaction.
- `src/evidenceStoreV2.js` — pure, storage-parameterised localStorage
  wrapper for the evidence bundle this phase relays from poker (task 2).
- `src/autofileV2.js` — pure planner: evidence bundle + known on-chain
  state → the list of dispute-filing calls still owed (task 5).

**Modified (twice, by two different tasks — see each task's own steps):**
- `build.mjs` — task 1 converts `entryPoints` to the array-of-objects form
  (`{in, out}` pairs) with `outdir: 'public'`, adding exactly one new entry,
  `mainV2.js` (two entries total: `main.js` and `mainV2.js`). `src/main.js`'s
  own build path is unchanged byte-for-byte (task 1 step 4's probe checks
  this). Task 7 later adds the third entry, `mainV2Recover.js`,
  unconditionally — task 7 does not check whether task 1 already added it,
  because task 1 never does.

**Untouched (D11/D13 — verified by task 8's probe, not just claimed):**
`src/main.js`, `src/abi.js`, `src/deployments.js`, `public/index.html`,
`server.mjs`.

## Design decisions pinned here (binding on every task below)

**1. Routing: a separate HTML entry point, not a query-string branch inside
`index.html`.** V1's `main.js` is one continuous render loop keyed on chain
`status`; splicing V2's declared-depth handshake and dispute machinery into
that same function would risk exactly the kind of entanglement D11 forbids.
A second static page (`v2.html`) served by the same unmodified `server.mjs`
(which already serves anything under `public/` — no server change needed)
keeps the two apps textually separate. **This is this phase's own call, not
handed down by any prior phase** — flagged as Open question 6, overridable
by P6/P7 if a query-param split turns out easier for the poker client's
Buyin-button code to target.

**2. The `?sessionkey=` URL bridge — a deliberate stand-in for P6, not a
permanent feature.** Session-key registration (task 3) needs the session
key's *address* from the poker tab, which today only exists once P6 ships
the sending side of task 2's new postMessage types. Rather than block this
phase's own testable surface on P6, this phase reuses V1's exact precedent:
`src/main.js`'s `opponentParam`/`prefilledOpponent`/`applyOpponentFromPoker`
pattern (a URL param read once at load, immediately superseded by the first
real `postMessage` from poker, never re-asserted after the tab has touched
it — `main.js:59-77,385-401`). `?sessionkey=0x…` fills the same role for the
session-key address. This is what makes this phase's operator-run floor
probe executable without P6 existing yet (Phase-boundary verification,
below) — and it stays useful afterward for the same reason the opponent
param does: a Buyin tab opened before poker's hello arrives.

**3. Evidence relay is additive to the existing hello cycle, not a new
timer.** Task 2's `vault:evidence-v2` message rides the same per-hello
resend discipline `vault:opponent` and `vault:progress` already use (Inputs
section, above — not all poker→Buyin messages resend, but the standing-state
ones this design is modelled on do). Justified by two real shipped bugs:
the dead-window signature-delivery bug, documented in
`docs/arc-history.md`'s V1 paragraph; and Buyin's own once-only-hello bug —
`sendHelloToOpener` used to dedupe an unchanged hello and send it exactly
once per session, which was "the actual bug behind 'the vault does not come
up automatic'" (its own code comment, `src/main.js:220-230` — this one is
not in `arc-history.md`, which covers only the dead-window and
hardcoded-127.0.0.1 bugs). No new interval, no new liveness assumption.

**4. Dispute-filing calls are driven sequentially, never in parallel.**
Task 5's auto-filer issues one `withBusy`-wrapped write at a time. Two
wallet popups racing for the same page is a worse failure mode than a slower
one-at-a-time queue — the exact reasoning `src/main.js`'s own `withBusy`/
`pendingSeq` machinery already encodes for V1's single-write-at-a-time model
(`main.js:757-877`); this phase reuses that machinery rather than inventing
a second one.

**5. `NotYetBuilt()` is an expected interim state, not an error.** Every
call this phase makes against `fileActions`, `postShares`, `phase2Act`, or
`resolve`'s marked-live-hand branch will revert with P2's named custom error
until P3 ships. `explainFailure` (task 3 step 7, task 5 step 5) gets a
dedicated branch for it — distinct from the generic "wrong moment" copy —
because conflating "this isn't built yet" with "you did something wrong" is
exactly the kind of unreadable-error failure `explainFailure` already exists
to prevent for V1 (`main.js:786-821`'s own comment explains why).

## Tasks

**Base ref for isolation gates (D17).** Every V1-untouched gate in this doc
uses `git diff 1c10e9c..HEAD -- <paths>`, never `--stat` and never
`git status` — both compare the worktree to the index and read empty the
moment changes are committed, which is vacuous under D13's commit-to-master
flow (exactly D17's concern). `1c10e9c` is the commit this phase's
implementation starts from: run `git rev-parse HEAD` in the vault repo
immediately before task 1's first edit, record the literal SHA here in this
doc (replacing every `1c10e9c` placeholder below with it), and use
that recorded value for every isolation gate for the rest of this phase,
including the operator-run floor's own V1-isolation checks.

### Task 1 — V2 app scaffold and chain wiring

**Goal:** a working, empty-shell V2 Buyin page — connect wallet, read a
`ChannelV2` session, render a status line — with zero edits to any V1 file.
The skeleton every later task's screens hang off.

**Files:** `public/v2.html` (new), `src/mainV2.js` (new), `src/abiV2.js`
(new), `src/deploymentsV2.js` (new), `build.mjs` (modified).

**Steps:**
1. **Resolve `TBD-P2-GETTER-ABI` mechanically, not by guessing further.**
   `ls contracts/out/ChannelV2.sol/ChannelV2.json` — if P2 has landed by the
   time this task runs, read the compiled `abi` array directly and hand-copy
   the exact function/getter signatures into `abiV2.js`, exactly as
   `src/abi.js`'s own header comment already documents doing for V1 ("Keep
   in sync by hand — there is no build step that ties the two together").
   If P2 has not landed yet, ship `abiV2.js` against this doc's own pinned
   surface (Session interface + dispute-filing interface, both verbatim from
   artifact-formats §9, plus the `TBD-P2-GETTER-ABI` read functions assumed
   `public` per this doc's Inputs section) and leave a `// TODO: reconcile
   against contracts/out/ChannelV2.sol/ChannelV2.json once P2 lands` comment
   at the top of the file — do not block this task's own dispatch on P2's
   landing order (same pattern P2's own task 8 step 1 used for
   `TBD-P1-VECTORS`).
2. `abiV2.js`: writes — `open`, `join`, `cancelOpen`, `deposit`,
   `openDispute`, `resolve`, `withdraw`, `fileReceipt`, `fileMarker`,
   `fileMarkerWithReceipt` (struct params as inline tuples, field order
   exactly formats §3/§4); reads — `sessions(bytes32)` (assumed `public`
   mapping auto-getter, full struct tuple in P2's declared field order),
   `credits(address) view returns (uint256)` (P2 task 6 step 1 names
   this `public` explicitly — the one read this phase does *not* need to
   guess), `window()`/`bank()`/`grace()` (assumed `public immutable`, V1
   precedent); errors — `'error NotYetBuilt()'` (P2 decision 10's literal
   name), included so viem can decode it on a revert (task 5 step 5). A
   `STATUS_V2` array mirroring `abi.js`'s `STATUS`, values
   `['None','AwaitingGuest','Active','Disputed','Closed']` per P2 task 1
   step 2's enum, order-sensitive — reconcile against the compiled ABI too.
3. `deploymentsV2.js`: `export const DEPLOYMENTS_V2 = {};` — empty object,
   same shape as `src/deployments.js`, a comment citing D11/D13 ("no address
   until P7 deploys") and noting the operator adds a throwaway `31337` entry
   locally for this phase's own floor probe, never committed.
4. `build.mjs`: change to
   `entryPoints: [{in:'src/main.js', out:'bundle'}, {in:'src/mainV2.js', out:'bundle-v2'}], outdir:'public'`
   (drop the single `outfile`) — confirmed 2026-08-17 against esbuild
   0.28.2's documented `{in,out}` entry-point form
   (`node_modules/esbuild/lib/main.d.ts`'s `BuildOptions.entryPoints` type,
   which accepts `{in: string; out: string}[]`) as the way to get two
   independently named outputs from one `outdir` without two separate
   `build()` calls.
5. `src/mainV2.js`: copy `src/main.js`'s wallet-connect / chain-read /
   polling skeleton (`connect`, `switchToDeploymentChain`, `readSession`
   reshaped for the wider V2 tuple, `startPolling`, `render`/`renderScreens`
   scaffold, `el()` helper, `withBusy`/`pendingCard`/`showPending`
   machinery — reused verbatim, this is exactly the "no framework, one file"
   convention to match, not reinvent) — parameterised against
   `CHANNEL_V2_ABI`/`DEPLOYMENTS_V2`/`STATUS_V2` instead of V1's. Add
   `31337: foundry` (from `viem/chains`) to the `CHAINS` map alongside the
   existing `84532: baseSepolia`, for local-anvil testing (this phase's own
   floor probe needs it; it costs nothing in production since no V2 contract
   is deployed to 31337 outside a dev machine).
6. `public/v2.html`: copy `public/index.html`'s `<head>`/`<style>` block
   verbatim (design decision 1), `<script type="module" src="./bundle-v2.js">`.

**Verification probe:** `cd /home/dev/projects/vault && npm run build` — YES
= exits 0, `public/bundle.js` and `public/bundle-v2.js` both exist and
`public/bundle.js`'s content is unchanged from a build immediately before
this task's edit (`git diff --stat -- public/bundle.js` — note
`public/bundle.js` is almost certainly gitignored per `build.mjs`'s own
comment "gitignored, regenerate after any `src/` change"; if so, this
sub-check is not runnable as a git diff and the probe is simply that the
build succeeds and V1's page still loads unchanged, verified by task 8's
grep instead). `git diff 1c10e9c..HEAD -- src/main.js src/abi.js
src/deployments.js` (D17 base-ref form, per the note above) — YES = empty.

**Dispatch:** `agent (workhorse, medium)` — closely mirrors an existing
file; the one new judgment call (the esbuild multi-entry form) is a cited,
confirmed API, not a design decision.

---

### Task 2 — postMessage extension and both-origin evidence store

**Goal:** define and receive the two new poker→Buyin message types this
phase needs (`vault:sessionkey-v2`, `vault:evidence-v2`), and persist what
arrives into Buyin's own `localStorage` — the "both origins" half of spec
§6's recovery story that P1's own doc (task 8 step 6) explicitly left to
this phase.

**Files:** `src/mainV2.js` (message handlers), `src/evidenceStoreV2.js`
(new).

**Steps:**
1. `vault:sessionkey-v2` (poker→Buyin), `TBD-P1-EVIDENCE-SHAPE`: this
   phase's own proposed shape, not yet ratified by P6 — `{ type:
   'vault:sessionkey-v2', v: 1, session, seat, sessionKeyAddress }` — **only
   the address ever crosses**; the private half stays inside
   `src/core/signing.ts` on the poker side (D2, formats §6). Mirrors
   `vault:opponent`'s shape exactly — sent from `poker/src/useGame.ts:735`
   (`w.postMessage({ type: 'vault:opponent', v: 1, session: r.id, address
   }, '*')`, the sender that defines the shape); received on the Buyin side
   at `src/main.js:406-409`. P6 either sends `vault:sessionkey-v2` matching
   this shape or amends it — same status as `vault:evidence-v2` below, not
   a frozen contract this phase has sole authority over.
2. `vault:evidence-v2` (poker→Buyin), `TBD-P1-EVIDENCE-SHAPE`: this phase's
   own proposed shape, not yet ratified by P6 —

       {
         type: 'vault:evidence-v2', v: 1, session,
         host, guest,                          // once known, for task 7's recovery filter
         receipts: [{ hand, subseq, hostStack, guestStack,
                       hostDeposit, guestDeposit, final,
                       sigHost, sigGuest }],    // formats §3 field order, hex strings
         marker: { hand, receiptHash, deckRoot, hostShareRoot, guestShareRoot,
                    hostCardPk, guestCardPk, button, sb, bb,
                    sigHost, sigGuest } | null, // formats §4, latest only
         actions: [{ hand, seq, action, amount, prev, sig }], // formats §5, latest chain
         shares: [{ pos, shareEnc, c, s, shareProof, c1Enc, c2Enc, deckProof }] | null,
       }

   Every numeric/binary field a hex string (JSON has no native bytes/BigInt).
   This is the shape P6 must either match or amend when it wires the sending
   side — recorded here so the coherence pass has something concrete to
   check against, not invented as a frozen cross-repo contract this phase
   has no authority to set alone.
3. Buyin-side handler in `mainV2.js`'s message listener (same
   `event.source !== window.opener` guard V1 already uses, `main.js:403-404`):
   on `vault:sessionkey-v2`, store `sessionKeyAddress` in module state (only
   if `!sessionKeyTouched`, mirroring `opponentTouched`'s "the arriving
   value never overwrites a value the code itself is already using" rule —
   here there's no user typing to protect, but a mid-flow overwrite mid-
   registration would be just as wrong); on `vault:evidence-v2`, call
   `evidenceStoreV2.save(localStorage, session, bundle)` unconditionally
   (idempotent — repeats cost nothing, exactly `vault:progress`'s own
   reasoning).
4. `evidenceStoreV2.js`: `save(store, session, bundle)` (keyed
   `vault2:evidence:${session}`, JSON-stringified), `load(store, session)`,
   `listSessions(store)` — enumerates every `vault2:evidence:*` key via
   `Storage.key(i)`/`store.length` — per MDN's "Storage: key() method" and
   "Storage: length property" (both part of the `Storage` interface every
   `localStorage` implementation exposes; a plain, synchronous integer-index
   enumeration, not an iterator or anything needing a polyfill) — and
   returns the parsed envelopes, used by task 7's recovery page.
5. **No new timer.** Design decision 3: `vault:evidence-v2` rides P6's
   existing hello-cycle send, same as every other poker→Buyin message; this
   phase's receiving code has nothing to poll for.

**Verification probe:** `grep -n "vault:sessionkey-v2\|vault:evidence-v2"
src/mainV2.js` — YES = both message types appear in the listener. A `node -e`
script (documented inline in this task's completion notes, not committed as
a project file, per this repo having no test runner to register it with):
construct a fake `Storage` object (`{ _d:{}, getItem, setItem, removeItem,
key: i => Object.keys(_d)[i], get length(){ return Object.keys(_d).length }
}`), dynamically `import('./src/evidenceStoreV2.js')`, `save` two envelopes
under different sessions, assert `load` round-trips each and `listSessions`
returns exactly two, ordered or unordered as implemented — YES = exact
match, NO = a real defect. `npm run build` exits 0.

**Dispatch:** `agent (session-tier, high)` — this is the cross-repo seam:
`TBD-P1-EVIDENCE-SHAPE` is a real coordination risk (a wrong guess here is
invisible until P6 tries to send against it), and task 5/7 both build on
`evidenceStoreV2.js`'s exact shape.

---

### Task 3 — Declared-depth handshake and session-key registration

**Goal:** the host "set the table" screen (`open()`), the guest "see the
whole table, join or don't" screen (`join()`), and `cancelOpen()` — with the
bond shown next to its consequence before either deposit (spec §2/§2.1) and
session-key registration via wallet `personal_sign` (formats §6).

**Files:** `src/mainV2.js`, `src/bondV2.js` (new).

**Steps:**
1. `src/bondV2.js`, `BigInt` throughout: `ceilDiv(a, b) = (a + b - 1n) / b`;
   `avgCeil(maxHost, maxGuest) = ceilDiv(maxHost + maxGuest, 2n)`;
   `bondFor(mine, other) = ceilDiv(11n * (avgCeil(mine,other) > mine ?
   avgCeil(mine,other) : mine), 10n)` — P2 decision 1, verbatim, cited in a
   comment alongside its worked case.
2. Host screen ("Step 1: set the table"): two amount fields — "the most
   you might ever put in" (`maxHost`) and "the most they might ever put in"
   (`maxGuest`) — plus a "put in now" field capped client-side at `maxHost`.
   Recompute both bonds live via `bondV2.js` on every keystroke, so the
   consequence text is on screen before any button is even enabled. Render,
   **verbatim-equivalent to spec §2/§2.1** (both sentences, every time,
   before the Open button):
   - *"Your bond is {bondHost} — 110% of the deeper of half the table or
     your own declared max. It's held separately and only ever burns; it
     never goes to your opponent."*
   - *"Play deeper than you declared and the table simply won't credit it —
     reopen at a bigger table instead."*
   - *"If you desert this session, you lose this."*
3. **Session-key registration.** Read `sessionKeyAddress` from task 2's
   handler (or the `?sessionkey=` URL param per design decision 2, until
   poker's real message arrives and supersedes it — same precedence rule as
   `applyOpponentFromPoker`). If absent, disable the Open button with
   *"Waiting for your poker table to tell us your session key…"* rather than
   letting the click silently fail. Build the registration hash:

       hash = keccak256(encodePacked(
         ['uint8','string','address','uint256','bytes32','address','address'],
         [0x04, 'vault/sessionkey/v2', deployment.address, BigInt(chainId),
          sessionId, account, sessionKeyAddress],
       ))

   exactly formats §6's field order, using viem's `encodePacked` (confirmed
   2026-08-17: `string` values become raw UTF-8 bytes with no length prefix,
   matching `abi.encodePacked(string)` — `node_modules/viem/_esm/utils/abi/
   encodePacked.js`). Obtain the wallet signature via
   `walletClient.signMessage({ account, message: { raw: hash } })` —
   confirmed 2026-08-17 (`node_modules/viem/_esm/actions/wallet/signMessage.js:5,50-68`,
   viem 2.55.13): this performs `personal_sign` and applies the EIP-191
   prefix to the raw digest, exactly formats §1's wallet-signed-artefact rule.
4. `open(sessionId, opponent, maxHost, maxGuest, sessionKeyAddress, walletSig)`
   with `value = depositNowHost + bondHost` — mirrors `main.js`'s
   `openChannel` (`main.js:879-890`) in shape, wider argument list.
5. Guest screen: reads `maxHost`/`maxGuest`/`bondGuest` off `sessions()`
   (`TBD-P2-GETTER-ABI`), renders the same two required sentences plus the
   full table ("your opponent can put in up to {maxHost}, you up to
   {maxGuest}"), a deposit-now field capped at `maxGuest` client-side (the
   real cap is the contract's, D4 — this is UX only), registers its own
   session key the same way as step 3, calls
   `join(sessionId, sessionKeyAddress, walletSig)` with
   `value = depositNowGuest + bondGuest`.
6. `cancelOpen(sessionId)` — identical to `main.js`'s `cancelOpen`
   (`main.js:905-915`), wired against `CHANNEL_V2_ABI`.
7. `explainFailure` additions (extend task 1's copied function): a
   `"below bond"` branch ("That doesn't cover the bond this table needs —
   check the amount and try again"), a `"past declared max"` branch (shared
   with task 4's deposit flow), and the `NotYetBuilt` branch per design
   decision 5 (used starting task 5, declared here since this is where
   `explainFailure` first gets extended).

**Verification probe:** `node -e` script importing `bondV2.js`, asserting
`bondFor(1500n*10n**18n, 500n*10n**18n) === 1650n*10n**18n` and
`bondFor(500n*10n**18n, 1500n*10n**18n) === 1100n*10n**18n` (P2 decision 1's
own pin, ETH-scale units) plus the equal-depths case
(`bondFor(1000n, 1000n) === 1100n`) — YES = exact match. `grep -in "the
table simply won't credit it\|if you desert this session, you lose this"
src/mainV2.js` (`-i`: the copy is sentence-cased, not asserting exact
capitalisation) — YES = both present. `npm run build` exits 0.

**Dispatch:** `agent (session-tier, high)` — money-adjacent (the bond
formula and the wallet-signed registration bytes both need to be exactly
right) and the seam P2's decisions 1–3 and formats §6 both bind.

---

### Task 4 — Deposit / rebuy flow

**Goal:** `deposit()`, available any time `status` is `Active` or
`Disputed`, with the "not chips yet" explanation surfaced (spec §3).

**Files:** `src/mainV2.js`.

**Steps:**
1. A deposit field, capped client-side at `maxX - depositedX` (both read
   from `sessions()`), visible whenever `status` is `Active` or `Disputed`.
2. Copy, verbatim-equivalent to spec §3: *"This tops up what you might play
   with — it isn't chips yet. It becomes chips the next time you both sign
   a receipt naming it. If a hand starts before that happens, this money is
   still safe; it just waits for the next hand boundary."*
3. `deposit(sessionId)` with `value` = the field's amount — same `withBusy`
   pattern as every other write in this app.
4. Reuse task 3 step 7's `"past declared max"` `explainFailure` branch; add
   `"not open for deposits"` (P2 task 2 step 1's revert string) with copy
   *"Deposits aren't open right now — check the session status above."*

**Verification probe:** `grep -n "it isn't chips yet" src/mainV2.js` — YES =
present. `npm run build` exits 0. Functional exercise happens at the
phase-boundary floor (task 8's smoke test includes a rebuy).

**Dispatch:** `agent (workhorse, medium)` — one function and one string,
following task 3's already-established patterns.

---

### Task 5 — Dispute open and duty auto-filing

**Goal:** an honestly-worded "open a dispute" button; from the moment
`status === 'Disputed'`, Buyin auto-files every §5.2 duty it can reach from
task 2's evidence store, on its own, the instant the page loads or the
evidence changes — spec §5.1's "no expertise required" promise, actually
built.

**Files:** `src/mainV2.js`, `src/autofileV2.js` (new).

**Steps:**
1. Dispute-open copy, honest per spec §8 item 1 (not softened): *"This ends
   the rest of tonight's session early. The hand in progress finishes for
   real, under time limits — then the table closes for good. Only open this
   if you mean it."* Behind an explicit confirm click, not a bare button
   (mirrors V1's claim-by-default countdown being a deliberate, named
   action, `main.js:1280-1285`).
2. `openDispute(sessionId)` — same `withBusy` pattern.
3. `src/autofileV2.js`: `plan(bundle, onChainState) → Call[]`, pure. Given
   task 2's evidence bundle and a small on-chain snapshot (whether `(0,0)`
   and each later receipt are already filed, `markedHand`, whether the
   latest marker is filed, whether the action chain tip is filed, which
   share positions are already posted — every one of these reads is itself
   `TBD-P2-GETTER-ABI`/P3-shaped, since P2 doesn't expose per-hand filing
   status as an enumerable read today; where it doesn't, `plan()` degrades
   to "file everything the bundle has and let the contract's own
   idempotence — or its `NotYetBuilt()` stub — decide," which is safe
   because filing something already on file is a no-op revert, not a
   double-spend). Returns an ordered list: `{fn: 'fileReceipt', args: [...]}`,
   `{fn: 'fileMarkerWithReceipt', args: [...]}` if a marker is pending,
   `{fn: 'fileActions', args: [...]}` if an action chain exists,
   `{fn: 'postShares', args: [...]}` if shares exist.
4. Wiring: on every render where `status === 'Disputed'`, call
   `evidenceStoreV2.load` then `autofileV2.plan`, and drive the returned
   calls through `withBusy` **one at a time** (design decision 4), showing
   *"Filing your evidence automatically — {n} of {total}…"*. Re-plan after
   each call lands (the evidence/on-chain state moved) rather than trusting
   a stale plan.
5. `fileActions`/`postShares` will revert `NotYetBuilt()` until P3 ships
   (design decision 5). Catch specifically — Solidity custom errors encode
   on the wire as a 4-byte selector, computed identically to a function
   selector (the first 4 bytes of `keccak256` of the error's canonical
   signature, here `"NotYetBuilt()"`) — <https://docs.soliditylang.org/en/latest/control-structures.html#custom-errors>,
   the same fact `vm.expectRevert(ChannelV2.NotYetBuilt.selector)` already
   relies on in P2's own tests. Add `'error NotYetBuilt()'` to task 1's
   `CHANNEL_V2_ABI` so viem can decode it: on a revert, walk the thrown
   error for a `ContractFunctionRevertedError` and check
   `.data?.errorName === 'NotYetBuilt'` — confirmed 2026-08-17 against
   `node_modules/viem/_esm/errors/contract.js:138-226` (viem 2.55.13):
   `ContractFunctionRevertedError` decodes the revert data against the
   supplied ABI and exposes the matched error's name at `.data.errorName`,
   which is the selector match above happening inside viem rather than by
   hand. Render *"The parts of your evidence that need a marked live hand
   aren't dispute-ready in this build yet — this is a known gap, not a
   problem with what you're holding."* rather than routing it through the
   generic revert copy.

**Verification probe:** `node -e` script exercising `autofileV2.plan(...)`
against three constructed fixtures — (a) nothing filed yet, full bundle →
plans every call; (b) `(0,0)` already on file, nothing else → plans only the
later receipts/marker/actions/shares; (c) empty bundle → plans nothing —
YES = each fixture's plan matches by hand-derivation. `grep -n
"NotYetBuilt" src/mainV2.js` — YES = the selector-matching catch exists.
`grep -in "this ends the rest of tonight's session early" src/mainV2.js` —
YES = the dispute-open honest-cost copy (step 1) is present; this is the
same string the operator-run floor's step 13 reads on screen (P5-2 — the
two halves compose). `npm run build` exits 0.

**Dispatch:** `agent (session-tier, high)` — this is the actual
implementation of spec §5.1's central promise; a silent bug here means the
one thing V2's whole dispute design is supposed to spare a player from
understanding, breaks exactly when it matters most.

---

### Task 6 — Dispute status timeline, settlement outcomes, and withdraw

**Goal:** render the window's phase with real timestamps; render the
settlement outcome once `status === 'Closed'` for the states AF-4 actually
rules on; drive the two-transaction good ending; `withdraw()`.

**Files:** `src/mainV2.js`.

**Steps:**
1. Phase timeline, reading `disputeOpenedAt` and `window()`/`bank()`/
   `grace()` (all `TBD-P2-GETTER-ABI`): before `disputeOpenedAt + window`,
   show *"Evidence window closes at {timestamp}."* At/after it, show
   *"The evidence window has closed — the frozen result is being worked
   out."* (Consolidation has no transaction of its own — P2 decision 5's
   note and spec §5.1 both say so; nothing to click here, it's a state, not
   a step.) A phase-2 appointment timestamp, when one exists, is
   **`TBD-P4-CONTINUATION`** — the birth-anchored per-duty deadlines (spec
   §5.2) live in P4's storage, unreadable by this phase; show *"A decision
   is due from someone — check back once P4 ships an appointment reader"*
   as an honest placeholder rather than a fabricated countdown.
2. Settlement outcomes, `status === 'Closed'`: read `credits[account]`
   (`TBD-P2-GETTER-ABI`, though P2 task 6 names this getter `public`
   explicitly — the one part of this list that isn't a guess) and render
   exactly one of, matched to AF-4's own wording (`review-findings.md`):
   - **Zero filings** (inferable only if this phase can tell — P2 doesn't
     expose `everReceipted`/`markedHand` as named public reads either,
     `TBD-P2-GETTER-ABI`): *"Nobody filed anything before the window
     closed, so the table treats this as never having started — your
     deposit and your bond are both back in full."*
   - **One or more filings, per-duty** (same read dependency): AF-4's rule
     is symmetric in the two players but the copy is not — the connected
     account is either the one who filed or the one who didn't, and both
     directions must actually exist as renderable strings, not one sentence
     plus a hand-waved mirror. Read `hostFiledInWindow`/`guestFiledInWindow`
     (`TBD-P2-GETTER-ABI`) to tell which side `account` is on, then render
     exactly one of:
     - *your own filing duty was met* (`account`'s own `…FiledInWindow` is
       true): *"Your deposit and your bond are back — you did what the
       dispute needed. Your opponent's bond was burned — they didn't file
       anything for the full 24-hour window."*
     - *your own filing duty was missed* (`account`'s own `…FiledInWindow`
       is false, the counterparty's is true): *"Your deposit is back, but
       your bond was burned — you didn't file anything for the full
       24-hour window. Your opponent's bond came back to them because they
       filed."*
     (The fourth combination, both sides' flags true, cannot reach this
     branch at all — task 3 step 7 of P2's doc only ever sets a flag for a
     player who actually filed, and AF-4's per-duty row is reached only
     when at least one side is absent; if P2's actual reads ever show both
     flags true here, that is a P2-side contract bug this phase's UI has no
     business papering over — render the generic `TBD-P3-ROWS` fallback
     below rather than guessing which sentence applies.)
   - **Anything else** (`markedHand > 0` — P3/P4's rows, `TBD-P3-ROWS`):
     *"Settled — see your balance below."* A generic fallback, deliberately
     not pretending to explain a row this phase cannot yet distinguish.
3. Two-transaction good ending: extend the `matchResult`-driven block
   (mirrors `main.js`'s `closeCooperative` card, `main.js:1265-1287`) to (a)
   build a `final` receipt from `matchResult`'s stacks (formats §3, both
   session-key signatures — sourced from the poker side via
   `vault:evidence-v2`'s `receipts` array, the entry with `final: true`),
   call `fileReceipt`; (b) once confirmed, call `resolve()`. One "Finish the
   match" button driving both `withBusy` calls back to back, per P2's
   Outputs-to-P5 note naming this exact deviation from V1.
4. `withdraw()`: a persistent button, shown whenever `credits[account] > 0`,
   disabled/hidden otherwise (task 8's floor probe checks the hidden case).

**Verification probe:** `grep -n "never having started" src/mainV2.js` — YES
= the zero-filings copy is present. `grep -c "didn't file anything for the
full 24-hour window" src/mainV2.js` — YES = **2** (M3: both per-duty
directions render as distinct, real strings sharing this clause, not one
sentence plus a described-but-unwritten mirror). `grep -n "opponent's bond
was burned" src/mainV2.js` and `grep -n "Your bond was burned" src/mainV2.js`
— YES = each finds exactly the one sentence it belongs to (confirms the two
directions are not just present twice by accident, but are the two distinct
sentences this step actually specifies). `npm run build` exits 0. The
two-transaction good ending and `withdraw`'s hidden-at-zero state are both
exercised by task 8's smoke.

**Dispatch:** `agent (workhorse, high)` — long, and every settlement string
here is quoting a specific ledger row (AF-4); precision against
`review-findings.md`'s actual wording matters more than usual for UI copy.

---

### Task 7 — Recovery page

**Goal:** a bare-address recovery screen, no session id required — spec §6:
"the bare address is a recovery page; receipts are stored under both
origins so a returning player is covered wherever they land."

**Files:** `public/v2-recover.html` (new), `src/mainV2Recover.js` (new),
`build.mjs` (modified — this task adds the third `entryPoints` entry,
`{in:'src/mainV2Recover.js', out:'bundle-v2-recover'}`; task 1 adds only
`mainV2.js`, never this one — see Files touched, above).

**Steps:**
1. `src/mainV2Recover.js`: connect-wallet screen only, no `?session=`
   parsing. On connect, call `evidenceStoreV2.listSessions(localStorage)`
   (task 2), filter to envelopes where `bundle.host === account ||
   bundle.guest === account` (case-insensitive address compare, matching
   `main.js`'s existing `.toLowerCase()` convention throughout).
2. Render one card per match found: room id, which seat this wallet holds,
   last-known `status` if the bundle carries one, and a link to
   `v2.html?session=<id>&seat=<host|guest>`.
3. Explicit copy under the list, always shown: *"This only finds sessions
   this browser has kept evidence for. A different browser or a cleared
   profile won't show anything here — that's exactly why receipts also live
   on your poker table's side; if this list is empty, check there instead."*
   (Honest about the limit — the poker-origin half of "both origins" is out
   of this phase's file scope, owned by P1/P6.)
4. `public/v2-recover.html`: same copied `<style>` block, `<script
   type="module" src="./bundle-v2-recover.js">`.
5. `build.mjs`: add `{in:'src/mainV2Recover.js', out:'bundle-v2-recover'}`
   to the `entryPoints` array task 1 already converted to the `{in,out}`
   form — the third entry, unconditionally (Files touched, above; task 1
   never adds it).

**Verification probe:** `node -e` script seeding a fake `Storage` (same
harness as task 2's probe) with two envelopes — one whose `host` matches a
test address, one that doesn't — dynamically importing `mainV2Recover.js`'s
filter logic (extracted as a small exported pure function,
`matchingSessions(envelopes, account)`, specifically so this probe doesn't
need a DOM) and asserting exactly one match — YES = correct filter. `npm
run build` exits 0, `public/bundle-v2-recover.js` exists.

**Dispatch:** `agent (workhorse, medium)` — small, self-contained, and its
one real risk (the filter logic) is made independently probable by pulling
it out as a pure function.

---

### Task 8 — Gas-reserve warning, V1-isolation guard, and copy pass

**Goal:** spec §8.6's gas-reserve warning; the mechanical checks that
D11/D13's untouched-V1 boundary and the no-hardcoded-host rule actually
hold, not just are claimed to.

**Files:** `src/mainV2.js`, `src/mainV2Recover.js`.

**Steps:**
1. Once `status !== 'None'` (the earliest state this app can observe on
   chain — spec §8.6 says "from `(0,0)` onward", and `(0,0)` itself is a
   poker-side receipt this app never sees directly; `status !== 'None'`
   is this phase's closest reachable proxy, flagged as Open question 5),
   read the connected wallet's native balance via
   `publicClient.getBalance({ address: account })` — confirmed 2026-08-17
   against `node_modules/viem/_esm/actions/public/getBalance.js:42`
   (viem 2.55.13; wraps `eth_getBalance`, takes `{address, blockTag, ...}`,
   returns the balance in wei as a `bigint` — <https://viem.sh/docs/actions/public/getBalance>)
   — on every poll tick and show a persistent dim warning under a
   threshold. Copy, verbatim-
   equivalent to spec §8.6: *"Gas is what lets you defend yourself if this
   session ever needs a dispute. Keep some test ETH in this wallet the
   whole time you're playing."*
2. Threshold: no number is pinned anywhere upstream of this phase. Default
   `0.01` ETH-equivalent (a round, visible number, easy for a later phase or
   the operator to change in one place) — Open question 3.
3. `grep -rn "slipgate\|127\.0\.0\.1\|localhost:8790" src/mainV2.js
   src/mainV2Recover.js` — must return nothing (the exact bug class
   `docs/arc-history.md` records for V1: a hardcoded origin worked on one
   machine and failed flatly the moment Loke reached it from a phone over
   the LAN).
4. `git diff 1c10e9c..HEAD -- public/index.html src/main.js
   src/abi.js src/deployments.js server.mjs` (D17 base-ref form — never
   `--stat`, which reads empty once committed, per the note at the top of
   Tasks) — must be empty (D11/D13, mechanically checked, not just asserted
   in prose).

**Verification probe:** both greps above (step 3 = empty output = YES; step
4 = empty output = YES). `npm run build` exits 0.

**Dispatch:** `agent (workhorse, low)` — small, mechanical, and exactly the
kind of check that's cheap to automate and expensive to skip (V1 shipped
with the hardcoded-origin bug once already, per `arc-history.md`).

## Phase-boundary verification

**Gate type: operator-run.** This phase's real floor is a person clicking
through two browser tabs against a local test chain — the only thing this
repo's tooling (no test framework, no deployed contract yet) can actually
prove end to end. Automated probes above the floor are each task's own
(collected below); the floor is the sequence that follows, **run by the
operator, each step YES/NO, exactly as written.**

**Before starting:** these steps assume tasks 1–8 have landed and
`npm run build` has been run once already (task 1's own probe).

1. **Start a local test chain.** In its own terminal window, run:

       ~/.foundry/bin/anvil

   Leave it running. What this does: it starts a free, fake Ethereum
   network on your own machine — no real test ETH, no waiting for Base
   Sepolia, and nothing here can ever touch real money. It prints ten
   ready-funded test accounts and their private keys — you'll need two of
   them in a moment.

2. **Deploy `ChannelV2` to it, with short test durations.** `DeployV2.s.sol`
   mirrors V1's `Deploy.s.sol` exactly (P2 phase doc, task 7 step 6): it
   reads the deploy key via `vm.envUint("PRIVATE_KEY")` and passes it
   straight to `vm.startBroadcast(pk)` inside the script — confirmed against
   `contracts/script/Deploy.s.sol:21,30` — so forge's own `--private-key`
   CLI flag is never consumed by this script and must **not** be passed;
   the key goes in the `PRIVATE_KEY` environment variable instead. In a
   second terminal:

       PRIVATE_KEY=<paste anvil's Account #0 private key here> \
       TEST_DURATIONS=true WINDOW_SECONDS=120 BANK_SECONDS=60 GRACE_SECONDS=60 \
       ~/.foundry/bin/forge script contracts/script/DeployV2.s.sol \
         --root /home/dev/projects/vault/contracts \
         --rpc-url http://localhost:8545 \
         --broadcast

   Anvil printed "Account #0" and its private key in the terminal from step
   1, right below the list of addresses — scroll up in that window to find
   it.

   This deploys the contract with a 2-minute dispute window instead of the
   real 24 hours, so you don't have to wait a day to see the dispute screens.
   Copy the deployed `ChannelV2` address it prints.

3. **Tell Buyin about it.** Open `src/deploymentsV2.js` and add:

       export const DEPLOYMENTS_V2 = {
         31337: { address: '<the address from step 2>', name: 'Local anvil', explorer: null },
       };

   Run `npm run build` again.

4. **Start Buyin.** `npm start` — leave it running. It's serving on
   `http://localhost:8790`.

5. **Set up two test wallets.** In your browser wallet (e.g. MetaMask), add
   a network: RPC URL `http://localhost:8545`, chain ID `31337`. Import two
   *different* private keys anvil printed in step 1 as two separate
   accounts — one will be "the host," one "the guest."

6. **Open the host tab.** Go to:

       http://localhost:8790/v2.html?session=smoketest&seat=host&sessionkey=<any third anvil address, pasted as-is>

   Connect the host's wallet. **YES/NO:** before any deposit button is
   clickable, you can read both of these exact phrases on screen — "if you
   desert this session, you lose this" and "the table simply won't credit
   it" (the same two phrases the automated `grep -in` probe below searches
   for, so a passing grep and a passing look-at-the-screen are checking the
   same thing).

7. Set "the most you might ever put in" and "the most they might ever put
   in" to any two small equal numbers (e.g. `1` and `1`), a small "put in
   now" amount (e.g. `0.1`), and click Open. Approve **two** wallet prompts
   — the session-key registration signature, then the deposit transaction.
   **YES/NO:** the tab settles on a screen that says you're waiting for
   your opponent.

8. **Open the guest tab.** Go to:

       http://localhost:8790/v2.html?session=smoketest&seat=guest&sessionkey=<a fourth anvil address>

   Connect the guest's wallet. **YES/NO:** you can see the whole table —
   both declared maxes and both bond amounts — before clicking anything.

9. Set a "put in now" amount and click Join. Approve the two prompts.
   **YES/NO:** within a few seconds, both tabs show `Status: Active`.

10. On either tab, make a second, smaller deposit (a rebuy). **YES/NO:**
    the "it isn't chips yet" sentence is visible, and the deposit succeeds.

11. On either tab, try to deposit an amount that would push your total past
    the number you declared as your own max in step 7/9. **YES/NO:** it's
    refused with a plain-English message (not a raw wallet error dump).

12. On either tab, look for a Withdraw button. **YES/NO:** it is absent or
    disabled (there is nothing to withdraw yet).

13. On the host tab, click "Open a dispute." Read the confirmation text,
    then confirm it, then approve the wallet prompt. **YES/NO:** the exact
    phrase "This ends the rest of tonight's session early" (the same phrase
    task 5's own `grep -in` probe searches for) appeared *before* the
    transaction, and afterward the screen shows an evidence-window closing
    time that is a real clock time roughly two minutes out.

14. **Prove the deadline is read from chain, not hardcoded (P5-1).** Step
    13's 2-minute window is the *only* duration this floor has exercised so
    far, and 2 minutes is also `WINDOW_SECONDS` from step 2 — passing step
    13 alone cannot tell "this page reads `window()` off the contract" from
    "this page has `120` written into it somewhere." Rule that out with a
    second, independent deployment at a deliberately different number.
    Start a **second** anvil instance, on a different port, in a third
    terminal:

        ~/.foundry/bin/anvil --port 8546

    Deploy `ChannelV2` to *this* one with a distinctive window — 777
    seconds, a number nothing else in this phase touches:

        PRIVATE_KEY=<this second anvil's own Account #0 private key> \
        TEST_DURATIONS=true WINDOW_SECONDS=777 BANK_SECONDS=60 GRACE_SECONDS=60 \
        ~/.foundry/bin/forge script contracts/script/DeployV2.s.sol \
          --root /home/dev/projects/vault/contracts \
          --rpc-url http://localhost:8546 \
          --broadcast

    Update `src/deploymentsV2.js`'s `31337` entry to this new address, then
    `npm run build` again. In your wallet, edit the network from step 5 so
    its RPC URL points at `http://localhost:8546` instead of `:8545` (same
    chain id 31337 — this is a second, separate chain, not the first anvil,
    which is still running untouched in its own terminal). Reload the host
    tab (same `?session=smoketest&seat=host&sessionkey=…` URL), connect,
    open a brand-new session, have the guest join, and open a dispute again
    — same clicks as steps 6–13. **YES/NO:** the evidence-window closing
    time now shown is roughly **13 minutes** out (777 seconds), not 2
    minutes — proving the number displayed tracks this deployment's own
    `window()` rather than a value baked into the page.

**What this floor deliberately does not cover:** real duty auto-filing
(task 5) — there is no poker tab in this smoke, so no `vault:evidence-v2`
ever arrives, so the evidence store is empty and `autofileV2.plan()` has
nothing to file. That path's own probe (task 5's `node -e` script) is the
only proof available until P6 ships a real sending side; a genuine
end-to-end dispute-filing smoke is P7's live sweep, not this phase's floor.

**Automated probes, above the floor (run these too, in this order):**

    cd /home/dev/projects/vault && npm run build
    git diff 1c10e9c..HEAD -- public/index.html src/main.js src/abi.js src/deployments.js server.mjs
    grep -rn "slipgate\|127\.0\.0\.1\|localhost:8790" src/mainV2.js src/mainV2Recover.js
    grep -n "vault:sessionkey-v2\|vault:evidence-v2" src/mainV2.js
    grep -in "the table simply won't credit it\|if you desert this session, you lose this" src/mainV2.js
    grep -in "this ends the rest of tonight's session early" src/mainV2.js
    grep -n "never having started" src/mainV2.js
    grep -c "didn't file anything for the full 24-hour window" src/mainV2.js
    grep -n "opponent's bond was burned" src/mainV2.js
    grep -n "Your bond was burned" src/mainV2.js
    grep -n "NotYetBuilt" src/mainV2.js

(`1c10e9c` per the D17 note at the top of Tasks — substitute the
recorded SHA, never `--stat`.) YES for each: `npm run build` exits 0; the
`git diff` and the first `grep` return empty output; every `grep -n`/`-in`
finds at least one match; the `grep -c` finds **exactly 2** (M3: both AF-4
per-duty directions — "you filed, they didn't" and "you didn't, they
filed" — share this clause, and 2 is the proof both actually render as
distinct strings rather than one sentence plus a described-but-unwritten
mirror; the two `grep -n` lines right after it each pin one direction by
its own distinguishing phrase, per task 6 step 2). Plus every task's own
`node -e` script (tasks 2, 3, 5, 7) — each YES = the asserted value matches
by hand-derivation.

## Outputs to next phase

**To P6 (client-chain, poker repo) — the seam it must fill:**
- **Two new message types to send, poker→Buyin**, shapes pinned in task 2:
  `vault:sessionkey-v2` (`{type, v:1, session, seat, sessionKeyAddress}`,
  address only, never the private key — D2) and `vault:evidence-v2`
  (`TBD-P1-EVIDENCE-SHAPE`, this phase's proposed bundle — receipts, latest
  marker, action chain, shares, each field-ordered per formats §3/§4/§5).
  Both must follow the existing resend-every-hello-cycle discipline
  (`OVERVIEW.md`) — a one-shot send repeats V1's own shipped bug.
- **The `?sessionkey=` URL param is a bridge, not a spec.** Once P6 sends
  `vault:sessionkey-v2` for real, it supersedes the URL param on first
  arrival, exactly as `vault:opponent` already supersedes `?opponent=`
  (design decision 2) — no coordination needed beyond matching that
  existing precedent.
- **The routing convention this phase picked** (design decision 1): V2
  sessions open `<buyin origin>/v2.html?session=<id>&seat=<host|guest>`,
  V1 sessions keep opening `<buyin origin>/?session=<id>&seat=<host|guest>`
  unchanged. The poker client's existing Buyin-button code
  (`OVERVIEW.md`'s Integration boundaries — "one button, rendered only
  behind a `?vault=1` flag") is what P6 extends to pick the right path for
  a V2 cash session; this phase does not touch that poker-side code.

**To P7 (deploy-live-sweep):**
- `src/deploymentsV2.js` is the one file P7 edits to go live — add the
  real Base Sepolia entry under key `84532`, same shape V1's
  `src/deployments.js` already uses. No other file in this phase's scope
  needs touching to point Buyin at a real deployment.
- Every `TBD-P2-GETTER-ABI` read in `src/abiV2.js` needs a final
  reconciliation pass against the actually-deployed contract's ABI before
  the live sweep — task 1 step 1's mechanical resolution step, re-run once
  more for certainty right before P7.

**To a follow-up pass on this phase (once P3/P4 ship):**
- `TBD-P3-ROWS`: task 6 step 2's settlement-outcome copy has one fallback
  bucket ("Settled — see your balance below") standing in for every §5.3
  resolution row P3/P4 actually build. Revisit once those land.
- `TBD-P4-CONTINUATION`: task 6 step 1's phase-2 appointment display is a
  placeholder sentence, not a real countdown, until P4 ships readable
  per-duty deadline state.
- Task 5's `autofileV2.plan()` degrades to "file everything the bundle has"
  wherever it cannot read fine-grained on-chain filing status
  (`TBD-P2-GETTER-ABI`/P3-shaped reads) — safe, but worth tightening once
  those reads exist, so the UI can say "already filed" instead of silently
  re-attempting a no-op.

## Open questions

1. **`TBD-P2-GETTER-ABI` — assumed `public` read surface.** Default:
   `sessions` is a `public` mapping (full struct auto-getter, V1 precedent,
   `Channel.sol:45`); `window`/`bank`/`grace` are `public immutable`
   (`Channel.sol:44`); `credits` is `public` (P2 task 6 step 1, already
   explicit, not a guess). **Overrules:** whoever implements task 1 step 1,
   mechanically, the moment `contracts/out/ChannelV2.sol/ChannelV2.json`
   exists — this is a resolve-by-reading item, not a judgment call, and the
   default above is only a placeholder until then.
2. **`TBD-P1-EVIDENCE-SHAPE` — this phase's own proposed
   `vault:evidence-v2` bundle shape (task 2 step 2).** Default: as written,
   field-ordered per formats §3/§4/§5, hex-string encoded. **Overrules:**
   whoever drafts P6, if the shape the poker side can actually produce
   differs — P6 is the real implementer of the sending side and this
   phase's shape is a proposal for coherence, not a frozen cross-repo
   contract only this phase has authority over.
3. **Gas-reserve threshold (task 8 step 2).** Default: `0.01` ETH-
   equivalent. **Overrules:** the operator, at any time — it's a single
   named constant, trivial to change, and no upstream document pins a real
   number.
4. **No JS test framework in this repo.** Default: build-green + grep-based
   structural probes + small uncommitted `node -e` scripts against this
   phase's pure modules + the operator-run two-tab floor (above). **Overrules:**
   the operator, if a real DOM-testing setup (e.g. `vitest` + `jsdom`,
   already proven in the poker repo) is wanted in the vault repo going
   forward — that's a tooling decision for a human to make once, not
   something this phase should introduce silently mid-UI-work.
5. **Gas-reserve trigger point (task 8 step 1).** Spec §8.6 says "from
   `(0,0)` onward"; `(0,0)` is a poker-side receipt this app cannot observe
   directly. Default: `status !== 'None'` (the earliest chain-observable
   proxy). **Overrules:** whoever has `TBD-P1-EVIDENCE-SHAPE` resolved and
   can see the actual `(0,0)` receipt arrive via `vault:evidence-v2` — at
   that point the trigger can move to the true event.
6. **Routing: separate `v2.html`, not a query-string branch (design
   decision 1).** Default: as built. **Overrules:** P6/P7, if a query-param
   split (`?v=2` on the existing `index.html`) turns out easier for the
   poker client's Buyin-button code to target — this phase's own call, made
   for file-separation clarity, not handed down by any prior phase.

## Recovery

**Tasks 1 → 2 → 3 → {4, 5, 6} → {7, 8}** is the real dependency order, not
parallel where it looks like it might be: task 3 reads the session-key state
task 2's message handler populates, and both tasks edit `src/mainV2.js`
directly, so 2 and 3 are sequential, not concurrent, despite task 2 not
depending on task 3's own screens. Task 1's scaffold and ABI are
load-bearing for everything after it. Task 7 (recovery page) only actually
needs tasks 1 and 2 (the evidence store, not the handshake or deposit
screens) — it is placed after task 6 in the task list for narrative order,
not because it depends on 3–6; an implementer free to reorder dispatch may
run it right after task 2. Within `{4, 5, 6}` and `{7, 8}`, the tasks in
each group have no dependency on each other or on their groupmates' order.

If this phase is interrupted mid-task: `npm run build` first — a clean
build with both `public/bundle.js` and `public/bundle-v2.js` present tells
you task 1 landed. Then `grep -n "^function \|^const \|^async function "
src/mainV2.js` against this doc's task list to find the first missing
screen/handler. Every task's own module (`bondV2.js`, `evidenceStoreV2.js`,
`autofileV2.js`) is independently `node -e`-probable regardless of how far
`mainV2.js`'s wiring got, so a half-finished task 5 doesn't block verifying
task 2 or task 3's pure logic in isolation.

**If any of `src/main.js`, `src/abi.js`, `src/deployments.js`,
`public/index.html`, or `server.mjs` show *any* diff**
(`git diff 1c10e9c..HEAD -- src/main.js src/abi.js
src/deployments.js public/index.html server.mjs` — D17 base-ref form, not
`git status`/`--stat`, both of which read empty once a change is
committed), stop and ask — D11/D13's untouched-V1
boundary was violated, and per this arc's own standing rule (P2's Recovery
section states the identical thing for its own V1 files) that is a
revert-the-edit conversation, not a continue-working one.

**If P2 has not landed by the time this phase starts implementation**, task
1 step 1's fallback (ship `abiV2.js` against this doc's own pinned surface,
flag every `TBD-P2-GETTER-ABI` read, reconcile later) is not a blocker —
this phase's own build/grep gates do not depend on P2's landing order, only
the operator-run floor's actual deploy step (phase-boundary verification,
step 2) does, and that step can simply wait.

## Coherence-pass amendment — 2026-08-17 (AF-10)

P6's Outputs name a required vault-repo addendum this doc must carry
(P6 could not ship it under its side-effect boundary): **task 2's
`sendHelloToOpener`-equivalent gains one field, `liveHand: number`,
read from `ChannelV2.liveHand(session)`, and `abiV2.js`'s read set
gains that getter.** Without it, P6's deal-gate confirmation (its task
6) and marker-floor recovery (its task 7) fall back to the direct
`vault:marker-result-v2` response only — sufficient for the local
floor, insufficient for crash recovery. One field, one ABI line;
task 2's implementer treats this amendment as part of the task.
