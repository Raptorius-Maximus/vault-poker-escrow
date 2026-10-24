# Phase 6 — client-chain (poker repo)

## Goal

Give the poker client chain awareness through the one seam the
architecture allows — Buyin, over `postMessage` — with **no direct RPC
or wallet-transaction call anywhere in this repo** (the poker tab may
still request a wallet *signature*, per the existing `personal_sign`
precedent at `vaultMaybeSign`, `src/useGame.ts:836-844`, confirmed
2026-08-17; it may never read or write the chain itself). Concretely:
a `vaultVersion` distinction so the client can tell a V1 sit-and-go
from a V2 cash session and route each down its own path; a
wallet-derived encryption key for the session private key P1 leaves in
plaintext, obtained once via a Buyin `personal_sign` round trip, with a
runtime determinism probe and an unencrypted fallback carrying an
on-screen warning; encrypted, hand-scoped persistence of the live
hand's 52 decryption shares, destroyed the moment that hand's receipt
is signed; the evidence bundle P5 proposed and left as
`TBD-P1-EVIDENCE-SHAPE`, built from P1's stores and resolved here;
marker posting through Buyin with mandatory retry-on-transient-failure
and an honest "waiting for the chain" pause — never a forfeit — for the
deal gate; the marker-floor leg of §9.1's recovery order that P1
deliberately left more conservative than the spec's final state; the
four V1 winner-takes-all forfeit sites rewritten so a V2 session never
unilaterally awards a stack, while V1 sessions keep exactly
`poker@d66a68a`'s behaviour; standing instructions (check-fold when the
bank runs low) as a client policy with a visible toggle; and the
decision clock reaffirmed as off-chain UX only. At the phase boundary,
`npm test` is green and one operator-run two-tab smoke against a local
Buyin (per P5's floor, extended) shows a real marker confirming, a real
evidence bundle arriving in Buyin, and a real dispute-pause never
turning into an award.

**Plan-not-shipped-code framing.** P1 (protocol substrate) and P5
(buyin-ui) are both cited below as **documents**, not as code on disk —
confirmed 2026-08-17: `ls src/core/` in this repo shows only the
pre-arc files (`betting.ts, cards.ts, elgamal.ts, evaluator.ts,
format.ts, game.ts, group.ts, proofs.ts, protocol.ts`); none of P1's
promised modules (`signing.ts, merkle.ts, dleqKeccak.ts, receipt.ts,
marker.ts, signedAction.ts, actionStore.ts, src/vectors/*`) exist yet,
and `git status --short` is clean. P1 is "checker-revision in flight"
and P5 is "in revision" per `README.md`'s Status block as of this
draft. **Every task below that imports a P1 module or calls a P1/P5
function must re-verify that function's actual shipped name, file, and
signature against the real diff before writing the import** — this
document cites P1's and P5's own phase docs, dated 2026-08-17, as the
contract; where this document's assumption about an unshipped internal
turns out wrong, the fix is a small additive extension (documented
per-task below), never a silent reinterpretation.

## Inputs from previous phase

**From P1 (protocol-substrate, poker repo) — `phase-1-protocol-substrate.md`'s
"Outputs to P6," mirrored precisely, not re-derived:**

- `src/core/marker.ts` builds and both-signs the marker; P1 stops at
  "both-signed and persisted." This phase adds the **posting**
  transaction (via Buyin) and the **deal-gate read** (waiting on-chain
  confirmation) — P1's task 5 explicitly declines both.
- `src/core/dleqKeccak.ts`'s `proveDleqKeccak` is built and tested by P1
  but never called outside tests there — "no share is posted in this
  phase." This phase is the first caller, when building the evidence
  bundle's `shares` field.
- **Two of D14's five load-bearing rules are this phase's to carry, not
  P1's:** "hole shares born only by a completing action" (task 5,
  below) and "deal gate pause" (task 6). P1's own task 9 comment-audits
  only the three rules it carries (write-ahead, refuse-on-cleared-storage,
  marker-pk hello-match refusal) — this phase's task 10 audits the other
  two, and the two audits together are what D14's "five load-bearing
  rules" require across the two phases.
- **P1's hand-number/button recovery (its task 4) implements only the
  local-storage leg of spec §9.1's two-source recovery order.** Its
  refuse-to-resume guard — "a client with no stored receipt for this
  session must not accept a hand number from its peer" — is **more
  conservative than the spec's final state**: it refuses to resume even
  when a marker floor exists on chain that could have recovered it.
  P1's own doc names this explicitly as P6's job: not just adding a
  chain read, but **loosening** the guard once that read exists (task 7,
  below).
- D2/D14: P1 persists the session private key **unencrypted** in
  `localStorage` at a write site it marks `// TODO(P6): encrypt under a
  wallet-derived key, spec §6` (P1's own Open question 3, default
  branch — this phase task 2's grep target).
- Cited functions this phase imports, by P1's own documented
  file/name (re-verify at dispatch time per the framing note above):
  `src/core/signing.ts` (`bindPreimage`, `signRaw`, the session
  keypair — address form crosses to Buyin, private key never does, D2);
  `src/core/marker.ts` (`buildMarkerPreimage`, the both-signed
  exchange); `src/core/receipt.ts` (`buildReceiptPreimage`,
  `loadNewestReceipt`, `latestReceiptHash` — P1's task 8 names these
  functions but does not name a dedicated store file the way task 7
  does for actions; this phase's task 5 locates them wherever P1's diff
  actually put them); `src/core/actionStore.ts` (`saveActionTip`,
  `loadActionTip`, keyed `vault:action:${sessionId}:${hand}` — **persists
  only the write-ahead tip, by design**, per P1's task 7; this phase's
  task 5 extends it additively, see that task).

**From P5 (buyin-ui, vault repo) — `phase-5-buyin-ui.md`'s "Outputs to
P6," mirrored precisely:**

- **Two new message types to send, poker→Buyin**, shapes pinned in
  P5's task 2: `vault:sessionkey-v2` — `{type: 'vault:sessionkey-v2',
  v: 1, session, seat, sessionKeyAddress}`, address only, private key
  never crosses (D2) — and `vault:evidence-v2` (`TBD-P1-EVIDENCE-SHAPE`,
  P5's proposed bundle: `receipts[]`, `marker | null`, `actions[]`,
  `shares[] | null`, every numeric/binary field a hex string). **Both
  must follow the existing resend-every-hello-cycle discipline** — a
  one-shot send repeats V1's own shipped `sendHelloToOpener` dedupe bug
  (`docs/arc-history.md`'s V1 paragraph; also `src/main.js:220-230`'s
  own code comment, vault repo).
- **The `?sessionkey=` URL param is a bridge, not a spec** — once this
  phase sends `vault:sessionkey-v2` for real, it supersedes the URL
  param on first arrival, exactly as `vault:opponent` already
  supersedes `?opponent=`.
- **The routing convention P5 picked:** V2 sessions open `<buyin
  origin>/v2.html?session=<id>&seat=<host|guest>`; V1 sessions keep
  opening `<buyin origin>/?session=<id>&seat=<host|guest>` unchanged.
  P5 names the poker-side function this phase extends: "the poker
  client's existing Buyin-button code … is what P6 extends to pick the
  right path for a V2 cash session" — confirmed 2026-08-17 as
  `vaultUrl()`, `src/useGame.ts:226-236` (builds
  `${vaultOrigin()}/?session=…&seat=…`, called from the header's
  window-opening code at `src/useGame.ts:646`).

**Genuine gaps in P1/P5 this phase must close itself, not silently
work around** (recorded here because a cold reader checking the
Outputs→Inputs chain will otherwise wonder why this document invents
message types P5 never proposed):

1. **P5's `mainV2.js` is silent on sending `vault:hello` and its
   siblings.** P5's task 1 step 5 copies "`main.js`'s wallet-connect /
   chain-read / polling skeleton … reused verbatim" into `mainV2.js`;
   `sendHelloToOpener` (`src/main.js:231-254`, vault repo, confirmed
   2026-08-17) is part of that same polling skeleton, so this phase
   assumes `mainV2.js` sends a `vault:hello`-shaped message on the same
   cadence. **This phase needs one field V1's `vault:hello` does not
   carry: `liveHand?: number`** (P2's `ChannelV2.liveHand(session)`
   getter, `phase-2-money-frame.md` task 4 step 6) — the deal-gate read
   and the marker-floor recovery leg both need it. This is an
   **additive field on an inherited message neither P1 nor P5 owns
   outright** (`vault:hello` predates this arc); it cannot be shipped
   from this poker-repo-only phase. Flagged loudly in Outputs/Open
   questions below as a required small addendum to P5's `mainV2.js`
   (add `liveHand` to `abiV2.js`'s read set and to `sendHelloToOpener`'s
   payload) — not this phase's file to touch (side-effect boundary),
   but this phase's dependency to name.
2. **Neither P1 nor P5 designs how poker tells Buyin "post this marker"
   or "derive my encryption key."** Both are new, poker-repo-owned
   request/response message pairs this phase introduces outright (task
   6, task 2) — not amendments to P5's two proposed types, genuinely
   new surface on the same seam, designed to the same conventions
   (`event.origin`/`event.source` checks, one-shot-vs-resend
   classification per P5's design decision 3). **The receiving side of
   these on Buyin is vault-repo work — fix round 1, B3/AF-11.3 ruled
   this phase owns both ends of its own new message pairs, since
   without an executor neither round trip has anyone to answer it.**
   Task 11, below, is the sanctioned, explicitly named exception to
   this phase's poker-repo-only side-effect boundary: it edits exactly
   one file outside this repo, the vault repo's `src/mainV2.js`, and
   nothing else there.

**Spec sections read in full 2026-08-17** (line numbers below cite
`docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`,
revision 8): §6 (keys and storage), §4 (the marker, deal gate), §5.2
(dispute duties, auto-filing), §9 items 5, 8, 11, 14, 17 (the concrete
defects this phase fixes), §5.1 (standing instructions are legal client
policy).

**Live source read for this doc** (poker repo, all grepped 2026-08-17
against `poker@d66a68a`, confirmed by `git rev-parse --short HEAD`):
`src/useGame.ts` (1630 lines — the vault seam at 700-990, `vaultInfoRef`
declared line 472 and populated line 958, `vaultUrl` lines 226-236,
`vaultOrigin`/`deriveVaultOrigin` lines 176-206, `graceFor` lines
63-64, `shouldEnableVault`/`vaultEnabled` lines 141-148, the four
forfeit-adjacent sites below), `src/worker.ts` (71 lines, whole file
read), `src/core/game.ts` (454 lines; `forfeit()` at 418-441, the `bye`
handler at 226, `beginDeal`/`act`/`applyPeerAction` at 229-296),
`src/core/protocol.ts` (`Session` class at line 86), `src/test/e2e.test.ts`
(the `connect()`/`pump()` harness, lines 15-33, current pre-P1 `Game`
constructor signature — P1's task 4 changes this; this phase's task 10
re-verifies before extending it), `src/test/grace.test.ts`,
`src/test/vault-persistence.test.ts` (`fakeStorage()` helper, line 11),
`package.json` (`"test": "vitest run"`, confirmed), `vite.config.ts`
(dev server fixed at port 5173). Vault repo (read-only, this phase
touches none of it): `src/main.js:220-254` (`sendHelloToOpener`),
`prototypes/marker-latency/RESULTS.md` (the 17/20 nonce-race finding,
quoted in task 6). `node_modules/viem/_esm/actions/wallet/signMessage.js`
(confirmed 2026-08-17, viem 2.55.13): `signMessage({account, message:
'a string'})` hex-encodes the string and calls `personal_sign`,
distinct from the `{raw: hash}` digest form P5's task 3 already uses
for registration — this phase's key-derivation round trip (task 2)
uses the human-readable string form so the wallet prompt is legible,
not an opaque hex blob.

**`npm test` baseline, executed 2026-08-17 against the current
`poker@d66a68a` checkout (before P1 has landed any code): 278 passing,
23 files, exit 0.** This is the same number P1's doc cites as its own
pre-phase baseline. P1 adds tests of its own before this phase starts;
that delta is unknown at drafting time and is carried as
**`TBD-P1-COUNT`** — this phase's own floor (below) states its pass
condition relative to that token, not to 278 directly.

## Files touched

**Created:**
- `src/core/sessionKeyCrypto.ts` — wallet-derived AES-GCM key
  derivation (the Buyin round trip + determinism probe), encrypt/decrypt
  of the session private key, the unencrypted-fallback path (task 2).
- `src/core/shareStore.ts` — encrypted, hand-scoped persistence of the
  52 decryption shares P1's `Game` caches at shuffle end but does not
  itself persist (task 3).
- `src/core/standingInstructions.ts` — pure preference store + the
  check-fold-when-bank-low policy predicate (task 4).
- `src/core/evidenceBundle.ts` — assembles `vault:evidence-v2`'s
  payload from P1's stores plus this phase's share store, applying the
  hole-share-birth gate (task 5).
- `src/core/forfeitPolicy.ts` — pure decision function extracted from
  the four sites below, so the V1/V2 branching is unit-testable without
  the full `useGame` hook (task 8).
- `src/test/vault-version.test.ts`, `src/test/session-key-crypto.test.ts`,
  `src/test/share-store.test.ts`, `src/test/standing-instructions.test.ts`,
  `src/test/evidence-bundle.test.ts`, `src/test/marker-posting.test.ts`,
  `src/test/marker-recovery.test.ts`, `src/test/forfeit-v2.test.ts`,
  `src/test/p6-load-bearing-audit.test.ts`,
  `src/test/reconnect-restore.test.ts` — new test files, one per task
  below unless noted, named after the module or behaviour under test
  per the existing `<topic>.test.ts` convention.

**Modified:**
- `src/useGame.ts` — every task below touches this file: `vaultUrl`/
  `roomLink`/`vaultEnabled` extended with `vaultVersion` (task 1 —
  `shouldEnableVault` itself is not modified, only called from
  `vaultEnabled`'s new second clause, see task 1 step 2);
  the session-key write site P1 marks `TODO(P6)` (task 2); a hook into
  the existing write-ahead `w.onmessage` interception point (P1's task
  7 location) for share persistence (task 3) and for firing the
  marker-post request once a marker is both-signed and persisted (task
  6); the standing-instructions toggle's state (task 4); evidence-bundle
  assembly and send, riding the existing `vaultSendProgress`-style
  hello-cycle callback (task 5); the new `vault:*` message
  senders/receivers (tasks 2, 5, 6) added to the existing `onMessage`
  listener (`src/useGame.ts:895-973`); the hand-number recovery guard
  (task 7); the four forfeit-adjacent sites (task 8, listed there by
  exact line) plus `vaultMaybeSign`'s gating (task 8); a decision-clock
  label (task 9).
- `src/core/game.ts` — `forfeit()` (line 418) gains a `vaultVersion`-
  aware branch (task 8); a hook at receipt-sign time for share-store
  destruction (task 3, if not more naturally placed in `useGame.ts` —
  task decides at implementation time, see task 3 step 4).
- `src/worker.ts` — the catch-all handler (line 69) gains V2-awareness
  via the same `forfeitPolicy.ts` predicate (task 8).
- `src/ui/App.tsx` — standing-instructions toggle UI (task 4), a
  "waiting for the chain" deal-gate banner (task 6), V2 forfeit-notice
  copy (task 8), a decision-clock label (task 9).
- `src/core/actionStore.ts` (P1-owned) — **additively** extended with
  `appendAction`/`loadActionChain` (task 5): P1's own store persists
  only the write-ahead **tip** per hand, by design, for the
  refuse-to-re-sign guard; the evidence bundle's `actions: []` field
  needs the **full ordered chain** for the hand, which is a genuinely
  different read. Re-verify against P1's actual shipped shape before
  writing this — if P1's diff already retains the full chain, this
  step is a no-op confirmation.
- P1's receipt-persistence code (task 5) — location **not pinned by
  P1's own doc** (task 8 there names the functions `loadNewestReceipt`/
  `latestReceiptHash` without naming a dedicated store file the way
  `actionStore.ts` is named for actions); wherever P1's diff puts it,
  additively extended with a `loadAllReceipts` export the same way.
- **`vault` repo's `src/mainV2.js` (task 11 — the sole, sanctioned
  exception to this document's poker-repo-only side-effect boundary,
  fix round 1 B3/AF-11.3).** Every other file in this list is in the
  poker repo; this one line is the entire scope of this phase's
  vault-repo footprint — no other vault-repo file (`abiV2.js`,
  `bondV2.js`, `evidenceStoreV2.js`, `autofileV2.js`, `build.mjs`, or
  any V1 file) is touched by this document.

**Deleted:** none.

## Design decisions pinned here (binding on every task below)

**1. `vaultVersion: 1 | 2`, threaded exactly like `vaultOn` already is —
and `vaultOn` itself must turn on for `?vault=2`, or nothing below ever
fires.** Neither P1 nor P5 gives the poker client a way to know which
contract flavour it is talking to — V1's `Channel.sol` and V2's
`ChannelV2.sol` are different contracts behind the same `postMessage`
seam, and every V2-only feature this phase ships (session-key crypto,
marker posting, evidence bundles, dispute-safe forfeits) must never
fire for a V1 session. `?vault=1` stays exactly as today; `?vault=2`
selects V2 cash mode, remembered in `localStorage` the same way
`vault:enabled` already is. **The seam itself only ever installs when
`vaultOn` is true** (`useGame.ts:907`'s listener-install effect,
`if (!vaultOn) return;`), and `vaultOn` is `vaultEnabled()`'s return
value (`src/useGame.ts:145-148`), which today is `shouldEnableVault(...)`
alone — `?vault=2` on its own would leave `vaultOn` false forever,
installing no listener and firing no `vault:*` message, making every
task in this phase dead code. **The fix, committed here, single change
site:** `vaultEnabled()` becomes `shouldEnableVault(location.search,
localStorage.getItem('vault:enabled')) || vaultVersionOf(location.search,
localStorage.getItem('vault:version')) === 2` — `shouldEnableVault`
itself keeps its exact current signature and every existing caller
unchanged; only `vaultEnabled()`, the one function that actually
produces `vaultOn`, gains the second clause. Task 1 step 2 below is
this fix. `vaultUrl()` picks `v2.html` vs the bare origin per P5's
routing convention when `vaultVersion === 2`. Task 1 ships this first;
every later task reads it, never redefines it — this is this phase's
own version of P1's task-8-before-4/5 reordering, recorded once,
authoritatively, in the Task order note below.

**2. `vault:sessionkey-v2` is sent exactly as P5 proposed it — matched,
not amended.** The address-only shape is complete for its purpose;
nothing this phase needs changes it.

**3. `vault:evidence-v2` is sent exactly as P5 proposed it, with one
additive field.** P5's shape (`type, v, session, host, guest, receipts[],
marker, actions[], shares[]` — the full envelope, including the two
top-level `host`/`guest` fields P5's task 2 step 2 names "once known,
for task 7's recovery filter," not just the four array/object fields)
needs no field renamed or retyped. This phase adds
`standingInstruction: 'none' | 'check-fold-low-bank'` (task 4) —
additive, per P5's own "P6 either matches or amends" framing for this
exact shape (`phase-5-buyin-ui.md`'s Outputs-to-P6 and its Open
question 2, both stated as this phase's authority to extend the
proposal, not artifact-formats §9 — that document's "may add fields"
convention is scoped to the on-chain contract interface, a different
surface). **This is a match with an additive extension, not an
amendment requiring a renamed-artifacts line** — no field P5 named
changes shape or meaning.

**4. Two genuinely new message pairs, not amendments to anything P5
proposed.** `vault:derive-key-v2`/`vault:derive-key-result-v2` (task 2)
and `vault:post-marker-v2`/`vault:marker-result-v2` (task 6) are new
surface this phase adds to the same seam — P5 never proposed anything
in this space (P5's scope was UI screens against an already-deployed
contract, not a poker-side chain-awareness client). Designed to the
same conventions P5 and P1 already use: `event.origin`-checked,
`v: 1`-tagged, one-shot for a real event (a signature returned, a
transaction's outcome) vs. resent-every-hello for standing state
(none of these four are standing state, so all four are one-shot,
matching `vault:sent`/`vault:confirmed`'s classification, not
`vault:opponent`/`vault:progress`'s).

**5. Retry lives in poker, not in Buyin, because poker owns the pause
state.** `prototypes/marker-latency/RESULTS.md`'s finding — "17 of 20
first-attempt sends failed transiently … a single retry after 2s fixed
every one … client marker-posting MUST carry retry-on-transient-failure"
— is addressed to the client, and Buyin (a thin per-call executor in
this design) has no reason to retry on its own initiative behind the
scenes while poker's deal gate sits paused not knowing why. Poker
resends `vault:post-marker-v2` itself on a transient failure report, at
a flat 2-second interval per RESULTS.md's own measured fix (task 6 step
4 — not an escalating backoff schedule; flat matches what was actually
measured to work, "a single retry after 2s fixed every one, 17/17"),
while the pause UI stays up throughout (task 6).

## Task order note

**Phase-base SHA (D17, fix round 1 B5): recorded at dispatch, not at
drafting time.** Every isolation/no-touch gate in this document (Phase-
boundary verification step 5, the Recovery section's scope-violation
check) is a `git diff 4acc658..HEAD -- <paths>` against this
phase's own starting commit — never `git status --short`/`--stat`
alone, which reads empty once a phase's own work is committed to
master (D13's flow) regardless of what actually changed, and never a
plain whole-tree `grep` alone, which cannot distinguish "already there
before this phase" from "this phase's own diff." `poker@d66a68a` is
**not** that SHA — P1 lands its own commits on top of it before this
phase starts implementation, and this phase's own gates must diff
against P1's actual last commit, not the pre-P1 baseline this document
was drafted against. **Whoever dispatches task 1 records the current
`git rev-parse HEAD` as `4acc658` in this note before any task
1 edit lands**, and every later gate in this document substitutes that
recorded value for `4acc658`.

Tasks build strictly on earlier tasks' outputs with **no forward
references**: 1 (the `vaultVersion` flag) is read by 2, 4, 5, 6, 8;
2 (the encryption key) is read by 3; 3 (shares) is read by 5; 4
(standing instructions) is read by 5; 5 (evidence bundle) and 6 (marker
posting) both read 1-4 but not each other, so they may dispatch in
either order or in parallel; 7 (marker-floor recovery) reads 6's
`liveHand` channel; 8 (forfeit sites) reads 1 only, so it may dispatch
any time after task 1 — placed after 7 here for narrative order, not
dependency; 9 (decision clock) reads 8's grace/deadline code for
context; 10 (audit + integration tests) reads everything and dispatches
last; **11 (Buyin-side executor handlers, vault repo — fix round 1 B3)
is independent of 1-10's poker-repo dependency chain entirely** (it
implements the *receiving* half of the message pairs tasks 2 and 6
design the *sending* half of) and may dispatch any time after 2 and 6
have pinned their wire shapes — in practice alongside them, not
strictly after, since task 11 only needs the message *shape*, not the
poker-side code to exist yet. Suggested dispatch order: **1, 2, 3, 4,
8, 5, 6, 11, 7, 9, 10** (8 moved up since it depends only on task 1,
freeing 5/6/7's dependency chain to run right after 4; 11 placed after
6 since it needs 6's `vault:post-marker-v2` shape finalized, but ahead
of 7, since task 7's own fallback — and this phase's operator floor,
gate 7 steps d/g — need task 11's executor actually running) — an
implementer free to reorder may run 5 and 6 in parallel once 1-4 land,
and task 11 in parallel with either, exactly as P1's own task-order
note permits for its independent foundations.

## Tasks

**Task-count ruling: 11, not the usual ≤10 boundary — recorded, not
silent.** Tasks 1-10 were this document's original count. Fix round 1's
B3/AF-11.3 (Buyin-side executor handlers) forced an eleventh: it cannot
merge into task 2 or task 6 (different repo, different side-effect
boundary, different verification floor — no vitest, no npm test, a
build-green + grep + `node -e` floor instead), and splitting it further
would only separate steps (the two receivers, their two senders) that
have to land together to be tested at all. Kept as one task, over the
usual boundary, for the same reason P1's own D16 addition became an
11th-hour task 10 there: every step is one coherent deliverable, and
nothing downstream of it is any smaller for having been split.

### Task 1 — `vaultVersion` and the Buyin-routing extension

**Goal:** the flag every later task in this phase is gated on, and the
routing change P5's Outputs-to-P6 names as this phase's job.

**Files:** modify `src/useGame.ts` (`vaultUrl`, `roomLink`,
`vaultEnabled` — `shouldEnableVault` itself is read, not edited).

**Steps:**
1. `shouldEnableVault(search, stored)` (`src/useGame.ts:141-142`)
   returns a boolean today and keeps its exact current signature and
   every existing caller unchanged. Add a sibling, pure and equally
   testable without a browser: `vaultVersionOf(search: string, stored:
   string | null): 1 | 2` — reads `?vault=2` (or a stored `'2'` under a
   new key `vault:version`) as V2, everything else (including today's
   bare `?vault=1`/stored `'1'`) as V1.
2. **The gating fix (design decision 1's BLOCKER-level requirement,
   single change site): `vaultEnabled()` itself** (`src/useGame.ts:145-148`,
   currently `shouldEnableVault(location.search,
   localStorage.getItem('vault:enabled'))` alone) **becomes:**

       export function vaultEnabled(): boolean {
         const v1 = shouldEnableVault(location.search, localStorage.getItem('vault:enabled'));
         const v2 = vaultVersionOf(location.search, localStorage.getItem('vault:version')) === 2;
         if (v1) localStorage.setItem('vault:enabled', '1');
         if (v2) localStorage.setItem('vault:version', '2');
         return v1 || v2;
       }

   This is what actually produces `vaultOn` (consumed at the listener-
   install effect, `useGame.ts:907`, `if (!vaultOn) return;`) — without
   this change, `?vault=2` alone leaves `vaultOn` false forever, no
   listener installs, no `vault:*` message ever fires, and every task
   in this phase is dead code. A separate `vaultVersion(): 1 | 2`
   wrapper (persists `vault:version` the same way, for callers that
   only need the version, not the combined boolean) is exported
   alongside it for task 1 step 5's ref.
3. `vaultUrl()` (`src/useGame.ts:226-236`): when `vaultVersion ===
   2`, build `${vaultOrigin()}/v2.html?session=…&seat=…` instead of
   `${vaultOrigin()}/?session=…&seat=…` — same query-param assembly
   otherwise (`buyinParam`/`opponentParam` untouched). Add a
   `sessionkey=` param once task 2 has generated the session key's
   address (forward-looking parameter, empty/absent until task 2 lands
   — P5's design decision 2 names this exact bridge and expects the
   poker side to supply it).
4. `roomLink()` (`src/useGame.ts:131-134`): extend its own `q` string
   the same way `vault=1` is added today, so a V2 invite link carries
   `vault=2` end to end (host and guest must agree on `vaultVersion`
   the same way they already must agree on `vaultOn` — `graceFor`'s own
   comment, `src/useGame.ts:63-64`, already states the "both sides must
   run the same one" property this mirrors).
5. `useRef`/`vaultVersionRef` mirroring `vaultOnRef` exactly
   (`src/useGame.ts:373-375`) — every later task reads the ref, never
   the raw state, inside closures the same way `vaultOnRef.current` is
   read at `src/useGame.ts:1247, 1321, 1384`.

**Verification probe:** `npx vitest run src/test/vault-version.test.ts`
— (a) `vaultVersionOf` returns 2 only for `?vault=2` or a stored `'2'`,
1 for every other input including `?vault=1`; (b) `vaultUrl` with
`vaultVersion=2` produces a `/v2.html?…` URL, unchanged for
`vaultVersion=1`; (c) a round trip through `roomLink`/`vaultVersionOf`
recovers the same version on both ends (the "must agree" property,
tested the same way `grace.test.ts` tests `graceFor`'s agreement
property); (d) **the blocker-level regression test:** `vaultEnabled()`
called with `search = '?vault=2'` and empty storage returns `true` —
the exact case that was dead before this task's step 2 fix — and with
`search = '?vault=1'` still returns `true` unchanged (V1's existing
behaviour, regression-gated).

**Dispatch:** agent (workhorse, low) — small, closely mirrors an
existing, already-tested pattern.

---

### Task 2 — Wallet-derived session-key encryption

**Goal:** spec §6: the session key "must survive the tab," "stored
encrypted under a wallet-derived key," "wallet determinism tested at
runtime, once per wallet address," "a non-deterministic wallet persists
the key unencrypted with an explicit on-screen warning," "deleted on
settlement." Replaces P1's plaintext write site.

**Files:** create `src/core/sessionKeyCrypto.ts`,
`src/test/session-key-crypto.test.ts`; modify `src/useGame.ts` (the
session-key write site P1 marks `// TODO(P6): encrypt under a
wallet-derived key, spec §6`; the new message pair's send/receive).

**Steps:**
1. **The round trip, poker→Buyin→poker, gated on `vaultVersionRef.current
   === 2`:** poker sends `{type: 'vault:derive-key-v2', v: 1, session,
   seat, nonce}` (a fresh random `nonce` per call, so two calls in the
   same session are distinguishable in Buyin's own logs even though the
   *signed message* is deterministic by design — see step 2). Buyin
   calls `walletClient.signMessage({account, message: 'Vault session
   key — session ${session} — do not sign this text on any other
   site.'})` (confirmed 2026-08-17: `signMessage` accepts a plain
   string and hex-encodes it before `personal_sign`,
   `node_modules/viem/_esm/actions/wallet/signMessage.js:53-56,64-68` —
   this is the human-readable form, distinct from P5 task 3's
   `{raw: hash}` digest form used for on-chain-verified registration;
   nothing here is ever chain-verified, so a formats-registry tag is
   not needed and deliberately not used) and replies
   `{type: 'vault:derive-key-result-v2', v: 1, session, nonce,
   signature}`. **One-shot, not resent** (design decision 4) — it
   answers a specific request, unlike the standing-state messages.
2. **The message text must be identical across calls for the same
   session** (no timestamp, no per-call nonce *inside the signed text*
   — the nonce rides in the wire envelope only, for Buyin's own
   logging, never inside what gets signed) — this is the whole
   precondition for the determinism probe below to mean anything.
3. **Determinism probe, once per wallet address** (spec §6, verbatim):
   request the round trip twice in immediate succession for the same
   session; compare the two returned `signature` byte-for-byte.
   Deterministic ⇒ proceed to step 4. Non-deterministic ⇒ step 6.
   Cache the boolean result in `localStorage` keyed
   `vault:wallet-deterministic:${walletAddress}` (the address, not the
   session — spec: "not taken from a compatibility list," but also not
   re-probed every session for the same already-tested wallet) so a
   later session with the same connected wallet skips the double round
   trip.
4. **Key derivation:** `crypto.subtle.digest('SHA-256', signatureBytes)`
   → 32-byte key material → `crypto.subtle.importKey('raw', material,
   'AES-GCM', false, ['encrypt', 'decrypt'])`. Deliberately simple
   (a single hash, no HKDF salt/info) — the property being used is the
   signature's determinism plus its ≥65 bytes of wallet-private-key-
   derived entropy, not a multi-context key-separation need; noted as
   Open question 1 in case a future phase wants HKDF instead.
5. `encryptSessionPrivateKey(key: CryptoKey, raw: Uint8Array):
   Promise<{iv: Uint8Array; ciphertext: Uint8Array}>` /
   `decryptSessionPrivateKey(key, blob)` via `crypto.subtle.encrypt`/
   `decrypt` with `{name: 'AES-GCM', iv}` (a fresh random 12-byte `iv`
   per encryption call, stored alongside the ciphertext — standard
   AES-GCM usage, no novel claim here). Replace P1's plaintext write
   site (the exact `// TODO(P6)` comment, grepped at dispatch time
   against P1's actual diff) with a call through this module; the
   stored blob shape becomes `{iv, ciphertext}` instead of the raw hex
   private key P1 shipped as its interim state.
6. **Unencrypted fallback** (non-deterministic wallet, step 3's other
   branch): store the raw private key exactly as P1 already does
   (no regression — this is P1's existing behaviour, not new risk),
   but set a persistent flag (`vault:key-unencrypted:${sessionId}`)
   that the UI (task 4's toggle area, or a dedicated banner) renders as
   an always-visible warning for the rest of the session: *"Your wallet
   doesn't sign the same way twice, so this table's session key isn't
   encrypted on this device. Don't use a shared or public computer for
   this match."* Verbatim-equivalent to spec §6's own trade-off framing
   ("losing recovery to guard against profile theft plus a colluding
   opponent is the wrong trade").
7. **Deletion on settlement:** hook the existing `vault:hello` handler's
   `status === 'Closed'` branch (`src/useGame.ts:951-954`, already sets
   `setVaultSettled(true)`) to also call
   `sessionKeyCrypto.destroy(sessionId)` — removes the encrypted (or
   unencrypted-fallback) session-key blob and the cached derived
   `CryptoKey` reference from memory. Per spec §6: "The session key is
   deleted on settlement, and is per match, never reused."

**Verification probe:** `npx vitest run src/test/session-key-crypto.test.ts`
— a `node -e`-style stub-`Storage`/stub-window harness (mirroring
`vault-persistence.test.ts`'s `fakeStorage()`) asserting: (a) two
identical signature inputs produce byte-identical derived
`CryptoKey`-backed encrypt/decrypt round trips (Web Crypto's `CryptoKey`
is opaque, so the test asserts round-trip correctness — encrypt then
decrypt recovers the original bytes — rather than reading the key
material directly); (b) two *different* signature inputs (simulating
non-determinism) produce a key whose round trip against the *other*
input's ciphertext fails to recover the original plaintext (proves the
derivation is sensitive to the signature, which is what makes the probe
meaningful); (c) the unencrypted-fallback path sets the warning flag
and stores the same raw bytes the encrypted path would have wrapped;
(d) `destroy()` removes the stored blob. Web Crypto's availability in a
real browser requires a secure context (HTTPS or `localhost`) — already
a hard requirement per spec §7, not a new one this task introduces.
**For the test environment specifically:** `vitest.config.ts` (this
repo, confirmed 2026-08-17) sets no `test.environment` — vitest's
default is plain Node, not `jsdom`/`happy-dom` (neither is a dependency
in `package.json`, confirmed; this repo's existing DOM-adjacent tests
are source-text-regex probes, per task 4's own note, not real DOM
rendering). `crypto.subtle` is available regardless, because it is
**Node's own native global as of Node ≥ 20** (confirmed 2026-08-17:
`node -e "console.log(typeof crypto.subtle)"` prints `object` on this
machine's Node v22.12.0, no browser environment, no polyfill, no vitest
environment setting involved) — the same fact this task's whole design
already rests on for the plain `node -e` probes P1's/P5's docs use
elsewhere in this arc. No environment change to `vitest.config.ts` is
needed for this task.

**Dispatch:** agent (session-tier, high) — new cryptographic subsystem,
security-adjacent (a session key protects real filed evidence), and the
determinism probe is exactly the kind of thing worth getting exactly
right rather than approximately right.

---

### Task 3 — Live-hand share persistence, encrypted

**Goal:** spec §6's amendment: "the live hand's decryption shares
survive the tab, and only they … persists them encrypted exactly as it
persists the session key, and destroys them the moment the hand's
receipt is signed."

**Files:** create `src/core/shareStore.ts`, `src/test/share-store.test.ts`;
modify `src/useGame.ts` (or `src/core/game.ts` — step 4 below decides)
for the persist-at-shuffle-end and destroy-at-receipt-sign hooks.

**Steps:**
1. `saveShares(store, key: CryptoKey, sessionId, hand, shares: {pos:
   number; shareEnc: Uint8Array}[]): Promise<void>` — JSON-serialize
   the 52 `(pos, shareEnc)` pairs, encrypt the serialized bytes via
   task 2's `encryptSessionPrivateKey`-equivalent (reuse the same
   `{iv, ciphertext}` shape and the same derived `CryptoKey` — spec §6:
   "persists them encrypted exactly as it persists the session key" —
   same key, same scheme, not a second cryptographic design). Keyed
   `vault:shares:${sessionId}:${hand}`, mirroring `actionStore.ts`'s
   `vault:action:${sessionId}:${hand}` naming (P1 task 7 step 2's
   pattern).
2. `loadShares(store, key, sessionId, hand): Promise<{pos, shareEnc}[]
   | null>` — decrypt and parse, `null` if nothing stored for that key.
3. `destroyShares(store, sessionId, hand): void` — `removeItem`, no
   decryption needed to delete.
4. **Persist-at-shuffle-end hook:** P1's task 5 step 2 computes all 52
   shares in `Game` "right after the host's second shuffle … cache the
   52 items" but does not persist them (P1's own scope: "no posting" —
   persistence for recovery is this phase's job, not P1's). Locate the
   exact point P1's diff caches them (re-verify at dispatch time — P1's
   doc names the moment but not a specific field name) and add a call
   to `saveShares` there. If that point lives inside `worker.ts`'s
   `Game` instance (off the main thread, same constraint P1's task 7
   step 1 already established for action persistence — no
   `localStorage` inside a Web Worker, confirmed against MDN by P1),
   route the 52 shares out via a new `post({ev: 'shares-cached',
   shares})` event and persist them in `useGame.ts`'s `w.onmessage`
   handler, the same synchronous-gap pattern P1's task 7 uses for
   write-ahead action persistence.
5. **Destroy-at-receipt-sign hook:** wherever P1's task 8 signs and
   persists the next hand-boundary receipt (both-signed, per P1's
   `nextHand()` extension), call `destroyShares` for the hand that
   receipt just closed. "The moment the hand's receipt is signed" —
   spec's own wording — pins this to the receipt-signing event, not to
   a later cleanup pass.

**Verification probe:** `npx vitest run src/test/share-store.test.ts`
— (a) a round trip through `saveShares`/`loadShares` against a fake
`Storage` and a real (test-generated) `CryptoKey` recovers all 52
`(pos, shareEnc)` pairs unchanged; (b) `destroyShares` followed by
`loadShares` returns `null`; (c) a construction with two different
hands' shares under the same session key does not cross-contaminate
(hand-scoped keying holds). The persist-at-shuffle-end and
destroy-at-receipt-sign *hooks themselves* are exercised by task 10's
reconnect/restore integration test, not by this task's own unit probe
(this task proves the store is correct in isolation; task 10 proves it
fires at the right moments in a real hand).

**Dispatch:** agent (session-tier, medium) — depends on task 2's
crypto module being correct; the store logic itself is straightforward
once that dependency exists.

---

### Task 4 — Standing instructions (check-fold when the bank runs low)

**Goal:** spec §5.1: "a client may carry standing instructions
(check-or-fold when the bank runs low, as online poker sit-outs do)" —
"legal by design," a client policy, not a contract rule. This phase
ships the toggle and the preference persistence; **acting on it during
an actual phase-2 dispute is `TBD-P4-CONTINUATION`** — P4 (disputes-
continuation) owns the on-chain phase-2 action machinery and has not
shipped (confirmed 2026-08-17: no `phase-4-disputes-continuation.md`
exists in this scaffold yet). This task's scope stops at "the
preference exists, is visible, and rides to Buyin in the evidence
bundle" — never at "the client autonomously files a phase-2 check or
fold," which needs P4's contract surface this repo cannot call anyway
(this repo never touches the chain directly, per this phase's own
Goal).

**Files:** create `src/core/standingInstructions.ts`,
`src/test/standing-instructions.test.ts`; modify `src/useGame.ts`
(state), `src/ui/App.tsx` (toggle UI).

**Steps:**
1. `type StandingInstruction = 'none' | 'check-fold-low-bank'`.
2. `savePreference(store, sessionId, value: StandingInstruction): void`
   / `loadPreference(store, sessionId): StandingInstruction` — keyed
   `vault:standing:${sessionId}`, defaulting to `'none'` when unset
   (opt-in, never a silent default that changes a player's exposure
   without their action).
3. App.tsx toggle, visible only when `vaultVersionRef.current === 2`
   (task 1): a labelled switch, *"If a dispute ever reaches a decision
   bank and mine gets low, check or fold automatically instead of
   risking a timeout."* — plain language, no "phase 2"/"bank" jargon
   assumed understood without this sentence attached.
4. **This phase does not implement the acting-on-it machinery.** The
   preference is included in `vault:evidence-v2`'s additive
   `standingInstruction` field (task 5, design decision 3) so that once
   P4/P5 ship phase-2 continuation, Buyin can read a player's
   already-expressed preference without a new round trip. Comment this
   boundary explicitly at the toggle's own definition site: `// Acting
   on this preference during an actual phase-2 dispute is
   TBD-P4-CONTINUATION — this file only stores and forwards the
   player's choice.`

**Verification probe:** `npx vitest run src/test/standing-instructions.test.ts`
— (a) `savePreference`/`loadPreference` round-trip against a fake
`Storage`; (b) default is `'none'` when nothing stored; (c) the toggle
is present in `App.tsx`'s rendered output only when a V2 flag is set
(a source-text regex probe, per this repo's `mobile.test.ts`/
`launch-flow.test.ts` precedent for source-text-only checks, since
`App.tsx` is a React component this repo has no DOM-rendering test
harness for beyond what already exists — confirm the exact precedent
pattern against those two files before writing this probe).

**Dispatch:** agent (workhorse, medium) — small, self-contained, one
genuine judgment call (scope boundary against P4) already resolved
above.

---

### Task 5 — Evidence bundle (resolves `TBD-P1-EVIDENCE-SHAPE`)

**Goal:** build and send `vault:evidence-v2` — P5's proposed shape,
matched (design decision 3) — from P1's persisted receipts, marker,
and action chain plus this phase's share store and standing-instruction
preference, applying D14's "hole shares born only by a completing
action" rule with a load-bearing comment and test.

**Files:** create `src/core/evidenceBundle.ts`,
`src/test/evidence-bundle.test.ts`; modify `src/useGame.ts` (send,
riding the hello-cycle callback), `src/core/actionStore.ts` (additive
`appendAction`/`loadActionChain`, per Files touched above), P1's
receipt-persistence code (additive `loadAllReceipts`, location
re-verified at dispatch time).

**Steps:**
1. **Extend `actionStore.ts` additively.** P1's `saveActionTip`/
   `loadActionTip` persist only the current write-ahead tip per hand —
   correct and sufficient for the refuse-to-re-sign guard P1 builds it
   for, insufficient for a dispute's full action-chain filing duty
   (spec §5.2 duty 3). Add `appendAction(store, sessionId, hand,
   action: SignedAction): void` (pushes onto an ordered array under a
   sibling key, `vault:actionchain:${sessionId}:${hand}`, distinct from
   the tip key so neither read path disturbs the other) and
   `loadActionChain(store, sessionId, hand): SignedAction[]`. Call
   `appendAction` from the exact same write-ahead call site P1's task 7
   step 3 marks `// load-bearing — do not relax` (persist-before-forward)
   — appending is additive to that persist call, not a replacement of
   it. **Re-verify against P1's actual shipped `actionStore.ts` before
   implementing** — if P1's diff already retains the full chain under a
   different name, this step becomes "read that name" instead of "add
   this function."
2. **Locate and extend P1's receipt store.** Add `loadAllReceipts(store,
   sessionId): SignedReceipt[]` returning every persisted receipt for
   the session, ordered by `(hand, subseq)`. Re-verify the actual store
   location against P1's shipped `useGame.ts`/`receipt.ts` diff at
   dispatch time (P1's own doc does not pin one, per the Files-touched
   note above).
3. `evidenceBundle.ts`: `build(sessionId, host, guest): Promise<Bundle>`
   — assembles:
   - `receipts`: `loadAllReceipts(...)`, hex-encoded per P5's shape.
   - `marker`: the latest persisted marker (P1's marker store, one
     entry — "latest only" per P5's shape) or `null`.
   - `actions`: `loadActionChain(...)` for the current/latest hand.
   - `shares`: **gated by the D14 rule, step 4 below** — `null` unless
     the gate opens.
   - `standingInstruction`: task 4's `loadPreference(...)` (design
     decision 3's additive field).
4. **D14 load-bearing rule: "hole shares born only by a completing
   action."** Spec §5.2: "posting them against a pending hand would let
   a counterparty who holds their own 52 shares locally read your cards
   and then decide with perfect information … the completing action is
   irrevocably on file before the victim's shares are due." This phase
   cannot observe on-chain filing state (that's Buyin/P3's job), so the
   client-side half of the rule is: **do not populate `shares` in the
   outgoing bundle for a hand whose action chain (step 1's
   `loadActionChain`) has no betting-completing action at its tip.**
   Implement as an explicit guard, commented `// load-bearing — do not
   relax (D14: hole-share-birth)` — **a rule-specific marker, not the
   plain "load-bearing — do not relax" string P1 already uses in
   `src/useGame.ts`/`src/core/actionStore.ts` for its own three rules**
   (fix round 1, M5/P6-3: a shared generic substring across files two
   different phases both write into makes P1's own exact-count audit
   collide with this phase's additions the moment both land; per-rule
   markers make every audit's grep target unambiguous regardless of
   what else lands in the same file). `const chain = loadActionChain(...); const
   complete = chain.length > 0 && isBettingComplete(chain-tip)` (reuse
   or mirror P1's replayed-betting-state-machine logic — re-verify
   whether P1 exports a completion predicate directly, or whether this
   task must derive one from `betting.ts`'s existing `closed` field the
   same way `game.ts`'s `runOutIfClosed` already reads `this.betting?.closed`,
   confirmed at `src/core/game.ts` in the section read above). If
   incomplete, `shares: null` regardless of what `shareStore.ts` (task
   3) holds locally — the shares exist on disk, encrypted, for the
   player's own recovery, but are withheld from the outgoing bundle.
5. **Send, riding the existing hello-cycle discipline** (design
   decision 4/P5's Inputs section): call `evidenceBundle.build(...)`
   and `w.postMessage({type: 'vault:evidence-v2', v: 1, session, host,
   guest, ...bundle}, '*')` from the same place `vaultSendProgress`
   already fires on every Buyin hello (`src/useGame.ts:777-813`'s
   pattern) — additive to that callback, not a new timer. Also send
   `vault:sessionkey-v2` (design decision 2, matched) from the same
   callback, using P1's session public-key address.

**Verification probe:** `npx vitest run src/test/evidence-bundle.test.ts`
— (a) a fixture with a complete action chain (ends in a signed fold, or
a full betting round) produces a bundle with `shares` populated; (b) an
identical fixture whose action chain has no completing action at its
tip produces `shares: null` even when the underlying `shareStore.ts`
has all 52 shares saved (the gate, tested directly, not just implied);
(c) `receipts`/`actions`/`marker`/`standingInstruction` each round-trip
through `build()` against hand-constructed store fixtures matching
P1's/task 4's actual export shapes (re-verify those shapes at dispatch
time per the framing note); (d) `grep -c "load-bearing — do not relax
(D14: hole-share-birth)" src/core/evidenceBundle.ts` reports **1** — the
full rule-specific marker, not the generic prefix (M5), so this
assertion cannot be satisfied by any comment other than this rule's
own.

**Dispatch:** agent (session-tier, high) — the cross-repo coordination
risk P5 itself named for its own evidence-relay task ("a wrong guess
here is invisible until P6 tries to send against it") is now this
phase's to retire; also carries one of the two D14 rules this phase
owns.

---

### Task 6 — Marker posting and the deal gate

**Goal:** spec §4's deal gate ("hand N+1 deals only after marker N
confirms — a pause, never a forfeit") and D14's second rule this phase
carries ("deal gate pause"). Implements the message pair design
decision 4 introduces, with the mandatory retry
`prototypes/marker-latency/RESULTS.md` establishes.

**Files:** create `src/test/marker-posting.test.ts`; modify
`src/useGame.ts` (the marker-send hook at P1's write-ahead
interception point, the new message pair, deal-gate state), `src/ui/App.tsx`
(pause banner).

**Steps:**
1. **Hook point:** P1's task 7 intercepts `w.onmessage` for
   write-ahead persistence of `act`/`marker`/`receipt` messages before
   forwarding to the transport. Once a `marker` message has been
   **both-signed** (P1's task 5 exchange completes — host signs, guest
   verifies-and-countersigns, sends back) and persisted, this phase
   fires the posting request from that same completion point (not from
   the earlier one-sided send).
2. **`vault:post-marker-v2` (poker→Buyin, one-shot per attempt, design
   decision 4):** `{type: 'vault:post-marker-v2', v: 1, session, seat,
   hand, marker: {...formats §4 fields..., sigHost, sigGuest}, receipt:
   {...formats §3 fields..., sigHost, sigGuest} | null}` — the
   `receipt` field carries the receipt to co-file when one is pending
   (P2's `fileMarkerWithReceipt`, the routine per-hand path,
   `phase-2-money-frame.md` decision 5), `null` when the referenced
   receipt is already filed. Only one player's poker tab needs to send
   this per hand in the honest case (either side's Buyin can submit a
   both-signed marker) — send from whichever seat's `useGame.ts`
   reaches the both-signed-and-persisted point first; if both send
   (a race, both honestly believing they're first), Buyin/the contract's
   own sequential-acceptance rule (`hand == markedHand + 1`) makes the
   second attempt a harmless no-op revert, not a double-post — no
   client-side coordination needed to prevent it.
3. **`vault:marker-result-v2` (Buyin→poker, one-shot):**
   `{type: 'vault:marker-result-v2', v: 1, session, hand, outcome:
   'confirmed' | 'transient-failure' | 'rejected', txHash?, error?}`.
   `'transient-failure'` is what step 4's retry targets;
   `'rejected'` (a real contract revert unrelated to network flakiness
   — e.g. a stale continuity hash) is not retried automatically, it
   surfaces as a distinct notice (step 5).
4. **Retry-on-transient-failure, mandatory** (design decision 5,
   RESULTS.md's own words: "MUST carry retry-on-transient-failure").
   On `'transient-failure'`, wait 2 seconds (RESULTS.md's own measured
   fix: "a single retry after 2s fixed every one, 17/17") and resend
   the identical `vault:post-marker-v2` request (same marker bytes,
   same signatures — nothing about the artefact changes on retry, only
   the submission attempt). Cap at a small bounded number of attempts
   (5, a round number with no measured basis beyond RESULTS.md's single
   retry being sufficient in the observed sample — flagged as Open
   question 2) before surfacing a persistent "still trying" state
   rather than giving up silently.
5. **The deal gate, honest and pause-only:** `beginMatch`/`nextHand`
   (P1's task 8 extension point) must not proceed to the next hand
   until this phase's marker-post request for the current hand reaches
   `'confirmed'` **or** the recovery leg (task 7) independently observes
   the same hand number via Buyin's `liveHand` read. While pending, the
   UI (`App.tsx`) shows: *"Waiting for the table to confirm on-chain —
   this usually takes a few seconds. Nothing is wrong; play will
   continue the moment it's confirmed."* **Never a forfeit, never a
   fold, never a timeout that awards anything** — comment the gate's
   own guard `// load-bearing — do not relax (D14: deal-gate pause)`.
   **This exact rule-specific marker, not the plain "load-bearing — do
   not relax" string P1's task 7 writes into this same file** (fix
   round 1, M5/P6-3, spec §4). This comment lands in `src/useGame.ts`,
   the same file P1's task 7 already writes two of its own comments
   into today — under the *old*, generic-substring wording, P1's own
   exact-2 grep there would read 3 the instant this comment landed,
   silently breaking a gate this phase doesn't own. M5 fixes this on
   **both** sides, coordinated: P1's companion fix (P1-4, same
   fix-round-1 row) moves P1's own three comments and its own audit
   grep to equally rule-specific markers (e.g. "(D14: write-ahead)"),
   so neither phase's grep target is ever a bare substring of the
   other's. This phase's own obligation, discharged here, is to never
   write the bare "load-bearing — do not relax" string on its own —
   every occurrence this phase adds carries its rule name.
6. **Cross-repo dependency, flagged not assumed:** step 5's "or observes
   via `liveHand`" branch needs `vault:hello`'s `liveHand` field (this
   document's Inputs-section gap 1). Until that field exists on the
   Buyin side, the gate can only use step 3's direct response — task 7
   documents the fallback precisely.

**Verification probe:** `npx vitest run src/test/marker-posting.test.ts`
— a stub "Buyin" responder (a plain function standing in for
`postMessage`, not a real window — mirrors this repo's existing
pattern of parameterising over `Pick<Storage, …>` rather than reaching
for the global, applied here to the message-send function instead):
(a) a responder that returns `'transient-failure'` twice then
`'confirmed'` results in exactly 3 send attempts, 2-second-apart
(fake timers), and the gate opens only after the third; (b) a
responder that returns `'rejected'` once results in exactly 1 attempt
and a distinct non-retry notice, never a silent retry loop; (c) the
gate's own state machine never calls anything resembling `forfeit()`
or mutates `stacksRef` regardless of outcome — asserted by spying on
those call sites and asserting zero calls across every branch above.
`grep -c "load-bearing — do not relax (D14: deal-gate pause)"
src/useGame.ts` reports **1** — the rule-specific marker (M5), which
task 10's combined audit re-runs; not counted against P1's own,
separately-graded "load-bearing — do not relax" generic-prefix count
in the same file, since this marker's suffix makes it a distinct
substring P1's own grep target never matches.

**Dispatch:** agent (session-tier, high) — money-adjacent (a bug here
either stalls the table indefinitely or, worse, opens a path where a
transient RPC failure gets misread as something that should forfeit
anything), and RESULTS.md's retry requirement is explicit and load-
bearing operationally even though D14 does not separately name "retry"
as one of its five rules.

---

### Task 7 — Marker-floor recovery (the second leg of §9.1)

**Goal:** loosen P1's conservative refuse-to-resume guard (P1's own
Outputs-to-P6 note: "more conservative than the spec's final state …
P6's job includes loosening this guard, not just adding a chain read").

**Files:** create `src/test/marker-recovery.test.ts`; modify
`src/useGame.ts` (the hand-number recovery path P1's task 4 builds).

**Steps:**
1. Spec §9.1's two-source recovery order: (1) the client's own stored
   receipts — P1's leg, strongest, "cannot be lied to about it"; (2)
   the on-chain marker floor — this phase's leg, via task 6's
   `liveHand` channel (the response message directly, or the amended
   `vault:hello` field once it exists on the Buyin side — task 6 step 6
   flags this dependency, resolved identically here).
2. **The loosening, precisely:** P1's guard today refuses to accept any
   hand number from the peer when local storage has no receipt for the
   session at all. This phase adds: if local storage is empty **but**
   a `liveHand` reading from Buyin (via a fresh `vault:hello` or a
   pending `vault:marker-result-v2`) reports a confirmed hand number
   `N > 0`, the client may resume at hand `N` (or `N+1`, per the deal
   gate — the marker at `N` is confirmed, so play resumes at the hand
   after it) rather than refusing outright. **Still refuses** when
   neither source exists (both local storage and the chain read are
   silent) — that residual case is exactly what P1's guard exists for,
   unchanged.
3. **Trust ordering, unchanged from spec:** the marker floor is
   consulted only as a *fallback* when local storage has nothing — a
   client with a stored receipt never lets a chain read override it
   (the local receipt is a stronger source per spec's own ordering,
   "cannot be lied to about it").

**Verification probe:** `npx vitest run src/test/marker-recovery.test.ts`
— (a) empty local storage + no chain read available ⇒ still refuses
(P1's original behaviour, regression-gated); (b) empty local storage +
a `liveHand` reading of `N` ⇒ resumes at the hand the deal gate implies,
never lower than `N`; (c) a populated local storage's receipt always
wins over a conflicting chain reading (trust-ordering test); (d) `npx
vitest run src/test/hand-number.test.ts` (P1's own test file, re-run
here) still passes unmodified — this task extends P1's guard, it does
not replace the file or its existing assertions.

**Dispatch:** agent (workhorse, medium) — a bounded, well-specified
loosening of an existing guard, not new architecture.

---

### Task 8 — The four forfeit sites, rewritten for V2

**Goal:** spec §9.2/§9.7/§9.14: V2 sessions must never unilaterally
award a stack. V1 sessions (`vaultVersion === 1`, or `vaultOn === false`)
keep exactly `poker@d66a68a`'s behaviour, regression-gated.

**Files:** create `src/core/forfeitPolicy.ts`, `src/test/forfeit-v2.test.ts`;
modify `src/useGame.ts` (three of the four sites plus `vaultMaybeSign`'s
gating), `src/core/game.ts` (`forfeit()`, the `bye` handler), `src/worker.ts`
(the catch-all).

**Steps:**
1. **The four sites, confirmed 2026-08-17 by exact line:**
   - `src/useGame.ts:1352-1400`ish, `onPeerRestart` — today, once a
     match has started, sets `stacksRef.current = {me: total, them: 0}`
     **directly in the hook**, bypassing `Game`/`worker` entirely, and
     tells the player "the whole buy-in is yours."
   - `src/useGame.ts:1320-1338`ish, the disconnect-grace `setTimeout` —
     posts `{cmd: 'forfeit', reason: '…', whole: true}` to the worker,
     which calls `game.forfeit(reason, true)`.
   - `src/core/game.ts:226`, the `bye` handler — `this.forfeit(\`opponent
     left: ${m.reason}\`)` (`whole` defaults `false` — pot-only, not the
     whole match).
   - `src/worker.ts:69`, the catch-all `catch` block — `game?.forfeit((err
     as Error).message)` (`whole` defaults `false` — pot-only).
2. **`forfeit()` itself** (`src/core/game.ts:418-441`) stays a pure,
   local, deterministic function — it computes `this.outcome`/
   `this.stacks` from the betting state it already has, transmits
   nothing, and touches no chain. This is harmless in isolation for
   either protocol version; the risk is entirely in what the *callers*
   do with its result afterward.
3. **`src/core/forfeitPolicy.ts`**: `decideForfeitOutcome(vaultVersion:
   1 | 2, whole: boolean): 'settle-locally' | 'pause-for-dispute'` — a
   small, pure, exhaustively-testable predicate: `vaultVersion === 1`
   (or non-vault free play) → `'settle-locally'` (today's behaviour,
   unchanged); `vaultVersion === 2` → **always** `'pause-for-dispute'`,
   regardless of `whole`. Every one of the four sites calls this before
   acting on a forfeit outcome.
4. **`onPeerRestart` rewritten:** when `decideForfeitOutcome` returns
   `'pause-for-dispute'`, do **not** touch `stacksRef`/`setStacks` at
   all. Instead: `setConn('gone')`, `setPeerAbandoned(true)` (unchanged
   — the connection-state signal stays honest), and a distinct notice:
   *"Your opponent's table closed. Nothing has been decided — if they
   don't come back, you can open a dispute in Buyin once the evidence
   window is available. Your side's receipts and action chain are
   already being kept ready to file."* No `whole=true` semantics for
   V2 — the money question is entirely deferred to receipts + the
   dispute path, per this phase's own Goal ("reach a final or file,
   never award stacks unilaterally").
5. **Grace timeout rewritten:** post `{cmd: 'forfeit', reason, whole:
   vaultVersion === 1}` — **V1 keeps `whole: true` unconditionally**,
   exactly `poker@d66a68a`'s deliberate, ratified behaviour (the
   operator's 2026-08-17 ratification and spec §9.2's own note: "the
   same rule was deliberately *extended* to the grace timeout for V1
   today … correct for V1"); this task must not silently reverse it.
   `whole`'s value is **moot for V2** — `decideForfeitOutcome` (step 3)
   returns `'pause-for-dispute'` for `vaultVersion === 2` regardless of
   what `whole` was passed, so the flag is set correctly here only for
   V1's sake, not read by the V2 branch at all. For V2, additionally
   skip even the pot-local `forfeit()` call's effect on `stacksRef`/UI
   state that would read as "decided" — the same `'pause-for-dispute'`
   notice as step 4.
6. **`game.ts:226`'s `bye` handler and `worker.ts:69`'s catch-all:** both
   already default `whole: false` (pot-only), which is much closer to
   V2-safe already. The remaining fix for both: after `forfeit()`
   returns, the **caller** (in `useGame.ts`, wherever the resulting
   `view()`/outcome reaches the UI) must not let V2 sessions treat
   `this.outcome`/`this.stacks` as chain-settleable — i.e., do not let
   this locally-computed pot-forfeit outcome flow into a receipt that
   gets signed as if both sides agreed to it. Practically: gate
   whatever code path would otherwise auto-advance to a receipt-signing
   step off a `forfeit`-reasoned `outcome` on `vaultVersion === 2`,
   showing the same pause notice instead. `Game`/`worker` need no
   internal changes for these two sites beyond what step 3's predicate
   consumes at the call site.
7. **`vaultMaybeSign` gated to V1 only.** `vaultMaybeSign()`
   (`src/useGame.ts:820-870`ish) signs `vaultResultHash(...)` — a V1-
   only, winner-takes-all-shaped hash Channel.sol verifies — and is
   currently unconditional once `vaultOn` is true. For V2 sessions this
   function must never fire: V2 settlement is receipts + `final` +
   `resolve()` (P1's/P2's machinery), never a single result hash. Add
   `if (vaultVersionRef.current !== 1) return;` at the top of
   `vaultMaybeSign`, commented with the reason (this is not one of the
   four named forfeit sites, but it is the mechanism that would turn
   any of their outcomes into real V1 chain money, so it is fixed in
   the same task rather than left as a silent gap).

**Verification probe:** `npx vitest run src/test/forfeit-v2.test.ts` —
(a) `decideForfeitOutcome(1, true) === 'settle-locally'`,
`decideForfeitOutcome(1, false) === 'settle-locally'`,
`decideForfeitOutcome(2, true) === 'pause-for-dispute'`,
`decideForfeitOutcome(2, false) === 'pause-for-dispute'` (exhaustive,
all four inputs); (b) a V1-configured harness reproduces
`poker@d66a68a`'s existing behaviour at all four sites byte-for-byte
(regression: re-run the *existing* forfeit-adjacent assertions, if any
exist in `grace.test.ts` or elsewhere — grep before writing, per the
hard rules — against an unmodified-for-V1 code path), **including a
direct assertion that the grace-timeout site posts `{cmd: 'forfeit',
whole: true}` when `vaultVersion === 1`** — step 5's own regression
target, checked explicitly rather than only implied by (a)'s pure-
function coverage; (c) a
V2-configured harness at each of the four sites never calls
`setStacks`/mutates `stacksRef` and never calls `vaultMaybeSign`'s
signing branch; (d) `vaultMaybeSign` with `vaultVersion=2` returns
immediately without reaching the `eth.request` call (spied, asserted
zero calls).

**Dispatch:** agent (session-tier, high) — four sites plus one gating
fix, genuine regression risk against V1's shipped behaviour
(`poker@d66a68a`, which stays the load-bearing baseline), and getting
the V1/V2 branch wrong in either direction is exactly the kind of bug
that is invisible until a real dispute.

---

### Task 9 — Decision clock: off-chain UX only

**Goal:** spec §9 item 5, resolved: "every money-deciding clock is now
the chain's … the off-chain decision clock decides table flow only, so
client-vs-relay ownership is a UX choice, no longer a settlement one."
Confirm the existing client-side clock (`armDeadline`, `graceFor`) is
never mistaken for a money clock in a V2 session, and label it so a
player cannot confuse it with the chain's window/bank clocks D15
parameterises.

**Files:** modify `src/useGame.ts` (label near the existing deadline
UI), `src/ui/App.tsx` (the countdown display), extend
`src/test/grace.test.ts`.

**Steps:**
1. **Audit, not redesign:** `armDeadline()`/`graceFor()`'s existing
   mechanism already only decides *this client's local UI* (when to
   show "your opponent may be gone," when to offer the pot-local
   forfeit today's V1 sites use) — it was never wired to move money on
   its own; task 8 is what makes that true robustly for V2 by cutting
   the sites that *did* let a local timeout move money. This task's
   job is the audit that confirms it and the label that says so.
2. Grep for any remaining path where a client-side deadline (`armDeadline`,
   `graceFor`, `peerDeadline`, `selfDeadlineBoth`) reaches `setStacks`
   or `vaultMaybeSign` without going through task 8's
   `decideForfeitOutcome` gate first — `grep -n "setStacks\|vaultMaybeSign"
   src/useGame.ts` cross-referenced by hand against every deadline
   call site; record the check as a negative-result comment in the
   test file (`// audited 2026-08-17: no client-side deadline reaches
   settlement outside forfeitPolicy.ts's gate`).
3. **Label, V2 only:** wherever the existing countdown UI renders
   (`App.tsx`, the peer-gone/deadline display), add, only when
   `vaultVersion === 2`: *"This clock is for your own screen only — it
   never decides money. If a real dispute opens, the chain keeps its
   own clocks (spec §5.1/§5.3), separate from this one."*

**Verification probe:** `npx vitest run src/test/grace.test.ts` — existing
assertions unchanged (regression), plus a new case asserting the label
string is present in `App.tsx`'s source text when V2 is active (source-
regex probe, same precedent as task 4's toggle check). The audit itself
(step 2) is recorded as a comment, not a runnable assertion — flagged
here rather than invented as a fake-passing test, since "no code path
does X" is better shown by task 8's own exhaustive branch coverage than
restated as a second, weaker grep-based test.

**Dispatch:** agent (workhorse, low) — mostly confirmation and one UI
string; the real work already happened in task 8.

---

### Task 10 — D14 comment audit, fixtures, and reconnect/restore integration tests

**Goal:** D12's fixtures this phase owns, the mechanical audit that
this phase's two D14 rules carry their required comments (mirroring
P1's own task 9), and integration tests proving the persist-at-shuffle-
end / destroy-at-receipt-sign hooks (task 3) and the deal-gate pause
(task 6) actually fire at the right moments in a real hand, not just in
each task's own isolated unit probe.

**Files:** create `src/test/p6-load-bearing-audit.test.ts`,
`src/test/reconnect-restore.test.ts`.

**Steps:**
1. **D14 comment audit, this phase's two rules, by distinct rule-specific
   marker, never by a generic count** (fix round 1, M5/P6-3; P1's task 9
   audits its own three rules the same, coordinated way — this is the
   other half): `grep -c "load-bearing — do not relax (D14:
   hole-share-birth)" src/core/evidenceBundle.ts` reports **1** (task 5
   step 4); `grep -c "load-bearing — do not relax (D14: deal-gate
   pause)" src/useGame.ts` reports **1** (task 6 step 5). Neither probe
   greps the bare "load-bearing — do not relax" prefix — that string
   also appears in `src/useGame.ts`/`src/core/actionStore.ts` from P1's
   own three rules, and a prefix-only count would conflate this phase's
   two markers with P1's three the moment both land in the same file.
   This task's own audit therefore cannot detect a P1 comment
   regression (that is P1's task 9's job, on P1's own rule-specific
   markers) — it only proves this phase's own two markers are present,
   exactly once each, by their full distinguishing text.
2. **Fixture re-derivation (D12):** `grep -n "^### Findings"
   docs/superpowers/parking/v2-cash-game-settlement.md` (vault repo)
   from `## Tenth cold check` onward, independently building the list
   of every constructed case belonging to this phase's scope (client
   chain-awareness, session-key/share persistence, forfeit rewrites,
   the deal gate). Diff against `fixtures-index.md`'s client-side row
   (bottom of file: "F12.3's canonical-amount signing, F14.3's
   write-ahead ordering … D14's load-bearing rules — enumerated in
   P1/P6 docs" — P1 already claims F12.3/F14.3; this phase's own claim
   is the D14 rules it carries, named in step 1). Report any
   client-chain-shaped case the re-derivation finds that
   `fixtures-index.md` does not already attribute to P1 or P6, as a
   plan finding for `review-findings.md`, not a silent addition here.
3. **`test_S_deal_gate_pause`** (named here, not in `fixtures-index.md`
   yet — step 2's re-derivation is what confirms whether this belongs
   there formally): a hand's marker post reports `'transient-failure'`
   twice, then never resolves within the test's timeframe; assert the
   client's state never transitions to anything resembling "hand N+1
   dealt" and never calls `forfeit()`/`setStacks`, only the pause UI
   state, for as long as the test lets it run.
4. **Reconnect/restore integration tests**, extending `e2e.test.ts`'s
   `connect()`/`pump()` harness (re-verify its current shape against
   P1's shipped diff first — P1's task 4 changes `Game`'s constructor
   signature, confirmed at `src/test/e2e.test.ts:19-20` today, pre-P1):
   (a) a hand plays to a betting-complete state, shares are saved via
   task 3's `saveShares` at shuffle end (asserted by reading the fake
   store directly), the receipt for that hand signs, and `loadShares`
   for that hand returns `null` immediately after (destroy-at-receipt-
   sign fires); (b) a simulated mid-hand "reload" (fresh `Game`
   instance, same session id, empty in-memory state but a populated
   fake store) recovers via task 7's marker-floor leg when local
   receipts are absent but a `liveHand` reading is supplied, and
   refuses when neither is available (task 7's fixture (a), re-run
   inside the fuller harness rather than in isolation, to catch any
   interaction task 7's own unit test wouldn't).

**Verification probe:** `npx vitest run src/test/p6-load-bearing-audit.test.ts
src/test/reconnect-restore.test.ts` — the two grep counts from step 1
match exactly; the fixture re-derivation report (step 2) is present in
the task's completion notes, present/absent per row, any drift flagged
as a plan finding rather than silently resolved; every integration
scenario in step 4 passes.

**Dispatch:** agent (workhorse, high) — long and exacting, follows
P1's own task-9 pattern closely, but the integration harness extension
needs real care (it is the one place this phase proves its pieces
compose, not just that each piece is individually correct).

---

### Task 11 — Buyin-side executor handlers (vault repo — sanctioned exception)

**Goal:** fix round 1, B3/AF-11.3: "P6 owns BOTH ends of its new
message pairs … without it session-key encryption + marker post have
no executor." Tasks 2 and 6 design and send `vault:derive-key-v2`/
`vault:post-marker-v2`; neither round trip has anyone to answer it
without this task. This is the **sole, explicitly sanctioned exception**
to this phase's poker-repo-only side-effect boundary (stated at the top
of this document's Inputs section) — it touches **exactly one file
outside the poker repo: the vault repo's `src/mainV2.js`**, and no
other vault-repo file. `abiV2.js`, `bondV2.js`, `evidenceStoreV2.js`,
`autofileV2.js` and every other file P5 owns stay untouched; a new pure
helper this task needs lives inline in `mainV2.js` rather than as a new
file, keeping the exception as narrow as the finding that authorized
it.

**Files:** modify `vault` repo's `src/mainV2.js` only. (Re-verify P5's
actual shipped shape before implementing — P5 is "in revision" per
`README.md`'s Status block, and this task's assumptions about
`mainV2.js`'s message-listener location and the `withBusy`/wallet-client
patterns are cited from P5's own phase doc, not from code on disk, per
this document's framing note at the top of Inputs.)

**`4b2af2c` (D17, fix round 1 B5): whoever dispatches
this task records `git -C /home/dev/projects/vault rev-parse HEAD` as
`4b2af2c` before this task's own edit lands** — the
Recovery section's vault-repo isolation check below diffs against it,
the same pattern the poker-repo `4acc658` uses for every other
task in this document.

**Steps:**
1. **`vault:derive-key-v2` receiver.** On receipt (same `event.origin`
   check P5's task 2 step 3 already establishes for
   `vault:sessionkey-v2`/`vault:evidence-v2` — re-verify the exact guard
   `mainV2.js` uses before reusing it), read `session` from the message
   (task 2 step 1's envelope carries `session`, `seat`, `nonce`; the
   `nonce` rides for Buyin's own logging only, never inside the signed
   text). Build the **identical fixed template** task 2 step 1 names —
   `'Vault session key — session ${session} — do not sign this text on
   any other site.'` — and call `walletClient.signMessage({account,
   message: text})` (viem's string form, the same call P5's task 3
   already uses for registration, confirmed 2026-08-17 against
   `node_modules/viem/_esm/actions/wallet/signMessage.js`). Reply
   `window.opener.postMessage({type: 'vault:derive-key-result-v2', v: 1,
   session, nonce, signature}, '*')` — mirrors `main.js`'s existing
   `window.opener.postMessage(...)` pattern for `vault:sent`/
   `vault:confirmed` (`src/main.js:843,864`, vault repo).
2. **`vault:post-marker-v2` receiver.** On receipt, read `session`,
   `hand`, `marker` (both-signed, formats §4 fields), and `receipt`
   (formats §3 fields, or `null` when the referenced receipt is already
   filed — task 6 step 2's envelope). Call `fileMarkerWithReceipt(...)`
   when `receipt` is present, else `fileMarker(...)` (P2's ABI, per P5
   task 1's `abiV2.js`), driven through the **existing single-write-at-
   a-time `withBusy`/`pendingSeq` machinery** (`main.js:757-877`'s
   pattern, the same machinery P5's design decision 4 already reuses
   for its own auto-filer) — never a second, parallel write queue.
3. **Result classification, one attempt, honestly reported — no retry
   here** (design decision 5: retry lives in poker, not Buyin). On a
   confirmed transaction: `window.opener.postMessage({type:
   'vault:marker-result-v2', v: 1, session, hand, outcome: 'confirmed',
   txHash}, '*')`. On a caught error: classify by shape, not by guessing
   — a network-level failure (timeout, connection reset, or the
   nonce-race shape `prototypes/marker-latency/RESULTS.md` measured —
   "nodes lag each other on nonce state, so rapid sequential sends
   race") reports `outcome: 'transient-failure'`; a caught revert
   carrying a real Solidity error/require string (a genuine on-chain
   rejection, e.g. a stale continuity hash) reports `outcome:
   'rejected', error`. This task sends the raw outcome of exactly one
   attempt each time it is asked; task 6's poker-side state machine is
   what decides whether and when to ask again.
4. **No new timer, no new origin logic.** Both handlers install into
   `mainV2.js`'s existing message listener (the same location task 2's
   own receivers install into, P5's task 2 step 3) — additive branches
   on `data.type`, not a second listener.

**Verification probe:** this repo has no JS test framework (P5's own
established fact, `phase-5-buyin-ui.md`'s Inputs section: "no `vitest`,
no `jest`, no DOM-testing library" — build-green + grep-based structural
probes + uncommitted `node -e` scripts is the established floor for
this repo, not a gap this task introduces). `cd /home/dev/projects/vault
&& npm run build` — exits 0. `grep -n "vault:derive-key-v2\|vault:post-marker-v2\|vault:derive-key-result-v2\|vault:marker-result-v2"
src/mainV2.js` — all four strings present. A `node -e` script
(documented inline in this task's completion notes, not committed, per
P5's task 2 precedent): construct two or three fake caught-error shapes
(a timeout-shaped error, a nonce-shaped RPC error, a revert-shaped viem
`ContractFunctionRevertedError`) and assert the classification function
this task exports routes each to the correct `outcome` — YES = exact
match, NO = a real defect. `git diff 4b2af2c..HEAD --
src/main.js src/abi.js src/deployments.js public/index.html server.mjs`
(D11/D13's V1-isolation check, base-ref form per D17 — not `--stat`
with no base, which reads empty once committed regardless of what
changed) — empty output, confirming this task's one authorized file
touches nothing V1 owns either.

**Dispatch:** agent (session-tier, high) — vault-repo file, a real
wallet-signature request and a real contract write, and the executor
half of two money-adjacent round trips this phase's own operator floor
(gate 7, steps c/d/g below) depends on existing at all.

## Phase-boundary verification

Gate type: **technical-auto floor + one operator-run probe.**

1. **YES/NO — full suite green.** `npm test` (`vitest run`). Baseline
   today, executed 2026-08-17 against unmodified `poker@d66a68a`: **278
   passing, 23 files, exit 0.** P1 lands its own tests before this
   phase starts implementation; run `npm test` once, immediately before
   task 1 dispatches (the same moment `4acc658` is recorded,
   per the Task order note's D17 addition), and read the actual number
   off that run — this is **`TBD-P1-COUNT`** only at drafting time,
   never at dispatch time, when it is a concrete, directly-observed
   integer (fix round 1, B8/P6-1: a threshold this document can only
   define by "summing at completion" is not checkable in advance and
   is not a real gate). **This phase's own contribution is a stated
   floor, pinned now, per task — not tallied later:** task 1 ≥ 4, task
   2 ≥ 4, task 3 ≥ 3, task 4 ≥ 3, task 5 ≥ 4, task 6 ≥ 3, task 7 ≥ 3,
   task 8 ≥ 4, task 9 ≥ 1, task 10 ≥ 4 (each number is the count of
   *genuinely new* lettered assertions that task's own Verification
   probe above enumerates in its own new test file — read directly off
   this document, not estimated). **Task 7's own floor is 3, not the 4
   items its probe lists**: probe item (d) there re-runs P1's
   pre-existing `hand-number.test.ts` to confirm no regression — those
   assertions already exist inside the count read at dispatch time (they
   are P1's, already in the baseline), so counting them again here would
   double-count and set an unmeetable floor; only (a)-(c), in this
   phase's own new `marker-recovery.test.ts`, are new. Summing the ten
   task floors gives **≥ 33 new passing tests**, fixed by this document,
   not by whatever tasks 1-10 happen to land. The gate: `npm test`'s
   post-phase passing count **≥ (the `npm test` count read at dispatch
   time) + 33**. A task landing more than its stated minimum is fine
   (more coverage, not a violated floor); landing fewer is not, since it
   falls short of assertions this document itself already commits to
   for that task.
2. **YES/NO — new modules exist and are typed.** `npx tsc --noEmit -p .`
   — exit 0, no new type errors from the five new `src/core/*.ts` files
   or the `useGame.ts`/`game.ts`/`worker.ts`/`App.tsx` signature
   changes.
3. **YES/NO — this phase's own tests pass in isolation.** `npx vitest
   run src/test/vault-version.test.ts src/test/session-key-crypto.test.ts
   src/test/share-store.test.ts src/test/standing-instructions.test.ts
   src/test/evidence-bundle.test.ts src/test/marker-posting.test.ts
   src/test/marker-recovery.test.ts src/test/forfeit-v2.test.ts
   src/test/p6-load-bearing-audit.test.ts src/test/reconnect-restore.test.ts`
   — all exit 0, no skipped tests.
4. **YES/NO — P1's own tests still pass unmodified in intent.** `npx
   vitest run src/test/hand-number.test.ts src/test/write-ahead.test.ts
   src/test/marker.test.ts src/test/receipt.test.ts src/test/signed-action.test.ts`
   (P1's own files, re-verify this exact list against P1's shipped diff
   before running, per the framing note) — exit 0; this phase extends
   P1's guards and stores, it does not weaken any assertion P1 shipped.
5. **YES/NO — no direct RPC call anywhere in this phase's diff.** Per
   D17 (fix round 1, B5): a whole-tree `grep` cannot distinguish
   "already there before this phase" from "this phase's own diff," so
   this gate is a diff against `4acc658` (recorded in the Task
   order note at dispatch), added lines only:

       git diff 4acc658..HEAD -- src/ \
         | grep -c '^\+.*\(eth_sendTransaction\|eth_call\|eth_getTransactionReceipt\|eth_blockNumber\|publicClient\|createPublicClient\|writeContract\|readContract\|getTransactionReceipt\|fetch(.*:8545\)'

   YES = `0` (poker repo; every chain interaction this phase adds routes
   through a `vault:*` postMessage to Buyin). **Blacklist widened past
   the original four tokens** (fix round 1, minor/P6-4): `readContract`
   and `getTransactionReceipt` (viem's read-call and receipt-polling
   surfaces, the same family as `writeContract`/`publicClient`, and
   just as much a direct-RPC violation as either), `eth_getTransactionReceipt`/
   `eth_blockNumber` (the raw JSON-RPC method names underneath those
   viem calls — catching a hand-rolled `window.ethereum.request(...)`
   that bypasses viem entirely, the same class of gap `eth_call`/
   `eth_sendTransaction` already close for the write side), and a bare
   `fetch(...:8545)` (catching a hand-rolled HTTP call straight at a
   local RPC port, no library involved at all — the most direct
   possible violation and the one none of the library-name tokens
   would ever match). Only *added* lines count (`^\+`, not D17's more
   general `^[-+]`) — this gate asks "did this phase's diff introduce a
   new RPC call," not "did the token's presence change," so a
   hypothetical removal of an RPC call would not need to trip it.
   `git diff 4acc658..HEAD -- src/ | grep -c
   '^\+.*\(eth_requestAccounts\|personal_sign\)'` **is** expected to be
   `> 0` (the existing `vaultMaybeSign` precedent this phase gates
   rather than removes, task 8 step 7, plus task 2's new derive-key
   round trip) — this probe distinguishes "no RPC" from "no wallet
   signature," per this phase's own Goal framing.
6. **YES/NO — D14 audit passes.** Task 10 step 1's grep counts match.
7. **Operator-run — one two-tab smoke, extending P5's own floor.**
   Assumes P1, P2, P5, and this phase have all landed and P5's own
   operator floor (`phase-5-buyin-ui.md`'s steps 1-9: anvil running,
   `DeployV2.s.sol` deployed with short test durations, Buyin serving
   on `:8790`) has already been run once and produced a live `Status:
   Active` V2 session between two Buyin tabs with two funded test
   wallets. **What this floor adds:** a real poker tab on each side,
   proving the seam this phase builds actually carries real bytes. **This
   requires task 11 to have landed and be running as part of that same
   Buyin instance** — steps c, d, and g below exercise the derive-key
   and post-marker round trips, and without task 11's executor handlers
   neither has anyone on the Buyin side to answer it (fix round 1, B3);
   this is exactly the gap B3 named this floor as unable to pass without.

   a. In a third and fourth terminal, `cd /home/dev/projects/poker &&
      npm run dev` (once — Vite serves both tabs from the one dev
      server, port 5173, confirmed in `vite.config.ts`).
   b. Open two browser tabs at `http://localhost:5173/?vault=2&room=…`
      (a fresh room id) — one as host, one as guest, exactly the normal
      two-tab poker flow, now with `vault=2` selecting V2 mode (task
      1). **YES/NO:** each tab's Buyin-opening button now opens
      `v2.html`, not the bare Buyin page.
   c. Complete the declared-depth handshake in each Buyin tab (P5's
      floor, steps 6-9) using the session key each poker tab now
      supplies automatically via `vault:sessionkey-v2` (rather than
      hand-typing `?sessionkey=…`, the bridge P5's floor used before
      this phase existed). **YES/NO:** neither Buyin tab shows the
      "waiting for your poker table" session-key message for more than
      one hello cycle (~4s) after the poker tab is open.
   d. Play one hand to completion on the two poker tabs. **YES/NO:**
      after the hand, each poker tab briefly shows the "waiting for the
      table to confirm on-chain" pause (task 6 step 5) before the next
      hand deals — a few seconds, not stuck.
   e. Stop `anvil` (Ctrl-C in its terminal) **before** starting a second
      hand, forcing a real transient failure. **YES/NO:** the pause
      message stays up, calm and specific ("nothing is wrong"), with no
      forfeit notice and no stack change on either tab, for as long as
      anvil is down.
   f. Restart `anvil` (same command, same terminal — note: a restarted
      local anvil is a **fresh chain**, so this step is a UI-behaviour
      check only, not a real confirmation; skip re-confirming the
      actual marker post and instead confirm the pause banner clears
      once the client's retry loop next reports back, which on a dead
      RPC will itself time out per task 6 step 4's attempt cap — verify
      the **cap message** appears rather than an infinite pause).
   g. In the host's Buyin tab, click "Open a dispute." **YES/NO:**
      within one hello cycle, the host's poker tab's evidence bundle
      (task 5) has been sent, and Buyin's own auto-filer (P5's task 5,
      already landed) shows at least the `(0,0)`/latest-receipt filing
      attempt firing on its own, unprompted.

**What this floor deliberately does not cover:** a genuine phase-2
dispute continuation (task 4's standing-instruction toggle has nothing
live to act on yet — `TBD-P4-CONTINUATION`), and the wallet-determinism
probe's non-deterministic branch (every wallet available for this
smoke is expected to be RFC-6979-deterministic; forcing the fallback
path is task 2's own unit-test territory, not reproducible live without
a genuinely non-deterministic signer). A full live-network dispute
sweep is P7's job, not this phase's floor.

## Outputs to next phase

**To P7 (deploy-live-sweep):**
- Every `vault:*` message this phase adds
  (`vault:derive-key-v2`/`-result-v2`, `vault:post-marker-v2`/
  `-result-v2`) is origin-checked the same way the existing eight are;
  no new origin logic for P7 to audit beyond re-confirming
  `deriveVaultOrigin`'s three-environment behaviour still holds
  unchanged (this phase does not touch it).
- The operator-run floor above (step 7) is the two-tab smoke P7's live
  sweep graduates from local anvil to Base Sepolia — same steps, real
  gas, real confirmation latency (already measured, RESULTS.md).
- `vaultVersion`'s `?vault=2` URL convention is what P7's own
  documentation/invite-link guidance should carry forward for real
  matches.

**Remaining vault-repo addendum, named for whoever revises P5 next
(genuinely out of this phase's scope — B3's sanctioned exception covers
only task 11's two message pairs, not this field):**
- `mainV2.js`'s `sendHelloToOpener`-equivalent needs one added field,
  `liveHand: number` (reading `ChannelV2.liveHand(session)`), and
  `abiV2.js`'s read set needs that getter added — both currently absent
  from P5's documented scope (this document's Inputs-section gap 1).
  Without it, task 6's deal-gate confirmation and task 7's recovery
  leg fall back to `vault:marker-result-v2`'s direct response only,
  which is sufficient for the operator floor above but not for the
  "recover from a completely fresh tab, no local storage, Buyin already
  ahead of me" case spec §9.1 describes. (Per this document's AF-10
  coherence-pass note above, this specific addendum is now recorded as
  P5's own dated amendment, not an open gap this phase still carries —
  named here only for completeness of this section's history.)

**Shipped by this phase, not merely named as a dependency (fix round 1,
B3):** Buyin **receiving** `vault:derive-key-v2` and
`vault:post-marker-v2` and **sending** their `-result-v2` counterparts
(this document's Inputs-section gap 2) is task 11, in `src/mainV2.js`,
the sanctioned exception to this phase's poker-repo-only boundary —
not a dependency left for a future phase to close.

## Open questions

1. **Key-derivation KDF: a single SHA-256, not HKDF (task 2 step 4).**
   Default: as designed — the signature already carries enough entropy
   and determinism is the load-bearing property, not domain separation
   across multiple derived keys (only one key is ever derived per
   wallet in this design). **Overrules:** whoever implements task 2, if
   a future phase needs a second key derived from the same wallet
   signature (at which point HKDF's `info` parameter would earn its
   place) — not needed for this phase's own scope.
2. **Marker-post retry cap: 5 attempts, not a number RESULTS.md
   measured (task 6 step 4).** Default: 5, with a visible "still
   trying" state past that rather than silent abandonment.
   **Overrules:** the operator, once live Base Sepolia congestion-tail
   data exists (§11.2(a)'s gated rerun, still open per `README.md`'s
   Prerequisites) — this phase's cap is a reasonable placeholder, not a
   measured constant.
3. **`vaultVersion` stored under a new `localStorage` key
   (`vault:version`), not folded into the existing `vault:enabled`
   value (task 1 step 1-2).** Default: as designed — keeps `vaultOn`
   ("is Vault on") and `vaultVersion` ("which contract") as genuinely
   separate axes, matching how P2/P5 keep V1 and V2 as separate
   contracts/pages rather than one contract with a mode flag.
   **Overrules:** nobody currently — this is a clean two-key design
   with no known downside; recorded as an open question only because
   it is a real choice, not because it is contested.
4. **`onPeerRestart`'s V2 rewrite (task 8 step 4) never falls back to
   any local settlement, ever — even a clearly-cooperative reload.**
   Default: as designed, per spec §0's own law ("each player's outcome
   must never depend on the counterparty's cooperation") — a peer
   reload always routes to "wait, or open a dispute," never a
   local-only "welcome back, resuming" shortcut for V2, unlike V1's
   friendlier "fresh stacks, no harm done" path for a reload *before*
   the match starts (which this phase does not touch — that branch
   stays, since spec's own law only binds *after* real money is at
   risk, and P1's task 4's own guard already treats "no receipts yet"
   as "nothing started"). **Overrules:** whoever runs the arc-end
   review, if a friendlier V2 pre-first-receipt reload path turns out
   needed — not addressed here since it mirrors P1's own already-drawn
   line (receipt `(0,0)` as the risk boundary).

## Recovery

- **P1's or P5's shipped shape differs from what this document assumed.**
  Every task above names its specific assumption and the file/function
  it depends on; the framing note at the top of Inputs states the
  general rule (re-verify before importing). Recovery for any single
  mismatch is a small additive fix at that one call site, not a
  document-wide rewrite — none of this phase's own architecture (the
  `vaultVersion` gate, the crypto module, the evidence bundle, the
  marker-posting state machine) depends on P1/P5's exact internal
  naming, only on the *existence* of the functions this document names.
- **The `liveHand` vault-repo addendum never lands before this phase
  needs to ship.** Tasks 6 and 7 both have a documented fallback (task
  6 step 6, task 7 step 2's "or a pending `vault:marker-result-v2`")
  that does not require it — the addendum sharpens the recovery leg's
  reach (a cold tab with zero local state and no in-flight post), it
  does not block the phase's own floor (verification step 7 above is
  written to pass without it).
- **A task's V2 branch is wrong in a way that also breaks V1.** Every
  task gates on `vaultVersion`/`vaultOn` at the call site, never inside
  a shared function that both versions call unconditionally (task 8's
  `forfeitPolicy.ts` is the clearest instance of this pattern — a pure
  function taking the version as an explicit argument, not reading a
  ref internally). Recovery from a bad V2 branch is therefore local to
  that one call site's gate, not a risk to V1's regression-gated tests
  (verification step 4 above exists specifically to catch this fast).
- **If any file this phase did not intend to touch shows an unexpected
  diff.** Per D17 (fix round 1, B5), the check is against
  `4acc658`, not `git status --short` (which reads empty once
  a change is committed, D13's own flow, and would silently pass a
  violation the moment it landed): `git diff 4acc658..HEAD --
  src/core/betting.ts src/core/evaluator.ts src/core/cards.ts
  src/core/format.ts src/core/group.ts` — none of these five files are
  in this phase's Files-touched list at all; any non-empty diff there
  is a scope violation, stop and ask. Same form for the vault repo,
  scoped to everything task 11 does **not** name: `git -C
  /home/dev/projects/vault diff 4b2af2c..HEAD -- src/main.js
  src/abi.js src/deployments.js src/abiV2.js src/bondV2.js
  src/evidenceStoreV2.js src/autofileV2.js public/ server.mjs build.mjs
  contracts/` — empty is the only YES; task 11's sanctioned exception
  is `src/mainV2.js` alone, and this is what proves it in practice, not
  just in prose.

## Coherence-pass amendment — 2026-08-17 (AF-10)

P4 closed after this doc's drafting; its three `TBD-P4-CONTINUATION`
sites resolve against P4's Outputs-to-P6 verbatim:
1. (line ~626, dispute-duty posting) **Post duties on birth**: each
   phase-2 duty's birth is an on-chain event (`Phase2ActFiled` or the
   street-close it implies); file the posting the instant the client
   observes it — never on a fixed clock.
2. (line ~659, evidence store) The store forwards phase-2 action
   history unchanged; `phase2Act` transactions are chain-ordered, so no
   client-side ordering logic is added.
3. (line ~1245, appointment display) First to-act moment is always
   `H0 = disputeOpenedAt + window`; later ones are announced by the
   opponent's own `Phase2ActFiled` events. Standing instructions remain
   pure client policy — `phase2Act` accepts any correctly-signed action
   from the registered session key (P4 ships no special entry point).
The vault-repo `liveHand` addendum this doc required of P5 is now
P5's own dated amendment (same AF-10 pass).
