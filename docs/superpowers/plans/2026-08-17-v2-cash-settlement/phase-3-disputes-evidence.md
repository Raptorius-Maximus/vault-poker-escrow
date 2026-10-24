# Phase 3 — disputes-evidence (vault repo, Solidity)

## Goal

Fill P2's `NotYetBuilt()` stubs with the machinery spec item 20 calls "the
largest single item in V2": phase-1 evidence filing (`fileActions`,
`postShares`), lazy consolidation with in-window equivocation burn, **the
betting-replay engine that reconstructs a hand from the marker plus a signed
action chain** (AF-1: this phase owns it, P4 reuses it unchanged), the triple
share check, the graduated crypto (ristretto DLEQ + the 7-card evaluator,
copied from the measured prototype), and §5.3's terminal resolution table for
every row **except** the pending-decision continuation, which P2's own stub
pattern hands to P4 with a named error. At the phase boundary: `ChannelV2.sol`
resolves a marked live hand whose action chain reached fold or full betting
completion inside the evidence window — fold pays the non-folder and returns
the folder's bond; a complete showdown decodes both hands and pays the
winner; an incomplete showdown burns the absent side's bond (muck) or both
(symmetric muck, or the fourth row on a malformed deck) — all from evidence
on file, no revert path, and every burn provably survives a `final` filed at
any point before, during, or after (§1.0's irrevocable-burns pin). A hand
still mid-decision when the window closes reverts a new, named error
(`PendingContinuation`) that only P4's phase-2 machinery clears.

## Split-feasibility ruling

**This phase splits: Part A (evidence filing, the betting-replay engine,
consolidation — tasks 1–8) and Part B (terminal resolution rows, the
remaining crypto graduation, fixtures — tasks 9–13), each independently
gated.** Grounds, stated plainly per the drafting brief's tripwire:

- **Scope.** AF-1's own verdict called this "the largest single item in V2,"
  and the task list below bears that out: a ported betting state machine
  (not a wrapper — a faithful integer port of `betting.ts`'s clamp, street,
  and closure logic), a new decode/evaluate pipeline with no prototype
  precedent (the measured `prototypes/dispute-gas/` covers DLEQ and the
  evaluator but not the ElGamal combine-and-match-against-52-points step —
  see Part B task 9), and a five-row resolution table each row of which is
  independently adversarial-tested. P2's whole phase — bond formula,
  receipts, markers, the pull-payment ledger — fit in 9 tasks; this phase's
  natural task count is comfortably past that before fixtures are even
  written, and the brief's own "≤10 tasks per doc-part" ceiling is the
  signal, not a target to force a 9th or 10th task into.
- **A clean seam exists, and it is not arbitrary.** Part A ends the moment
  the frozen chain is known to be terminal-or-pending — that fact (fold,
  betting-complete, or "no further filed action exists for the node whose
  turn it is") falls out of the replay engine alone, before any card is
  looked at. Part B starts from "terminal, now decide who gets what,"
  which needs the crypto (decode, evaluate) Part A's replay engine never
  touches. A checker attacking this seam (REVIEW-BRIEF's gate-attack
  instruction) will find Part A's own gate provable without Part B's
  machinery: "does a filed fold chain revert `PendingContinuation`? No —
  it falls through to `NotYetBuilt` (Part B not yet shipped) or, once Part
  B lands, resolves." Part A's tests assert the *routing*, not the
  *payout* — exactly the same shape as the P2/P3 seam REVIEW-BRIEF already
  scrutinized and found sound.
- **Alternative rejected: whole-phase, single gate.** Every task still
  depends on Part A's replay engine existing before Part B's rows can be
  tested end-to-end, so a single gate would just make Part B's tests the
  de facto phase boundary anyway — collapsing two provably-independent
  checkpoints into one gate loses a checkpoint for no parallelism gain,
  the same reasoning P2's task 1 used *against* splitting (there, splitting
  bought nothing because every task depended on task 1's storage; here,
  the two parts are large enough and separable enough that *not* splitting
  loses a real, cheap verification point).
- **Alternative rejected: split along the crypto/logic axis instead**
  (e.g., "all crypto graduation in one part, all state-machine logic in
  the other"). Rejected because `postShares`' triple check (Part A) is
  crypto (DLEQ + Merkle) that the replay engine's consolidation needs
  nothing from, while the fourth row's malformed-deck detection (Part B)
  is state-machine-shaped (it fires only after the replay engine already
  said "terminal"). The evidence-vs-resolution axis used above tracks the
  spec's own structure (§5.1/§5.2 vs. §5.3) more closely than a
  crypto/logic axis would.

Both parts ship in this one document, numbered continuously (Part A: tasks
1–8; Part B: tasks 9–13), each with its own **Phase-boundary verification**
block. An orchestrator may dispatch Part A, gate it, then dispatch Part B —
or run both back-to-back — without re-deriving the boundary.

## Inputs from previous phase

**From P2 (`phase-2-money-frame.md`'s own Outputs to next phase section,
mirrored verbatim, not re-worded):**

> `ChannelV2.sol` with `openDispute`, the AF-4 zero-filings/per-duty branches
> at `markedHand == 0` (decision 7 — **not** a both-burn §1.3 branch, which
> is struck), and four `NotYetBuilt()`-reverting surfaces (`resolve`'s
> marked-live-hand branch, `fileActions`, `postShares`, `phase2Act`) whose
> signatures are frozen (`SharePost` spelled out verbatim in artifact-formats
> §9; `Act` derived from §5's field list — a decision-level note, not a §9
> literal). P3 replaces the stub *bodies* only — no interface churn, per the
> phase brief's explicit requirement. P3 also inherits `receiptAt`,
> `markedHand`, `hostFiledInWindow`/`guestFiledInWindow` (AF-4's per-duty
> presence tracking — P3's own duty tracking for markers/actions/shares can
> extend the same pattern rather than inventing a new one), `_burnBond`,
> `credits`, `paidOut`, and `burned` as the storage surface its
> consolidation and resolution-table logic reads and writes.

Concretely, this phase inherits from P2's shipped `contracts/src/ChannelV2.sol`:
`Status` enum (`None, AwaitingGuest, Active, Disputed, Closed`);
`disputeOpenedAt`, `markedHand`; `receiptAt[session][hand]` (a receipt
*hash* per hand, highest-subseq); `hostFiledInWindow`/`guestFiledInWindow`;
`_burnBond(bytes32 session, bool isHost) internal` (idempotent, pre-declared
P2 task 1 step 11); `credits`, `paidOut[session]`, `burned[session]`,
`hostBurned`/`guestBurned`; `_recoverRaw`/`_recoverEIP191`/`_binding`;
`sessionKeyHost`/`sessionKeyGuest` (addresses); `host`/`guest` (wallet
addresses); `bondHost`/`bondGuest`; `highestFinalHand`/`Subseq`/`Hash`/
`HostStack`/`GuestStack`/`HostDeposit`/`GuestDeposit`; `error NotYetBuilt();`
declared at contract scope and thrown by `fileActions`, `postShares`,
`phase2Act`, and `resolve()`'s `markedHand[session] > 0` branch (P2 task 5
step 3, the exact revert this phase's task 7 replaces with real routing).
**Confirmed against the live source, not assumed:** `git -C
/home/dev/projects/vault log --oneline -1 -- contracts/src/ChannelV2.sol`
and a fresh `~/.foundry/bin/forge build --root
/home/dev/projects/vault/contracts` are this phase's own first steps
(task 1) precisely so a stale read of P2's doc never substitutes for reading
the contract P2 actually shipped.

**From P1 (`phase-1-protocol-substrate.md`'s D16 output, by name):**
`src/vectors/p1-vectors.json` and `src/vectors/Vectors.sol`, committed in the
poker repo, sha256sum recorded in P1's task-10 commit message. **Per D18
(fix round 1, superseding this doc's original D16-only framing): P2 is the
single owner of the copy into the vault repo** — a task step in
`phase-2-money-frame.md` places both files at
`contracts/test/vectors/{p1-vectors.json,Vectors.sol}` and gates P2's own
phase boundary on `sha256sum -c` against P1's recorded hashes. **This
phase does not sync the vectors itself and does not own a second copy
mechanism.** This phase's task 2 re-runs `sha256sum -c` against the copy
P2 already landed, immediately before this phase's own tests read from
it — a repeatable re-verification, not a second sync. **Per D18, a missing
or mismatched copy is a hard gate FAILURE for task 2**, not a condition
this phase falls back around; there is no vault-side fallback path left
for the happy-path vector-consuming tests (tasks 3, 5, 8, 13) if task 2
fails.

**Live source read for this doc, 2026-08-17:**
`contracts/src/Channel.sol` (191 lines, V1, untouched — D11) — read from the
live file, since it exists. **`contracts/src/ChannelV2.sol` and
`contracts/test/ChannelV2.t.sol` do not exist yet at drafting time — P2 is
a phase *plan*, not shipped code** — so this doc's Inputs section above is
built from `phase-2-money-frame.md` (P2's phase doc) exactly as this
phase's own task 2 already treats P1's vector artifacts (cite the doc, not
a file that isn't there yet); task 1 step 0 below is the real guard, a
dispatch-time re-verification against whatever P2 actually shipped before
this phase's own work proceeds. Also read: `contracts/foundry.toml`
(`src = "src"`, `out = "out"`, `libs = ["lib"]`, no cross-repo remapping —
confirmed via `find /home/dev/projects/vault/contracts -iname
"remappings.txt"`: the search returned completely empty, no
`remappings.txt` exists anywhere under `contracts/`, not even inside
`lib/forge-std`), `prototypes/dispute-gas/` in full (`src/`, `test/`,
`gen/`, `README.md`, `foundry.toml`), and
`/home/dev/projects/poker/src/core/betting.ts` in full (223 lines),
`elgamal.ts` (in full), `cards.ts` (in full), `protocol.ts`'s `POS` constant
(line 52). `~/.foundry/bin/forge` 1.7.1 confirmed installed; `forge snapshot
--root /home/dev/projects/vault/contracts --match-contract ChannelTest`
probed 2026-08-17 against V1's existing suite: runs, writes
`.gas-snapshot`, confirms V1's 26-test count independently (matches P2's
citation) — command form confirmed, not assumed.

## Files touched

**Created:**
- `contracts/src/Ristretto.sol`, `contracts/src/Dleq.sol`,
  `contracts/src/Evaluator7.sol` — copied from
  `prototypes/dispute-gas/src/` (task 1; by copy, not remapping — see task
  1's reasoning).
- `contracts/src/Evidence.sol` — new: position-bound Merkle leaves (formats
  §7), a generic sorted-pair Merkle verifier, the 52-card point table, and
  the ElGamal combine-and-match decode helper (task 1, task 9).
- `contracts/src/BettingReplay.sol` — new: the ported betting state
  machine, as a standalone library so P4 can import and call it without
  depending on `ChannelV2`'s internals (task 5; AF-1's "P4 reuses it").
- `contracts/test/BettingReplay.t.sol` — new: isolated tests of the ported
  engine against `betting.ts`'s own semantics (task 5, task 8).
- `contracts/test/Evidence.t.sol` — new: Merkle/DLEQ/decode tests separate
  from the money-frame `ChannelV2.t.sol` (task 1, task 4, task 9).

**Modified:**
- `contracts/src/ChannelV2.sol` — `fileActions`, `postShares` bodies
  (replacing `NotYetBuilt()`); `resolve()`'s `markedHand[session] > 0`
  branch (replacing `NotYetBuilt()` with real routing, tasks 7 and 10–11);
  a **disclosed extension** to `fileReceipt` (task 3, a new per-hand stacks
  cache) and to `resolve()`'s `finalEligible` branch (task 12, a
  matured-duty-burn crystallization call) — both additive to P2-owned
  functions, no signature change, called out explicitly rather than
  silently folded in, per the arc's amendment discipline. `phase2Act`
  stays exactly as P2 left it — untouched, still `NotYetBuilt()`, P4's.
- `contracts/test/ChannelV2.t.sol` — extended with tasks 3–4, 7, 10–13's
  fixtures.

**Deleted:** none. `Bench.sol`'s `verifyChain` (the prototype's action-chain
verifier) is **deliberately not copied or adapted** — it signs off on the
superseded `seq % 2` signer-parity model AF-2 struck (`Bench.sol`: `require
(signer == (a.seq % 2 == 0 ? host : guest), "bad signer")`); this phase's
`BettingReplay.sol` derives the legal signer from the replayed state
instead (task 5). `Bench.merkleVerify`'s generic sorted-pair walk *is*
reused (task 1) — only the leaf shape and the signer-selection logic are
superseded, not the tree-walking arithmetic.

## Design decisions pinned here (binding on every task below)

**1. Self-authenticating identity — no claimed-`isHost` field anywhere this
phase adds.** Every artefact this phase verifies (a signed action, a posted
share) carries its own cryptographic proof of whose it is: an action's
`ecrecover`'d signer either matches `sessionKeyHost`, matches
`sessionKeyGuest`, or the filing is worthless and ignored; a share's DLEQ
either verifies against `hostCardPk` or `guestCardPk` (or neither, and the
post is worthless). **Formats §9 permits adding fields to `SharePost`** ("may
add fields but not remove or re-type"), and a `bool isHost` field was
considered and rejected: a claimed field is a fact to *verify against* the
proof, which is strictly more code for zero additional soundness — the proof
alone already disambiguates, and it is impossible for one `(pos, shareEnc,
c1Enc, c2Enc)` tuple to pass DLEQ against *both* cardPks (the two players'
secrets differ), so trying both verifications and keeping whichever succeeds
is total, self-contained, and adds no trust surface. Same reasoning for
`fileActions`' signer resolution (task 3) — no `Act` field names the actor;
`ecrecover` against both registered keys does.

**2. `fileActions` storage: one candidate slot per (hand, seq, signer),
`filedAt` stamped, equivocation burn eager and window-gated.** Per hand and
`seq`, up to two stored candidates exist — one keyed to a host-signed
submission, one to a guest-signed submission (self-authenticated per
decision 1; a submission that recovers to neither key is not stored at all,
cheap-reverted or silently dropped, task 3 picks one and states it). A
second submission from the **same** signer at the same `(hand, seq)`:
identical to the stored one → silent dedup (`F14.4`, the spec's declared
"normal case"); **distinct** (differs in `action`/`amount`, same `prev`,
i.e. same node) → this is formats §5's equivocation, checked the instant
the second one lands, **and burns `_burnBond` right there, but only if
`block.timestamp < disputeOpenedAt[session] + window`** (D8, F14.3: "a pair
… admissible only if complete in-window" — the check is on the *current*
block at insertion time, which is exactly when the second signature of the
pair completes the pair). This makes the equivocation burn **eager, not
part of a later consolidation pass** — a deliberate simplification over
"detect equivocation during chain-walking," and it is sound because formats
§5 states equivocation is a **pairwise, same-key, same-node** fact,
checkable with no knowledge of any other node's state (unlike legality,
which needs the whole prefix replayed). **Consolidation (task 6) still
separately filters every candidate — equivocating or not — by `filedAt <
disputeOpenedAt[session] + window`** before the replay engine ever sees it;
a filing that lands after the window (whether or not it collides with
anything) never enters the frozen chain, which is what makes the window
boundary uniform across "extends the chain" and "conflicts with the
chain" rather than two separately-reasoned rules.

**3. The betting-replay engine is a standalone library, ported not
wrapped.** `BettingReplay.sol` reimplements `startHand`/`toCall`/
`minRaiseTo`/`maxRaiseTo`/`legalActions`/`applyAction`/`nextStreet` from
`/home/dev/projects/poker/src/core/betting.ts` as integer Solidity, cited
line-by-line in task 5. Two facts from that source, verified by reading it
in full (not by remembering the design conversation that referenced it),
carry the whole legality check:
- **Blinds post via `min(blind, stack)`** (`betting.ts:48-49`) — a short
  stack posts what it has, never more.
- **The clamp reduces to an integer range check.** `applyAction`'s bet
  branch (`betting.ts:150-158`) computes `hi = maxRaiseTo(st, seat)`,
  `lo = min(minRaiseTo(st, seat), hi)`, then `target = min(hi, max(lo,
  round(amount)))`. For any **integer** `amount` already inside `[lo, hi]`,
  `target == amount` — every integer in that closed range is a fixed
  point of the clamp. Because D7 requires the client to sign the
  **post-clamp** amount and the contract never sees the client's raw
  pre-clamp request (formats §5: "canonical post-clamp integer;
  `amount(32)`"), exact-legality validation of a `bet` action is exactly
  `require(lo <= amount && amount <= hi)` — **no clamping computation is
  ever performed on chain**, only a range check against `lo`/`hi` computed
  from the replayed state. This is the phase brief's own citation ("the
  fifteenth check proved the clamp reduces to an integer range check")
  turned into the actual verification rule, not left as a design-doc
  claim.
- **Turn order:** button acts first preflop (`betting.ts:56`,
  `toAct: button`), non-button first postflop (`betting.ts:196`, `toAct:
  other(button)`). `BettingReplay` derives `toAct` purely from replaying
  seq 0..k-1 — **never from `seq % 2`** (AF-2, formats §5, and the exact
  reason `Bench.sol`'s `verifyChain` is not reused, see Files touched).
- **Short all-in does not reopen betting**: `raiseSize >= st.lastRaiseSize`
  gates whether `actedSinceAggression` resets to `{seat}` alone or merely
  gains `seat` (`betting.ts:161-166`) — ported verbatim, integer
  comparison, no float involved anywhere in the original either.
- **`canAct`** (`betting.ts:118-121`) and its use to close a betting round
  (`betting.ts:181`) port directly — a stack of exactly 0 can never be
  asked to act again.
- **`nextStreet`** (`betting.ts:186-198`) resets `committed` to zero both
  seats, `lastRaiseSize = bigBlind`, clears `actedSinceAggression`,
  auto-closes the new street if either stack is now empty (all-in runout —
  the cascade that can carry a hand straight to river with no further
  actions filed at all), and sets `toAct = other(button)`.

**Reused by P4, unchanged.** `BettingReplay`'s public entry point (task 5)
takes exactly what phase 2 also has: button, sb, bb, baseline stacks, and an
ordered action list; P4 extends the *ordered action list* with on-chain
phase-2 actions and calls the same function — this is the literal meaning
of AF-1's "reused by P4," stated once here as the contract fact P4's own
phase doc will cite.

**3a. Chip-space vs. wei-space — the two-space split, stated explicitly
(B1, fix round 1; artifact-formats §1's amendment).** `BettingReplay`
operates **entirely in chip-space** — the engine's native unit — and
never sees a wei figure anywhere inside it: the marker's `sb`/`bb` fields
are chips (formats §4, amended), and every canonical signed-action
`amount` this library validates against `[lo, hi]` (decision 3) is
likewise chips (formats §5, amended) — `BettingReplay`'s inputs and
outputs are internally consistent without any conversion. **`ChannelV2`'s
own storage is wei throughout** (receipts, `receiptStacksAt`, the bond
formula, the whole pull-payment ledger — unchanged, P2's existing
assumption, now stated rather than left implicit). **The receipt is the
one artefact that crosses between the two spaces**, and exactly one
function in this phase performs the crossing:
- **Wei → chips, at consolidation (task 6), once per call, uncached.**
  `weiPerChip = receiptStacksAt[session][0].hostDeposit /
  (200 * bb)` — the fixed rate formats §1 names
  (`wei_per_chip = deposit_wei / starting_chips`), computed from the
  `(0,0)` receipt's wei deposit and `startingChips = 200 * bb` (spec §3:
  "the buy-in is 200 big blinds"; `bb` read from the marked hand's own
  marker, valid for the whole session since blinds are fixed all session,
  spec §2.1 — no new stored field needed, the marker P2 already verifies
  and stores is sufficient). **Confirm at implementation time** that this
  matches whatever `startStack`/`TableConfig.depth` P1's client actually
  resolves to for a V2 cash session (`/home/dev/projects/poker/src/core/
  format.ts:112`'s `startStack(config)` is generally parameterized on
  `config.depth`, not hardcoded to 200 — spec §3 fixes `depth = 200` for
  V2 specifically, but this task's `200` literal is this phase's own
  on-chain derivation of `starting_chips`, not a value any artefact
  transmits directly, so a mismatch here is a real risk worth a dedicated
  fixture, not just an assumption). Convert the baseline receipt's
  `hostStack`/`guestStack` (wei) to chip-space via integer division by
  `weiPerChip`, with `require((weiStack % weiPerChip) == 0, "chip/wei rate
  mismatch")` as a sanity check — exact by construction if the client
  built every wei figure as `chips * weiPerChip` (formats §1's amendment),
  so a remainder here signals a wrong rate or a corrupted receipt, not a
  normal rounding case to tolerate silently.
- **Chips → wei, at settlement (tasks 10–11), by multiplication, always
  exact.** `BettingReplay`'s final chip-space payout (via the ported
  `settle()`, task 10 step 1) is converted back with a single
  multiplication, `weiDelta = chipsPayout * weiPerChip` — multiplication
  never loses precision the way the wei→chips division could, so no
  sanity check is needed on this side of the boundary.

`_consolidate` (task 6) computes `weiPerChip` once per call and threads it
through its return tuple and `_resolveTerminal`'s parameters (task 7)
exactly as it already threads `completingFiledAt` (B2) — one function
computes it, every downstream row consumes the same value, none
re-derives it.

**4. Consolidation is genuinely lazy — a `view` computation, no storage
write of its own.** "The frozen chain is a pure function of phase-1
filings" (§5.1) is implemented literally: task 6's `_consolidate(session,
hand)` reads `markedHand`'s stored action candidates (already filtered
in-window per decision 2), reads the marker's button/sb/bb (chips,
decision 3a) and the cached receipt-stacks baseline (decision 7 below,
wei — converted to chip-space per decision 3a before it reaches
`BettingReplay`), and calls `BettingReplay` fresh — every time it is
invoked, from whichever transaction happens to need it first (task 7's
`resolve()` wiring, or a `view` call from off-chain tooling). Nothing is
cached between calls except the state decision 2 already persists (the
filed candidates themselves) and, per decision 3a, `weiPerChip` itself is
recomputed each call rather than cached — consolidation itself
has no "has this run yet" flag, matching D8's "needs no transaction of its
own."

**5. `postShares`: the triple check runs at file time, not deferred; a
failing post is simply not recorded.** Formats §9's `SharePost` supplies
`c1Enc`/`c2Enc` directly from the filer, but decision 10's rule ("the
contract never takes `c1` from the filer's word") is enforced by the
**Merkle deck proof**, not by refusing the field — `c1Enc ‖ c2Enc` must
Merkle-include in `deckRoot` at the claimed position `p` via `deckProof`
before the DLEQ check ever runs against it (formats §7's exact three-step
order). A post that fails any of the three checks (share→shareRoot,
ciphertext→deckRoot same `p`, DLEQ→cardPk) is **not stored and does not
revert** — the caller (a legitimate client, or nobody) simply wasted their
own gas; only a post that *passes all three* sets
`sharePosted[session][hand][pos][player] = true` and caches the share point
for task 9's combine step. This is what makes "posted" in §5.3's muck row
("every position the terminal state requires from that player, each
passing the triple check") a direct storage read rather than a
re-verification at resolution time.

**6. Card decode has no prototype precedent — new work, cited to source.**
`prototypes/dispute-gas/` measures DLEQ and the evaluator but never
combines two shares into a card. The client's own primitive
(`/home/dev/projects/poker/src/core/elgamal.ts:76-79`,
`combineShares(ct, ...shares) = ct.c2 - sum(shares)`) and the card encoding
(`cards.ts:16-22`, card `i` ⟷ `BASE.multiply(i+1)`, deterministic, no
randomness) port directly: `Evidence.sol` holds a `bytes32[52]` table of the
52 encoded points (computed once, off-chain, by a short deterministic
script — task 9 — and pasted as constants, **not** computed on-chain via
52 scalar multiplications per lookup, which the measured ~524k-gas
scalar-mul-and-encode figure would make prohibitively expensive per
position) and a `decode(Ristretto.Pt c2, Ristretto.Pt hostShare, Ristretto.Pt
guestShare) → (bool ok, uint8 card)` helper that computes `c2 - hostShare -
guestShare` and linear-scans the 52-entry table for an exact encoding
match. **A miss (`ok == false`) is not an error — it is the fourth row's
trigger** (task 11): every check upstream passed (both shares' individual
DLEQs, both Merkle inclusions) and the combined point still isn't one of
the 52 protocol cards, which by §4's totality lemma is possible only if the
deck itself was dishonestly committed at marker-signing time — both
signers' fault, per the marker's both-signature attestation.

**7. Two disclosed extensions to P2-owned code, both tied to
proven-burns-irrevocable.** Neither changes a function's external
signature; both are additive bodies inside functions P2 shipped, and both
exist because P2's `resolve()` structure (final short-circuit, checked
*before* the `markedHand > 0` dispute branch even runs) would otherwise let
a `final` outrun evidence this phase's own machinery produces:
- **`fileReceipt` gains a per-hand stacks cache.** P2's task 3 step 5
  tracks only `receiptAt[session][hand]` (a **hash**) per hand, plus a
  separate cache for `final`s only (P2 task 3 step 8). The betting-replay
  engine's baseline (decision 3, "baseline receipt stacks") needs the
  **actual** `hostStack`/`guestStack`/`hostDeposit`/`guestDeposit` of the
  highest-subseq receipt at hand N−1 (the one the marker's `receiptHash`
  names) — not just its hash, since `resolve(bytes32 session)` (formats
  §9) takes no extra parameters and cannot have the caller re-supply the
  receipt at resolution time. Task 3 adds
  `receiptStacksAt[session][hand] = (hostStack, guestStack, hostDeposit,
  guestDeposit)`, written at the exact same "if `r.subseq` is the new
  highest for that hand" conditional P2's `fileReceipt` already evaluates
  (`phase-2-money-frame.md` task 3 step 5) — one new mapping write beside
  an existing one, not a new code path.
- **`resolve()`'s `finalEligible` branch gains a matured-duty-burn
  crystallization call.** F16.1 ("final lands before the equivocation pair
  is filed; pair filed before payout execution → bond still burns") and
  F16.3 ("burn facts on chain before a final; computation runs after →
  burned") both presuppose that *any* call to `resolve()` — including one
  that takes the final short-circuit and never reaches the
  `markedHand > 0` branch this phase otherwise owns — still reflects
  matured burns. Equivocation is already eager (decision 2) and needs no
  help. **Missed-duty burns (task 11) are not eager** — they depend on a
  deadline having passed, which only a transaction can observe — so task
  12 adds one call, `_crystallizeMaturedDuties(session)`, at the top of
  `resolve()`'s `finalEligible` branch, before it reads `hostBurned`/
  `guestBurned`. This is stated once here and implemented in task 12,
  after Part B's duty deadlines (task 11) exist to crystallize.

**8. Terminal-vs-pending routing uses a new, named error — not
`NotYetBuilt`.** P2's stub pattern (`error NotYetBuilt();`, thrown at every
surface this phase fills) exists so P3 knows exactly which bodies to
replace. This phase, having built real machinery up to "the frozen chain
shows a pending decision" (§5.3), owes P4 the same courtesy at the *next*
boundary: `error PendingContinuation();`, thrown only when the replay
engine's result is neither `FOLD` nor `COMPLETE` — i.e., a filed action
exists for every seq the chain has reached so far, but the street in
progress is not yet closed, or a required next action was never filed at
all. `phase2Act` remains `NotYetBuilt()`, untouched — P4 fills that
surface *and* replaces this phase's `PendingContinuation` throw with real
phase-2 routing; the two names distinguish "P2 never built this" from "P3
built up to here, no further."

**9. Revert style.** `require(cond, "string")` throughout, matching
P2/V1's convention, **except** `PendingContinuation` (decision 8) and the
fourth row's resolution, which per spec is explicitly **total — no revert
path** (thirteenth check, finding 6; §5.3's table, fourth row): a
malformed deck is not an error state, it is a resolution outcome (both
bonds burn, settle at the receipt baseline) and must return normally like
every other row.

---

## Part A — evidence, replay engine, consolidation

**Phase-base SHA, recorded at dispatch (D17, fix round 1).** Every
isolation/no-touch gate in this doc (V1-untouched, P4's `phase2Act`
stub-untouched) compares against a fixed commit, not the working tree —
`git diff --stat` against worktree/index reads empty once everything is
committed, which is vacuous under D13's commit-to-master flow, not proof
of anything. Before task 1 dispatches: run `git -C
/home/dev/projects/vault rev-parse HEAD` and record the result as
**`<phase-3-base>`** in this task's own completion notes — every gate
below that says `<phase-3-base>` means literally that recorded commit,
substituted at gate-run time, never re-derived. The same SHA anchors both
Part A's and Part B's gates (Part B does not re-capture a second base —
Part B's own diffs are still measured from the same phase-start point, so
a gate can tell "P3 touched this" from "P3 didn't," not merely "this
differs from whatever HEAD happens to be right now").

### Task 1 — Graduate crypto libraries; Merkle leaves; card-point table

**Goal:** `Ristretto.sol`, `Dleq.sol`, `Evaluator7.sol` compiling inside
`contracts/src/`, plus `Evidence.sol` carrying formats §7's position-bound
leaves, a generic Merkle verifier, and the 52-card point table (decision 6)
— every later task in both parts depends on these existing.

**Files:** `contracts/src/Ristretto.sol`, `contracts/src/Dleq.sol`,
`contracts/src/Evaluator7.sol` (new, copied), `contracts/src/Evidence.sol`
(new), `contracts/test/Evidence.t.sol` (new — test contract named
`EvidenceTest`, matching `Channel.t.sol`/`ChannelV2.t.sol`'s
`<Subject>Test` naming convention; task 9 extends this same file/contract,
does not create a second one).

**Split-feasibility note.** This task bundles four concerns (library copy,
Merkle leaves, generic Merkle verify, card-point table) but stays one task
on different grounds than "everything downstream imports it" — that isn't
actually true of every task (tasks 2, 3, 5, 6, and 7 need none of this
task's output; only tasks 4, 9, and 10 do). The real reason is that this is
**foundational, low-judgment infrastructure that gains nothing from being
split**: a copy operation, two leaf-hash formulas already pinned by formats
§7, a generic tree walk already proven in the prototype, and a
deterministically-computable constant table — none of the four pieces has
an independent design question splitting would let a second dispatch
resolve in parallel, so separating them only adds bookkeeping (two task
completions to track, two build-green checkpoints for work that compiles
as a unit) without buying anything a single dispatch doesn't already give.

**Steps:**
0. **Re-verify P2's shipped contract before building on it.** This doc's
   Inputs section above was drafted against `phase-2-money-frame.md` (P2's
   *plan*), since `ChannelV2.sol` did not exist at drafting time. Before
   any further step in this task: `git -C /home/dev/projects/vault log
   --oneline -1 -- contracts/src/ChannelV2.sol` and a fresh
   `~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts`
   confirm P2 actually shipped, then read the real
   `contracts/src/ChannelV2.sol` and `contracts/test/ChannelV2.t.sol` to
   confirm the storage fields, function names, and stub error this doc
   cites throughout (`Status`, `markedHand`, `receiptAt`, `_burnBond`,
   `NotYetBuilt`, the four `NotYetBuilt()` surfaces) match what this doc
   assumed from the plan. A mismatch here is a stop-and-reconcile finding,
   not something to paper over in a later task.
1. **Copy, not remap — stated and justified.** `find
   /home/dev/projects/vault/contracts -iname "remappings.txt"` (probed
   2026-08-17) returns **completely empty — no `remappings.txt` exists
   anywhere under `contracts/`, including inside `lib/forge-std`**; the
   repo's convention for external Solidity code is a `lib/` git-style
   dependency (forge-std), and `prototypes/dispute-gas/` is a **sibling
   standalone Foundry project**
   with its own `foundry.toml`/`src`/`test` — not set up as an importable
   library from any consumer's `foundry.toml`. Adding a cross-directory
   remapping (`dispute-gas/=../prototypes/dispute-gas/src/`) would work
   mechanically but creates a live coupling between a throwaway
   measurement scaffold and production contract code, which the prototype
   README's own framing ("Prototype, not production") argues against.
   Copy `prototypes/dispute-gas/src/Ristretto.sol`,
   `prototypes/dispute-gas/src/Dleq.sol`,
   `prototypes/dispute-gas/src/Evaluator7.sol` into `contracts/src/`
   verbatim — pragma `^0.8.24` in all three (confirmed via `head -5` on
   every file, 2026-08-17) matches `ChannelV2.sol`'s own pragma exactly, so
   no version adaptation is needed. Add a one-line header comment on each
   copied file: `// Copied from prototypes/dispute-gas/src/<Name>.sol,
   <date> — see that file's README for the differential-testing chain that
   validated it.`
2. `contracts/src/Evidence.sol`: `shareLeaf(uint8 pos, bytes32 shareEnc) →
   bytes32` and `deckLeaf(uint8 pos, bytes32 c1Enc, bytes32 c2Enc) →
   bytes32`, formats §7's exact byte layout (`0x05 ‖
   "vault/shareleaf/v1" ‖ uint8(pos) ‖ shareEnc` and `0x06 ‖
   "vault/deckleaf/v1" ‖ uint8(pos) ‖ c1Enc ‖ c2Enc`).
3. `merkleVerify(bytes32 leaf, bytes32[] calldata proof, bytes32 root) →
   bool` — sorted-pair `keccak256(min(a,b) ‖ max(a,b))` walk, identical
   arithmetic to `Bench.sol`'s `merkleVerify` (reused logic, new file — the
   function itself is leaf-shape-agnostic, so no adaptation needed beyond
   moving it).
4. **The 52-card point table (decision 6).** Compute `BASE.multiply(i+1)`
   for `i` in `0..51` via a short, deterministic, noble-validated Node
   script (mirrors `prototypes/dispute-gas/gen/gen.mts`'s validation
   discipline: cross-check every value against `@noble/curves` before
   trusting it — no randomness anywhere, per `cards.ts:16-22`'s own
   deterministic construction), paste the 52 ristretto encodings as a
   `bytes32[52] private constant CARD_POINTS` array (or an equivalent
   `pure` function returning a fixed array — either is fine, whichever
   compiles cheapest) in `Evidence.sol`, each with a comment citing
   `cards.ts:19` (`p = BASE.multiply(BigInt(i + 1))`). **This script is
   throwaway** (its only job is emitting 52 constants once) — it is not a
   second vector generator and does not participate in D16's cross-repo
   parity machinery, because nothing on the client side needs to match it
   byte-for-byte; the client already computes the same 52 points from the
   same formula independently (`cards.ts`), and this task's only
   obligation is that the **contract's own copy is correct**, checked by
   the differential probe below.
5. `combine(Ristretto.Pt memory c2, Ristretto.Pt memory hostShare,
   Ristretto.Pt memory guestShare) → Ristretto.Pt memory` — `c2 -
   hostShare - guestShare` via `Ristretto.add`/`Ristretto.neg` (mirrors
   `elgamal.ts:76-79`'s `combineShares`; `elgamal.ts:71-73` is
   `decryptionShare`, a different function — cited separately in decision
   6 below). `decode(...)` itself (the
   52-entry linear scan) is task 9's, once `postShares`' storage (task 4)
   exists to feed it real shares — this task only builds the table and the
   combine arithmetic, both of which have no dependency on task 4.
6. **M2 (fix round 1, P3-4) — contract-side proof that position-binding
   actually changes the root, not just prose asserting it does:** in
   `EvidenceTest`, build a small tree (a handful of leaves) two ways from
   the **same** `(pos, shareEnc)` pairs — once via `Evidence.shareLeaf`
   (formats §7's position-bound shape, `0x05 ‖ domain ‖ uint8(pos) ‖
   shareEnc`) and once via the prototype's superseded unbound shape
   (`keccak256(shareEnc)` alone, no tag, no position — `formats §10`'s
   documented delta) — and assert the two resulting roots **differ**.
   This is the mechanical version of what decision language elsewhere in
   this doc only asserts in prose; a filer who reuses the prototype's
   leaf shape must fail a real `Evidence.merkleVerify` call against a
   position-bound root, and this test is what proves that mechanically
   rather than by construction argument alone.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts
    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract EvidenceTest -vv

YES/NO: build exits 0, no errors mentioning `Ristretto.sol`, `Dleq.sol`,
`Evaluator7.sol`, or `Evidence.sol`; `EvidenceTest` passes, including step
6's position-bound-vs-unbound root-divergence assertion (M2). Separately,
a differential check for the card-point table (not a `forge` probe — a
plain computation, inside the side-effect boundary): `node -e` reproducing
`cards.ts`'s formula via `@noble/curves` for a handful of sampled indices
(0, 1, 12, 25, 51) and comparing hex output against the pasted constants
**is the check this task's own completion notes must show was run**, since
nothing in `forge build` catches a transcription error in 52 hand-pasted
constants.

**Dispatch:** `agent (session-tier, high)` — foundational; every later task
in both parts imports this file, and a subtle leaf-shape or table error
here is invisible until a real dispute fixture fails much later.

---

### Task 2 — Verify P2's landed vector copy (`sha256sum -c`, hard-fail)

**Goal:** per D18 (fix round 1, single-owner ruling): **P2 owns copying**
`src/vectors/{p1-vectors.json,Vectors.sol}` from the poker repo into
`contracts/test/vectors/` and gating its own phase boundary on
`sha256sum -c` against the hashes P1's task 10 recorded. **This phase does
not copy anything and does not own a second copy mechanism** — it
re-verifies the copy P2 already landed, on the same `sha256sum -c` basis,
immediately before this phase's own vector-consuming tests (tasks 3, 5, 8,
13) read from it. **A missing or mismatched vector file is a gate FAILURE
for this task, full stop — never a fallback pass.**

**Files:** none created or modified — a verification step whose result
gates whether tasks 3/5/8/13 may proceed with vector-based construction.

**Steps:**
1. Resolve the landed path: `contracts/test/vectors/p1-vectors.json` and
   `contracts/test/vectors/Vectors.sol` (D18's stated location — confirm
   against P2's **shipped** phase doc, not this drafted plan, since P2's
   own D16-era draft used the inert token `TBD-P1-VECTORS` before D18
   pinned the real path).
2. Recover the hashes P1's task 10 recorded in its own commit message
   (poker repo, `git -C /home/dev/projects/poker log --grep=sha256 -1` or
   equivalent — confirm the actual recording convention against P1's
   shipped doc) and write them to a local `sha256sum`-format manifest;
   run `sha256sum -c` against the vault repo's landed copy.
3. **Exit code 0 (hashes match) → proceed**; tasks 3/5/8/13 build their
   vector-based constructions from `contracts/test/vectors/p1-vectors.json`
   directly. **Any other outcome — the files are absent, or `sha256sum -c`
   reports a mismatch — is a hard gate FAILURE for this task.** Stop and
   report as a plan finding; do **not** fall through to building this
   phase's happy-path tests with `vm.sign` instead. Per D18: `vm.sign`
   remains permitted **only** for the negative/mutation cases tasks 8/9/13
   already call for on their own terms (a deliberately-wrong signature, a
   deliberately-truncated chain — constructions a valid vector could never
   represent by definition) — it is never a substitute for a missing or
   broken happy-path vector.

**Verification probe:**

    sha256sum -c <manifest built in step 2> --status

YES/NO: exit code `0` is the only passing outcome; any non-zero exit is a
recorded FAILURE that halts this phase's dispatch (task 3/5/8/13 cannot
correctly proceed without the vectors this task exists to confirm) — not a
"still YES, flagged" result. This is the literal correction D18 makes to
this phase's earlier draft, which is deleted along with this wording.

**Dispatch:** `agent (workhorse, low)` — a lookup-and-verify task, no
design judgment, but its FAILURE outcome is a real halt condition for the
phase, not an informational note.

---

### Task 3 — `fileActions`: storage, eager equivocation, receipt-stacks cache

**Goal:** the dispute-only action-filing entry point (decision 1's
self-authentication, decision 2's storage model and eager in-window burn),
plus the disclosed `fileReceipt` extension (decision 7) the replay engine's
baseline needs.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. Add `struct ReceiptStacks { uint256 hostStack; uint256 guestStack;
   uint256 hostDeposit; uint256 guestDeposit; }` and `mapping(bytes32 =>
   mapping(uint64 => ReceiptStacks)) receiptStacksAt;` to `ChannelV2`'s
   storage. In `fileReceipt` (P2's function), at the exact conditional
   that already updates `receiptAt[session][r.hand]` on a new
   highest-subseq (P2 task 3 step 5), also write
   `receiptStacksAt[session][r.hand] = ReceiptStacks(r.hostStack,
   r.guestStack, r.hostDeposit, r.guestDeposit)`. Comment this addition
   explicitly: `// P3 extension (decision 7): caches full stacks, not just
   the hash, for the replay engine's baseline lookup.`
2. `struct ActCandidate { address signer; uint8 action; uint256 amount;
   bytes32 prev; bytes32 actionHash; uint40 filedAt; bool exists; }` and
   `mapping(bytes32 => ActCandidate[2]) actionsAt;` keyed by
   `keccak256(session, hand, seq)`; index 0 reserved for whichever of
   `sessionKeyHost`/`sessionKeyGuest` the first stored candidate at that
   slot matched, index 1 for the other (decided at insertion, not fixed in
   advance — a host-signed candidate can land in either array slot,
   whichever is empty or already holds a host-signed entry).
3. Action preimage builder per formats §5 exactly (mirrors task-1-adjacent
   work already established by P1/P2's pattern):
   `0x03 ‖ "vault/act/v2" ‖ binding ‖ hand(8) ‖ seq(8) ‖ action(1) ‖
   amount(32) ‖ prev(32)`.
4. `fileActions(bytes32 session, Act[] calldata acts, bytes[] calldata
   sigs) external`: `require(status == Disputed, "not disputed")`;
   `require(acts.length == sigs.length, "length mismatch")`; for each
   `(act, sig)`: compute `actionHash`; recover the signer via
   `_recoverRaw` and test against `sessionKeyHost` and `sessionKeyGuest`
   in turn (decision 1) — neither match → skip this entry (no revert for
   the whole batch on one bad entry, since `fileActions` is "any segment,
   any order," formats §9, and a batch should not fail atomically on one
   garbage entry from elsewhere); a match → look up the slot for
   `(session, act.hand, act.seq)`:
   - Empty slot for this signer → store `ActCandidate(signer, act.action,
     act.amount, act.prev, actionHash, uint40(block.timestamp), true)`.
   - Occupied slot, same signer, `actionHash` equal → no-op (dedup).
   - Occupied slot, same signer, `actionHash` different → **equivocation**
     (decision 2): if `block.timestamp < disputeOpenedAt[session] +
     window`, call `_burnBond(session, signer == sessionKeyHost)` (the
     idempotent P2 primitive — a second equivocation from the same signer
     in the same dispute is a no-op via its own guard, matching D13's
     "burns are idempotent per bond"); regardless of the window check,
     **do not overwrite** the stored candidate — "the earliest-filed
     stands for the replay" (§5.1) means the first-stored entry is
     authoritative and the second is simply rejected from the chain.
   - Occupied slot from the **other** signer (the array's other index is
     free) → store as the second candidate normally; this is not
     equivocation (different keys, formats §5: "cross-key forks remain
     impossible" as a burn category — a wrong-signer candidate is a
     legality question for task 6's replay, not a misconduct question for
     this task).

   **AF-6, orchestrator ruling on D8's "lowest-hash same-block tie":** D8
   describes consolidation as "earliest-filed-per-node, lowest-hash
   same-block tie" — a tiebreak this task's first-stored-wins rule never
   implements, and deliberately so. The two rules are equivalent here, not
   in conflict: D8's paper rule is written for consolidation conceived as
   an **off-chain** computation over a set of timestamped filings, where
   two filings can genuinely carry the same block timestamp and need a
   second, deterministic tiebreak to produce a total order. On chain,
   **EVM transaction execution within a block is strictly sequential** —
   every `fileActions` call that lands in the same block still executes
   one after another, in a fixed order, so the *storage-arrival* order
   (whichever `ActCandidate` write happens first) is already a total
   order with no genuine simultaneity left to break a tie over. "First
   stored wins" **is** "earliest-filed wins" once filing is itself an
   on-chain, sequentially-ordered event — the hash tiebreak has nothing
   left to resolve, because the case it exists for (two filings truly
   concurrent, no inherent order between them) cannot arise in a
   transaction-ordered environment. **Do not implement a hash
   comparison** — there is no pair of candidates this task's storage
   model could ever present it with. The covering test is the existing
   same-block equivocation case in task 8's `test_F13_4_equivocation_burn`
   (step 4 there: two distinct same-node signatures from one key, filed
   in the same block via back-to-back calls in one test) — extend that
   fixture's assertion to also confirm which of the two calls "won" is
   exactly whichever call's transaction executed first (the test's own
   call order), not a hash comparison of any kind.
5. Emit `ActionsFiled(session, hand, count)` or per-entry, implementer's
   choice — no test depends on the event shape, only on storage state.
6. **In-window filter lives in task 6, not here** — this task stores every
   syntactically valid, correctly-signed candidate regardless of timing
   (decision 2's window check governs only the *equivocation burn side
   effect*, not storage); consolidation (task 6) is what refuses to walk a
   late-filed candidate into the frozen chain. Stating this once here so
   task 6 does not re-derive it: storing a late candidate is harmless
   because nothing reads `actionsAt` except the replay engine, and the
   replay engine filters by `filedAt`.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0.

**Dispatch:** `agent (session-tier, high)` — the equivocation-burn side
effect and the receipt-stacks extension are both load-bearing money-safety
surface (F13.4, F14.3, and the replay engine's whole baseline depend on
this task being exactly right).

---

### Task 4 — `postShares`: the triple check at file time

**Goal:** decision 5 — Merkle share, Merkle deck (same position), DLEQ
against whichever cardPk verifies; store only passing posts; no revert on
a failing one.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. Storage: `mapping(bytes32 => mapping(uint8 => mapping(address =>
   Ristretto.Pt))) postedShare;` (keyed `keccak256(session, hand)` → pos →
   player address → the decoded share point, cached for task 9),
   `mapping(bytes32 => mapping(uint8 => mapping(address => bool)))
   sharePosted;` for the pass/fail flag decision 5 describes, and
   `mapping(bytes32 => mapping(uint8 => Ristretto.Pt)) deckC2At;` (keyed
   `keccak256(session, hand)` → pos → the decoded `c2` point of the
   deck-committed ciphertext at that position — written once, by
   whichever post first passes its deck-Merkle check for that position;
   task 9's `decodeAt` reads this directly rather than re-deriving `c2`
   from a filer's later claim). Two mappings rather than one
   struct-valued one for the share side — implementer's choice, either
   compiles; state whichever was chosen in completion notes since task 9
   reads it back.
2. `postShares(bytes32 session, SharePost[] calldata posts) external`:
   `require(status == Disputed, "not disputed")`; the marked live hand is
   `markedHand[session]`. For each `post`:
   - `bytes32 shareLf = Evidence.shareLeaf(post.pos, post.shareEnc);`
     verify `Evidence.merkleVerify(shareLf, post.shareProof, root)` against
     **both** `hostShareRoot` and `guestShareRoot` in turn (self-
     authentication, decision 1) — whichever root the proof verifies
     against determines candidate ownership for this post; verifying
     against neither → skip, no revert (decision 5).
   - `bytes32 deckLf = Evidence.deckLeaf(post.pos, post.c1Enc,
     post.c2Enc);` verify `Evidence.merkleVerify(deckLf, post.deckProof,
     deckRoot)` (the single deck root, not player-specific) at the
     **same** `post.pos` — decision 10/formats §7's "same index p" rule;
     fail → skip. Pass → decode `post.c2Enc` via `Ristretto.decode`.
     **`Ristretto.decode` returns `(bool ok, Pt memory)`, and `ok ==
     false` is a real, distinct case here** — the bytes Merkle-included
     into `deckRoot` at this position are not a valid ristretto255
     encoding at all (malformed at the *encoding* level, not "a valid
     point that happens not to be one of the 52 cards," which is task 9's
     separate, later failure mode over the *combined* point). Per
     decision 5's spirit: skip, do not store, do not revert — this single
     post is simply invalid for this position, exactly like a failing
     Merkle or DLEQ check above, and the position remains un-posted
     (contributing to a muck outcome at resolution, not to the fourth
     row, since the fourth row requires every check to have *passed*).
     Only on `ok == true` write `deckC2At[key][post.pos]` if not already
     set (idempotent — every honest post for the same position decodes to
     the same `c2`, so a repeat write is a harmless no-op, not something
     to guard with an extra branch).
   - `Dleq.verify(cardPkForOwner, post.c1Enc, post.shareEnc, post.c, post.s)`
     where `cardPkForOwner` is `hostCardPk` if the share-root check matched
     host, else `guestCardPk` — fail → skip.
   - All three pass → `postedShare[key][post.pos][owner] =
     decode-to-Pt(post.shareEnc)` (the wire encoding decoded to a
     `Ristretto.Pt` via `Ristretto.decode`, reused directly since the DLEQ
     check already ran `Ristretto.decode` internally — cache the decoded
     point rather than re-decoding in task 9); `sharePosted[key][post.pos]
     [owner] = true`.
3. Emit `SharePosted(session, hand, pos, owner)` per passing post (skipped
   posts emit nothing — "no revert" per decision 5 is not "no signal";
   silence is the signal for a failing post, matching the muck row's own
   silence-is-the-fact structure).
4. **No in-window filter here.** Unlike actions, a share posting has no
   equivocation-shaped misconduct category — two DIFFERENT shares for the
   same `(hand, pos, owner)` cannot both pass the DLEQ against the same
   `cardPk` (the proof is unique to the actual secret), so there is
   nothing to burn on conflict; only completeness (posted or not, by each
   duty's own deadline) matters, and deadlines are task 11's concern, not
   this task's storage.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. Functional probe deferred to task 8/13 (a real Merkle
tree + DLEQ proof, built from task 2's vectors or `vm.sign`-equivalent
constructions, posted and confirmed stored).

**Dispatch:** `agent (session-tier, high)` — decision 10's "never taken
from the filer's word" is exactly what a checker will target; the ordering
(Merkle-deck-then-DLEQ, never DLEQ first) is load-bearing for that
property and must not be silently reordered.

---

### Task 5 — `BettingReplay.sol`: the ported betting-replay engine

**Goal:** decision 3, in full — a standalone library P4 also imports.
**Operates entirely in chip-space (decision 3a) — no wei figure enters
this library anywhere; the caller (task 6) is responsible for converting
its wei-denominated baseline into chips before calling `replay`, and for
converting the result back after.**

**Files:** `contracts/src/BettingReplay.sol` (new),
`contracts/test/BettingReplay.t.sol` (new — test contract named
`BettingReplayTest`, same naming convention as `ChannelV2Test`; task 8
extends this same file/contract).

**Steps:**
1. Port `BettingState` (`betting.ts:23-37`) to a Solidity struct: `street`
   (an enum `Preflop, Flop, Turn, River`), `committedHost`/`committedGuest`,
   `investedHost`/`investedGuest`, `stackHost`/`stackGuest`, `toActIsHost`,
   `lastRaiseSize`, `actedSinceAggressionHost`/`Guest` (two bools, since
   Solidity has no cheap `Set<Seat>` for a two-element universe —
   `betting.ts`'s `Set<Seat>` is exactly a pair of booleans once the seat
   universe is fixed at two), `closed`, `foldedIsHost` (a tri-state: not
   folded / host folded / guest folded — a `int8` or a separate `bool
   hasFolded` plus `bool foldedIsHost` is fine, implementer's choice),
   `bigBlind`.
2. `startHand(bool buttonIsHost, uint256 stackHost, uint256 stackGuest,
   uint256 sb, uint256 bb) → State` — posts `min(sb, stackButton)` and
   `min(bb, stackNonButton)` (`betting.ts:48-49`), `toActIsHost =
   buttonIsHost` (button acts first preflop, `betting.ts:56`).
3. `toCall`, `minRaiseTo`, `maxRaiseTo`, `legalActions`-equivalent
   (`betting.ts:77-109`) ported as `internal pure` helpers — these are
   read-only arithmetic, no state mutation, straightforward integer
   translation (`Math.min`/`Math.max` → Solidity's own min/max, which
   `< ? :` expresses directly, no library needed for two-operand min/max).
4. `applyAction(State memory st, bool actorIsHost, uint8 action, uint256
   amount) → (State memory, bool ok)` — mirrors `applyAction`
   (`betting.ts:127-183`) exactly: `fold` sets `closed = true`,
   `foldedIsHost = actorIsHost`; `check`/`call` update
   `actedSinceAggression`/commit chips per `toCall`; `bet` validates
   **exactly** `lo <= amount && amount <= hi` (decision 3's range-check
   simplification — `lo`/`hi` computed via step 3's helpers) and, if
   legal, commits `amount`, updates `lastRaiseSize`/`actedSinceAggression`
   per the `raiseSize >= lastRaiseSize` test (`betting.ts:161-166`); an
   action that fails its legality check (wrong actor, wrong `action` for
   the current `legalActions`, or an out-of-range `bet` amount) returns
   `ok = false` and **does not mutate `st`** — the caller (task 6) treats
   this exactly like "no candidate exists for this seq," i.e. the chain
   stops here, not a revert.
5. `closeAndAdvance(State memory st, bool buttonIsHost) → (State memory,
   bool stillLive)` — after `applyAction` returns `closed = true`
   (round-over, not fold), mirrors `nextStreet` (`betting.ts:186-198`):
   resets committed/`lastRaiseSize`/`actedSinceAggression`, advances
   `street`, re-`closed`s if either stack is now 0 (all-in runout —
   `stillLive` stays true, the caller loops this function again
   automatically since the new street is immediately closed too, cascading
   exactly as `betting.ts`'s own callers do by repeatedly invoking
   `nextStreet` after every `applyAction` that closes a round), sets
   `toActIsHost = !buttonIsHost`. Returns `stillLive = false` once `street`
   was already `River` and closes again (mirrors `nextStreet`'s `idx ===
   STREETS.length - 1` early return, `betting.ts:189`) — this is the
   "betting complete" terminal signal task 6 reads.
6. `enum TermKind { NONE, FOLD, COMPLETE }` and the public entry point:
   `replay(bool buttonIsHost, uint256 sb, uint256 bb, uint256 stackHost,
   uint256 stackGuest, Cand[] memory ordered) → (TermKind kind, address
   folder, State memory finalState, uint256 lastAcceptedSeq, uint256
   completingFiledAt)` — **every `uint256` here is chip-space** (`sb`,
   `bb`, `stackHost`, `stackGuest` in, and every amount inside `finalState`
   out); task 6 is the only caller and the only place a wei value ever
   touches this function's boundary. `Cand` is the caller-prepared, already
   in-window-filtered, seq-ordered view into task 3's `actionsAt` storage
   (task 6 builds this array; `BettingReplay` itself touches no storage —
   `pure`, testable with hand-built inputs with no `ChannelV2` deployment
   at all, which is exactly why task 5's own test file is separate from
   `ChannelV2.t.sol`). Walks `ordered` by seq starting at `startHand`'s
   result: at each step, requires a candidate exists whose `signer`
   matches the just-computed `st.toActIsHost`'s corresponding session key
   (host key if `toActIsHost`, else guest) — a candidate from the *wrong*
   signer at that seq is skipped/ignored (not an error; the chain simply
   has no valid continuation there, `kind` stays `NONE`); applies it via
   step 4; on `fold` → `kind = FOLD`, stop; on round-close → step 5's
   cascade, then continue the loop if a next-seq candidate exists, else
   stop with `kind = NONE` (pending — task 7 routes this to
   `PendingContinuation`); if `closeAndAdvance` reports `stillLive =
   false` (river closed or all-in cascade reached the end) → `kind =
   COMPLETE`, stop. `completingFiledAt` is the `filedAt` of the **last
   accepted candidate** when `kind == COMPLETE` (decision 3's birth
   anchor for task 11's share-duty deadlines) — `0` when `kind == FOLD`
   (a fold owes no share duties at all, §5.3's fold row).

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract BettingReplayTest -vv

YES/NO: exits 0. Minimum assertions this task's own tests must cover
(independent of any `ChannelV2` wiring): (a) a folded chain returns
`FOLD` with the correct folder; (b) a chain reaching river-close with both
sides having acted returns `COMPLETE`; (c) an all-in on the flop with no
further filed actions cascades `closeAndAdvance` straight to `COMPLETE`
with zero additional candidates consumed (mirrors `betting.ts:195`'s
auto-close); (d) a chain missing its next seq's candidate returns `NONE`;
(e) a `bet` whose signed `amount` sits **exactly** at `lo` and **exactly**
at `hi` both succeed (the range-check boundary, decision 3), and `lo − 1`/
`hi + 1` both fail; (f) a short all-in raise (`raiseSize < lastRaiseSize`)
does not reopen action for a seat that already acted (mirrors
`betting.ts:161-166`, cross-checked directly against a `node -e`
computation running the **actual** `applyAction` from `betting.ts` on the
same inputs — the side-effect boundary permits this as a read-only
differential check, and it is the strongest verification available short
of a shared vector file, which D16 does not extend to this phase's
replay engine); **(g) M1 (fix round 1, P3-2) — out-of-turn candidate,
the AF-2 turn-order property's own probe, currently missing:** a chain
where a *validly-signed* candidate exists at seq `k`, but its signer does
not match the replayed `st.toActIsHost`'s corresponding key (e.g. the
non-button seat's action stored at the seq the button was actually due to
act) → assert `replay` treats this exactly as "no candidate at seq `k`"
(`kind == NONE`, chain stops at `lastAcceptedSeq == k − 1`) — **not** as
an accepted action, and **not** as equivocation (a different-signer
candidate at the same node is a legality question, decision 2's own
distinction, not a same-key conflict). This is the fixture step 6's
"skipped/ignored" clause describes in prose; it had no test asserting it
before this fix.

Both (a)-(g) are Part A's own gate content (task 8's `--match-contract
BettingReplayTest` run), not deferred to Part B.

**Dispatch:** `agent (session-tier, high)` — this is the task REVIEW-BRIEF
and AF-1 both name as the phase's contract-owning centerpiece; a subtle
port error here (an off-by-one in `minRaiseTo`, a missed `stillLive`
cascade) is invisible until a real dispute fixture disagrees with
`betting.ts`, and P4 inherits whatever this task ships unchanged.

---

### Task 6 — Consolidation: the lazy wrapper around the replay engine

**Goal:** decision 4 — build task 5's `Cand[]` array from task 3's storage,
in-window-filtered, perform the wei→chip conversion decision 3a assigns to
this function, and expose the result as an internal `view` helper
`resolve()` (task 7) calls.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `_consolidate(bytes32 session) internal view returns (BettingReplay.TermKind
   kind, address folder, BettingReplay.State memory finalState,
   uint256 lastAcceptedSeq, uint256 completingFiledAt, uint256 weiPerChip)`:
   `hand = markedHand[session]`; read the marker's `button`/`sb`/`bb`
   (chip-space, decision 3a — P2's stored marker fields; confirm the exact
   field names against the shipped `ChannelV2.sol`, task 1's re-read);
   read `receiptStacksAt[session][hand - 1]` (task 3's extension, wei) as
   the baseline.
2. **Compute `weiPerChip` (decision 3a):** `startingChips = 200 * bb`
   (spec §3's fixed V2 buy-in convention, `bb` from this same marker read
   in step 1); `weiPerChip = receiptStacksAt[session][0].hostDeposit /
   startingChips`; `require(receiptStacksAt[session][0].hostDeposit %
   startingChips == 0, "chip/wei rate mismatch")` (decision 3a's sanity
   check). Convert the baseline: `chipStackHost =
   receiptStacksAt[session][hand-1].hostStack / weiPerChip`,
   `chipStackGuest = .../ weiPerChip`, each with the same exactness
   `require`.
3. Build `ordered`: walk `seq = 0, 1, 2, …` reading `actionsAt[keccak256
   (session, hand, seq)]`'s two slots; **filter by `filedAt <
   disputeOpenedAt[session] + window`** (decision 2's window boundary,
   applied here uniformly to both equivocating and non-equivocating
   candidates); stop building the array at the first `seq` with no
   in-window candidate at all (the replay engine itself also stops there,
   so building further is wasted work, not a correctness issue either
   way — implementer's choice whether to pre-truncate or let
   `BettingReplay.replay` discover it). Every stored `amount` inside
   `ordered` is already chip-space (formats §5, decision 3a) — no
   conversion needed here, only for the baseline stacks (step 2).
4. Call `BettingReplay.replay(button, sb, bb, chipStackHost,
   chipStackGuest, ordered)` (step 2's chip-space values, step 1's
   chip-space `sb`/`bb`); return its result directly **plus `weiPerChip`**
   — this function does **no** interpretation of the replay result (fold
   vs. complete vs. pending is task 7's routing, not this task's) and no
   interpretation of `weiPerChip` either (converting a payout back to wei
   is task 10/11's job); this function only computes and hands the rate
   forward.
5. **No storage write anywhere in this function** — `view`, not even a
   "consolidation ran" flag, per decision 4's literalism about laziness.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. **P3-5 (fix round 1): the single-line `grep "internal
view" | grep _consolidate` pipe from this doc's earlier draft is fragile**
— a multi-line function signature (likely, given step 1's six-element
return tuple) can easily put `_consolidate`, `internal`, and `view` on
three different lines, which that pipe would silently fail to match even
on a correct implementation. Replaced with a line-span-aware check:

    awk '/function _consolidate\(/,/\{/' contracts/src/ChannelV2.sol | grep -c "view"

YES = at least 1 — the declaration, wherever its line breaks fall,
contains the `view` keyword somewhere between `function _consolidate(`
and its opening `{`. **The stronger proof is the compiler itself, not the
grep**: Solidity treats a state-mutating statement inside a
`view`-declared function as a hard compile error, not a warning — so
`forge build`'s own success with this signature declared `view` is
already proof no storage write exists in the body; the `awk`/`grep` above
only confirms the declaration says what this task's steps require it to
say, which the compiler is separately enforcing.

**Dispatch:** `agent (workhorse, high)` — mechanical given tasks 3 and 5
are both already pinned; the only judgment call (the window filter) is
already fully specified by decision 2.

---

### Task 7 — Wire `resolve()`'s `markedHand > 0` branch: terminal-vs-pending routing

**Goal:** replace P2's `revert NotYetBuilt();` (P2 task 5 step 3, the
`markedHand[session] > 0` branch) with a call into task 6's consolidation
and a route to either `PendingContinuation` (decision 8) or a placeholder
that Part B's tasks 10–11 fill with the real resolution table. **This task
does not implement any resolution row itself** — it only proves the
routing, so Part A's own gate can assert "a folded/complete chain reaches
the resolution boundary; a pending one reverts the right error" without
Part B existing yet.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `error PendingContinuation();` at contract scope (decision 8).
2. In `resolve()`, replace the `markedHand[session] > 0` branch's body:
   call `(kind, folder, finalState, lastAcceptedSeq, completingFiledAt,
   weiPerChip) = _consolidate(session)`; on `TermKind.NONE` → `revert
   PendingContinuation();`; on `TermKind.FOLD` or `TermKind.COMPLETE` →
   call a new internal stub, `_resolveTerminal(session, kind, folder,
   finalState, completingFiledAt, weiPerChip) internal returns (bool)`
   (decision 3a's rate threaded through here so Part B's rows never
   re-derive it), **which this task declares but leaves reverting
   `NotYetBuilt()`** (Part B's task 10 replaces this stub's body — the
   same "interface exists, body comes later" contract P2 used on this
   phase, now handed one level deeper).
3. This is the one place in this phase's own task list where a forward
   reference must be avoided explicitly (the brief's own caught-defect
   precedent, P2's `_burnBond`/task-5/task-6 ordering): `_resolveTerminal`
   is **declared here, in task 7**, precisely so Part A's gate can build
   and test the routing (steps above) without Part B's body existing yet,
   and Part B's task 10 only fills the body — no task in Part B
   redeclares or moves this function. State this once, as P2's doc did.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, and `grep -c "PendingContinuation" contracts/src/ChannelV2.sol`
returns at least 2 (the error declaration plus the throw site).

**Dispatch:** `agent (workhorse, medium)` — small, mechanical wiring; the
design judgment (the two-stub-layer pattern) is already decided above.

---

### Task 8 — Part A tests: fixtures, replay-engine differential coverage, gas baseline

**Goal:** the six fixture rows Part A's scope owns outright, plus M2's
position-mismatch negative for `postShares` (fix round 1, P3-4 — the rest
belong to Part B, task 13), plus a gas snapshot establishing this phase's
own baseline against the measured prototype figures.

**Files:** `contracts/test/ChannelV2.t.sol`, `contracts/test/BettingReplay.t.sol`
(extended from task 5).

**Steps:**
1. `test_F12_1_truncation_loses_full_window`: file a chain truncated at
   the truncator's own river bet; separately, file the fuller chain
   (containing the truncator's own later signatures, per the spec's
   framing) inside the same window; assert consolidation's frozen chain
   equals the fuller one — `_consolidate` returns `COMPLETE` with the
   longer chain's terminal state, not `NONE`/the shorter one.
2. `test_F12_3_clamp_parity`: honest wire chain with a clamped bet (raw
   200 → canonical 120, from P1's committed vector — task 2 is a hard gate
   per D18, so this construction is always vector-backed by the time this
   task runs, never a `vm.sign` substitute); assert
   `BettingReplay.applyAction` accepts `amount = 120` and the replayed
   state's `committed` matches exactly; assert `amount = 200` (the
   pre-clamp figure) is rejected by the `lo/hi` range check (it must be
   above `hi`, confirming the fixture is a real clamp case, not a
   trivially-legal one).
3. `test_F12_6_first_marker_in_window`: dispute opened before marker N
   confirms; file the both-signed marker for hand N inside the window
   (P2's `fileMarker`, callable during `Disputed` per P2's own
   `require(status == Active || status == Disputed, ...)`); assert
   `markedHand` reflects N and a fold filed for hand N resolves against
   the live hand, **not** refunded as if hand N never began.
4. `test_F13_4_equivocation_burn`: same signer, same `(hand, seq, prev)`,
   two distinct `(action, amount)` pairs, both filed in-window; assert
   `_burnBond` fired exactly once for that signer (idempotence via P2's
   existing guard) and the earliest-filed candidate is what
   `_consolidate` uses. Include the identical-duplicate case (F14.4)
   as a sub-case: same signer, same content, filed twice → no burn, no
   duplicate storage effect. **AF-6 sub-case (D8's "lowest-hash
   same-block tie," covered without a hash comparison — task 3 step 4):**
   file the two distinct candidates via two separate calls inside the
   same test block (no `vm.roll` between them, matching real same-block
   filing); assert the *first*-executed call's candidate is what
   `_consolidate` uses regardless of either candidate's hash — confirming
   storage-arrival order (not a hash comparison) is what "wins" a
   same-block conflict on chain.
5. `test_F14_3_pair_in_window_only`: two distinct same-node signatures
   from one key, the **second** filed at `disputeOpenedAt + window + 1`
   (`vm.warp` past the boundary before filing it) → assert **no** burn
   fires (decision 2's window-gated check), and assert the late candidate
   does not enter `_consolidate`'s frozen chain either (task 6's filter).
6. `test_F14_5_boundary_conventions`: a candidate filed in the exact block
   whose timestamp equals `disputeOpenedAt + window` (the half-open
   interval's own boundary, `[open, open+24h)` — phase 1 is `<`, not
   `<=`) → assert it is treated as **phase 2**, i.e. excluded from
   consolidation (matches the fourteenth check's finding 5a, cited in the
   spec's §5.1); separately, a filing that lands in the **same block** as
   a duty's own deadline counts as met (finding 5b) — construct a case
   where a duty's `dueAt` equals the current block's timestamp exactly and
   assert the filing in that block is accepted, not late (this sub-case
   depends on Part B's deadline machinery existing for a *duty* deadline
   specifically — if task 11 has not landed yet when this task runs, scope
   this sub-case to the **window** boundary alone here and note the
   duty-deadline half as carried forward to task 13, rather than blocking
   task 8 on Part B).
7. **M2 (fix round 1, P3-4) — `postShares` position-mismatch negative:**
   a `SharePost` whose `shareProof` genuinely proves inclusion at position
   `p` (a real, passing `shareLeaf(p, shareEnc)` → `shareRoot` proof) but
   whose `deckProof` proves inclusion of a **different** position `q ≠ p`
   (a real, passing `deckLeaf(q, c1Enc, c2Enc)` → `deckRoot` proof, built
   honestly for `q`, then submitted inside a `SharePost` claiming `pos =
   p`) → assert `postShares` does **not** store this post (`sharePosted`
   stays `false` at both `p` and `q` for this filer, `deckC2At[key][p]` is
   not written from it) and does **not** revert — decision 10/formats
   §7's "same index `p`" rule (task 4 step 2) exists exactly to catch
   this, and this fixture is the first thing to prove it actually does
   rather than only being described in prose.
8. Gas baseline: `~/.foundry/bin/forge snapshot --root
   /home/dev/projects/vault/contracts --match-contract ChannelV2Test`
   (command form confirmed 2026-08-17 against V1's suite, see Inputs);
   read the `.gas-snapshot` entries for `postShares` (one passing triple
   check) and `fileActions` (one accepted candidate); compare informally
   against the prototype's measured **DLEQ ~2,969,269 gas/share** and
   **Merkle inclusion ~3,786 gas** (`prototypes/dispute-gas/README.md`'s
   measured table) — not a pass/fail gate (this contract embeds the same
   library code inside a bigger call, so some overhead is expected), but
   record the comparison in completion notes; a divergence of more than
   roughly 2× either figure is worth flagging to the operator before P7,
   mirroring P2's own non-blocking gas-sanity gate.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test -vv
    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract BettingReplayTest -vv

YES/NO: both exit 0, all seven named fixtures pass (steps 1–6 plus M2's
position-mismatch negative), gas comparison recorded in completion notes.

**Dispatch:** `agent (workhorse, high)` — long, exacting, follows patterns
tasks 3/5/6/7 already established; not architecture-inventing.

---

## Part A — Phase-boundary verification

Gate type: **technical-auto**.

1. **YES/NO — build.** `~/.foundry/bin/forge build --root
   /home/dev/projects/vault/contracts` exits 0.
2. **YES/NO — Part A test suites green.** Both probes in task 8 exit 0.
3. **YES/NO — V1 isolation and P2-extension discipline, both as literal
   greps (P3-3, fix round 1: this item was a human-read check mislabeled
   `technical-auto` — both halves are now real, base-ref'd greps, per
   D17):**
   - **3a — V1 untouched:** `git -C /home/dev/projects/vault diff
     <phase-3-base>..HEAD -- contracts/src/Channel.sol
     contracts/test/Channel.t.sol contracts/script/Deploy.s.sol` — YES =
     empty output (D11).
   - **3b — P2-owned functions extended only at their disclosed sites
     (D9 amendment 2026-08-17/AF-30, fix applied here per that amendment's
     own instruction: "task 8 updates the gate wording to match" — the
     original `2`-count wording conflated a Part-A boundary with a
     whole-phase one, drafted before AF-30 discovered `_fileMarkerCore`'s
     third disclosed extension):**
     `git -C /home/dev/projects/vault diff <phase-3-base>..HEAD --
     contracts/src/ChannelV2.sol | grep -c "P3 extension"` — YES = exactly
     `4` at the Part A boundary: task 3's `fileReceipt`
     `receiptStacksAt` cache (1 occurrence) and task 3/`_fileMarkerCore`'s
     `markerAt` persistence (the D9 amendment's third disclosed
     extension — 3 occurrences, one per comment site: the `MarkerData`
     struct comment, the `markerAt` mapping comment, and the
     `_fileMarkerCore` body comment) — both cite decision 7 (the marker
     one as "decision 7-adjacent," per the amendment's own framing), each
     carrying a literal `P3 extension` comment string. Task 12's
     `finalEligible`/`_crystallizeMaturedDuties` extension (the amendment's
     numbered extension 2) is Part B's, not counted here — it lands only
     once task 12 ships, and Part A's own diff (this gate's scope) must
     not include it. This does not prove the diff touches *nothing else*
     inside those functions (a content grep counts markers, it does not
     diff line-by-line), but it does mechanically confirm the intended
     Part-A extension points exist and that no *undisclosed* `P3
     extension` comment was added beyond the amendment's accounted-for
     set — a real, if coarser, signal than the count alone might suggest,
     and one worth widening in the arc-end review if a checker wants the
     full line-by-line diff read.
4. **YES/NO — routing proven without Part B.** A fold chain and a
   betting-complete chain both reach `_resolveTerminal`'s stub (still
   `NotYetBuilt()` — confirmed by `vm.expectRevert(ChannelV2.NotYetBuilt.selector)`
   in a task-8-adjacent test) rather than `PendingContinuation`; a
   genuinely incomplete chain reverts `PendingContinuation` and nothing
   else. This is the seam REVIEW-BRIEF asked every gate to attack:
   **construct the case where the probe passes while the capability is
   broken** — here, that would be `_resolveTerminal` never actually being
   reached for a real terminal chain (e.g. an off-by-one in `_consolidate`'s
   seq walk silently reports `NONE` for a complete chain). Task 8's
   fixtures (2, `test_F12_3_clamp_parity`, and the differential check in
   task 5's own probe) are what make this the case the gate actually
   exercises, not merely a shape that could pass vacuously.
5. **YES/NO — no chain, no deploy, no P4 surface touched (B5/D17, fix
   round 1 — this doc's earlier `git diff --stat | grep -c phase2Act`
   form could never fail even on a real touch, since `--stat` reports
   file-level summary lines, none of which contain the token
   `phase2Act`; replaced with a content-level diff grep, base-ref'd per
   D17):**

       git -C /home/dev/projects/vault diff <phase-3-base>..HEAD -- contracts/src/ChannelV2.sol | grep -c '^[-+].*phase2Act'

   YES = `0` — no added or removed line anywhere in this phase's diff
   mentions `phase2Act` at all (untouched, still P2's stub).

---

## Part B — terminal rows, remaining crypto graduation, fixtures

### Task 9 — Card decode & combine

**Goal:** decision 6's `decode()` function — combine two posted shares,
match against the 52-point table, surface a clean "which card, or none"
result Part B's terminal rows consume.

**Files:** `contracts/src/Evidence.sol`.

**Steps:**
1. `decode(Ristretto.Pt memory c2, Ristretto.Pt memory hostShare,
   Ristretto.Pt memory guestShare) → (bool ok, uint8 card)`: compute
   `combine(...)` (task 1 step 5), `bytes32 enc = Ristretto.encode(...)`,
   linear-scan `CARD_POINTS` for an exact match; `ok = false` if none
   found (the fourth row's trigger, decision 6).
2. Wire a convenience wrapper `decodeAt(bytes32 session, uint64 hand,
   uint8 pos) → (bool ok, uint8 card)` inside `ChannelV2.sol` (not
   `Evidence.sol`, since it reads `postedShare`/`sharePosted` storage —
   `Evidence.sol` stays storage-free) that first checks
   `sharePosted[key][pos][host] && sharePosted[key][pos][guest]` (both
   required — decoding needs both contributions, per `elgamal.ts`) and, if
   either is missing, returns `ok = false` **without calling `decode`at
   all** — this is the muck condition (a position nobody or only one side
   posted), distinct from the fourth row (both posted, all checks passed,
   decode still fails). Terminal-row logic (task 11) must not confuse
   these two `ok = false` causes; keep them as two separately-named
   conditions in the resolution code, not one boolean.
3. Deck ciphertext's `c2` for a given position is task 4's
   `deckC2At[key][pos]` (task 4 step 1/step 2, written the first time any
   post's `c1Enc ‖ c2Enc` passes the deck-Merkle check for that position) —
   `decodeAt` reads it directly; this task adds no new deck-side storage.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract EvidenceTest -vv

YES/NO: exits 0; assert a genuine card (both shares from a real
`decryptionShare`-equivalent construction, cross-checked via `node -e`
against `elgamal.ts`'s own `decryptionShare`/`combineShares`) decodes to
the expected index; assert a deliberately malformed pair (e.g. a
duplicate-card deck, per F13.6) decodes to `ok = false`.

**Dispatch:** `agent (session-tier, medium)` — small surface, but the two
distinct `ok = false` causes (muck vs. fourth row) are exactly the
distinction a checker will probe first.

---

### Task 10 — Terminal rows: fold and cards-decide

**Goal:** the two "evidence complete, someone provably won" rows of
§5.3's table; fills task 7's `_resolveTerminal` stub for these two cases
(the remaining three land in task 11).

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `_resolveTerminal(bytes32 session, TermKind kind, address folder,
   BettingReplay.State memory finalState, uint256 completingFiledAt,
   uint256 weiPerChip)` (task 7's signature, `weiPerChip` added per
   decision 3a): on `TermKind.FOLD` — compute the chip-space payout via
   the ported `settle()` (`betting.ts:204-223`): `excess =
   |finalState.investedHost - finalState.investedGuest|` (chips) returns
   to whoever overpaid before the contested remainder splits by winner —
   port this arithmetic directly, it is the same shape task 5 already
   ported once for `applyAction`'s bookkeeping, just applied once at the
   end rather than per-action. **Convert the resulting chip-space
   payout/invested deltas to wei by multiplying each by `weiPerChip`
   (decision 3a — the only conversion this row needs, always exact)**,
   then overlay onto the baseline `receiptStacksAt[session][hand-1]`
   (D9's precedence, spec §1.2: "receipt for hand N−1 plus an adjudicated
   outcome for hand N settles at the receipt's stacks moved by the
   adjudicated pot"); **the folder's bond returns** (spec §5.3's fold
   row — folding is a completed decision, not misconduct); no `_burnBond`
   call on this path at all.
2. On `TermKind.COMPLETE`: determine required positions from `finalState`'s
   final `street` — `POS.hostHole = [0,1]`, `POS.guestHole = [2,3]`
   always required; `POS.flop = [5,6,7]` if `street >= Flop`; `POS.turn =
   [9]` if `street >= Turn`; `POS.river = [11]` if `street == River`
   (`protocol.ts:52-58`, confirmed via source read — **this constant is a
   fixed protocol convention, not something this phase invents**; cite
   the exact line in the implementation comment). Check
   `sharePosted[...][pos][host] && sharePosted[...][pos][guest]` for
   **every** required position, for **both** players (each player owes
   their own contribution to every required position, not just their own
   hole cards — decoding is joint, `elgamal.ts:76-79`) — if any required
   position is missing either side's post, this is **not** the
   cards-decide row, fall through to task 11's muck rows instead (this
   task's own `_resolveTerminal` body checks completeness first and
   defers to a `_resolveMuck`/`_resolveSymmetricMuck`/`_resolveFourthRow`
   helper task 11 adds, rather than this task attempting the incomplete
   cases itself).
3. All required positions complete → `decodeAt` (task 9) every required
   position; any single `ok = false` among them → **the fourth row**
   (task 11), not this task's success path — "all checks pass yet a
   combined decryption fails to decode" is exactly this condition,
   discovered here but resolved by task 11's body. All decode → evaluate
   both hands via `Evaluator7.evaluate(uint8[7])` (host's two hole cards
   plus the board; guest's two hole cards plus the board — the board's
   card count depends on `street`, same conditional as step 2, and a
   preflop-or-earlier all-in runout still reaches `River` per
   `BettingReplay`'s cascade, so the board is always exactly the cards
   `street == River` requires by the time `COMPLETE` is reached);
   determine winner via `Evaluator7`'s packed-score comparison (higher
   wins; a tie is a split, mirroring `settle()`'s `winner === null`
   branch, `betting.ts:216-218`); compute the chip-space payout via the
   same ported `settle()` step 1 uses, convert to wei by multiplying by
   `weiPerChip` (decision 3a), and overlay onto the baseline receipt; pot
   to winner (or split); **both bonds return** (spec §5.3's cards-decide
   row — no burn on this path).

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. Functional probe is task 13's fixtures (F11.1 for fold,
the cards-decide happy path).

**Dispatch:** `agent (session-tier, high)` — the required-position
derivation from `street` and the evaluator wiring are both places a
checker will look for an off-by-one (e.g. a flop-only hand mistakenly
requiring turn/river positions, or vice versa).

---

### Task 11 — Terminal rows: muck, symmetric muck, fourth row; birth-anchored deadlines

**Goal:** the three "someone (or both) provably failed a duty" rows,
gated by decision's birth-anchored deadline rule (spec §5.2:
`max(hour 24, birth + 6h)`), plus the dead-man-switch fixture's economics.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. **Duty deadline, two-arg, computed once per call, read everywhere it's
   needed — B2 (fix round 1): `dueAt` takes the birth timestamp as an
   explicit parameter rather than re-deriving it, so every caller
   (including P4's, which already expects this shape) passes the same
   value it already has in hand instead of recomputing consolidation
   itself:**

       dueAt(bytes32 session, uint256 completingFiledAt) internal view
         returns (uint256)
       {
         return max(disputeOpenedAt[session] + window, completingFiledAt + grace);
       }

   `completingFiledAt` is never read from storage inside `dueAt` itself —
   every call site in this task already holds it, because `_resolveTerminal`
   (task 7's declared signature) takes `completingFiledAt` as one of its
   own parameters, sourced from `_consolidate`'s return (task 6, itself
   from `BettingReplay.replay`'s `completingFiledAt`, task 5) — the
   on-chain filing time of whichever action completed betting for the
   marked hand. This single function is spec §5.2's birth-anchored rule,
   stated once; every row below calls it with the same in-scope
   `completingFiledAt`, none re-derives it or re-runs consolidation to get
   it again.
2. `_resolveTerminal`'s completeness check (task 10 step 2) found the
   chain `COMPLETE` but at least one required position is missing a post
   from at least one side. **Before resolving anything**, require
   `block.timestamp >= dueAt(session, completingFiledAt)` (the parameter
   already in scope) — if the deadline hasn't passed yet, `resolve()` must
   **not** settle prematurely (a player who still has time to post cannot
   be mucked early); revert with the same `"window open"`-style string P2
   uses elsewhere (task's own choice of exact string, consistent with
   decision 9's `require` convention) — this is **not**
   `PendingContinuation` (that error means "no action filed for the next
   node," a different situation from "actions complete, shares not yet
   all posted, grace still running").
3. **One-sided muck:** if exactly one player is missing at least one
   required position's post (the other has posted every required
   position for themselves and, since decoding is joint, has also
   necessarily posted their contribution wherever the *other* side's
   position needed it — check both directions explicitly, do not assume
   symmetry) → the pot moves to the complete poster: `finalState.invested*`
   (chips) already gives the contested amount each side put in this hand,
   so the whole pot (converted to wei by `weiPerChip`, decision 3a — the
   same conversion tasks 10's rows use) goes to the complete poster,
   overlaid on the baseline receipt; `_burnBond` on the incomplete side;
   the complete side's bond returns.
4. **Symmetric muck:** both players missing at least one required
   position each (not necessarily the same position) → both bonds burn
   via `_burnBond` (idempotent, safe to call both unconditionally here);
   settle at the **baseline receipt alone**, no pot overlay at all (spec
   §5.3: "settle at the receipt baseline" — the pot from the disputed
   hand is not awarded to either side, since neither proved anything).
5. **Fourth row:** all required positions posted by both sides
   (completeness check in step 2/task 10 step 2 passed) but task 9's
   `decodeAt` returned `ok = false` for at least one position, **or** the
   decoded 52-card set for the hand contains a duplicate (a second,
   independent malformed-deck signal: even if every individual position
   decodes to *some* card, two required positions decoding to the *same*
   card index is the deck-malformed condition too — check this
   explicitly, it is a distinct failure mode from a position that decodes
   to nothing at all) → both bonds burn; settle at the receipt baseline;
   **return normally, no revert** (decision 9, thirteenth check finding
   6 — this row is total, not an error path, and must be reachable by a
   plain `resolve()` call returning success).
6. `test_S_dead_man_switch` groundwork (fixture itself is task 13's, this
   step is the mechanism it exercises): confirm, as a code comment citing
   the parking doc's worked case, that a player who files nothing at all
   until the very last block before `dueAt(session, completingFiledAt)`
   and then completes every duty in that block still avoids the muck
   (finding 5b's "same block counts as met," already proven at the window
   level by task 8's `test_F14_5`; this step's own fixture is the
   **duty**-level instance of the identical rule, since `dueAt`'s value
   can differ per hand from the window's own close, driven by whatever
   `completingFiledAt` that hand's own `_resolveTerminal` call was
   passed).

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. Functional probes are task 13's five remaining fixture
rows plus `test_S_dead_man_switch`.

**Dispatch:** `agent (session-tier, high)` — `REVIEW-BRIEF`'s error record
names exactly this shape of risk ("prose rationales attached to correct
rules rot silently"): the birth-anchor formula is one function
(`dueAt(session, completingFiledAt)`, step 1), gated at exactly one call
site (step 2, before any row below it can be reached) — an implementer
must not duplicate a second `block.timestamp >= dueAt(...)` check inside
steps 3 or 5's own bodies (they run only after step 2's gate already
passed and would otherwise silently diverge from it if a second copy of
the deadline logic were ever hand-written there instead of relying on
step 2's guard).

---

### Task 12 — Crystallize-on-any-resolve: extend `resolve()`'s `finalEligible` branch

**Goal:** decision 7's second disclosed extension — close the composition
gap F16.1/F16.3 name, now that task 11's duty-deadline machinery exists to
crystallize.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `_crystallizeMaturedDuties(bytes32 session) internal`: if
   `markedHand[session] == 0`, no-op (nothing to crystallize — P2's own
   `markedHand == 0` branches handle their own bond fate already, decision
   7 of P2's doc). Else, compute `(kind, folder, finalState,
   lastAcceptedSeq, completingFiledAt, ) = _consolidate(session)` (six
   return values per task 6 step 1 — `weiPerChip` discarded here via the
   trailing empty slot, since this function only crystallizes burns, never
   a payout, and has no use for the conversion rate); if `kind ==
   TermKind.COMPLETE` and `block.timestamp >= dueAt(session,
   completingFiledAt)` (task 11 step 1, called with the
   `completingFiledAt` this same `_consolidate` call just returned — not
   a second, independent derivation) and the completeness check (task 10
   step 2 / task 11 step 3–5)
   would burn one or both bonds, and neither `hostBurned` nor
   `guestBurned` (whichever this pass would set) is **already** set →
   call the same `_burnBond` calls task 11's rows would call. **This
   duplicates task 11's own burn-decision logic in miniature** — stated
   plainly as a real cost, not hidden: the alternative (making task 11's
   `_resolveTerminal` itself idempotent and calling it from both the
   `finalEligible` branch and the `markedHand > 0` branch) was considered
   and rejected because `_resolveTerminal` also **pays out**, and the
   `finalEligible` branch must pay out at the **final's** stacks, not the
   dispute-resolution table's — two payout computations cannot both run
   for one `resolve()` call. A shared **burn-only** helper (this
   function) that both branches call, separate from the **payout**
   logic each branch keeps to itself, is the smaller and more honest
   duplication.
2. Call `_crystallizeMaturedDuties(session)` as the **first** line inside
   `resolve()`'s `finalEligible` branch (P2's existing code, before it
   reads `hostBurned`/`guestBurned` to compute `hostPayout`/
   `guestPayout`) — a one-line addition to an already-shipped function,
   commented `// P3 extension (decision 7): crystallizes matured duty
   burns before a final can pay out around them (F16.1, F16.3).`
3. **This function does not need to run inside the `markedHand > 0`
   dispute branch itself** — task 11's rows already crystallize burns as
   part of resolving that branch directly; this task's helper exists
   *only* for the `finalEligible` short-circuit's benefit.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. Functional probe is `test_F16_1_evidence_window_survives_final`
and `test_F16_3_lazy_crystallisation` (task 13).

**Dispatch:** `agent (session-tier, high)` — this is precisely the
"old-artefact × new-phase seam" REVIEW-BRIEF's error record flags as the
orchestrator's own recurring blind spot (composing new machinery
correctly, under-specifying its interaction with the oldest machinery —
here, P2's `finalEligible` branch). A checker should specifically try to
construct a final that pays out **before** this task's line runs, in
whatever order the implementer actually wrote the branch.

---

### Task 13 — Part B tests: remaining fixtures, D12 re-derivation, gas snapshots

**Goal:** the ten fixture rows Part B owns (F10.1, F11.1, F12.2, F13.6,
F14.1, F15.1, F15.2, F16.1, F16.3, `S_dead_man_switch`), the mandatory D12
re-derivation report, and a full-phase gas snapshot.

**Files:** `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. `test_F10_1_fiction_dies_to_evidence`: refused showdown, offer a
   fiction receipt; victim files the fuller action chain plus shares
   instead → cards decide, true result (task 10's cards-decide row),
   fiction receipt never settles because the marked hand's dispute
   resolution overlay takes precedence per D9.
2. `test_F11_1_fold_is_final_decision`: chain ends in a signed fold;
   folder disputes anyway → pot to non-folder, **folder's bond returns**
   (task 10 step 1 — confirm this explicitly, since it is the row most
   likely to be miscoded as a burn by analogy with the muck rows).
3. `test_F12_2_wrong_key_root_burns_owner`: marker committed with a
   wrong-key `shareRoot`; posted shares pass Merkle (they were built
   against the wrong-key root, self-consistently) but fail DLEQ against
   the marker's `cardPk` → `sharePosted` never sets for that position →
   muck against the committer at `dueAt` (task 11 step 3), **not** a
   revert and **not** the fourth row (the fourth row requires all checks
   to pass; this case fails DLEQ, so it is muck, a distinction the
   fixture must assert explicitly). **Small negative sub-case, alongside
   this triple-check test (task 4 step 2):** a `SharePost` whose
   `c2Enc` is Merkle-included into `deckRoot` at the claimed position
   (proof passes) but is not a valid ristretto255 encoding
   (`Ristretto.decode` returns `ok == false`) → assert `postShares`
   neither reverts nor writes `deckC2At` for that position, and the
   position resolves as un-posted (muck), not as the fourth row — the
   same not-reverting, not-storing discipline as every other failing
   triple-check leg, asserted for this specific leg.
4. `test_F13_6_fourth_row_total`: both seats sign a malformed deck (52×
   same card, per the fixture's own framing); Merkle and DLEQ all pass
   (the commitment is internally consistent, just dishonest); `decodeAt`
   or the duplicate-card check (task 11 step 5) fires → both burn,
   receipt baseline. **Four named assertions, all required (P3-6, fix
   round 1 — Part B's own gate 4 reads these back, so absence of any one
   is a gate failure, not just a weaker test):** (a) `vm.expectRevert` is
   **not** used anywhere in this test (a test that expects a revert would
   silently pass on a bug that reverted for the *wrong* reason); (b)
   `credits[host]` and `credits[guest]` after `resolve()` equal the
   receipt-baseline stacks exactly, with **no** pot overlay; (c)
   `burned[session] == bondHost + bondGuest`; (d) `hostBurned &&
   guestBurned` are both `true`.
5. `test_F14_1_birth_anchored_deadline`: a completing call filed at
   23:59 (one minute before window close); assert the resulting
   hole-share duty's `dueAt` is `birth + 6h` (29:59), **not** `hour 24`
   (which has already passed) — the frozen-terminal hand must **not**
   resolve early via a premature muck at hour 24; `vm.warp` to just
   before 29:59 and confirm `resolve()` still reverts "window open" (or
   equivalent), then warp past it and confirm the muck row fires.
6. `test_F15_1_burn_survives_final`: equivocate (burn crystallises via
   task 3's eager check), then both players sign and file a `final` →
   assert stacks settle per the final's own numbers (task 12's
   crystallization is a no-op here since the burn already happened
   eagerly) **and** the burned bond stays burned (`hostBurned`/
   `guestBurned` still set, `bondHost`/`bondGuest` excluded from the
   final payout per P2's existing `finalEligible` arithmetic).
7. `test_F15_2_symmetric_muck`: chains auto-filed by both sides' clients
   (mirroring an honest crash scenario), both machines then die before
   posting any shares → symmetric muck (task 11 step 4): both burn,
   settle at baseline, no pot overlay.
8. `test_F16_1_evidence_window_survives_final`: file a `final` first (not
   yet resolved — recall only `resolve()` pays, per P2 decision 4); *then*
   file the second half of an equivocation pair (still in-window); call
   `resolve()`; assert the burn crystallised eagerly (task 3) applies
   correctly to the final's payout via task 12's line.
9. `test_F16_3_lazy_crystallisation`: a duty deadline matures (missed
   grace) with **no** transaction touching the session at all until,
   much later, `resolve()` is called once — assert the burn applies
   correctly on that single call, proving "proof is the filings, never
   the computation event" is actually true of this implementation, not
   just asserted in the spec.
10. `test_S_dead_man_switch` (task 11 step 6's fixture): worked at
    concrete numbers analogous to the parking doc's own worked cases
    (state the chosen numbers in a comment); a player who files/posts
    everything required in the exact last block before their `dueAt`
    still avoids the muck — assert the margin lost by waiting that long
    (gas plus whatever timing risk) is nonzero but the **bond** margin
    (110%) is never at risk for a player who makes the deadline, matching
    the fixture's own one-line description ("conditional silence at hour
    23 still loses by the bond margin" — i.e. loses *nothing* the bond
    protects, only ordinary lateness risk).
11. **D12 mandatory re-derivation** (mirrors P2 task 8 step 3 exactly):
    run

        grep -n "^### Findings" /home/dev/projects/vault/docs/superpowers/parking/v2-cash-game-settlement.md

    then read every finding from `## Tenth cold check` (confirmed at line
    1601 as of this doc's drafting — re-grep, don't trust the cached line
    number) through the end of the file (2852 lines total, confirmed via
    `wc -l`), independently building the list of every constructed case
    belonging to P3's scope (consolidation, equivocation, in-window
    admissibility, the replay engine, the triple check, the terminal
    resolution table, birth-anchored deadlines, proven-burns-irrevocable).
    **Diff this list against `fixtures-index.md`'s P3 rows** (confirm the
    current row set at read time: `F10.1, F11.1, F12.1, F12.2, F12.3,
    F12.6, F13.4, F13.6, F14.1, F14.3, F14.5, F15.1, F15.2, F16.1, F16.3,
    S_dead_man_switch` — sixteen rows as of this doc's drafting). Report
    the enumeration in this task's completion notes: confirm each index
    row is still present in the parking doc as read, and flag — as a plan
    finding, not a silent addition or drop — any constructed case the
    re-derivation finds that the index lacks, or any index row the
    re-derivation can no longer locate a case for.
12. Full-phase gas snapshot: `~/.foundry/bin/forge snapshot --root
    /home/dev/projects/vault/contracts --match-contract ChannelV2Test`;
    record the `.gas-snapshot` entries for `resolve()` under each of the
    five terminal rows plus a worst-case showdown (9 required positions,
    per the prototype README's own worked worst case — "preflop all-in
    showdown: 9 cards, 18 shares" — cross-check that this phase's
    `postShares` call count for that scenario is also 18, confirming the
    required-position derivation in task 10 step 2 matches the measured
    scenario exactly); compare informally against the prototype's
    **~27M gas per filing** worst-case figure (`README.md`'s measured
    table) — non-blocking, recorded for the operator.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test -vv

YES/NO: all tests pass (Part A's task 8 fixtures plus every fixture added
here); completion notes contain the D12 enumeration report and the gas
comparison.

**Dispatch:** `agent (workhorse, high)` — long and exacting, follows every
pattern tasks 3–12 already established; the D12 re-derivation is a
literal grep-and-read obligation, not a design task, but the fixture
constructions (especially F13.6's no-revert assertion and F14_1's
birth-anchor timing) need real care.

---

## Part B — Phase-boundary verification

Gate type: **technical-auto**.

1. **YES/NO — build.** `~/.foundry/bin/forge build --root
   /home/dev/projects/vault/contracts` exits 0.
2. **YES/NO — full ChannelV2 suite green, Part A and Part B together.**
   `~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts -vv`
   exits 0; V1's 26 tests unaffected (D11 spot-check, same probe P2's own
   gate used).
3. **YES/NO — no stub surfaces remain that this phase owns.**
   `grep -n "NotYetBuilt" contracts/src/ChannelV2.sol` shows the error
   declaration and **exactly one** remaining live throw site
   (`phase2Act`, P4's) — `fileActions`, `postShares`, and
   `_resolveTerminal`'s five rows must show **zero** `NotYetBuilt`
   references; `PendingContinuation` is the only new revert this phase
   leaves standing, and it must appear **only** at `_consolidate`'s
   `TermKind.NONE` route (task 7), nowhere inside `_resolveTerminal`.
4. **YES/NO — total resolution on the fourth row, proven by the actual
   payout, not merely by the absence of a revert (P3-6, fix round 1: "no
   `expectRevert` in the test" is satisfied by a test that asserts
   nothing at all about outcome — a vacuous pass on a badly broken
   fourth row that happens to return without reverting for the wrong
   reason).** `test_F13_6_fourth_row_total` (task 13) must contain, and
   this gate confirms by reading the test body, **all** of: (a) no
   `vm.expectRevert` call anywhere in the test (the no-revert property,
   still checked); (b) an explicit assertion that `credits[host]` and
   `credits[guest]` after `resolve()` equal the **receipt-baseline**
   stacks exactly — no pot overlay at all (decision matches task 11 step
   5's "settle at the receipt baseline"); (c) an explicit assertion that
   `burned[session]` equals `bondHost + bondGuest` (both bonds burned,
   not one); (d) an explicit assertion that `hostBurned && guestBurned`
   are both `true`. A test satisfying only (a) does **not** pass this
   gate — the completion notes must show (b)-(d) as named assertions in
   the test source, not merely described in prose.
5. **YES/NO — D12 report and gas snapshots exist.** Task 13's completion
   notes contain both, per that task's own verification probe.
6. **YES/NO — P4's surface is exactly what this phase promises (D17,
   same base-ref content-grep form as Part A's gate 5, re-run against
   Part B's own additional diff):**

       git -C /home/dev/projects/vault diff <phase-3-base>..HEAD -- contracts/src/ChannelV2.sol | grep -c '^[-+].*phase2Act'

   YES = `0` for Part B's diff too (P4's stub remains completely
   untouched across both parts of this phase).

---

## Outputs to next phase

**To P4 (disputes-continuation, vault repo):**
- **`BettingReplay.sol`'s interface, unchanged, reused directly — and
  entirely chip-space (decision 3a).** P4's phase-2 actions extend the
  same `Cand[] ordered` array this phase's `_consolidate` builds — a
  phase-2 on-chain action is just another candidate, chain-ordered by
  seq, with `filedAt` no longer meaningfully window-gated (phase 2 has
  its own bank/grace clock, not the phase-1 window). P4's phase doc
  should cite `BettingReplay.replay`'s exact signature (task 5) as its
  own starting point, not re-derive the port — and, per decision 3a,
  P4 inherits the same wei/chip boundary: `BettingReplay` never sees
  wei, so P4's own consolidation-equivalent (if it extends `_consolidate`
  rather than calling it) must perform the same `weiPerChip` conversion
  this phase's task 6 does, using the same `receiptStacksAt[session][0]`
  rate rather than deriving a second one.
- **`_consolidate(bytes32 session)`'s frozen-chain result** is what P4's
  phase-2 machinery starts *from* — the `TermKind.NONE` case this phase
  reverts as `PendingContinuation` is precisely P4's entry point: take
  the same `lastAcceptedSeq`/`finalState`/`toActIsHost` this phase's
  replay engine already computed, and extend it with on-chain phase-2
  actions via `phase2Act` (still `NotYetBuilt()`, entirely P4's to fill —
  this phase never touched its body).
- **The `dueAt`/birth-anchor pattern (task 11 step 1)** generalizes
  directly to phase-2's own street-transition graces (spec §5.3: "a
  posting that becomes due during phase 2 … is a duty with a six-hour
  grace from the moment it becomes due") — P4 should reuse the same
  `birth + grace` shape, not invent a second deadline formula.
- **`postedShare`/`sharePosted`/`postShares` are P4's to keep calling
  unchanged** — phase-2 showdown shares are posted exactly the same way
  as phase-1 ones (the triple check has no phase-awareness at all,
  decision 5), just without the in-window equivocation-style gating that
  only ever applied to actions, never to shares (task 4 step 4).
- **`_burnBond`, `credits`, `paidOut`, `burned`** — unchanged storage
  surface, same as P2 handed this phase; P4's bank-fold and missed-grace
  burns are new *callers*, not new primitives.
- **What remains stubbed, precisely:** `phase2Act` (P2's stub,
  untouched by this phase) is the **only** surface left for P4. Every
  other formats §9 entry point (`fileReceipt`, `fileMarker`,
  `fileMarkerWithReceipt`, `fileActions`, `postShares`, `resolve`) is
  fully implemented as of this phase's Part B gate — P4 extends
  `resolve()`'s behavior only insofar as a `PendingContinuation`-routed
  hand now has somewhere real to go (phase2Act's body), not by touching
  any of this phase's own five resolution rows.

**Contract address / ABI:** none — deployment stays P7-only (D11/D13); P4
builds against `contracts/out/` after this phase's own `forge build`
succeeds, same as P2 handed P3.

**Vectors, per D18:** `contracts/test/vectors/{p1-vectors.json,Vectors.sol}`
is P2's landed copy, gated by P2's own `sha256sum -c` and re-verified by
this phase's task 2 (also `sha256sum -c`, also hard-fail). P4 consumes the
same landed copy directly — it does not need a third re-verification of
its own, since P2's and this phase's gates already establish the copy is
trustworthy by the time P4 runs.

## Open questions

1. **Whether `_crystallizeMaturedDuties` (task 12) should also run inside
   `openDispute` or `fileActions`/`postShares` themselves, rather than only
   at `resolve()`'s `finalEligible` entry.** Default: only at `resolve()`
   (task 12's own reasoning — cheapest correct placement, since nothing
   reads `hostBurned`/`guestBurned` except payout computation, and payout
   only ever happens inside `resolve()`). **Overrules:** whoever drafts
   P4 or the arc-end reviewer, if a scenario surfaces where an off-chain
   observer (P5's UI, say) needs to see a matured-but-uncrystallized burn
   reflected in `hostBurned` *before* anyone calls `resolve()` — in that
   case the crystallization call should move earlier (e.g. into
   `postShares`/`fileActions` themselves, run once per call, idempotent
   either way) rather than staying resolve()-only.
2. **The 52-card point table's storage form** (task 1 step 4: hardcoded
   `bytes32[52]` constants vs. computed once via `Ristretto.mul` and
   cached in a mapping the first time `decode` runs). Default: hardcoded
   constants (cheapest per-call gas, since this is dispute-path code
   where every gas unit is already measured against a ~3M-gas DLEQ
   baseline and a 52-entry linear scan of stored constants is
   negligible by comparison). **Overrules:** the operator, only if
   Solidity's constant-array size limits or the differential-check
   script (task 1) surfaces a transcription-error risk large enough to
   prefer computing-and-caching instead — a real but currently
   unevidenced risk, flagged rather than dismissed.
3. **Whether Part A and Part B should ship as two separate dispatched
   phases in `arc-run`, or one continuous dispatch.** Default: two
   dispatches, gated independently (this doc's own split ruling's whole
   point — a real checkpoint between them). **Overrules:** the operator
   running `arc-run`, who may reasonably choose to dispatch both back to
   back in one session if Part A's gate passes cleanly and there is no
   reason to pause; the two-gate structure exists to make that choice
   *informed*, not to force a stop.

## Recovery

If this phase is interrupted mid-task: **the real dependency chain in Part
A is 1 → 3 → 5 → 6 → 7** (task 1's libraries before task 3's storage before
task 5's engine before task 6's wrapper before task 7's wiring) — not "every
task depends on every earlier one." Task 2 (vector sha256sum verification)
is independent of the rest and can run, or be skipped and revisited, in any
order. Task 4 (`postShares`) depends only on task 1 (`Evidence.sol`'s leaf
builders and Merkle verify), not on tasks 3/5/6/7 at all — a resumed
session missing task 4 does not block tasks 5–7, and vice versa. A resumed
session should `~/.foundry/bin/forge build --root
/home/dev/projects/vault/contracts` first, then `grep -n "function \|error
\|struct \|library " contracts/src/ChannelV2.sol contracts/src/Evidence.sol
contracts/src/BettingReplay.sol` against this doc's task list to find the
first missing surface. Task 8 is additive to the test files only and can
restart from a clean `forge test` run regardless of where it stopped.

**Part B tasks 9–12 similarly build in order** (task 9's decode before
task 10/11's rows before task 12's cross-branch crystallization, which
cites task 11's `dueAt`) — same recovery pattern.

**If `_resolveTerminal` is found with a body that is neither the task-7
stub (`revert NotYetBuilt();`) nor a complete implementation of all five
rows (tasks 10–11), stop and ask** — a partially-filled resolution table
is the one state in this phase most likely to look like it works (three
rows correct, two still reverting) while silently failing exactly the
adversarial fixtures (task 13) that exist to catch it; do not assume a
partial implementation is "close enough" to keep building on top of, since
task 12's crystallization helper (Part B's last piece before tests)
duplicates task 11's burn logic and will duplicate it *wrong* if task 11
itself is incomplete.

**If `contracts/src/Channel.sol`, `contracts/test/Channel.t.sol`, or
`contracts/script/Deploy.s.sol` show *any* diff** (`git status --short --
contracts/src/Channel.sol contracts/test/Channel.t.sol
contracts/script/Deploy.s.sol`), stop and ask — same D11/D13 boundary P2's
doc names, unchanged by this phase.
