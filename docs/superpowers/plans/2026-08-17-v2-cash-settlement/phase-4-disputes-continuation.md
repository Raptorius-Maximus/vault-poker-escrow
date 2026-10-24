# Phase 4 — disputes-continuation (vault repo, Solidity)

## Goal

Fill P3's `PendingContinuation` seam: the phase-2 play §5.3 promises when
the frozen chain (P3's `_consolidate`) shows a pending decision instead of
a terminal one. Ship `phase2Act` — the turn-player's on-chain extension of
the action chain, validated by P3's `BettingReplay` unchanged — plus the
cumulative six-hour decision bank metered by block timestamps, phase-2-born
posting duties (birth = the on-chain event that made a position required,
6h grace, only counterparty-side postings pause a clock), and termination
(fold — signed, open, or by bank — or a completed runout) routed into P3's
existing five-row resolution table with no changes to that table's code.
At the phase boundary: a hand that was `PendingContinuation` at P3's
boundary now resolves fully through `resolve()` — bank-decided folds pay
the non-folder and return the folder's bond (folding is never misconduct);
a completed continuation reaches P3's cards-decide/muck/symmetric-muck/
fourth rows exactly as if the same evidence had arrived inside phase 1;
every phase-2-born posting duty is priced identically to a phase-1 one
(same bond, same `_burnBond`). The dispute's end is termination plus the
maturity of every born grace (§5.4), not consolidation.

## Split-feasibility ruling

**This phase does not split.** P3's two-part structure existed because Part
A (evidence, replay, consolidation) and Part B (new crypto graduation,
five terminal rows) were genuinely separable — Part B needed
Merkle/DLEQ/evaluator surface Part A never touched, and each part's own
gate was independently provable without the other's machinery. P4 has no
such axis: it adds **zero new crypto surface** (postShares' triple check,
`decodeAt`, `Evaluator7`, `_resolveTerminal`'s five rows are all P3's,
called unchanged) and **zero new resolution rows** (a bank-fold reuses
P3's fold row exactly; a phase-2 showdown reuses cards-decide/muck exactly).
Every task below is one coherent engine extension — turn validation, a
clock, and a birth-timestamp cache — that only becomes meaningful once
`phase2Act` itself exists, so a split would produce the same "every task
still depends on task 1" collapse P2's task 1 (correctly) declined to
split for. Nine tasks, one gate.

## Inputs from previous phase

**From P3 (`phase-3-disputes-evidence.md`'s own Outputs to next phase
section, mirrored verbatim, not re-worded):**

> - **`BettingReplay.sol`'s interface, unchanged, reused directly.** P4's
>   phase-2 actions extend the same `Cand[] ordered` array this phase's
>   `_consolidate` builds — a phase-2 on-chain action is just another
>   candidate, chain-ordered by seq, with `filedAt` no longer meaningfully
>   window-gated (phase 2 has its own bank/grace clock, not the phase-1
>   window). P4's phase doc should cite `BettingReplay.replay`'s exact
>   signature (task 5) as its own starting point, not re-derive the port.
> - **`_consolidate(bytes32 session)`'s frozen-chain result** is what P4's
>   phase-2 machinery starts *from* — the `TermKind.NONE` case this phase
>   reverts as `PendingContinuation` is precisely P4's entry point: take
>   the same `lastAcceptedSeq`/`finalState`/`toActIsHost` this phase's
>   replay engine already computed, and extend it with on-chain phase-2
>   actions via `phase2Act` (still `NotYetBuilt()`, entirely P4's to fill —
>   this phase never touched its body).
> - **The `dueAt`/birth-anchor pattern (task 11 step 1)** generalizes
>   directly to phase-2's own street-transition graces (spec §5.3: "a
>   posting that becomes due during phase 2 … is a duty with a six-hour
>   grace from the moment it becomes due") — P4 should reuse the same
>   `birth + grace` shape, not invent a second deadline formula.
> - **`postedShare`/`sharePosted`/`postShares` are P4's to keep calling
>   unchanged** — phase-2 showdown shares are posted exactly the same way
>   as phase-1 ones (the triple check has no phase-awareness at all,
>   decision 5), just without the in-window equivocation-style gating that
>   only ever applied to actions, never to shares (task 4 step 4).
> - **`_burnBond`, `credits`, `paidOut`, `burned`** — unchanged storage
>   surface, same as P2 handed this phase; P4's bank-fold and missed-grace
>   burns are new *callers*, not new primitives.
> - **What remains stubbed, precisely:** `phase2Act` (P2's stub,
>   untouched by this phase) is the **only** surface left for P4. Every
>   other formats §9 entry point (`fileReceipt`, `fileMarker`,
>   `fileMarkerWithReceipt`, `fileActions`, `postShares`, `resolve`) is
>   fully implemented as of this phase's Part B gate — P4 extends
>   `resolve()`'s behavior only insofar as a `PendingContinuation`-routed
>   hand now has somewhere real to go (phase2Act's body), not by touching
>   any of this phase's own five resolution rows.

*(Every "task N" inside the quoted block above is P3's own numbering,
naming P3's tasks — left untouched per "mirrored verbatim." Every other
"task N" in this document, from here on, is this phase's own numbering.)*

Concretely, this phase inherits from P3's shipped `contracts/src/ChannelV2.sol`
(and, unmodified, `contracts/src/BettingReplay.sol` and
`contracts/src/Evidence.sol`): `_consolidate(bytes32 session)` (returns
`BettingReplay.TermKind`, `folder`, `finalState`, `lastAcceptedSeq`,
`completingFiledAt`); `_resolveTerminal(bytes32 session,
BettingReplay.TermKind kind, address folder, BettingReplay.State memory
finalState, uint256 completingFiledAt) internal returns (bool)` (P3 task 7
step 2's declared signature, filled by P3 tasks 10–11 with the five §5.3
rows); `error PendingContinuation();` (thrown today only at
`_consolidate`'s `TermKind.NONE` route, P3 task 7); `ActCandidate` struct
(P3 task 3 step 2: `signer, action, amount, prev, actionHash, filedAt,
exists`); `actionsAt` (the phase-1 candidate storage this phase's frozen
prefix reads, unchanged); `postedShare`/`sharePosted` (P3 task 4);
`decodeAt` — **in `ChannelV2.sol`, not `Evidence.sol`** (P3 task 9 step 2's
own wording: "`Evidence.sol` stays storage-free," so the wrapper that
reads `postedShare`/`sharePosted` storage lives beside them in
`ChannelV2.sol`; fix-round-1 M6 caught this doc's earlier
mis-attribution) — the `Act` struct
(P2 task 5 step 4, phase2Act's still-`NotYetBuilt()` stub); `window`,
`bank`, `grace` (P2 task 1 step 4's constructor `immutable`s — `bank` is
this phase's own duration, unused by P2 or P3); `disputeOpenedAt`,
`markedHand`, `receiptStacksAt` (P3 task 3 step 1), `sessionKeyHost`/
`sessionKeyGuest`, `_recoverRaw`, `_binding`, `_burnBond`, `credits`,
`paidOut`, `burned`, `hostBurned`/`guestBurned`.

**P3 is a plan, not shipped code, at this doc's drafting time** (AF-6
finding 1's lesson, the same framing P3's own doc used for P2): README.md's
Status section records P3 as "in-flight… (draft committed)," its checker
verdict REVISE (AF-6, three MAJOR, no BLOCKER, in revision) — so
`contracts/src/ChannelV2.sol`, `BettingReplay.sol`, and `Evidence.sol` do
not exist on disk as this doc is written. The Inputs above are therefore
built from `phase-3-disputes-evidence.md` (P3's *drafted* phase doc,
post-AF-6-ruling text) exactly as P3's own Inputs section was built from
`phase-2-money-frame.md` rather than a not-yet-existent `ChannelV2.sol` —
and task 1 step 0 below is this phase's own dispatch-time
re-verification, run against whatever P3 *actually* shipped (which may
differ from this drafted text at the margin — AF-6's revision is still
in flight) before any other step in this phase proceeds.

**Live source read for this doc, 2026-08-17:** `contracts/foundry.toml`
(`src = "src"`, `out = "out"`, `libs = ["lib"]`, unchanged since P2/P3's
reads); `find /home/dev/projects/vault/contracts -iname "ChannelV2*"`
returns nothing (confirms the plan-not-shipped-code framing above, not
assumed); `~/.foundry/bin/forge --version` confirms `1.7.1` installed,
same toolchain P2/P3 used; `/home/dev/projects/poker/src/core/betting.ts`
read in full (223 lines — reproduced verbatim below where this phase's
own logic depends on a specific line, rather than re-citing P3's already-
verified citations secondhand); `/home/dev/projects/poker/src/core/protocol.ts:52-58`
re-confirmed directly (`POS = { hostHole: [0,1], guestHole: [2,3], flop:
[5,6,7], turn: [9], river: [11] }`) — this phase's own street-runout task
(task 6) depends on the exact same constant P3 task 10 step 2 already
cited, re-read here rather than trusted secondhand per this arc's citation
discipline. `docs/superpowers/parking/v2-cash-game-settlement.md`'s
thirteenth cold check (finding 1, the "one schedule, three readings"
withheld-bet schedule, lines 2355–2369) and fourteenth cold check
(finding 1, the 23:59-completing-call schedule, lines 2566–2581) read in
full — these are this phase's own readyTime task's adversarial test
vectors (task 3), not re-derived from memory.

## Files touched

**Created:** none. This phase adds no new `.sol` files — `BettingReplay.sol`
and `Evidence.sol` are imported and called exactly as P3 shipped them
(library functions, no modification); the small amount of new logic this
phase needs (the combined-array wrapper, the bank clock, birth-timestamp
tracking) lives inside `ChannelV2.sol` as new internal functions and
storage, the same place P3 put `_consolidate` rather than a separate file.

**Modified:**
- `contracts/src/ChannelV2.sol` — `phase2Act`'s body (replacing
  `NotYetBuilt()`, task 4); new storage: `phase2ActionsAt`, `birthAt`,
  `showdownBirthAt`, `postedAt` (task 1), plus the `_frozenPrefix` and
  `_requiredBoardPositions` helpers (task 1); `resolve()`'s throw site
  for `_consolidate`'s `TermKind.NONE` route — **replaces** P3 task 7's
  `revert PendingContinuation();` with a call into this phase's
  `_consolidatePhase2` (task 5, wired in task 7) — `PendingContinuation`
  itself is **not** deleted as an error declaration (P3's `resolve()`
  doc-comment and any off-chain tooling may still reference the selector;
  only its one throw site moves) but the phase-1-only meaning it had is
  retired in favor of this phase's own `error Phase2InProgress();`
  (declared task 1, thrown task 7) for the "still live, nobody's bank is
  empty yet" case; a **disclosed extension** to `postShares` (task 2,
  additive to a P3-owned function, no signature change) caching each
  passing post's timestamp; `_crystallizeMaturedDuties` gains a
  phase-2-aware branch (task 7).
- `contracts/test/ChannelV2.t.sol` — extended with tasks 3, 8–9's
  fixtures.

**Deleted:** none.

## Design decisions pinned here (binding on every task below)

**1. `_consolidatePhase2` reuses `BettingReplay.replay` by concatenation,
not by re-deriving its loop.** P3's Outputs is explicit that "a phase-2
on-chain action is just another candidate" in the same `Cand[]` shape
`_consolidate` already builds. This phase's own consolidation helper
builds **one** array — P3's frozen in-window prefix (task 6 step 2's
exact filter: `actionsAt` entries with `filedAt < disputeOpenedAt +
window`, walked from `seq = 0`) followed by this phase's own
`phase2ActionsAt[session][hand]` (append-only, ordered by `seq`,
populated only by successful `phase2Act` calls — no equivocation slot
pair is needed here, unlike P3's dual-candidate `actionsAt`, because every
phase-2 candidate is itself a single on-chain transaction: there is no
race to resolve, the chain's own transaction ordering already is the
total order) — then calls `BettingReplay.replay(...)` **once** on the
combined array. `BettingReplay.sol` is not modified, not extended, not
wrapped in a second copy of its loop; this phase calls the exact function
P3 shipped. The frozen-prefix-building loop itself (walking `actionsAt`,
filtering by the window) is a five-line pattern P3 task 6 step 2 already
fully specifies; this phase re-runs that **same filter**, as its own
`_frozenPrefix` helper (task 1 step 6), rather than requesting a
disclosed extension to `_consolidate`'s return signature — a smaller,
lower-risk change than altering a function P3's own gate already tested,
for a loop this short.

**2. Two kinds of "still pending," two different errors, on purpose.**
P3's `PendingContinuation` meant exactly one thing: "phase 1's frozen
chain alone does not terminate; only phase-2 machinery — which does not
exist yet in P3's scope — can finish it." That machinery now exists. When
`_consolidate` returns `TermKind.NONE`, this phase's `resolve()` branch
(task 7) no longer reverts at all — it proceeds into `_consolidatePhase2`.
That inner call can itself still find the hand undecided (the current
to-act player's bank has not emptied and they have not yet filed), and
**that** is a genuinely different fact — evidence exists, phase 2 is
running, nobody has done anything wrong, just come back later — so it
gets its own error, `error Phase2InProgress();`, declared in task 1
alongside this phase's other new storage and thrown from task 7's
`resolve()` wiring, rather than reusing `PendingContinuation`'s name for
a state P3 never described. `PendingContinuation` stays declared (P3's
`_consolidate`-only callers, if any exist by the time this phase ships,
still see the same selector for the same fact); this phase never throws
it.

**3. Bank-fold is derived, not stored, at query time — mirrors P3's own
consolidation laziness.** P3 decision 4 made `_consolidate` a `view`
computation "invoked... every time it is invoked, from whichever
transaction happens to need it first," with no "has this run yet" flag.
This phase's bank-exhaustion check is the same shape: nothing is written
to storage when a bank empties. A bank-fold is discovered — not
recorded — the first time anything calls `resolve()` (or, off-chain, a
`view` read of `_consolidatePhase2`) at or after the exhaustion instant.
This is sound because bank exhaustion, once true, stays true forever
(banks only deplete — `_bankSpent`, itself a `view` re-derivation over
`phase2ActionsAt`'s own stored `filedAt`s, task 3, never decreases as a
function of a later query time), so **any** query at or after the
exhaustion instant agrees on the fold and the instant it happened. No
"first caller wins a race" exists — every caller computes the same
answer from the same immutable stored facts.

**4. `phase2Act` reverts on illegality; `fileActions` does not — this is
a deliberate divergence from P3's own pattern, stated because a checker
will otherwise flag it as an inconsistency.** P3 task 3 step 4 skips a bad
`fileActions` entry silently rather than reverting the whole batch,
because `fileActions` is "any segment, any order" (formats §9) — a
best-effort evidence drop where one garbage entry should not sink
everyone else's filing in the same call. `phase2Act` takes exactly one
action from exactly one caller in exactly one transaction; formats §9's
own comment on it — `phase2Act(...) // reverts out-of-turn/illegal/
mis-amounted (spec §5.3)` — already settles this: a live decision that
fails validation must revert cleanly (the caller's wallet shows a failed
transaction, not a silently-ignored one, matching D14's spirit even
though this specific check is not one of the four named load-bearing
client rules), not vanish into storage nobody reads.

**5. Open-fold bypasses `BettingReplay`'s own legality gate; every other
action does not.** Spec §5.3: "On chain, fold is legal at any to-act node
— in either phase," but `betting.ts`'s `legalActions` (`betting.ts:99-109`,
confirmed by direct re-read for this doc) only offers `fold` when
`toCall(st, seat) > 0` (line 102: `need > 0 ? ['fold', 'call'] :
['check']`) — an open-fold (folding when facing a check option) is never
in that list. P3's `BettingReplay.applyAction` is a faithful port of
`applyAction` including this exact gate (P3 decision 3, task 5 step 4:
"an action that fails its legality check... returns `ok = false`"), and
P3's own Files-touched section is explicit that `BettingReplay.sol` is
reused **unchanged** by this phase — so this phase cannot ask
`BettingReplay.applyAction` to accept an open-fold; the library's
legality gate has no phase-awareness and none is being added to it. This
phase's `phase2Act` (task 4) therefore branches **before** calling into
`BettingReplay`: if `a.action == FOLD`, apply it directly (`closed =
true`, `foldedIsHost = actorIsHost` on the in-memory `State` — the same
two fields `BettingReplay.applyAction`'s own fold branch sets,
`betting.ts:139-142`'s Solidity port per P3 task 5 step 4) without
consulting `legalActions` at all; every other action (`check`/`call`/
`bet`) still goes through `BettingReplay.applyAction` exactly as P3 built
it, unmodified. The turn check (is this signer actually to-act at this
seq) and the chain-linking check (`a.prev` equals the actionHash of the
prevailing tip) apply to an open-fold exactly as they do to any other
action — only the *action-menu* gate is bypassed, never the *whose-turn*
gate. A concession only ever hurts its signer (spec §5.3), so bypassing
the menu costs nothing.

**6. Birth is tracked per required-position class, not once globally —
and this phase's own consolidation reduces it back to a single number P3's
existing `dueAt` formula already knows how to consume.** P3 task 11 step 1
built one global `completingFiledAt` because Part A's frozen chain is
always known **instantly**, in full, the moment it is read — every
required position becomes knowable in the same view call, so anchoring
every duty's birth to the single latest fact (the chain's own completion
instant) is sound and, if anything, generous (a true, earlier per-position
birth would only ever produce an *earlier*, stricter deadline; using the
later single number can only ever be more forgiving, never less). Phase 2
breaks that: a live continuation can close the flop at hour 30 and not
reach a river decision until hour 50 — genuinely different birth instants
for genuinely different duty classes, which is exactly what §5.2/§5.3 mean
by "a street closing → next board card shares" as a *separate* event from
"a call completing betting → showdown shares." This phase therefore
tracks four birth instants per marked hand — `birthAt[Flop]`,
`birthAt[Turn]`, `birthAt[River]` (each stamped the instant
`closeAndAdvance`'s ported cascade, P3 task 5 step 5, transitions **into**
that street — an all-in runout cascade stamps several of these with the
*same* `filedAt`, since they really were born simultaneously by one
action) and `showdownBirthAt` (stamped the instant `TermKind.COMPLETE` is
reached, mirroring P3's `completingFiledAt` exactly, just now possibly a
live phase-2 timestamp instead of a frozen-evidence one). At resolution
time, this phase computes **one** number —
`effectiveCompletingFiledAt = showdownBirthAt`, maxed with `birthAt[c]`
for every board class `c` this phase's own `_requiredBoardPositions`
(decision 8) would include for the hand's final street — and passes
*that* to `_resolveTerminal(session, kind, folder, finalState,
effectiveCompletingFiledAt)` exactly where P3 task 7 step 2 already
declared a `completingFiledAt` parameter. **This deliberately reuses
decision 8's own board-street thresholds (Flop/Turn/River), not P3's
terminal-completeness set** — the two happen to share the same three
street cutoffs by construction, since both ask "which board streets has
this hand reached," but this phase's own helper is cited here, not P3's,
to keep the two sets (this phase's board-only gate vs. P3's
holes-always-included set) from being silently conflated by a future
edit. Because P3 task 11 step 1's `dueAt = max(hour 24, completingFiledAt
+ grace)` adds the same constant `grace` to whatever it is given,
`max(birth_1, …, birth_k) + grace == max(birth_1 + grace, …, birth_k +
grace)` — feeding the max-of-births through the existing single-argument
formula is *exactly* the max of each class's own deadline, with zero
modification to P3 tasks 10–11's shipped code. **Resolved per fix-round-1
B2, not a contingency:** P3 ships `dueAt(session, completingFiledAt)` as
an explicit two-argument function (the caller supplies the birth; `dueAt`
never re-reads `_consolidate` internally to derive its own), and
`_resolveTerminal` already took `completingFiledAt` as an explicit
parameter per its own task 7 step 2 signature — both facts this phase's
substitution above depends on. Task 1 step 0's dispatch-time
re-verification still confirms both signatures landed exactly as P3
committed (a real revision can under-ship what it promised even after a
ruling settles the design), but this doc no longer carries a fallback
branch for `dueAt` re-deriving its own birth internally — B2 retired that
possibility at the ruling level, not just for this phase's own text.

**7. The bank clock and duty postings are two entirely independent
systems that happen to share a birth-and-grace vocabulary.** §5.2 states
it directly: "every mechanical posting is a duty, never a bank item."
`postShares` is never gated by the bank, and `phase2Act`'s bank
bookkeeping never reads `sharePosted` except as the "counterparty-side
posting on file" input to *pausing* the clock (decision 8) — a posting
duty's own deadline (decision 6) and a to-act decision's bank cost
(decision 8) are computed from different birth events (a street closing
vs. a player becoming to-act) and never share a formula. Keeping them
visibly separate — separate storage, separate helper functions, cited
separately in every task below — is what makes "acting blind is always
legal" (task 4) and "posting duties are never a bank item" (task 8's
`test_F12_4_postings_are_window_duties`) two independently true,
independently testable facts rather than one conflated mechanism a
checker has to untangle.

**8. Sole-obstacle readyTime — the pure function, stated once, and named
so it cannot be confused with P3's own position set.** For a phase-2
to-act node, let `baseline` be `H0 = disputeOpenedAt[session] + window`
if no phase-2 action has yet been filed for this hand (the fixed,
known-in-advance hour-24 appointment — F13.1's own lesson: a phase-1
tip's own filing time is irrelevant to phase 2's clock, only the
appointment is), or the `filedAt` of the most recently accepted phase-2
candidate otherwise (an on-chain transaction genuinely hands the turn to
the other seat the instant it lands, the same immediate-alternation model
`betting.ts` already uses off-chain).

`_requiredBoardPositions(street) internal pure returns (uint8[] memory)`
(task 1 step 7) is this phase's **own** helper, and it is a **different
set from three other things this document discusses**, all of which sound
like "the positions this street needs": it is `POS.flop` if `street >=
Flop`, `POS.turn` if `street >= Turn`, `POS.river` if `street == River`
(`protocol.ts:52-58`) — **board positions only**. It is *not* P3 task 10
step 2's terminal-completeness set (which additionally, always, requires
`POS.hostHole`/`POS.guestHole` — a fact this phase's own task 6 cites
directly from P3, never through this helper). It is *not* decision 6's
four birth-timestamp classes (which track *instants*, not a position
list, though they share the same three street thresholds — decision 6
says so explicitly, to make the overlap visible rather than coincidental).
**Hole positions are deliberately excluded from `_requiredBoardPositions`,
and this is load-bearing, not an oversight or a simplification:** a
to-act player's own decision (fold/check/call/bet) never depends on
either hand's hole cards — hole shares are never posted before showdown
by design (§5.2: "a hole-share duty is born only by the filing of a
betting-completing action"). If the clock gate required hole postings
before it could start, it could **never start** for any pre-showdown
decision — a structural deadlock, not merely an overly conservative rule.
No implementer should "simplify" by reusing P3's terminal-completeness
set here; doing so would silently deadlock the bank clock for every hand
that reaches a decision before showdown, which is every hand this phase
exists to handle.

The clock has **not started** — no bank can ever be charged, no fold can
ever trigger — while any position in `_requiredBoardPositions(finalState.street)`
lacks its **counterparty**-side posting (the to-act player's own
contribution to those same positions is irrelevant to their own clock,
decision 7/thirteenth check finding 2 — F13.2). Once every required
counterparty posting is on file:

    readyTime = max(baseline, max over p in _requiredBoardPositions(street) of postedAt[key][p][counterparty])

`postedAt` is this phase's own disclosed extension to `postShares` (task
2). This is a **pure function of on-chain facts already committed** —
`disputeOpenedAt`, `window`, prior `phase2ActionsAt.filedAt`s, and
`postedAt` timestamps — computable identically by any caller at any later
time, with no retroactive interval anywhere (the thirteenth check's own
lesson, restated: phase-2 filings are totally ordered on-chain events
against a frozen chain, so this is computable, unlike a bank interval
reasoned over off-chain wire timestamps).

**9. Bank spend and the exhaustion boundary.** `_bankSpent(session,
isHost)` sums, over every phase-2 candidate that player actually filed,
`filedAt(candidate) - readyTime(candidate's node)` — a `view` re-walk of
`phase2ActionsAt`, not a separately maintained running total (matches
decision 3's laziness: nothing is written besides the candidates
themselves). At the *current*, not-yet-filed node, remaining bank as of
`now` is `bank - _bankSpent(session, isHost) - (now - readyTime)`, only
meaningful once `readyTime` is defined (decision 8) — while it is
undefined (a required posting is still missing), remaining bank is simply
`bank - _bankSpent(...)`, untouched by elapsed real time, and no fold can
trigger. **Boundary convention, chosen to match every other boundary this
arc already pinned rather than invent an asymmetric new one**
(fourteenth check finding 5b, formats-level "a filing and a deadline in
the same block counts as met"): the player is bank-folded once elapsed
**strictly exceeds** remaining bank at node start, i.e. a `phase2Act` call
landing in the exact block where spend would equal the bank exactly is
still accepted — the same "boundary favors the actor" convention used for
the window close and every duty deadline in this arc, not a new,
stricter rule invented for banks alone.

## Tasks

**Task-ordering note (build-order fix, checker-caught defect).** This
phase's own checker caught the exact AF-4 shape P2's build-order fix
already named: an earlier draft had `phase2Act` (the chain-extension and
bank-check entry point) declared as task 3, calling `_frozenPrefix`
(drafted as a step *inside* what was then task 5) and `_readyTime`/
`_bankSpent` (drafted as task 4) — both undeclared at that draft's own
`phase2Act` `forge build` checkpoint, so that checkpoint could not have
passed as drafted. Fixed two ways, chosen for the reason each helper
actually needed: `_frozenPrefix` has no design question of its own (P3
task 6 step 2's filter, moved verbatim) and no reason to wait for
anything phase-2-specific, so it is **pre-declared in task 1** alongside
this phase's other new storage — the same shape P2 used for `_burnBond`
(task 1 there, task 5 there consumes it). `_requiredBoardPositions`
(decision 8's own helper, needed by both the readyTime task and
`phase2Act`) is pre-declared there too, for the identical reason.
`_readyTime`/`_bankSpent`, by contrast, are a real, independently
adversarial-tested unit of work (decision 8's own subtlety) that
`phase2Act` genuinely depends on — so that task is **resequenced ahead of
`phase2Act`** rather than stub-declared: what was drafted as task 4
(readyTime/bank spend) is now **task 3**, and what was drafted as task 3
(`phase2Act`) is now **task 4**. Task numbering below now equals
dependency order for every task through 5: 1 → 2 → 3 → 4 → 5, with task 6
additionally depending on 4 and 5, task 7 on 5, and tasks 8–9 on
everything through 7 — see Recovery for the full graph, stated once there
rather than re-derived per task.

**Base-ref pin (D17, fix-round-1 B5).** Every isolation/no-touch gate in
this phase's Phase-boundary verification section (gates 3 and, by
citation, the Recovery section's own `git status` checks) diffs against
`<P4-BASE-SHA>` — the commit hash of `/home/dev/projects/vault` immediately
before this phase's task 1 begins. Whoever dispatches task 1 records the
real hash (`git -C /home/dev/projects/vault rev-parse HEAD`, run once,
before any of this phase's own commits land) in this note's own token,
replacing `<P4-BASE-SHA>` in this doc, exactly as D17 requires ("the
phase-base SHA recorded in the phase doc's own task-ordering note at
dispatch"). Every gate below cites the token rather than re-deriving or
re-recording it, so there is exactly one place this phase's base commit
is written down.

---

### Task 1 — Storage: dispatch-time re-verification, phase-2 candidate array, shared helpers

**Goal:** confirm P3's shipped contract matches this doc's Inputs section,
then add the storage and the two shared, no-judgment-call helpers
(`_frozenPrefix`, `_requiredBoardPositions`) this phase's later tasks
depend on — no bank/turn/chain logic yet.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
0. **Re-verify P3's shipped contract before building on it** (mirrors P3
   task 1 step 0's own pattern, one level deeper). `git -C
   /home/dev/projects/vault log --oneline -1 -- contracts/src/ChannelV2.sol
   contracts/src/BettingReplay.sol contracts/src/Evidence.sol` and a fresh
   `~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts`
   confirm P3 actually shipped (its AF-6 revision, not this doc's read of
   the drafted plan); then read the real `ChannelV2.sol`,
   `BettingReplay.sol`, and `Evidence.sol` to confirm every symbol this
   doc cites by name in Inputs above — `_consolidate`, `_resolveTerminal`
   (and specifically whether it takes `completingFiledAt` as an explicit
   parameter, decision 6's contingency), `PendingContinuation`,
   `ActCandidate`, `actionsAt`, `postedShare`/`sharePosted`, `Act`, the
   duration `immutable`s, `_burnBond` — matches what this doc assumed. A
   mismatch is a stop-and-reconcile finding, not something to paper over
   in a later task, exactly as P3 task 1 step 0 requires of itself.
1. `struct Phase2Cand { address signer; uint8 action; uint256 amount;
   bytes32 prev; bytes32 actionHash; uint40 filedAt; }` — deliberately
   *not* reusing P3's `ActCandidate` type verbatim even though the fields
   match, because P3's struct carries an `exists` flag whose only purpose
   is P3's dual-candidate-per-slot equivocation model (decision 1: "no
   equivocation-shaped misconduct category" applies here — every
   phase-2 candidate is a successfully-validated on-chain transaction,
   never a stored-but-possibly-wrong guess); a same-shaped-but-distinct
   type keeps that difference visible in the code rather than borrowing a
   flag this phase never needs. **The same reasoning underlies AF-6's
   orchestrator ruling on P3's own same-block tiebreak
   (`review-findings.md`, AF-6): EVM transaction execution is strictly
   sequential, so there is no genuine simultaneity for a total order to
   need a tiebreak over.** P3 needed that ruling because `fileActions`
   accepts *evidence about the past* (a filing can claim any `seq` at any
   time, so two candidates can genuinely collide in storage). `phase2Act`
   accepts *the present move itself* — there is no second candidate to
   collide with, because the turn/chain-link check (task 4 step 4)
   rejects anything but the single next legal action before it is ever
   stored. No tiebreak logic exists anywhere in this phase, for a
   stronger reason than AF-6's: not "ties resolve deterministically" but
   "ties cannot arise." (Task 8 step 8 adds a direct behavioral fixture
   for this claim, not just this citation.)
2. `mapping(bytes32 => mapping(uint64 => Phase2Cand[])) phase2ActionsAt;`
   — keyed `session => hand => ordered array`, append-only, written only
   by a successful `phase2Act` (task 4).
3. `mapping(bytes32 => mapping(uint64 => uint256[4])) birthAt;` — keyed
   `session => hand => [Flop, Turn, River, reserved]` (index 0 unused,
   `Street` enum's `Preflop` has no birth event; index 3 free for the
   `showdownBirthAt` companion field below, or a separate mapping —
   implementer's choice, state which was picked in completion notes since
   task 6 reads it back) plus `mapping(bytes32 => mapping(uint64 =>
   uint256)) showdownBirthAt;` for the betting-complete instant
   (decision 6).
4. `mapping(bytes32 => mapping(uint64 => mapping(uint8 => mapping(address
   => uint256)))) postedAt;` — keyed `session => hand => pos => player =>
   timestamp`, the disclosed extension task 2 writes to.
5. `error Phase2InProgress();` at contract scope (decision 2) — declared
   here, **thrown by task 7** (not this task — this task only declares
   it, matching the "declare where later tasks can already build against
   it" pattern task 7 step 1 relies on).
6. `_frozenPrefix(bytes32 session, uint64 hand) internal view returns
   (BettingReplay.Cand[] memory)`: P3 task 6 step 2's own filter, moved
   here rather than left inside a later task's body (this task-ordering
   note, above) — walk `seq = 0, 1, …` reading `actionsAt[keccak256
   (session, hand, seq)]`'s candidates, filtered by `filedAt <
   disputeOpenedAt[session] + window`, stop at the first `seq` with no
   in-window candidate. Returns the array `BettingReplay.replay` expects
   (same `Cand` type P3 task 5 step 6 declares). Depends only on
   `actionsAt`, `disputeOpenedAt`, and `window` — all pre-existing P2/P3
   storage — so it needs nothing this phase adds beyond this task's own
   steps 0–5.
7. `_requiredBoardPositions(BettingReplay.Street street) internal pure
   returns (uint8[] memory)` (decision 8): `POS.flop` (`[5,6,7]`) if
   `street >= Flop`, additionally `POS.turn` (`[9]`) if `street >= Turn`,
   additionally `POS.river` (`[11]`) if `street == River`
   (`protocol.ts:52-58`) — **never** `POS.hostHole`/`POS.guestHole`.
   Decision 8's own text carries the full reasoning for the hole
   exclusion (deadlock avoidance); this step is the implementation, not a
   restatement.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, no errors mentioning `ChannelV2.sol`.

**Dispatch:** `agent (session-tier, high)` — the re-verification step
governs whether every later task's assumptions hold; a storage layout
error here forces every later task's rework, and steps 6–7 are shared
dependencies every other task calls, so an error here propagates further
than in any other task.

---

### Task 2 — Disclosed extension: `postShares` caches `postedAt`

**Goal:** the one additive change to a P3-owned function this phase makes
— cache each passing post's timestamp, needed by decision 8's `readyTime`.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. In `postShares` (P3 task 4 step 2), at the exact point a post passes
   all three checks and P3's own code sets `sharePosted[key][post.pos]
   [owner] = true`, also set `postedAt[session][hand][post.pos][owner] =
   block.timestamp`. Comment this addition explicitly: `// P4 extension
   (decision 8): timestamp cache for the phase-2 bank clock's
   sole-obstacle computation.`
2. No other change to `postShares` — the triple check, the skip-not-revert
   discipline on a failing post, the `deckC2At` cache: all P3's, untouched.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. `grep -n "postedAt\[" contracts/src/ChannelV2.sol` shows
exactly one write site (inside `postShares`) and this phase's own read
sites (tasks 3/5, not yet written at this task's checkpoint — so a single
write-site match is expected here).

**Dispatch:** `agent (workhorse, medium)` — one line inside an existing,
already-tested function; no new judgment.

---

### Task 3 — ReadyTime and bank spend: dedicated adversarial task

**Goal:** decision 8's `readyTime` and decision 9's `_bankSpent` as
standalone, independently testable `view` functions, proven against the
thirteenth and fourteenth cold checks' own worked schedules — not
deferred to the general fixtures task, per this arc's own instruction
that the readyTime definition earns its own adversarial coverage. Both
functions depend only on task 1's storage/helpers and task 2's
`postedAt` — neither depends on `phase2Act` (task 4) existing, which is
exactly what lets this task run before it.

**Files:** `contracts/src/ChannelV2.sol`, `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. `_readyTime(bytes32 session, uint64 hand, bool forHost, Phase2Cand[]
   memory combined, BettingReplay.State memory finalState) internal view
   returns (bool started, uint256 readyTime)`: `baseline =
   phase2ActionsAt[session][hand].length == 0 ? disputeOpenedAt[session]
   + window : phase2ActionsAt[session][hand][phase2ActionsAt[session]
   [hand].length - 1].filedAt` (decision 8's `H0`-or-last-handoff rule).
   Call `_requiredBoardPositions(finalState.street)` (task 1 step 7 —
   **not** a re-derivation; this task calls the shared helper, it does
   not reimplement the street conditional a second time); for each
   returned position, read `postedAt[session][hand][pos][counterparty]`
   (counterparty = the *other* player from `forHost`); if any is `0`
   (unset), return `(false, 0)` — the clock has not started (decision 8).
   Else return `(true, max(baseline, max of the read timestamps))`.
2. `_bankSpent(bytes32 session, uint64 hand, bool forHost) internal view
   returns (uint256)`: walk `phase2ActionsAt[session][hand]`, summing
   `filedAt(i) - readyTimeAtNode(i)` for every candidate signed by the
   player identified by `forHost` — `readyTimeAtNode(i)` is computed by
   re-invoking step 1's logic against the **prefix ending just before**
   candidate `i` (the state and street as of that node), not the current,
   final state — implementer's choice whether this re-walks
   `BettingReplay` incrementally or calls `replay()` on successive
   prefixes; either is correct, note which was chosen (the array is
   short — bounded by the ~66h/street-count structure, not a
   scalability concern this phase needs to optimize; task 4 step 3 notes
   the identical cost shape for `phase2Act`'s own full-array re-replay).
3. Both functions are `view`, callable with no session in `Disputed`
   status required at the Solidity level (though every real caller only
   ever invokes them from `phase2Act`/`resolve()`, both of which already
   gate on `status == Disputed`) — no new access-control surface, just
   arithmetic over already-stored facts.
4. **Test-only harness, declared once, reused by every probe below**
   (mirrors P2 task 9's `_burnBond` harness pattern — a contract in the
   test file, not `src/`, subclassing `ChannelV2` purely to expose
   `internal` functions to direct calls): `_readyTime` and `_bankSpent`
   are `internal`, and this task's own probes need to call them directly
   (not through `phase2Act`, which does not exist until task 4) —
   `ChannelV2TestHarness` exposes `readyTimeExternal(...)` and
   `bankSpentExternal(...)` thin wrappers, plus a `pushPhase2Cand(bytes32
   session, uint64 hand, Phase2Cand memory c)` setter that writes directly
   into `phase2ActionsAt`, letting a test construct an arbitrary
   phase-2 action history — including a multi-action, alternating one —
   without needing `phase2Act`'s external entry point to exist yet. This
   is the same harness technique, applied one function earlier in this
   phase's own build order than P2 needed it.
5. **Adversarial probe 1 — `test_F13_1_no_private_deadlines`
   (thirteenth check finding 1, translated into the shipped two-phase
   design).** Construct the check's own numbers (1000/1000 stacks, bonds
   1100, blinds 5/10; chain through the check's own action 6 — preflop
   A-30/B-call, flop B-check/A-60/B-call, turn B-check, 90 each
   committed) filed as ordinary phase-1 evidence; file the withheld
   action 7 (`bet 500`) at `disputeOpenedAt + window - 5` (23:55-style,
   still in-window) so it lands in the **frozen** chain at consolidation.
   Assert: the phase-2 node facing B is `finalState.toActIsHost ==
   false` (B to act) with **zero** entries in `phase2ActionsAt` yet, and
   `_readyTime` returns `baseline == disputeOpenedAt + window` — **not**
   action 7's own `filedAt` — confirming B's bank starts fresh at the
   hour-24 appointment regardless of when within phase 1 the frozen tip's
   last action was actually filed (the exact fact that kills the check's
   three-reading ambiguity; this fixture is the regression pin for the
   two-phase split's own soundness, owned here rather than P3 because it
   is a bank-clock fact, not a consolidation fact).
6. **Adversarial probe 2 — `test_F13_2_own_postings_never_pause`
   (thirteenth check finding 2).** From a phase-2 node facing player X
   with a required board position, have X's **own** counterparty already
   post (satisfying `_readyTime`'s requirement) while X's **own**
   contribution to that same position remains unposted; assert
   `_readyTime` still returns `started == true` with a `readyTime` wholly
   unaffected by X's own missing post — X cannot suppress their own clock
   by withholding their own posting (decision 8's `postedAt[...]
   [counterparty]` lookup structurally excludes the player's own posting
   from the formula; this test asserts the *behavior*, not just re-reads
   the code).
7. **Boundary probe:** a hand-constructed action filed at the exact
   instant where `elapsed == bank - _bankSpent(...)` (spend would equal
   the bank exactly) is confirmed acceptable by `_readyTime`/`_bankSpent`'s
   own arithmetic (`remaining == 0`, not negative); one second later
   (`vm.warp`), the identical construction shows `remaining < 0`
   (decision 9's boundary convention) — this task tests the **arithmetic**
   directly; task 4's own fixtures (task 8) re-run the same boundary
   through an actual `phase2Act` call once that entry point exists.
8. **Adversarial probe 3 — `test_handoffBaseline_notH0` (fix-round-1
   B6/P4-1, BLOCKER — the gap the previous round's three probes all
   missed).** Probes 1–2 and the boundary probe above all construct a
   phase-2 node with **zero** entries in `phase2ActionsAt` — every one of
   them exercises only the `H0` branch of decision 8's baseline ternary
   (`phase2ActionsAt[...].length == 0 ? H0 : lastCandidate.filedAt`). A
   `_readyTime` that hard-codes `baseline = H0` unconditionally — ignoring
   the handoff branch entirely — would pass all three unchanged, while
   silently bank-folding **both** seats six hours after `H0` regardless
   of how much real play happened in between (exactly the finding's own
   failure mode). This probe closes that gap directly: via the harness
   (step 4), push **three** alternating `Phase2Cand` entries into
   `phase2ActionsAt` — host at `T0 = H0 + 1000`, guest at `T1 = T0 +
   2000` (`vm.warp(T1)` before the push, so `block.timestamp` genuinely
   advances between insertions — "real elapsed time," not a bare storage
   write with no clock movement), host again at `T2 = T1 + 1500`
   (`vm.warp(T2)`). After **each** push, call `_readyTime` for the player
   now to-act and assert `started == true` with `baseline` (and, absent
   any board-posting requirement for this fixture's construction,
   `readyTime` itself) equal to the **most recently pushed candidate's
   own `filedAt`** — `T0` after the first push, `T1` after the second,
   `T2` after the third — asserted **distinctly at all three handoffs**,
   not just the last one, so a `_readyTime` that only special-cases "the
   very first phase-2 action" (rather than genuinely reading "the most
   recent" every time) still fails this test. None of the three asserted
   values may equal `H0` — the assertion that would pass under the
   hard-coded-`H0` bug this probe exists to catch.
9. **Adversarial probe 4 — `test_lateCounterpartyPosting_movesReadyTime`
   (fix-round-1 P4-2 — "pausing" tested in the direction it actually
   pauses).** Probes 1–2 above establish that a **missing** counterparty
   posting stops the clock from starting (`started == false`) and that a
   **present** counterparty posting doesn't get re-triggered by the
   player's own missing one — but neither asserts what `readyTime`
   **becomes** once a required counterparty posting lands **after**
   `baseline` has already been reached. Construct a node whose `baseline`
   is a known value `B` (via the handoff harness technique, step 8, or a
   plain `H0` case — either establishes `B`); advance `block.timestamp`
   past `B` with **no** required counterparty posting on file yet
   (`_readyTime` returns `started == false`, confirming the clock is
   genuinely paused, not just slow); then post the required counterparty
   share at `T_post > B` (via `postShares`, task 2's real entry point —
   this probe *can* use it, since `postShares` is P3's, already shipped,
   unlike `phase2Act`); call `_readyTime` again and assert `started ==
   true` with `readyTime == T_post`, **not** `B` — the clock starts at
   the moment the obstacle clears, later than baseline, confirming
   `max(baseline, postedAt)` actually resolves to the *later* operand
   when the posting is what's late, not merely that the `max` exists in
   the formula.
10. **Adversarial probe 5 — `test_bankSpent_attributesOwnActionsOnly`
    (fix-round-1 P4-3).** Via the harness (step 4), push an alternating
    host/guest/host/guest history (four candidates, real elapsed time
    via `vm.warp` between each, as in probe 3) with deliberately
    *different* per-node elapsed gaps for host's actions than for
    guest's (so a bug that summed the wrong player's gaps, or both
    players' gaps together, produces a numerically distinct — not
    coincidentally equal — wrong answer); assert `_bankSpent(session,
    hand, true)` (host) equals the sum of **only** host's own two gaps,
    and `_bankSpent(session, hand, false)` (guest) equals the sum of
    **only** guest's own two gaps — neither includes the other player's
    elapsed time, confirming attribution, not just that some non-zero
    number comes out.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test --match-test "test_F13_1|test_F13_2|test_bankBoundary|test_handoffBaseline|test_lateCounterpartyPosting|test_bankSpent_attributes" -vv

YES/NO: exits 0, all six named fixtures pass (the original two cold-check
probes, the boundary probe, and the three fix-round-1 probes closing the
handoff/pausing-direction/attribution gaps).

**Dispatch:** `agent (session-tier, high)` — REVIEW-BRIEF's own error
record and this task's brief both name this the subtlest definition in
the phase; fix-round-1's own B6/P4-1 finding is direct evidence that
"proven against worked schedules" is not the same claim as "every branch
of the formula is exercised" — get all six probes above passing before
`phase2Act` (task 4) or `_consolidatePhase2` (task 5) consume
`_readyTime`/`_bankSpent`, since every fold/termination computation
downstream is only as sound as this arithmetic.

---

### Task 4 — `phase2Act`: signature, turn/chain checks, open-fold, canonical amounts

**Goal:** decisions 4–5 in full — the single-action, revert-on-illegal
entry point that extends the chain, delegating every non-fold action to
`BettingReplay.applyAction` unmodified. Everything this task calls
(`_frozenPrefix`, `_requiredBoardPositions` from task 1; `_readyTime`,
`_bankSpent` from task 3) is already declared by the time this task's own
`forge build` probe runs — no forward reference.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. Action preimage: identical builder to P3 task 3 step 3 (formats §5) —
   `0x03 ‖ "vault/act/v2" ‖ binding ‖ hand(8) ‖ seq(8) ‖ action(1) ‖
   amount(32) ‖ prev(32)`. Reuse the existing helper if P3 exposed one
   (`internal` visibility, confirmed at task 1 step 0), else duplicate the
   five-line builder — implementer's choice, note which in completion
   notes.
2. `phase2Act(bytes32 session, Act calldata a, bytes calldata sig)
   external`: `require(status == Disputed, "not disputed")`. Compute
   `actionHash`; recover signer via `_recoverRaw` (P3/P2's helper,
   unchanged) against `sessionKeyHost`/`sessionKeyGuest` in turn; neither
   match → `revert("bad signer")` (decision 4 — revert, not skip).
3. Build the combined array via `_frozenPrefix(session, hand)` (task 1
   step 6) plus `phase2ActionsAt[session][hand]`; call
   `BettingReplay.replay(...)` on it; require `kind == TermKind.NONE`
   (else the hand is already terminal — a `phase2Act` call against an
   already-fold/complete hand has nothing to extend) →
   `revert("already terminal")`. **Cost note:** this rebuilds the
   combined array and re-runs `BettingReplay.replay` from scratch on
   every `phase2Act` call — the identical cost shape to `_bankSpent`'s
   own per-node re-walk (task 3 step 2), bounded by episode length
   (~66h/street-count structure), not a scalability concern at this
   arc's scale; not optimized here for the same reason `_bankSpent`
   isn't (decision 3's laziness). Open question 2 below extends to cover
   this cost alongside `_bankSpent`'s.
4. Turn check: `require((finalState.toActIsHost ? sessionKeyHost :
   sessionKeyGuest) == signer, "not your turn")`. Chain-link check:
   `require(a.seq == lastAcceptedSeq + 1 && a.prev == <actionHash of the
   candidate at lastAcceptedSeq>, "bad chain link")` — the same two facts
   P3's replay engine itself enforces internally for phase-1 candidates
   (task 5 step 6: "a candidate from the *wrong* signer... is skipped");
   here, since this is a single revert-or-accept call rather than a
   batch, both checks are explicit `require`s rather than a walked skip.
   **This is also what makes phase-2 collision-free (task 1 step 1, task
   8 step 8): a second `phase2Act` call at a `seq` already accepted fails
   this exact check**, since `lastAcceptedSeq` has already advanced past
   it — there is no slot for a second candidate to occupy.
5. Bank check (decision 9, task 3's helpers): compute `readyTime` and
   `_bankSpent(session, finalState.toActIsHost)`; require **either** all
   required counterparty postings for `_requiredBoardPositions
   (finalState.street)` are on file **and** `block.timestamp <=
   readyTime + (bank - _bankSpent(...))` (elapsed does not strictly
   exceed remaining bank), **or** no required counterparty posting is on
   file yet at all (clock never started, decision 8 — the action proceeds
   unconditionally, this is "acting blind," `S_blind_action`). If a
   required posting *is* missing but the clock's baseline has been
   reached and remaining bank would be negative were the clock running —
   that case cannot arise by construction (an unset `postedAt` makes
   `readyTime` undefined, never a past instant), so no third branch is
   needed; state this explicitly as a comment rather than adding an
   unreachable `else`.
   Fails the bank check → `revert("bank spent")` — this specific revert
   means the true on-chain state is already a structural bank-fold at
   this node; the caller should call `resolve()` instead, which discovers
   the same fold via `_consolidatePhase2` (task 5) and settles it — a
   comment to this effect belongs at this revert site.
6. Action application: `if (a.action == FOLD) { finalState.closed = true;
   finalState.foldedIsHost = finalState.toActIsHost; }` (decision 5 — no
   call into `BettingReplay.applyAction` at all for this branch) `else {
   (finalState, bool ok) = BettingReplay.applyAction(finalState,
   finalState.toActIsHost, a.action, a.amount); require(ok, "illegal
   action"); }`.
7. Street-close cascade: if `finalState.closed` and `a.action != FOLD`
   (a round closed, not a fold), call `BettingReplay.closeAndAdvance`
   (P3 task 5 step 5) in the same loop shape `replay()` itself uses,
   stamping `birthAt[session][hand][uint8(finalState.street)] =
   block.timestamp` **before** advancing if the new street is `Flop`,
   `Turn`, or `River` (decision 6) — an all-in cascade that crosses
   multiple streets in this one call stamps each crossed street with this
   same `block.timestamp` (they were born together). If the cascade ends
   with `stillLive == false` (betting complete), also stamp
   `showdownBirthAt[session][hand] = block.timestamp`.
8. Append `Phase2Cand(signer, a.action, a.amount, a.prev, actionHash,
   uint40(block.timestamp))` to `phase2ActionsAt[session][hand]`.
9. Emit `Phase2ActFiled(session, hand, a.seq, a.action)`.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, and `grep -c "NotYetBuilt" contracts/src/ChannelV2.sol`
has dropped by exactly one relative to task 1's count (only `phase2Act`'s
stub is removed by this phase; no other `NotYetBuilt()` site changes).

**Dispatch:** `agent (session-tier, high)` — this is the phase's own
contract-owning centerpiece; the open-fold bypass and the turn/chain
checks are exactly what a checker will target first (decision 5's own
framing: "every other action does not" bypass `BettingReplay`'s gate — a
checker should try to smuggle a `bet`/`call` through the fold branch).

---

### Task 5 — `_consolidatePhase2`: the combined-array wrapper and bank-fold discovery

**Goal:** decisions 1 and 3 — the `view` function `resolve()` (task 7)
calls, producing a phase-2-aware `TermKind` that folds a bank-exhausted
player without ever writing that fact to storage. Depends on task 1's
`_frozenPrefix` and task 3's `_readyTime`/`_bankSpent` only — **not** on
task 4's `phase2Act` function body (it reads `phase2ActionsAt` storage
directly, which task 4 populates at runtime but which this function
never calls into) — so this task could in principle be built before task
4; it is sequenced after only because `phase2Act` is the more central,
higher-risk surface and this task's own fold-discovery logic reads more
naturally once the entry point that produces its inputs already exists.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `_consolidatePhase2(bytes32 session) internal view returns
   (BettingReplay.TermKind kind, address folder, BettingReplay.State
   memory finalState, uint256 effectiveCompletingFiledAt)`: `hand =
   markedHand[session]`; build `prefix = _frozenPrefix(session, hand)`
   (task 1 step 6); append `phase2ActionsAt[session][hand]` (cast to
   `BettingReplay.Cand` — same field shape, task 1 step 1's note) to get
   `combined`; call `BettingReplay.replay(buttonIsHost, sb, bb,
   stackHost, stackGuest, combined)` (marker fields and
   `receiptStacksAt[session][hand-1]` baseline, read exactly as P3 task 6
   step 1 does) → `(k, f, st, lastSeq, _)` — P3's own `completingFiledAt`
   return value is **discarded** here; this phase computes its own (step
   3 below).
2. If `k != TermKind.NONE` (the hand already terminated purely from filed
   evidence — a signed fold, an open-fold, or a completed runout with no
   live phase-2 decision ever needed) → return `(k, f, st,
   <effectiveCompletingFiledAt from step 3 if k == COMPLETE, else 0>)`.
3. If `k == TermKind.COMPLETE`: `effectiveCompletingFiledAt =
   showdownBirthAt[session][hand]`, maxed with `birthAt[session][hand][c]`
   for every board class `c` that `_requiredBoardPositions(st.street)`
   (task 1 step 7) would include for this street — **the same helper and
   the same three thresholds decision 8's clock gate uses, deliberately,
   not P3's terminal-completeness set** (decision 6's own explicit note;
   see that decision for why the two sets must stay distinct).
4. If `k == TermKind.NONE` (genuinely pending as of the frozen-plus-filed
   evidence alone): call `_readyTime(session, hand, st.toActIsHost,
   combined, st)` (task 3 step 1). If `started == false` → return `(NONE,
   address(0), st, 0)` (still pending, clock not running, no fold
   possible — task 7 routes this to `Phase2InProgress`). If `started ==
   true`: compute `remaining = bank - _bankSpent(session, hand,
   st.toActIsHost) - (block.timestamp > readyTime ? block.timestamp -
   readyTime : 0)`; if `remaining < 0` (strictly, decision 9's boundary)
   → return `(FOLD, st.toActIsHost ? host : guest, st, 0)` — the
   bank-fold, discovered here, never written to storage (decision 3).
   Else return `(NONE, address(0), st, 0)`.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. `grep -n "internal view" contracts/src/ChannelV2.sol |
grep _consolidatePhase2` confirms no state mutation, the same literal
check P3 task 6's own probe used for `_consolidate`.

**Dispatch:** `agent (session-tier, high)` — this function is where
decisions 1, 3, 6, and 8's pieces all meet; a checker will specifically
try to construct a case where a call to `_consolidatePhase2` and a later
call disagree (decision 3's own claim), so the function must be provably
a pure re-derivation with no hidden dependency on call order.

---

### Task 6 — Street runout integration: confirming no new position logic is needed

**Goal:** state, and test, that P3 task 10 step 2's required-position
derivation already handles a live phase-2 continuation correctly with no
new logic — only this phase's birth-timestamp bookkeeping (tasks 4, 5) is
new. This task's own "step" is a targeted regression test, not new
contract code.

**Files:** `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. **Why no new derivation exists, stated once so no later task
   re-invents it:** P3 task 10 step 2 derives required positions purely
   from `finalState.street` (`POS.hostHole`/`guestHole` always;
   `POS.flop` if `street >= Flop`; `POS.turn` if `street >= Turn`;
   `POS.river` if `street == River`) — a function of the **final** street
   reached, with no reference to *how* that street was reached. **This is
   P3's own terminal-completeness set, distinct from this phase's
   `_requiredBoardPositions` (decision 8, task 1 step 7) — this task
   confirms P3's set composes correctly with a live continuation; it does
   not use or extend this phase's board-only clock-gate helper at all.**
   Because `BettingReplay.replay`'s cascade (`closeAndAdvance`, P3 task 5
   step 5) is the same function whether it is consuming purely frozen
   phase-1 evidence (Part A's context) or the combined array this phase
   feeds it (task 5), a hand that reaches `River` via two phase-2
   `phase2Act` calls produces the exact same `finalState.street ==
   River` P3's existing formula already handles. This phase adds no
   branch, no override, no new constant to P3's set.
2. Construct a fixture: a frozen chain (phase-1 evidence) that reaches
   only the flop (pending on the turn), then two `phase2Act` calls that
   close the turn and the river live; assert the resulting required
   positions (via whatever this phase's task 5/task 8's `_resolveTerminal`
   call site computes) include `POS.turn` and `POS.river` correctly, and
   that `birthAt[Turn]`/`birthAt[River]` (task 4 step 7) hold the
   `phase2Act` calls' own `filedAt`s, distinct from each other and from
   `showdownBirthAt`.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test --match-test test_streetRunoutBirths -vv

YES/NO: exits 0.

**Dispatch:** `agent (workhorse, medium)` — confirms an already-established
formula composes correctly; no new design surface.

---

### Task 7 — Wire `resolve()`: replace `PendingContinuation`, extend crystallization

**Goal:** the phase's own boundary-closing wiring — `resolve()`'s
`_consolidate`-`TermKind.NONE` route now proceeds into
`_consolidatePhase2` instead of reverting, and `_crystallizeMaturedDuties`
(P3 task 12) gains a phase-2-aware branch so F16.1/F16.3's composition
guarantee extends to phase-2-born duties too. **The gap this closes is
the same shape AF-6's checker independently confirmed in P2's code**
(`review-findings.md`, AF-6: "P2's `resolve()` `finalEligible` branch
returns before the `markedHand` branch, making the F16.1/F16.3
composition gap real" — the reason P3 needed its own task 12 in the
first place). P3's task 12 closed the gap for phase-1-only burns; this
task closes the same gap one layer further out, for burns that can only
be discovered by walking phase-2's own on-chain continuation
(`_consolidatePhase2`) — a `final` filed and raced past a matured
phase-2-born duty must still find that duty burned, for the identical
reason P3's task 12 exists.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. In `resolve()`, at the exact site P3 task 7 step 2 put `revert
   PendingContinuation();` (the `TermKind.NONE` branch of the
   `markedHand[session] > 0` route): replace with a call to
   `_consolidatePhase2(session)` (task 5) → `(kind2, folder2, finalState2,
   effCompletingFiledAt)`. On `TermKind.NONE` → `revert
   Phase2InProgress();` (declared task 1 step 5, thrown here). On
   `TermKind.FOLD` or `TermKind.COMPLETE` → call `_resolveTerminal(session,
   kind2, folder2, finalState2, effCompletingFiledAt)` — the **same**
   function P3 tasks 10–11 built, unmodified, now receiving a
   phase-2-derived `finalState`/`completingFiledAt` instead of Part A's
   frozen-only ones. No forward reference: `_resolveTerminal` already
   exists (P3 shipped it, task 1 step 0 re-confirmed it), and
   `_consolidatePhase2` already exists (task 5) before this task runs.
2. `_crystallizeMaturedDuties` (P3 task 12): after its existing
   `TermKind.COMPLETE` branch (P3's own, over `_consolidate`'s
   frozen-only result), add: if `_consolidate` itself returned `NONE`
   (the marked hand's phase-1 evidence alone is pending), additionally
   call `_consolidatePhase2(session)` and, if **that** returns
   `TermKind.COMPLETE` with `block.timestamp >= dueAt(session,
   effCompletingFiledAt)` (decision 6's substituted value) and a burn this
   pass would fire per P3 task 11's rows and hasn't already fired →
   crystallize it the same way P3 task 12 step 1 does for the phase-1-only
   case. Comment: `// P4 extension (decision 6): crystallizes matured
   phase-2-born duty burns before a final can pay out around them
   (F16.1/F16.3, generalized to phase-2 births).` A `TermKind.FOLD` result
   from `_consolidatePhase2` needs **no** crystallization call at all — a
   fold (bank or otherwise) never itself burns a bond (decision "bank-fold
   is a fold," the phase's own hard rule); only a missed *posting* duty
   (task 11's rows, reached only via `TermKind.COMPLETE`) ever does.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, and `grep -c "PendingContinuation" contracts/src/ChannelV2.sol`
now shows the error **declared** but with **zero** live throw sites inside
`resolve()` (P3's only throw site is this task's own replacement);
`grep -c "Phase2InProgress" contracts/src/ChannelV2.sol` shows exactly 2
(declaration, task 1 step 5, + the one throw site this task adds).

**Dispatch:** `agent (session-tier, high)` — REVIEW-BRIEF's error record
flags exactly this shape ("old-artefact × new-phase seam," here P3's
`finalEligible`/crystallization machinery meeting this phase's new
phase-2 completion path) as the orchestrator's own recurring blind spot;
a checker should specifically try to construct a `final` that pays out
before this task's added crystallization branch runs.

---

### Task 8 — Fixtures: bank, termination, duties, chain-link collision

**Goal:** the seven fixture rows most directly exercising this phase's
own bank/termination/duty machinery (readyTime's own two rows, F13.1/
F13.2, plus the three fix-round-1 probes closing the handoff/pausing/
attribution gaps, already shipped by task 3), plus a behavioral
regression test for the no-equivocation-collision claim task 1 step 1
makes by citation alone, plus an end-to-end integration companion to
task 3's own handoff-baseline proof now that `phase2Act` exists to drive
it.

**Files:** `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. `test_F10_5_crash_at_showdown_survivable`: a frozen chain pending a
   call; `phase2Act` files the completing call on-chain (birthing
   `showdownBirthAt` at that call's `filedAt`, task 4 step 7); the
   counterparty's client "crashes" (posts nothing immediately); they
   return and post every required share before `dueAt(session,
   showdownBirthAt) = max(hour 24, showdownBirthAt + grace)`; `resolve()`
   reaches cards-decide (P3 task 10 step 3) with **no** burn — this is
   the phase's own end-to-end happy path, exercising `phase2Act` →
   birth-tracking → `postShares` → `_resolveTerminal` in one fixture.
2. `test_F12_4_postings_are_window_duties`: betting completes via a live
   `phase2Act` call; the completing player's own shares (owed as part of
   the same joint-decode requirement, decision 7) are posted well inside
   the `birth + grace` window but **after** `block.timestamp` would have
   exceeded a *bank*-shaped deadline had one applied — assert no
   bank-fold check is ever consulted for a posting (decision 7's
   separation: grep the posting's resolution path and confirm it reads
   only `dueAt`/`sharePosted`, never `_bankSpent`/`_readyTime`), and the
   duty is met, no burn.
3. `test_F12_5_one_muck_price`: construct a phase-2-resolved muck (one
   side misses a required position past `dueAt`) and a phase-1-resolved
   muck (P3's own `test_F12_2`-style construction, reused/re-run here)
   side by side; assert the burned amount is `bondHost`/`bondGuest`
   identically in both — this phase adds no second muck price, it calls
   the same `_burnBond`/task-11 rows P3 shipped.
4. `test_F13_7_banks_sequential`: a phase-2 episode where player A's bank
   empties first (structural bank-fold via `_consolidatePhase2`); assert
   `resolve()` settles via the fold row **before** player B's own
   cumulative spend could ever reach their bank total — i.e., assert
   `_bankSpent(session, hand, false)` (B's spend) at the moment of A's
   fold is strictly less than `bank`, confirming the both-banks-empty
   state this arc's spec calls structurally unreachable never has a
   chance to occur (obstacles are sequential — only one player's clock is
   ever running at a time, task 3's `_readyTime` design plus task 4's
   turn check together enforce this).
5. `test_S_absentee_ceiling`: a to-act absentee's bank empties at a node
   where the present player has an outstanding bet; assert the pot at
   resolution equals exactly what was legitimately wagered up to the fold
   node (P3 task 10 step 1's `excess = |investedHost - investedGuest|`
   return-to-overpayer arithmetic, reused unchanged) — the present player
   cannot grow the pot further against a bank-folding opponent; uncalled
   excess returns.
6. `test_S_desert_then_return`: a bank-fold occurs (player away during
   their to-act stretch), but that same player met every separate duty
   they owed (phase-1 filing duties, any posting duties born before the
   fold) — assert their bond returns in full, confirming the fold itself
   never calls `_burnBond` (P3 task 10 step 1's "no `_burnBond` call on
   this path at all," inherited unchanged); contrast in the same test's
   comments (not a second assertion — already covered by P2/P3's own
   fixtures) that missing an *unrelated* duty for the full window is a
   separate, already-tested failure mode this phase does not re-test.
7. `test_S_blind_action`: a to-act player calls `phase2Act` with a legal
   action while a required counterparty board-share posting is **not**
   on file; assert the call succeeds (task 4 step 5's "no required
   posting on file yet → proceeds unconditionally" branch) — legality
   never depends on a card, confirmed as behavior, not just read from the
   code.
8. `test_phase2Act_secondCallSameSeq_revertsBadChainLink` (task 1 step
   1's no-equivocation-collision claim, tested behaviorally, not just
   cited): file one legal `phase2Act` action at the current to-act node;
   attempt a second `phase2Act` call still targeting the same `seq`
   (whether identical, or a different action/amount at that node) —
   assert the first call succeeds and the second **reverts** `"bad chain
   link"` (task 4 step 4's chain-link check, since `lastAcceptedSeq` has
   already advanced past that `seq` by the time the second call lands).
   This is the direct evidence for "there is no second candidate to
   collide with" — phase-2 has no dual-slot storage for the second call
   to even land in, unlike `fileActions`' equivocation path.
9. `test_phase2Act_handoffBaseline_endToEnd` (integration companion to
   task 3 step 8's `test_handoffBaseline_notH0`, now that a real
   `phase2Act` exists to drive it): the identical three-alternating-action
   schedule as task 3's harness-injected version, this time filed via
   **actual** `phase2Act` calls with `vm.warp` advancing real time between
   each; assert the third player's remaining bank, read via a fourth call
   attempt right at the boundary computed from `T2` (not `H0`), matches
   task 3's own arithmetic exactly. This does not re-derive the arithmetic
   — it confirms `phase2Act`'s own append path (step 8's `Phase2Cand`
   write) produces exactly the storage shape task 3's harness simulated,
   so the isolated proof and the wired-up entry point agree.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test -vv

YES/NO: exits 0, all seven index-fixture rows plus the chain-link
collision regression test and the handoff-baseline integration companion
pass.

**Dispatch:** `agent (workhorse, high)` — long and exacting, follows
patterns tasks 4/5/7 already established; not architecture-inventing.

---

### Task 9 — Fixtures: legality/accounting, D12 re-derivation, short-duration timing

**Goal:** the remaining two fixture rows (F11.2, S_continuation_accounting),
the mandatory D12 re-derivation report, and timing tests run against D15's
short constructor durations rather than `vm.warp`-only coverage of paths
P7's live sweep will actually exercise.

**Files:** `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. `test_F11_2_no_cancel_escape`: a player facing a raise mid-hand opens
   a dispute instead of folding on the wire; the window closes with the
   chain pending; phase 2 begins; assert the **only** entry points that
   ever mutate the marked hand's outcome are `phase2Act`'s four-action
   alphabet and the structural bank-fold — `grep -n "external" contracts/src/ChannelV2.sol`
   confirms no cancel-shaped function exists anywhere in the contract
   (the absence itself is the assertion, not a revert test against a
   function that was never going to exist) — and that the facing
   player's only route past the decision is exactly the same fold/call/
   bet the wire offered.
2. `test_S_continuation_accounting`: a phase-2-extended `bet` at the
   `hi` boundary of `BettingReplay`'s own range check (P3 task 5 step 4)
   confirms it is capped by `stackHost`/`stackGuest` as derived from
   `receiptStacksAt[session][hand - 1]` (P3 task 3 step 1's baseline,
   unchanged) — a bet cannot exceed what the receipt baseline allows,
   even mid-phase-2; after `resolve()` settles this hand, assert the
   deposits invariant (P2 task 6: `depositedHost + depositedGuest +
   bondHost + bondGuest == paidOut[session] + burned[session]`) still
   holds exactly, confirming the overlay this phase's payout computation
   applies composes correctly with P2's accounting, not just P3's.
3. **D12 mandatory re-derivation** (mirrors P2 task 8 step 3 and P3 task
   13 step 11 exactly): run

       grep -n "^### Findings" /home/dev/projects/vault/docs/superpowers/parking/v2-cash-game-settlement.md

   then read every finding from `## Tenth cold check` through the end of
   the file (re-grep the actual line count and section boundaries at
   implementation time — this doc's own reads above found the thirteenth
   check at line 2333 and the fourteenth at line 2545, but re-confirm
   rather than trusting a cached number, per this arc's own discipline),
   independently building the list of every constructed case belonging
   to P4's scope (phase-2 bank accounting, readyTime/sole-obstacle,
   phase-2-born posting duties, street-runout birth tracking, bank-fold
   termination, the ~66h bound). **Diff this list against
   `fixtures-index.md`'s P4 rows** (confirm the current row set at read
   time: `F10.5, F11.2, F12.4, F12.5, F13.1, F13.2, F13.7,
   S_absentee_ceiling, S_desert_then_return, S_blind_action,
   S_continuation_accounting` — eleven rows as of this doc's drafting).
   Report the enumeration in this task's completion notes: confirm each
   index row is still present in the parking doc as read, and flag — as a
   plan finding, not a silent addition or drop — any constructed case the
   re-derivation finds that the index lacks, or any index row the
   re-derivation can no longer locate a case for.
4. **Short-duration timing tests (D15).** Deploy a `ChannelV2` instance
   in the test file's own `setUp` (or a dedicated test function) with
   short constructor durations — e.g. `window = 100, bank = 30, grace =
   45` (seconds; concrete values documented in a comment, chosen so the
   ratios mirror the spec's 24h/6h/6h roughly, not copied from D15's
   prose verbatim since D15 only pins the *pattern*, not specific test
   numbers). **`bank != grace` is deliberate, per fix-round-1 C10:** the
   spec's own production values (6h/6h) make `bank` and `grace`
   numerically identical, so a constructor-argument swap (`bank`/`grace`
   passed in the wrong order to `new ChannelV2(window, grace, bank)`,
   say) would silently compile, deploy, and pass every test that never
   distinguishes the two durations by value — this instance's `30`
   vs. `45` makes such a swap immediately visible as a wrong-by-15-seconds
   failure in whichever assertion reads a bank-shaped deadline where a
   grace-shaped one was expected, or vice versa — mirroring
   `DeployV2.s.sol`'s `TEST_DURATIONS=true` override
   path (P2 task 7 step 4), **not** a same-instance `vm.warp` applied to
   the spec's real 24h/6h/6h constants. Construct a boundary-arithmetic
   case analogous to the parking doc's own 23:55/29:59-style worked
   numbers (fourteenth check finding 1: a completing action filed one
   tick before the window closes births a duty due `birth + grace`, past
   the window's own close) **scaled to this instance's own short
   durations** — assert the scaled birth-anchor arithmetic holds exactly
   (a duty born at `window - 1` second is due at `birth + grace`, not
   `window`, confirming the max-of-hour-24-and-birth-plus-grace formula
   generalizes correctly at any duration scale, not just the spec's
   production numbers). `vm.warp` is used freely *within* this short-
   duration instance for the boundary arithmetic itself — D15's rule is
   about never testing a path P7's sweep will exercise using only
   `vm.warp` against hardcoded spec durations, not a ban on `vm.warp`
   generally.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test -vv

YES/NO: all tests pass (task 8's eight tests plus this task's two, plus
task 3/6's earlier ones); completion notes contain the D12 enumeration
report and the short-duration deployment's own gas/behavior notes.

**Dispatch:** `agent (workhorse, high)` — long and exacting, follows every
pattern tasks 4–8 already established; the D12 re-derivation is a literal
grep-and-read obligation, not a design task, but the short-duration
deployment and its scaled boundary arithmetic need real care, not
mechanical translation from the spec's production numbers.

---

## Phase-boundary verification

Gate type: **technical-auto**.

1. **YES/NO — build.** `~/.foundry/bin/forge build --root
   /home/dev/projects/vault/contracts` exits 0.
2. **YES/NO — full ChannelV2 suite green.** `~/.foundry/bin/forge test
   --root /home/dev/projects/vault/contracts -vv` exits 0; V1's 26 tests
   and every P2/P3 test from earlier phases still pass (D11 spot-check,
   the same probe every earlier phase's gate used).
3. **YES/NO — V1 and P2/P3 isolation preserved (D17: base-ref, not
   `--stat`).** `git -C /home/dev/projects/vault diff <P4-BASE-SHA>..HEAD
   -- contracts/src/Channel.sol contracts/test/Channel.t.sol
   contracts/script/Deploy.s.sol` empty (D11); `git -C
   /home/dev/projects/vault diff <P4-BASE-SHA>..HEAD -- contracts/src/BettingReplay.sol
   contracts/src/Evidence.sol` empty (this phase's own promise — reused
   unchanged, task-1-through-9 never touch these files). `<P4-BASE-SHA>`
   is the commit this phase's task-ordering note pins at dispatch, per
   D17 — **not** `git diff --stat`, which reads empty against a committed
   worktree regardless of what changed (D13's commit-to-master flow makes
   `--stat`'s worktree-vs-index comparison vacuous the moment work is
   committed, the exact trap D17 exists to close).
4. **YES/NO — no stub surfaces remain.** `grep -n "NotYetBuilt"
   contracts/src/ChannelV2.sol` shows the error declaration with **zero**
   live throw sites anywhere in the contract (P3 left exactly one,
   `phase2Act`'s stub — this phase's own task 4 removes it, and it was
   the last one, per P3's own Outputs "the only surface left for P4").
   **This gate alone is not sufficient evidence `phase2Act` works** — it
   passes equally on a correct implementation and on an empty `{}` body
   that merely deletes the `revert NotYetBuilt();` line without replacing
   it with anything; **gate 2 (the full test suite, including task 4's
   own `forge build` and every task 8/9 fixture actually exercising
   `phase2Act`) is the real check that a body exists and is correct**,
   this gate only confirms the *surface* was touched at all.
5. **YES/NO — the readyTime seam is proven, not merely present.** This is
   the seam REVIEW-BRIEF asks every gate to attack: construct the case
   where the probe passes while the capability is broken. Here, that
   would be `_readyTime`/`_bankSpent` compiling and returning *some*
   answer while silently ignoring the sole-obstacle rule (e.g., pausing
   on a player's *own* missing posting), the fresh-appointment rule (e.g.,
   anchoring to a phase-1 filing time instead of `H0`), **or the handoff
   rule (e.g., hard-coding `baseline = H0` and never reading the most
   recent phase-2 candidate's own `filedAt` — fix-round-1 B6/P4-1's own
   finding, caught only because a fixture was added that actually forces
   the ternary's second branch).** Task 3's `test_F13_1_no_private_deadlines`,
   `test_F13_2_own_postings_never_pause`, `test_handoffBaseline_notH0`,
   `test_lateCounterpartyPosting_movesReadyTime`, and
   `test_bankSpent_attributesOwnActionsOnly` are what make this the case
   the gate actually exercises — all five must be present and passing,
   confirmed by name in the test file, not merely "some bank test
   exists." A test suite that is green with only the first two present is
   **not sufficient** — that was exactly fix-round-1's finding against
   this doc's own previous revision.
6. **YES/NO — bank-fold routes through the unmodified fold row.**
   **Test-based only, per fix-round-1 P4-4** (a source grep for
   `_burnBond` is path-unaware — it cannot be scoped to "just the
   `TermKind.FOLD` branch inside `_resolveTerminal`" without parsing
   Solidity control flow, and an unscoped `grep -n "_burnBond"` over the
   whole file finds every legitimate call P3's other rows make, proving
   nothing about this specific path — so this gate drops the grep
   entirely rather than ship a check that looks precise and isn't). Task
   8's `test_S_desert_then_return` asserts directly, in Solidity, that a
   bank-folded player's `credits` include their full bond — a stronger,
   correctly-scoped check than any source grep could be, since it
   observes the actual payout rather than the presence of a function
   call.
7. **YES/NO — no collision path exists in phase 2.** Task 8's
   `test_phase2Act_secondCallSameSeq_revertsBadChainLink` is present and
   passing, confirming behaviorally (not merely by citation, per task 1
   step 1's own admission that this needed a test) that phase-2 has no
   equivalent of `fileActions`' equivocation storage race.
8. **YES/NO — D12 report and the short-duration timing tests exist.**
   Task 9's completion notes contain both, per that task's own
   verification probe.

## Outputs to next phase

**To P6 (client-chain, poker repo):**
- **Post duties on birth, not on a fixed schedule.** Phase-2-born posting
  duties (`birthAt[Flop]`/`[Turn]`/`[River]`, `showdownBirthAt`, task 4
  step 7) are each individually on-chain events the client can watch
  directly (`Phase2ActFiled` or the street-close it implies) — `TBD-P6-CLIENT`:
  the client should file a posting the instant its own birth event is
  observed on chain, not wait for any fixed clock, since `dueAt` is
  `birth + grace` per class and a client that waits risks the muck row
  for no benefit.
- **Answer appointments, not "show up once."** The first phase-2 to-act
  moment is always `H0 = disputeOpenedAt + window`, known the instant the
  dispute opens (§5.1); every subsequent to-act moment is announced by
  the *opponent's own* on-chain `phase2Act` transaction (this phase's
  `Phase2ActFiled` event) — `TBD-P6-CLIENT`: the client should watch for
  this event and treat it as the presence trigger, the same shape V1's
  `iAmHere` pattern already establishes for a different purpose.
- **Standing-instruction hooks: this phase merely does not preclude
  them.** §8.11 names blind action and standing instructions as phase 2's
  legal mitigations; blind action is a contract-level fact this phase
  ships (task 4 step 5, `S_blind_action`) — a to-act player's action is
  never gated on a card. Standing instructions (an automated
  check-or-fold near bank exhaustion) are **entirely a client-side
  policy** (`TBD-P6-CLIENT`): `phase2Act` accepts any correctly-signed
  action from the registered session key regardless of who or what
  produced the signature, so a standing-instruction automation is simply
  another caller using the same persisted session key — no new contract
  surface, no special-cased entry point, and this phase adds none.
- **The four forfeit sites (P1/P6's own naming, cross-referenced here):**
  a client that never files anything during phase 1 defaults per P2/P3's
  existing rows; a client that never returns during phase 2 defaults per
  this phase's bank-fold (pot only) plus its separate posting-duty
  deadlines (bond) — the two consequences are independent, per decision
  7, and P6 should not conflate "lost the hand" with "lost the bond" in
  its own forfeit messaging.
- **No P3 symbols were renamed by this phase's own revision.** This
  phase introduces two internal helpers of its own (`_frozenPrefix`,
  `_requiredBoardPositions`, both task 1) that are new, not renamed —
  neither collides with, nor stands in for, any name P3 or P2 already
  ships. P6 briefs referencing P3's `postShares`/`sharePosted`/`decodeAt`
  or P2's Session interface need no update on account of this revision.

**To P7 (deploy-live-sweep, both repos):**
- **Sweep-exercisable endings, this phase's own contribution:** a
  signed fold reaching phase 2's frozen tip (already P3's, unchanged); an
  **open fold** filed live via `phase2Act` (task 4 step 6 — new,
  phase-2-only); a **bank-fold** (task 5 — new, requires letting a short
  `bank` duration actually expire, exactly the reason D15 exists); a
  **live-continuation showdown** (a hand that closes further streets via
  `phase2Act` before reaching cards-decide/muck — new); a
  **phase-2-born-duty muck** (a posting duty whose birth was a live
  `phase2Act` call, not a frozen-evidence one — new). All five are
  reachable inside a human calendar session only against the short
  `TEST_DURATIONS=true` instance (D15) task 9 exercises — P7's deploy
  script should deploy that instance alongside the production-duration
  one specifically so this phase's own endings are sweep-exercisable, not
  just unit-tested.
- **Contract address / ABI:** none — deployment stays P7-only (D11/D13);
  P7 builds against `contracts/out/` after this phase's own `forge build`
  succeeds, same as every earlier phase handed the next.

## Open questions

**RESOLVED 2026-08-17 via fix-round-1 B2 (cross-cutting ruling on P3).**
This doc's drafted item 1 asked whether `dueAt`/`_resolveTerminal` take
`completingFiledAt` as an explicit parameter in P3's shipped code or
re-derive it internally from `_consolidate` — a question this phase could
not settle unilaterally since `dueAt`'s arity is P3's to decide. B2 settled
it at the ruling level: P3 ships `dueAt(session, completingFiledAt)` as an
explicit two-argument function. Decision 6's own text above now states
this as resolved, not contingent; task 1 step 0's dispatch-time
re-verification still confirms the two-arg signature landed (a shipped
revision can under-deliver a ruling), but that is ordinary re-verification
discipline, not an open design question — removed from this list rather
than left as an item whose "wrong-symbol" framing (treating `dueAt`'s
arity as if `_resolveTerminal`'s own signature were the uncertain one)
fix-round-1 flagged as confusing which symbol actually carried the risk.

1. **Whether the phase's re-derivation-not-memoization cost — `_bankSpent`'s
   per-node re-walk (task 3 step 2) *and* `phase2Act`'s own full-array
   rebuild-and-replay on every call (task 4 step 3) — should be memoized
   rather than recomputed from scratch.** Default: recompute in both
   places (decision 3's laziness, matching P3 decision 4's own choice for
   `_consolidate`) — the array is short (bounded by the ~66h/street
   structure, not a scalability concern at this arc's scale), and
   `phase2Act`'s own re-replay pays the identical cost shape once per
   real decision, not once per query, which is a materially smaller
   multiplier than `_bankSpent`'s repeated `view` reads. **Overrules:**
   the operator, only if P7's gas measurements (task 9, informational)
   show either recomputation is materially expensive at realistic
   phase-2 chain lengths — a real but currently unevidenced risk, flagged
   rather than dismissed, mirroring P3's open question 2 on the
   card-point table's storage form.
2. **Whether `phase2ActionsAt`'s array-append storage pattern should be
   replaced with a `keccak256(session, hand, seq)`-keyed mapping (P3's
   `actionsAt` shape) instead, for cheaper single-slot reads.** Default:
   append-only array (task 1 step 2) — simpler to build the combined
   `Cand[]` array task 5 needs (a single concatenation, no seq-by-seq
   mapping walk), and phase-2 chains are short enough that the array's
   own length is never a practical gas concern. **Overrules:** the
   operator, only if a checker or P7's gas measurements find the array
   form materially more expensive than a keyed mapping at realistic
   phase-2 chain lengths.

## Recovery

If this phase is interrupted mid-task: **the real dependency chain,
corrected from a drafting-time BLOCKER (this doc's own checker, applied
per the task-ordering note above), is:**

    1 → {2, 3} → 4 → 5 → 7
    task 3 needs: 1, 2
    task 4 needs: 1, 3           (NOT 5 — _consolidatePhase2 is a sibling, not a dependency)
    task 5 needs: 1, 3           (NOT 4 — reads phase2ActionsAt storage, never calls phase2Act's body)
    task 6 needs: 4, 5
    task 7 needs: 1 (Phase2InProgress), 5
    task 8, 9 need: everything through 7

Concretely: task 1's storage and shared helpers (`_frozenPrefix`,
`_requiredBoardPositions`) before task 2's `postedAt` extension and task
3's `_readyTime`/`_bankSpent` (both need only 1 and 2) before task 4's
`phase2Act` (needs 1 and 3) and task 5's `_consolidatePhase2` (needs 1
and 3, but **not** 4 — a resumed session that finds task 5 done and task
4 not yet started is in a valid, recoverable state, not a sign of drift,
since task 5 only reads storage task 4 happens to populate at runtime)
before task 6's regression test (needs 4 and 5) and task 7's `resolve()`
wiring (needs 5). A resumed session should `~/.foundry/bin/forge build
--root /home/dev/projects/vault/contracts` first, then `grep -n "function
\|error \|struct " contracts/src/ChannelV2.sol` against this doc's task
list to find the first missing surface. Tasks 8–9 are additive to the
test file only and can restart from a clean `forge test` run regardless
of where they stopped.

**If `contracts/src/Channel.sol`, `contracts/test/Channel.t.sol`,
`contracts/script/Deploy.s.sol`, `contracts/src/BettingReplay.sol`, or
`contracts/src/Evidence.sol` show *any* diff** (`git status --short --
contracts/src/Channel.sol contracts/test/Channel.t.sol
contracts/script/Deploy.s.sol contracts/src/BettingReplay.sol
contracts/src/Evidence.sol`), stop and ask — D11/D13's untouched-V1
boundary, plus this phase's own promise to reuse P3's crypto/replay
surface unchanged, both live in this one check.

**If `phase2Act` is found with a body that is neither the P2/P3 stub
(`revert NotYetBuilt();`) nor a complete implementation of task 4's steps
1–9, stop and ask** — a partially-wired turn/chain/bank check is the one
state in this phase most likely to look like it works (accepts honest
play, silently missing the open-fold bypass or the bank check) while
failing exactly the adversarial fixtures (tasks 3, 8) that exist to catch
it.
