# Phase 2 — money-frame (vault repo, Solidity)

## Goal

Ship `ChannelV2.sol` — a new, separate contract from V1's `Channel.sol`
(D11/D13: V1 stays untouched) — carrying the money frame the whole arc
stands on: the declared-depth Session interface, the per-player deposit
ledger, raw-digest session-key receipt/marker verification, the `final`
good ending with its burn-ledger irrevocability hook, and a dispute
*shell* (open/unwind/never-started, everything richer stubbed
`NotYetBuilt()`) that P3 fills without interface churn. Contract tests
before any UI, per the spec's §11 build order.

**Naming:** the new contract is `ChannelV2` in `contracts/src/ChannelV2.sol`
— V1's file is `Channel.sol` holding contract `Channel`; `ChannelV2` is the
straightforward continuation of that convention (confirmed no existing
`ChannelV2` symbol anywhere in the repo — `grep -rn "ChannelV2" contracts/`
returns nothing today). Deploy script is a new file, `DeployV2.s.sol`
(contract `DeployV2`), not an edit to `Deploy.s.sol` (D11: V1's deploy
path is untouched).

## Inputs from previous phase

- `docs/superpowers/plans/2026-08-17-v2-cash-settlement/artifact-formats.md`
  (the scaffold, normative — D1) and
  `docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`
  (revision 8). P1 runs in parallel on the poker repo. **D16
  (`decisions.md`'s final entry — added after this doc's first draft)
  changes what P1 hands this phase:** P1 ships a vector generator
  (pattern: `prototypes/dispute-gas/gen/gen.mts`) that emits the
  canonical receipt/marker/action preimages, hashes, and signatures as
  committed files in the poker repo. **D18 (fix round 1) makes P2 the
  owner of copying and gating that parity, not P1 or a shared
  responsibility:** task 8 step 1 copies `src/vectors/{p1-vectors.json,
  Vectors.sol}` into `contracts/test/vectors/` and records P1's task-10
  commit-message hashes in a checksums file; phase-boundary gate 7
  re-verifies with `sha256sum -c`. **Tasks 8 and 9 consume that copy
  for every construction their tests build**, falling back to in-test
  `vm.sign` (as `Channel.t.sol` already does for V1) **only** for
  negative and mutation tests, where the test deliberately signs
  something wrong — never as a happy-path substitute (D18 makes a
  missing or mismatched vector file a hard gate **failure**, not a
  fallback pass; this doc's earlier fallback wording is struck). The
  exact synced path is written here as the inert token
  **`TBD-P1-VECTORS`**, since P1's revision implementing D16 is landing
  concurrently with this doc's revision — task 8 step 1 resolves the
  literal path at implementation time, confirming the actual
  location/branch against P1's shipped phase doc before writing the
  import. This supersedes this doc's original claim ("this phase never
  needs one") — recorded as a correction, not a silent edit, per the
  arc's amendment discipline.
- Live source read for this doc: `contracts/src/Channel.sol` (191
  lines), `contracts/test/Channel.t.sol` (433 lines, uses `forge-std`'s
  `Test`), `contracts/foundry.toml` (`src = "src"`, `out = "out"`,
  `libs = ["lib"]`), `contracts/script/Deploy.s.sol`, and
  `prototypes/dispute-gas/src/Bench.sol` +
  `prototypes/dispute-gas/test/Measure.t.sol` (pure-library idioms,
  confirms the `seq % 2` signer convention artifact-formats §10 already
  flags as superseded — do not copy it).
- `contracts/lib/forge-std` exists (installed); `~/.foundry/bin/forge`
  1.7.1 is the toolchain; `Channel.t.sol` already depends on
  `forge-std/Test.sol`, so this phase uses the same.

## Files touched

- `contracts/src/ChannelV2.sol` — new.
- `contracts/test/ChannelV2.t.sol` — new.
- `contracts/script/DeployV2.s.sol` — new.
- `contracts/test/DeployV2.t.sol` — new (task 7 step 7, fix round 1 B7).
- `contracts/test/vectors/{p1-vectors.json,Vectors.sol,CHECKSUMS.sha256}`
  — new, copied from the poker repo, not authored here (task 8 step 1,
  D16/D18, fix round 1 B4).
- No edits to `contracts/src/Channel.sol`, `contracts/test/Channel.t.sol`,
  or `contracts/script/Deploy.s.sol` (D11).

## Design decisions pinned here (binding on every task below)

These are load-bearing and not left to task-time judgment, per the hard
rule on integer rounding and structural ambiguity:

**1. Bond formula, rounding stated explicitly (D4, spec §2).** For
player `i` with declared max `M_i`, and the other player's declared max
folded into `M_host + M_guest`:

    ceilDiv(a, b) = (a + b - 1) / b                  // b > 0, standard Solidity idiom
    avgCeil       = ceilDiv(M_host + M_guest, 2)
    base_i        = max(avgCeil, M_i)                // both operands already integers — no rounding needed here
    bond_i        = ceilDiv(11 * base_i, 10)

  Both rounding steps round **up**. Each step can only *increase* the
  value relative to the true real-numbered `1.1 × max((M_h+M_g)/2, M_i)`,
  so `bond_i` is never below the spec formula's value — coverage never
  loses to truncation. Verified against the parking doc's own numbers
  (`docs/superpowers/parking/v2-cash-game-settlement.md:1772`, "Verified
  sound" section): `M_host=1500, M_guest=500` → `avgCeil=1000`,
  `base_host=1500 → bond_host=1650`; `base_guest=1000 → bond_guest=1100`.
  Matches the doc's `1650/1100` exactly — this is `test_S_bond_coverage_maxima`
  (task 9).

**2. Both bonds are computable at `open()`, not `join()`.** The Session
  interface (artifact-formats §9) has the host pass `maxHost` **and**
  `maxGuest` to `open()` — "the host proposes the whole table." So
  `bond_host` and `bond_guest` are both derived and stored at `open()`
  time; `join()` only reads the pre-stored `bondGuest`, it does not
  recompute anything. The guest cannot negotiate `maxGuest` — only
  accept (join) or not.

**3. `msg.value` splits into bond + initial deposit, not a separate
  parameter.** `open()`'s `msg.value = host buy-in + bond_host` (formats
  §9, verbatim). Since `bond_host` is deterministic from `(maxHost,
  maxGuest)`, the contract computes it first, then
  `depositHost0 = msg.value − bondHost` (revert if `msg.value < bondHost`),
  then applies the same declared-depth cap as every other deposit
  (`depositHost0 ≤ maxHost`). Symmetric for `join()`/`bondGuest`.
  `depositHost0` may be zero — a player may post exactly the bond and
  fund their stack later via `deposit()`.

**4. `fileReceipt`/`fileMarker` store and verify; only `resolve()` pays.**
  Filing (whether a `final` or plain evidence) never moves money by
  itself. `resolve()` is the single payout executor, matching the
  interface comment verbatim ("lazy: consolidates + settles when due")
  and the task brief's own phrase "resolve() routing: final
  short-circuit / ... / unwind." This means the good-ending UX is two
  transactions (file, then resolve) rather than one — call this out to
  P5 as an `Outputs to next phase` item; it is a real deviation from
  V1's single-call `closeCooperative` and is deliberate, not an
  oversight.

**5. Markers are posted routinely, every hand, not just in disputes.**
  Spec §4: "Dealing hand N+1 is gated on marker N being confirmed on
  chain" — this is the deal gate, and it fires during ordinary play, no
  dispute needed. §11.2(a)'s measured 61,740 gas figure is explicitly
  "marker + co-filed receipt calldata" — the routine per-hand
  transaction bundles the marker with the receipt it needs for
  continuity, in one call. Because of this:

  - **A marker is accepted only for `hand == markedHand[session] + 1`**
    (strictly sequential, `markedHand` starts at 0). This single rule
    satisfies *both* of spec §4's separately-stated rules at once:
    duplicate rejection (hand `N` can only ever be posted once, since
    after acceptance `markedHand` becomes `N` and the next accepted
    value is `N+1`) and "first marker always admissible during the
    window" (the same acceptance rule applies unconditionally, dispute
    or not — no special-casing needed). This is a genuine design
    addition beyond the pinned interface shape, allowed under
    artifact-formats §9's "may add fields but not remove or re-type"
    — record it as such in code comments.
  - **Continuity** is `receiptAt[session][m.hand - 1] == m.receiptHash`,
    where `receiptAt[session][h]` is the hash of the *current
    highest-subseq* receipt filed for hand `h` (naturally encodes "the
    overlay baseline is the highest subseq" from spec §4's rebuy-split
    rule, since a higher-subseq filing always overwrites the mapping
    entry). `fileMarker` accepts a marker **and an optional
    already-known receipt to co-file in the same call** — ship this as
    two entry points: `fileMarker(...)` (receipt must already be on
    file) and `fileMarkerWithReceipt(...)` (files the receipt first,
    identical checks to `fileReceipt`, then the marker) — the second is
    the routine per-hand path that reproduces the measured gas figure.
  - **Marker catch-up is sound and explicitly admitted, not just a side
    effect.** Sequential acceptance (`hand == markedHand + 1`) does not
    restrict *how many* markers land in one window — if a modified
    client pair skipped routine posting during play (say hands 4–7 were
    played off-chain with no on-chain marker for any of them), a filer
    can post markers 4, 5, 6, 7 **in sequence**, each one immediately
    satisfying the next's `hand == markedHand + 1` check, as long as
    the matching receipts are on file or co-filed for continuity at
    each step. This is sound for the same reason single-marker filing
    is sound (spec §4's "first marker always admissible during the
    window," generalized to a run of them): the player currently ahead
    strictly prefers catching the floor up to the truth over leaving it
    low, so the incentive that makes filing dominate silence at one
    hand holds at each hand in the catch-up sequence too. Tested as
    `test_S_marker_catchup` (task 9): a legitimate multi-marker
    catch-up sequence is **accepted**, not just single-marker
    duplicate-rejection (which is all `test_F11_3` originally covered).

**6. The floor check lives in `resolve()`, not in `fileReceipt`.**
  `fileReceipt` never rejects a `final` for being "below the floor" —
  it stores it and updates `highestFinal` tracking unconditionally (by
  `(hand, subseq)` order). `resolve()` decides, at settlement time,
  whether the stored highest final actually clears
  `finalHand >= markedHand[session]` (spec §4: "settlement must account
  for the highest marked hand: receipt ≥ N"). If it doesn't clear the
  floor, `resolve()` does **not** revert — it falls through to the
  dispute-status branch below. This is exactly `test_F10_2` (task 9):
  filing receipt N−1 as `final` against a confirmed marker for hand N
  must not settle; it must fall through to the (P3-owned) overlay path.

**7. `resolve()`'s dispute branch at `markedHand == 0` — rewritten per
  AF-4, superseding this doc's original both-burn §1.3 branch.** A
  checker independently confirmed the derivation below (once any marker
  confirms, `markedHand > 0` always leaves a marked live hand for the
  dispute to fall back on). But the orchestrator's ruling
  (`review-findings.md`, AF-4) supersedes what this doc originally did
  with that narrowed window: spec §1.3's symmetric **both-burn** branch
  is **unreachable dead code in V2** and must not be implemented.
  Reasoning, recorded here because it is not obvious: at
  `markedHand == 0`, "the session began but nobody filed" is not
  attestable on chain — a begun-but-unfiled session is observationally
  identical to never-started. Once you accept that, the only
  meaningful fact the contract can ever observe at `markedHand == 0` is
  *whether any filing happened at all*, and if one did, *who* filed
  it — and bond fate must then follow spec §1.0's own overarching law
  ("each player's outcome must never depend on the counterparty's
  cooperation... your bond returns if and only if **you** performed
  your dispute duties"), never a joint/mutual penalty.

  Once `finalEligible` is false, `resolve()` requires `status ==
  Disputed` and the window closed, then branches first on
  `markedHand[session] > 0` (P3/P4's territory regardless of what's
  filed), and only then on `everReceipted[session]` (whether *any*
  filing happened — at `markedHand == 0` the only reachable filing is
  `(0,0)`, so this is exactly "zero filings" vs. "one or more"):

  | Check | Branch | Outcome |
  |---|---|---|
  | `markedHand[session] > 0` | marked live hand exists | `revert NotYetBuilt()` — P3/P4's §5.3 table |
  | `markedHand == 0`, `!everReceipted` | zero filings at window close | **never-started semantics**: full refund — deposits **and both bonds** return (spec §1.3, tenth-check finding 6) |
  | `markedHand == 0`, `everReceipted` | one or more filings | **§5.4 settlement with per-duty bond fate**, not a joint unwind: settle at deposits (the only receipt reachable here, `(0,0)`, has `stack == deposit` by definition); each player's *own* bond returns if `hostFiledInWindow`/`guestFiledInWindow[session]` is set for them (they performed the filing duty — task 3 step 7 tracks this), and burns via `_burnBond` only for a player absent the **full 24h** window (spec §8.2's declared "vanishing entirely" cost, not a both-burn) |

  Note the "one or more filings" row is genuinely unilateral even
  though `(0,0)` is a single, jointly-signed artifact: the duty spec
  §5.2 names is *filing* it on chain, not having co-signed it earlier,
  so `hostFiledInWindow`/`guestFiledInWindow` tracks who actually
  submitted a filing transaction (task 3 step 7), not who is named in
  the artifact's signatures. A player whose counterparty files `(0,0)`
  on their behalf, while they themselves submit nothing for the entire
  window, still burns under this rule — that is the declared §8.2 cost,
  stated plainly rather than smoothed over. **Do not implement a
  symmetric both-burn path for this branch** — it is the specific thing
  AF-4 struck.

  Derivation of the `markedHand`-gating itself (checker-confirmed,
  unchanged from this doc's first draft): the task brief's worked
  citation (`docs/superpowers/parking/.../"200/1800"`,
  `v2-cash-game-settlement.md:1702,1786`) predates the tenth cold
  check's per-hand marker and deal gate (D6's rewrite) and does not
  transfer unchanged — in the *current* design, once any marker
  confirms (`markedHand > 0`), there is always a marked live hand for
  the dispute to fall back on, even under total silence during the
  window (an empty/no-action hand is a *pending decision*, which phase
  2's bank eventually bank-folds — never treated as "no filing at
  all"). So the branch table above is reachable *only* at
  `markedHand == 0` — before hand 1 was ever dealt on chain. Task 9's
  fixtures use fresh, current-design numbers, not the stale `200/1800`
  pair (Open questions, item 1, now resolved by AF-4 rather than left
  as a re-derivation question).

  `everReceipted` is a single bool, not per-hand tracking: because
  `markedHand == 0` implies no hand was ever dealt, the *only* receipt
  that could possibly exist under that condition is `(0,0)` (every
  other receipt presupposes a dealt hand). So "was any receipt ever
  filed" and "was `(0,0)` ever filed" coincide exactly when
  `markedHand == 0`, and a single flag suffices.

**8. Burn ledger: P2 ships the primitive and its idempotence; P3/P4
  supply the sources.** An internal `_burnBond(bytes32 session, bool
  isHost)`, **pre-declared in task 1** (see the task-ordering note at
  the top of Tasks — not task 6, which only consumes it): no-ops if
  that player's burn flag is already set for this session, else sets
  the flag, adds `bond_i` to `burned[session]`, and excludes that bond
  from any future payout. Decision 7's per-duty branch (AF-4) is the
  one P2-owned *caller* of it — a player absent the full window burns
  their own bond there; there is no other P2-owned caller (the
  symmetric both-burn path this doc originally described there is
  struck). Because P3/P4's misconduct sources
  (equivocation, missed grace) don't exist yet, `test_F15_3` (task 9)
  exercises idempotence via a small test-only harness contract
  (declared in the test file, not in `src/`) that subclasses
  `ChannelV2` purely to expose `_burnBond` for direct, repeated calls —
  proving the guard holds before P3/P4 ever call it for real. Record in
  a code comment that this internal function is the contract surface
  P3/P4 build their burn sources against.

**9. Signature recovery — two routines, not one, per AF-2.** V1's
  `_recover` (`Channel.sol:177`) always applies the EIP-191 prefix; per
  the formats doc's explicit note (§1: "the session-key recovery
  routine is new code, not a reuse of `_recover`"), `ChannelV2` ships
  two internal functions:
  - `_recoverRaw(bytes32 digest, bytes calldata sig)` — **no** prefix,
    `ecrecover(digest, v, r, s)` directly, low-s enforced (`s ≤
    SECP256K1N_HALF`, same constant V1 already uses at `Channel.sol:42`
    — reuse the literal value, cite the source line in a comment).
    Used for receipts and markers, verified against the *registered
    session key address*, not the wallet.
  - `_recoverEIP191(bytes32 digest, bytes calldata sig)` — identical to
    V1's `_recover` body (prefix `"\x19Ethereum Signed Message:\n32"`
    per **EIP-191** <https://eips.ethereum.org/EIPS/eip-191>, then
    `ecrecover`, same low-s check). Used **only** for session-key
    registration inside `open()`/`join()`, verified against the wallet
    address (`msg.sender`).
  `ecrecover` itself is a Solidity built-in backed by the secp256k1
  ECDSA-recovery precompile at address `0x01` — no new claim needed
  beyond what V1 already exercises in `Channel.t.sol`'s signature tests;
  this phase's negative tests (task 9) re-run the same malleability
  shape against **both** new recovery paths.

**10. Revert style.** Every revert is a `require(cond, "string")`,
  matching V1/`Channel.t.sol`'s convention (`vm.expectRevert("...")`) —
  **except** the P3-stub paths inside `resolve()`, `fileActions`,
  `postShares`, and `phase2Act`, which use the exact named custom error
  `error NotYetBuilt();` (literal name from this phase's brief) so P3
  can `vm.expectRevert(ChannelV2.NotYetBuilt.selector)` and knows
  exactly which surfaces it is replacing.

## Tasks

**Task-ordering note (build-order fix, checker-caught defect).** Task 5's
`resolve()` calls `_burnBond`, which this doc originally scoped to task 6
— landing task 5 before task 6 would leave `resolve()` referencing an
undeclared internal function, so `forge build` would fail at task 5's own
checkpoint. Fixed by **pre-declaring `_burnBond` in task 1** (task 1 now
carries step 11) rather than resequencing task 6 ahead of tasks 3–5: this
keeps task numbering equal to dispatch order everywhere in this doc — an
orchestrator can still run 1 → 9 in document order. Task 6's own step
list shrinks accordingly; see its steps for what's left.

**Phase-base SHA (D17, fix round 1).** At dispatch, record
`git -C /home/dev/projects/vault rev-parse HEAD` as
**`<PHASE-2-BASE-SHA>`**. Phase-boundary gate 3 (V1 isolation) diffs
against this SHA, not `--stat` — `git diff --stat` compares worktree to
index and reads empty once committed, which is vacuous under D13's
commit-to-master flow (the exact defect D17 exists to close).

**Split-feasibility ruling, task 1.** Task 1 bundles four concerns
(scaffold/enums, signature-recovery plumbing, the Session interface, the
bond formula) plus, now, the `_burnBond` primitive. Kept whole rather
than split: every one of tasks 2–9 depends on task 1's full storage
struct and recovery helpers being fixed before it can compile against
them, so a split only adds a hard sequential dependency with no
parallelization benefit — two tasks that must still run back-to-back in
the same order, for no gain.

### Task 1 — Scaffold, Session interface, session-key registration, bond formula

**Goal:** `ChannelV2.sol` compiles with the `Status` enum, per-session
storage, constructor, and `open`/`join`/`cancelOpen` implementing the
Session interface (artifact-formats §9) plus session-key registration
(§6) and the bond formula (decision 1–3 above).

**Files:** `contracts/src/ChannelV2.sol` (new).

**Steps:**
1. `pragma solidity ^0.8.24;` (matches `Channel.sol:2`, `foundry.toml`
   has no pinned solc version beyond what's in `lib/`).
2. `enum Status { None, AwaitingGuest, Active, Disputed, Closed }`.
3. Per-session storage (a struct is fine): `host`, `guest`,
   `sessionKeyHost`, `sessionKeyGuest` (addresses — the registered
   session-key *address form*, per formats §6), `maxHost`, `maxGuest`,
   `bondHost`, `bondGuest`, `depositedHost`, `depositedGuest`, `status`,
   plus the fields tasks 3–6 add (`disputeOpenedAt`, `markedHand`,
   `everReceipted`, `hostFiledInWindow`, `guestFiledInWindow` — decision
   7's per-duty presence tracking, AF-4 — the `highestFinal*` fields,
   `hostBurned`, `guestBurned`, `burned`, `paidOut`). Declare the whole
   struct now so later tasks only add fields, never restructure.
4. Constructor: `constructor(uint256 _window, uint256 _bank, uint256
   _grace)`, each `require(... > 0, "duration required")` (mirrors
   `Channel.sol:55-58`'s pattern), stored `immutable`. No chain-id guard
   here — V1 puts that in the deploy script only (`Deploy.s.sol:16-19`);
   task 7 mirrors it in `DeployV2.s.sol`, not the contract.
5. Implement `_recoverRaw` and `_recoverEIP191` (decision 9) and the
   shared binding-prefix helper `_binding(bytes32 session) → bytes`
   returning `abi.encodePacked(address(this), block.chainid, session)`
   (formats §1's universal binding rule).
6. Implement the registration-preimage builder per formats §6 exactly:
   `0x04 ‖ "vault/sessionkey/v2" ‖ binding ‖ player(20) ‖ sessionKey(20)`.
7. `open(bytes32 session, address opponent, uint256 maxHost, uint256
   maxGuest, address sessionKey, bytes calldata walletSig) external
   payable`: require session unused (`status == None`), `opponent !=
   address(0) && opponent != msg.sender` (mirrors `Channel.sol:63`),
   `maxHost > 0 && maxGuest > 0`. Compute `bondHost`/`bondGuest` per
   decision 1, using the passed `maxHost`/`maxGuest` (decision 2).
   Verify `_recoverEIP191(_registrationHash(session, msg.sender,
   sessionKey), walletSig) == msg.sender`; store
   `sessionKeyHost = sessionKey`. Split `msg.value` per decision 3
   (`require(msg.value >= bondHost, "below bond")`;
   `depositHost0 = msg.value - bondHost`; `require(depositHost0 <=
   maxHost, "past declared max")`). Store everything, `status =
   AwaitingGuest`.
8. `join(bytes32 session, address sessionKey, bytes calldata
   walletSig) external payable`: require `status == AwaitingGuest`,
   `msg.sender == guest` (mirrors `Channel.sol:77`). Verify
   registration the same way against `guest`. Split `msg.value`
   against the **pre-stored** `bondGuest`/`maxGuest` (no recomputation
   — decision 2). `status = Active`.
9. `cancelOpen(bytes32 session) external`: `status == AwaitingGuest`,
   `msg.sender == host`, refund `depositedHost + bondHost` in full
   (V1 parity, `Channel.sol:84-93`, but refunding the bond too since
   nothing was ever risked), `status = Closed`.
10. Emit events on each (`Opened`, `Joined`, `Cancelled` at minimum,
    naming free).
11. **Pre-declared here per the task-ordering note above, not task 6:**
    `_burnBond(bytes32 session, bool isHost) internal` — no-ops if that
    player's `hostBurned`/`guestBurned` flag is already set for this
    session, else sets the flag and adds `bondHost`/`bondGuest` to
    `burned[session]` (decision 8). Fully self-contained given this
    task's own struct fields; task 5 calls it, task 6 only *consumes*
    it (credits/withdraw, the invariant), task 9 tests its idempotence
    directly via a test-only harness.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, no errors mentioning `ChannelV2.sol`.

**Dispatch:** `agent (session-tier, high)` — contract-owning draft,
decisions 1–3 and 9 live here first and every later task inherits the
storage shape.

---

### Task 2 — Deposit ledger and `deposit()`

**Goal:** rebuys, capped at the declared max, any time pre-settlement.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `deposit(bytes32 session) external payable`: `require(status ==
   Active || status == Disputed, "not open for deposits")` (spec §3:
   "any time between hands" — pre-settlement, which per D9's precedence
   includes mid-dispute since nothing has closed yet).
2. Identify caller as host or guest (`require(msg.sender == host ||
   msg.sender == guest, "not a player")`).
3. `newTotal = depositedX + msg.value; require(newTotal <= maxX, "past
   declared max"); depositedX = newTotal;` — whole deposit reverts on
   cap violation, no partial credit (spec §3: "The contract refuses a
   deposit that would push a player's total past their declared M_i" —
   refuses, not truncates).
4. Emit `Deposited(session, who, amount, newTotal)`.
5. **Load-bearing note, as a code comment, citing spec §3:** "An
   un-receipted deposit is not chips" — `deposit()` only ever grows
   `depositedX`; it never touches stacks, and the contract never
   credits a receipt on its own. Crediting happens only inside a
   receipt both players signed (task 3).

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0.

**Dispatch:** `agent (workhorse, medium)` — single function, cap check,
no new judgment calls beyond what task 1 already fixed.

---

### Task 3 — Receipt filing and verification

**Goal:** `fileReceipt` — raw-digest dual-signature verification, total
order tracking, the deposits invariant, the deposit-not-exceeding-received
check, and `highestFinal` tracking for task 5's payout.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. Receipt preimage builder per formats §3 exactly:
   `0x01 ‖ "vault/receipt/v2" ‖ binding ‖ hand(8) ‖ subseq(4) ‖
   hostStack(32) ‖ guestStack(32) ‖ hostDeposit(32) ‖ guestDeposit(32) ‖
   final(1)`. **Unit note (fix round 1, B1):** all four amount fields
   are **wei**, not chips — the client's chip engine converts at
   `wei_per_chip = deposit_wei / starting_chips`, fixed at `(0,0)`; this
   contract only ever sees and stores wei (already this doc's
   assumption throughout the bond formula, deposit ledger, and payout
   arithmetic — stated explicitly now rather than left implicit).
2. `fileReceipt(bytes32 session, Receipt calldata r, bytes calldata
   sigHost, bytes calldata sigGuest) public`: `require(status == Active
   || status == Disputed, "not open for filing")`. Recover both
   signatures via `_recoverRaw` against `sessionKeyHost`/`sessionKeyGuest`
   (not the wallet addresses — the whole point of decision 9).
3. Invariant: `require(r.hostStack + r.guestStack == r.hostDeposit +
   r.guestDeposit, "stacks/deposits mismatch")` (spec §1.1, verbatim
   equation).
4. Deposit-not-exceeding-received: `require(r.hostDeposit <=
   depositedHost && r.guestDeposit <= depositedGuest, "deposit exceeds
   received")` (spec §1.1: "each recorded deposit must not exceed what
   the contract actually received" — checked against the **current**
   cumulative total, the only thing observable on chain; deposits are
   monotonic non-decreasing so this is the correct and only
   implementable form of the check).
5. Update `receiptAt[session][r.hand]` if `r.subseq` is the new highest
   for that hand (decision 5's continuity dependency) — track per-hand
   highest, not a single session-wide cursor, since disputes may file
   segments out of filing-order.
6. Set `everReceipted[session] = true` unconditionally on any
   successful filing (decision 7).
7. **Presence tracking for decision 7's per-duty branch (AF-4):** if
   `status == Disputed` and `msg.sender == host`, set
   `hostFiledInWindow[session] = true`; symmetric for `guest`. This is
   what lets `resolve()` distinguish "the filer" from "the counterparty
   absent the full 24h" when `markedHand[session] == 0` and at least
   one filing exists — the only duty P2 itself can attribute, since the
   only artifact reachable at that state is `(0,0)`. (Filing outside a
   dispute, i.e. `status == Active`, does not set these — presence only
   matters once a window is running.)
8. If `r.final`: compare `(r.hand, r.subseq)` lexicographically against
   the stored `highestFinal*`; if higher (or none stored), overwrite
   the cached fields (`highestFinalHand`, `highestFinalSubseq`,
   `highestFinalHash`, and the stack/deposit fields task 5's payout
   formula needs). **Do not** floor-check here (decision 6).
9. Emit `ReceiptFiled(session, r.hand, r.subseq, r.final)`.
10. Negative-test hook: this is the function most of task 9's require
    sweep targets — write it so every `require` above has a distinct,
    stable string.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. (Task 8's happy-path test is the real functional
probe for this task; build-green is the boundary-local check.)

**Dispatch:** `agent (session-tier, high)` — the receipt invariant and
the deposit-not-exceeding check are exactly what the tenth-check
findings turned on; this is core money-frame correctness surface.

---

### Task 4 — Marker filing, acceptance, and the deal-gate getter

**Goal:** `fileMarker` / `fileMarkerWithReceipt` per decision 5, plus
`liveHand(session) → uint64` for the client's deal gate.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. Marker preimage builder per formats §4 exactly:
   `0x02 ‖ "vault/marker/v2" ‖ binding ‖ hand(8) ‖ receiptHash(32) ‖
   deckRoot(32) ‖ hostShareRoot(32) ‖ guestShareRoot(32) ‖
   hostCardPk(32) ‖ guestCardPk(32) ‖ button(1) ‖ sb(32) ‖ bb(32)`.
   (P2 never inspects `deckRoot`/`shareRoot`/`cardPk` contents beyond
   hashing them — that's P3's triple-check territory; P2 just needs the
   bytes to build the correct hash and store it.)
3. `_fileMarkerCore(bytes32 session, Marker calldata m, bytes calldata
   sigHost, bytes calldata sigGuest) internal`: `require(status ==
   Active || status == Disputed, "not open for filing")`;
   `require(m.hand == markedHand[session] + 1, "not next hand")`
   (decision 5 — this single check *is* both duplicate-rejection and
   admits-during-window); recover both sigs via `_recoverRaw` against
   the registered session keys; `require(receiptAt[session][m.hand - 1]
   == m.receiptHash, "continuity")`; set `markedHand[session] = m.hand`;
   emit `MarkerFiled(session, m.hand)`.
4. `fileMarker(bytes32 session, Marker calldata m, bytes calldata
   sigHost, bytes calldata sigGuest) external` — thin wrapper calling
   `_fileMarkerCore` (used when the referenced receipt is already on
   file from an earlier filing).
5. `fileMarkerWithReceipt(bytes32 session, Marker calldata m, bytes
   calldata sigHostM, bytes calldata sigGuestM, Receipt calldata r,
   bytes calldata sigHostR, bytes calldata sigGuestR) external` — calls
   `fileReceipt(session, r, sigHostR, sigGuestR)` (task 3's function,
   made `public` for this reuse) then `_fileMarkerCore`. This is the
   routine per-hand transaction; it must reproduce the ~61,740-gas
   shape from §11.2(a) — not a hard gate here (that number was measured
   on a prototype, not this contract), but note it in a comment so
   task 8's happy-path test can sanity-check the same call isn't wildly
   more expensive.
6. `function liveHand(bytes32 session) external view returns
   (uint64)` — returns `markedHand[session]` (0 = no hand ever dealt).
   This is the entire client deal-gate surface (spec §4: "hand N+1
   deals only after marker N confirms").
7. **Catch-up needs no new function** (decision 5): a client that fell
   behind posts markers 1, 2, 3… as separate calls to `fileMarker`/
   `fileMarkerWithReceipt`, each accepted the moment the previous one
   confirms (`test_S_marker_catchup`, task 9) — do not add a batched
   "post N markers" entry point, it isn't needed and would just be a
   second code path proving the same thing.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0.

**Dispatch:** `agent (session-tier, high)` — the sequential-acceptance
design is a genuine addition beyond the pinned interface shape and
needs the same care as task 3.

---

### Task 5 — Dispute shell: `openDispute` and `resolve()` routing

**Goal:** the AF-4 dispute branch from decision 7 (zero-filings full
refund vs. one-or-more-filings per-duty bond fate — **not** a both-burn
unwind), the final short-circuit with the burn-ledger consult and
unaccounted-deposit refund, and the stub surfaces for P3.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `error NotYetBuilt();` at contract scope (decision 10).
2. `openDispute(bytes32 session) external`: `require(status == Active,
   "not open for dispute")`; `require(msg.sender == host || msg.sender
   == guest, "not a player")`; `status = Disputed`;
   `disputeOpenedAt = block.timestamp`. Emit `DisputeOpened(session,
   msg.sender, block.timestamp)`. (Calling it twice reverts on the
   `status == Active` check the second time — `Disputed` is not
   `Active` — no separate re-entry guard needed.)
3. `resolve(bytes32 session) external`:
   - `require(status == Active || status == Disputed, "nothing to
     resolve")`.
   - `finalEligible = highestFinalHash != 0 && highestFinalHand >=
     markedHand[session]` (decision 6's floor check, evaluated here,
     not at filing time).
   - **If `finalEligible`:** compute (using the cached
     `highestFinal*` fields from task 3):
     - `unaccountedHost = depositedHost - highestFinalHostDeposit`
       (non-negative: deposits are monotonic, and the cached deposit
       field is always ≤ the total at *filing* time, itself ≤ the
       total now).
     - `unaccountedGuest = depositedGuest - highestFinalGuestDeposit`.
     - `hostPayout = highestFinalHostStack + unaccountedHost +
       (hostBurned ? 0 : bondHost)`.
     - `guestPayout = highestFinalGuestStack + unaccountedGuest +
       (guestBurned ? 0 : bondGuest)`.
     - `credits[host] += hostPayout; credits[guest] += guestPayout;`
     - `paidOut[session] += hostPayout + guestPayout` (task 6's
       invariant field).
     - `status = Closed`; emit `Settled(session, ...)`; return.
   - **Else require `status == Disputed`** (else revert "nothing to
     resolve" — no dispute open and no eligible final means there is
     truly nothing to do yet), **and require
     `block.timestamp >= disputeOpenedAt + window`** (else revert
     "window open", V1's exact phrasing at `Channel.sol:155,160`).
   - **If `markedHand[session] > 0`:** `revert NotYetBuilt();` — the
     marked-live-hand §5.3 table is P3/P4's. (Check this first: the two
     branches below only apply at `markedHand == 0`.)
   - **If `!everReceipted[session]` (zero filings, decision 7 row 2,
     AF-4):** `credits[host] += depositedHost + bondHost;
     credits[guest] += depositedGuest + bondGuest;` update
     `paidOut[session]` by the same total; `status = Closed`; emit
     `Settled`; return. Full refund, no burn — spec's "one new pre-play
     branch," and per AF-4 this is now the *only* branch that returns
     both bonds unconditionally.
   - **Else (`everReceipted[session]` true, `markedHand[session] ==
     0`, decision 7 row 3, AF-4 — one or more filings, per-duty bond
     fate, NOT a both-burn):** `credits[host] += depositedHost;
     credits[guest] += depositedGuest;` (the only reachable receipt
     here is `(0,0)`, where `stack == deposit`, so this is a plain
     wash, not a redistribution); then, independently for each player:
     `if (hostFiledInWindow[session]) { credits[host] += bondHost; }
     else { _burnBond(session, true); }` (symmetric for guest — task 3
     step 7 is what sets `hostFiledInWindow`/`guestFiledInWindow`).
     Update `paidOut[session]` by whatever was credited (deposits plus
     any returned bonds — burned bonds go through `_burnBond` into
     `burned[session]`, never `paidOut`); `status = Closed`; emit
     `Settled`; return. **Do not** write a path that burns both bonds
     together here — that was this doc's original design and AF-4
     struck it as spec §1.3's both-burn branch being unreachable dead
     code in V2 (a begun-but-unfiled session is observationally
     identical to never-started, so bond fate must follow individual
     conduct, per spec §1.0, all the way down — see decision 7 for the
     full reasoning).
4. Stub the rest of the dispute-filing interface (artifact-formats §9)
   exactly as named there, each reverting immediately:
   `fileActions(bytes32, Act[] calldata, bytes[] calldata) external
   pure { revert NotYetBuilt(); }`,
   `postShares(bytes32, SharePost[] calldata) external pure { revert
   NotYetBuilt(); }`,
   `phase2Act(bytes32, Act calldata, bytes calldata) external pure {
   revert NotYetBuilt(); }`. Declare the `SharePost` struct exactly as
   formats §9 spells it out; **`Act` is not spelled out in §9** —
   derive its fields from formats §5's signed-action field list
   (`hand`, `seq`, `action`, `amount`, `prev` — the preimage fields,
   not the signature bytes, which stay a separate `bytes[]` /
   `bytes calldata` parameter per §9's shape). P3 needs the ABI to
   exist even though the bodies are empty — this is the "interface
   exists, bodies come later" contract the phase brief asks for.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0, and `grep -c "NotYetBuilt" contracts/src/ChannelV2.sol`
returns at least 4 (the error declaration + 3 stub calls; `resolve`'s
own stub branch may share the same literal call site count check —
adjust the exact number to whatever the implementation lands on, but
the probe must find every one of `fileActions`/`postShares`/
`phase2Act`/`resolve`'s marked-hand branch reverting with it).

**Dispatch:** `agent (session-tier, high)` — this is the seam
`REVIEW-BRIEF.md` names as the closest thing to a regime-collision risk
in the whole plan; the routing logic ties every earlier task together
and is exactly what P3 inherits.

---

### Task 6 — Pull-payment, burn ledger, and the accounting invariant

**Goal:** `credits`/`withdraw`, wiring up the (task-1-declared)
idempotent `_burnBond` primitive (decision 8), and the per-session
`depositsIn + bondsIn == paidOut + burned` bookkeeping the tests
assert.

**Files:** `contracts/src/ChannelV2.sol`.

**Steps:**
1. `mapping(address => uint256) public credits;` (global, not
   per-session — ETH is fungible; the *invariant* is what's per-session,
   not the pull-payment ledger itself. Spec §1.4: "Per-session
   accounting only. Never read `address(this).balance`" — this governs
   how payouts are *computed*, task 5 already does that from
   `s.buyIn`-equivalent stored fields, never `address(this).balance`.
   `credits` accumulating across sessions for the same address is fine
   and is what V1 lacks and §9.3 asks P2 to add.)
2. `withdraw() external`: `uint256 amt = credits[msg.sender];
   require(amt > 0, "nothing to withdraw"); credits[msg.sender] = 0;`
   then the same checks-effects-interactions pattern V1's `_pay` uses
   (`Channel.sol:172-175`) — zero the ledger *before* the external
   call, `(bool ok,) = msg.sender.call{value: amt}(""); require(ok,
   "transfer failed");`. This is what fixes spec §9.3's "one reverting
   payee kills the whole payout" — a stuck withdrawer no longer blocks
   `resolve()`.
3. **`_burnBond` is not this task's to write** — it was pre-declared in
   task 1 (step 11, task-ordering note) precisely so task 5's
   `resolve()` can call it without a forward reference. This task only
   *consumes* it: nothing here redeclares or edits it.
4. `burned` and `paidOut` are per-session `uint256` fields already
   declared in task 1's struct; every code path in task 5 that credits
   a payout increments `paidOut[session]` by the same amount, and every
   `_burnBond` call (task 1, called from task 5) is the only way
   `burned[session]` grows. No other function writes either field —
   this is what makes the invariant testable as a pure function of the
   two.
5. Code comment stating the invariant verbatim, citing spec §1.4:
   `depositedHost + depositedGuest + bondHost + bondGuest ==
   paidOut[session] + burned[session]`, asserted once a session reaches
   `Closed` (never mid-session — a session mid-dispute has neither
   number final yet).

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

YES/NO: exits 0. (Task 9's `test_F15_3_idempotent_burns` and the
invariant assertion inside task 8's happy path are the functional
probes.)

**Dispatch:** `agent (workhorse, high)` — mechanical given tasks 1–5
already pinned the design, but it is money-movement code and the
checks-effects-interactions ordering is exactly what V1's own
reentrancy test (`Channel.t.sol:377-395`) exists to catch — get it
right the first time.

---

### Task 7 — `DeployV2.s.sol`: chain-id guard and D15 durations

**Goal:** a deploy script mirroring `Deploy.s.sol`'s chain-id refusal,
taking window/bank/grace as constructor args, asserting the spec's
default values unless a test-durations override is explicit (D15), plus
a forge test proving the D15 guard actually fires (fix round 1, B7).

**Files:** `contracts/script/DeployV2.s.sol` (new),
`contracts/test/DeployV2.t.sol` (new).

**Steps:**
1. Mirror `Deploy.s.sol`'s structure exactly: `import {Script,
   console2} from "forge-std/Script.sol";`, `contract DeployV2 is
   Script`, the same `BASE_SEPOLIA = 84532` / `ANVIL_LOCAL = 31337`
   constants and the same `require(block.chainid == BASE_SEPOLIA ||
   block.chainid == ANVIL_LOCAL, "refusing to deploy: ...")` guard
   verbatim (D11).
2. Spec defaults as named constants: `WINDOW_DEFAULT = 24 hours`,
   `BANK_DEFAULT = 6 hours`, `GRACE_DEFAULT = 6 hours` (D15, spec §5.1/
   §5.2/§5.3's 24h/6h/6h figures — `86400`/`21600`/`21600` seconds).
3. Read overrides via `vm.envOr`, same idiom as `Deploy.s.sol:22`:
   `uint256 window = vm.envOr("WINDOW_SECONDS", WINDOW_DEFAULT);` (and
   `BANK_SECONDS`, `GRACE_SECONDS` likewise).
4. **The D15 assertion:** `bool testDurations = vm.envOr("TEST_DURATIONS",
   false); if (!testDurations) { require(window == WINDOW_DEFAULT &&
   bank == BANK_DEFAULT && grace == GRACE_DEFAULT, "refusing to deploy
   non-spec durations without TEST_DURATIONS=true"); }`. **Deviation
   from the phase brief's literal wording**, stated plainly: D15 says
   "unless an explicit `--test-durations` flag is passed" — `forge
   script` has no custom-flag parser (V1's own `Deploy.s.sol` only ever
   reads env vars, never a bespoke CLI flag), so this phase implements
   the override as `TEST_DURATIONS=true` in the environment, the exact
   mechanism `Deploy.s.sol` already uses for `WINDOW_SECONDS`. Same
   spirit, same idiom, no new deploy-tooling surface.
5. `console2.log` each duration and whether `TEST_DURATIONS` is set,
   so "P7's deploy prints which duration set each instance carries"
   (D15) is satisfied.
6. `vm.startBroadcast(pk); ChannelV2 channel = new
   ChannelV2(window, bank, grace); vm.stopBroadcast();`
7. **D15 guard test (fix round 1, B7) — new file
   `contracts/test/DeployV2.t.sol`.** A `forge-std` `Test`, mirroring
   `Channel.t.sol`'s `setUp` style: `vm.chainId(ANVIL_LOCAL)` (31337,
   set **explicitly** rather than assumed from Foundry's default test
   chain id — this is the one place this doc would otherwise make an
   unverified world-facing claim, so it names a one-line probe instead:
   the explicit call, not an assumption). `vm.setEnv("PRIVATE_KEY",
   vm.toString(uint256(0xA11CE)))` (or any nonzero key) and the
   duration env vars, then instantiate `DeployV2` and call `.run()`
   twice:
   - **(a) non-spec duration reverts:** `vm.setEnv("WINDOW_SECONDS",
     "3600")` (anything ≠ `86400`), `TEST_DURATIONS` unset →
     `vm.expectRevert("refusing to deploy non-spec durations without
     TEST_DURATIONS=true")` — copy step 4's exact string via a shared
     constant or direct reference, don't retype it by hand, so a future
     edit to one can't silently diverge from the other.
   - **(b) the complement:** spec defaults (`WINDOW_SECONDS=86400`,
     `BANK_SECONDS=21600`, `GRACE_SECONDS=21600`), `TEST_DURATIONS`
     unset → `run()` succeeds; assert the deployed `ChannelV2`'s
     constructor-stored durations read back the spec defaults (add
     public getters in task 1 if the immutable fields aren't already
     public — `window()`/`bank()`/`grace()`).

**Files (this step only):** also touches `contracts/test/DeployV2.t.sol`
(new) — added to the top-level Files touched list.

**Verification probe:**

    ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts
    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract DeployV2Test -vv

YES/NO: build exits 0; the script does not import or reference
`Channel.sol`/`Deploy.s.sol` at all (`grep -n "Channel\.sol\|Deploy\.s\.sol"
contracts/script/DeployV2.s.sol` returns nothing — confirms D11's
untouched-V1 boundary at the file level); both `DeployV2Test` cases
pass (non-spec-duration revert with its exact string, spec-duration
complement succeeds and reads back the defaults).

**Dispatch:** `agent (workhorse, medium)` — closely mirrors an existing
file, and step 7's guard test is mechanical (two `run()` calls, one
expected to revert) once steps 1–6 are done; no new judgment beyond
decision 10's already-resolved deviation.

---

### Task 8 — Tests: constructive happy path + fixture re-derivation report

**Goal:** one end-to-end Foundry test proving the whole money frame
composes (open → join → (0,0) → routine per-hand markers → a `final` →
`resolve()` → `withdraw()`, invariant holds throughout), **and** the
mandated re-derivation of the fixture class from the parking doc.

**Files:** `contracts/test/ChannelV2.t.sol` (new).

**Steps:**
1. **Vector copy + parity ownership (D16/D18, fix round 1 B4) — P2
   owns this, not a P1 responsibility once the file lands.** Copy
   `src/vectors/p1-vectors.json` and `src/vectors/Vectors.sol` from the
   poker repo (`~/projects/poker` — confirm the actual path/branch
   against P1's shipped phase doc, since P1's D16 revision is landing
   concurrently with this one) into `contracts/test/vectors/` in this
   repo. Read the two sha256 hashes P1 recorded in its task-10 commit
   message (the commit that ships `src/vectors/*`) and write them into
   `contracts/test/vectors/CHECKSUMS.sha256` in standard `sha256sum`
   format (`<hash>  p1-vectors.json` / `<hash>  Vectors.sol`, two
   spaces, filenames relative to that directory). Commit the checksums
   file alongside the copied vectors, not regenerated at gate time — a
   hash regenerated from the copy would trivially match itself and
   prove nothing about parity with P1's original. Phase-boundary gate 7
   verifies this file against the copies with `sha256sum -c`.
2. **Construct from the committed shared vectors, not from scratch**
   (D16). Build the happy path's receipts/markers/signatures by
   **reading vectors out of** `contracts/test/vectors/p1-vectors.json`
   (step 1's copy) — not by hand-deriving preimages and calling
   `vm.sign` for every artefact as this doc originally specified. Keep
   a `_sigRaw(uint256 pk, bytes32 digest)` helper (no EIP-191 prefix —
   signs the raw digest directly with `vm.sign`, mirroring
   `Channel.t.sol:41-46`'s `_sig` but without the
   `keccak256(abi.encodePacked("\x19...", ...))` wrapping step) and a
   `_sigEIP191(uint256 pk, bytes32 digest)` helper (keeps that
   wrapping, for registration sigs) **only** for cases the vector set
   cannot cover: negative and mutation tests (task 9) that deliberately
   sign something wrong, out of order, or malformed — a vector, by
   construction, is always a *valid* artefact. These two helpers are
   what every negative test in task 9 reuses, so build them carefully
   here regardless. **D18, stated hard: there is no fallback here.** A
   happy-path construction that cannot resolve the vectors (file
   missing, hash mismatch, `p1-vectors.json` not yet shaped as this
   task expects) is a recorded **gate FAILURE** at phase-boundary gate
   7 that halts the phase — not a "build it with `vm.sign` instead and
   note the gap" pass, which this doc originally specified and D18
   struck. If P1 genuinely hasn't landed the vectors when this task is
   dispatched, that is a sequencing problem to raise to the operator
   (Open questions, item 4), not something this task papers over by
   itself.
3. Happy path, one test function: host and guest addresses via
   `vm.addr`, session keys as a *separate* keypair per player
   (`vm.addr(hostSessionPk)` distinct from the wallet address — this
   is the whole point of D2, don't accidentally sign with the wallet
   key where a session key is required). `open()` with the exact
   `maxHost`/`maxGuest` numbers `p1-vectors.json` uses (read them from
   the vector file, don't pick independent round numbers — the numbers
   in this test and the numbers in the vector file must not silently
   diverge), `join()`, then the vector receipt `(0,0)` (already signed
   with both session keys, per the vector file), `fileMarkerWithReceipt`
   for hand 1 (co-filed, per decision 5), a second marker for hand 2
   (co-filed with a receipt closing hand 1), then a `final` receipt at
   `(2, 0)` naming redistributed stacks — all sourced from the vector
   file — `fileReceipt`, `resolve()`, `withdraw()` for both players,
   and assert final balances match `hostPayout`/`guestPayout` computed
   by hand plus the invariant from task 6 (`depositedHost +
   depositedGuest + bondHost + bondGuest == paidOut + burned`, with
   `burned == 0` on this path).
4. **Fixture re-derivation (D12, mandatory, not optional):** run

       grep -n "^### Findings" /home/dev/projects/vault/docs/superpowers/parking/v2-cash-game-settlement.md

   then read every finding from the section starting `## Tenth cold
   check` (confirmed at line 1601 as of this doc's drafting — re-grep,
   don't trust the cached line number) through the end of the file,
   independently building the list of every constructed case that
   belongs to P2's scope (settlement, receipts, the bond, deposits,
   marker acceptance, `final` ordering/terminality, the burn ledger,
   the zero/one-filing dispute branch). **Diff this list against
   `fixtures-index.md`'s P2 rows** (as amended for AF-4 — confirm the
   current row set at read time rather than trusting this list:
   `F10.2, F10.3, F10.4, F10.6, F11.3, F15.3,
   S_zero_filings_full_refund, S_one_filing_perduty_bonds,
   S_bond_coverage_maxima, S_marker_catchup`). Report the enumeration
   in the task's completion notes: confirm each index row is still
   present in the parking doc as read, and flag — as a plan finding,
   not a silent addition or silent drop — any case the re-derivation
   finds that the index lacks, or any index row the re-derivation can
   no longer locate a constructed case for. **Two drifts are already
   known and resolved, not open** — carry them forward into the report
   rather than re-discovering them: the `200/1800` numbers predate the
   marker rewrite (decision 7), and the both-burn §1.3 branch those
   numbers described is superseded by AF-4's per-duty ruling (also
   decision 7). Still complete the full sweep independently — AF-4
   resolved *these two*, not "re-derivation is no longer needed."

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test --match-test test_happyPath -vv

YES/NO: the named test passes, and the completion notes contain the
fixture-enumeration report (present/absent per row, any drift flagged).

**Dispatch:** `agent (workhorse, high)` — long, multi-step construction
following an established pattern (`Channel.t.sol`), plus a literal
grep-and-read task; not architecture-inventing, but long and exacting.

---

### Task 9 — Tests: negative-require sweep + fixtures-index P2 rows

**Goal:** every `require`/custom-error path in `ChannelV2.sol` has a
negative test, plus the ten fixtures this phase owns
(`test_F10_2_marker_blocks_stale_settlement`,
`test_F10_3_final_ordered_terminal`,
`test_F10_4_declared_depth_rebuys`,
`test_F10_6_never_started_full_refund`,
`test_F11_3_marker_sequencing`,
`test_F15_3_idempotent_burns`,
`test_S_zero_filings_full_refund`, `test_S_one_filing_perduty_bonds`,
`test_S_bond_coverage_maxima`, `test_S_marker_catchup` — exact names
from `fixtures-index.md` as amended for AF-4; confirm the current row
set at implementation time).

**Files:** `contracts/test/ChannelV2.t.sol`.

**Steps:**
1. Negative tests are built with `vm.sign`, not vectors (D16, task 8
   step 1 — vectors are always valid artefacts by construction, so
   every deliberately-broken signature/order/amount here is hand-built).
   Enumerate every `require(cond, "...")` and the `NotYetBuilt` reverts
   added across tasks 1–6 (`grep -n 'require(' contracts/src/ChannelV2.sol`
   after task 6 lands) and write one `vm.expectRevert("<exact string>")`
   test per condition, following `Channel.t.sol`'s naming convention
   (`test_<function>_<condition>_reverts`). Include, at minimum: wrong
   opponent/self at `open`; `msg.value < bond` at `open`/`join`; past
   declared max at `open`/`join`/`deposit`; non-invited `join`; both
   malleability directions (`_recoverRaw` **and** `_recoverEIP191`,
   task 8's two `vm.sign` helpers) — the raw-digest path needs its own
   high-`s` flip test, distinct from V1's, since it's genuinely new
   code (decision 9); stale-order/continuity failures in `fileMarker`;
   `resolve()` called with `window open`; `resolve()` on an already-
   `Closed` session; the three `NotYetBuilt()` stubs.
2. `test_F10_2_marker_blocks_stale_settlement`: file receipt N−1 as
   `final`, confirm marker N (co-filed with a *different*, non-final
   receipt at N−1 first, or via a plain hand-progression sequence),
   call `resolve()`, assert it reverts `NotYetBuilt()` (decision 6/7's
   floor logic routes here, not to a silent no-op).
3. `test_F10_3_final_ordered_terminal`: file `final` at `(5,0)`, then a
   higher `final` at `(10,0)`, `resolve()`, assert payout used the
   `(10,0)` numbers; separately assert a call to `resolve()` (or any
   filing function) after `status == Closed` reverts.
4. `test_F10_4_declared_depth_rebuys`: `deposit()` up to exactly `M_i`
   succeeds; one wei past it reverts "past declared max"; a deposit
   never named by any filed receipt is refunded via the
   `unaccountedHost`/`unaccountedGuest` path at settlement (assert the
   payout includes it).
5. `test_F10_6_never_started_full_refund`: `open`, `join` (deposits
   recorded), `openDispute`, `vm.warp` past window, **no** marker, no
   receipt ever filed, `resolve()`, assert both players' `credits`
   equal `deposit + bond` in full (no burn). This is decision 7's
   zero-filings row — the same code path `test_S_zero_filings_full_refund`
   (step 8 below) exercises with different numbers; keep both, they pin
   the same rule from two different fixture lineages (F10.6 from the
   parking doc, S_zero_filings from AF-4).
6. `test_F11_3_marker_sequencing`: post marker 1, attempt to post
   marker 1 again (duplicate) → reverts "not next hand"; post marker 3
   before marker 2 exists → same revert; confirms `liveHand()` reflects
   only confirmed markers.
7. `test_F15_3_idempotent_burns`: via the test-only harness from
   decision 8, call `_burnBond(session, true)` twice for the same
   session; assert `burned[session]` increased only once by
   `bondHost`, and a subsequent settlement path correctly excludes that
   bond exactly once (not double-subtracted anywhere).
8. `test_S_zero_filings_full_refund` (replaces this doc's original
   `test_S_unwind_never_pays` — AF-4 struck the both-burn branch it was
   testing): equal declared maxima 1000/1000, bonds 1100/1100, both
   deposit, both sign `(0,0)` off-chain, marker for hand 1 **never**
   confirms, `openDispute`, window closes, **nobody files anything at
   all** → `resolve()` credits each player `deposit + bond` in full
   (`1000 + 1100` each). This is the zero-filings row of decision 7's
   table.
9. `test_S_one_filing_perduty_bonds` (the second replacement fixture) —
   **both directions** (fix round 1, M3: swap seat roles so per-duty
   bond fate is tested for host-files/guest-silent **and**
   guest-files/host-silent, not just one, since a test that only ever
   exercises the same seat as "the filer" cannot catch a bug that
   accidentally hardcodes host-favoring logic in `resolve()`'s branch):
   - **(a) host files, guest silent:** same setup as step 8, except
     host files `(0,0)` on chain before the window closes, guest files
     nothing for the entire window. `resolve()` must credit: both
     players their own deposit (`1000` each, the wash — `(0,0)`'s
     stack equals its deposit); host's bond back in full (`1100` —
     they performed the filing duty); guest's bond burned via
     `_burnBond` (`burned[session] == 1100`, guest absent the full
     window — spec §8.2's declared cost).
   - **(b) guest files, host silent (the swap):** identical setup, seat
     roles reversed — guest files `(0,0)`, host files nothing.
     `resolve()` must credit symmetrically: both deposits back, guest's
     bond back in full, **host's** bond burned. Run as a second session
     (fresh `bytes32` id) in the same test function, not a copy-pasted
     second test, so both directions share the same assertions helper
     and can't silently drift apart.

   Assert **no strategy beats honest play at any `(M_host, M_guest)`**
   — structurally, not by trying alternatives: at `markedHand == 0` the
   only reachable
   receipt is `(0,0)`, where `stack == deposit` for both players by
   definition (task 3 step 3's invariant, evaluated at the one receipt
   this branch can ever see), so there is no stack disparity reachable
   at this state for either player to extract via timing or refusal —
   the assertion is that this holds *by construction*, not a search
   over adversarial numbers. State this reasoning as a code comment,
   not just an assertion.
10. `test_S_bond_coverage_maxima`: `maxHost = 1500, maxGuest = 500`,
    assert `bondHost == 1650` and `bondGuest == 1100` immediately after
    `open()`/`join()` (decision 1's worked case, matches the parking
    doc exactly — no drift here, record that in the completion notes
    as a confirmed-sound pin, not a finding).
11. `test_S_marker_catchup` (decision 5's addendum): play/skip hands so
    that markers 1–2 confirm normally, then hands 3–5 happen off-chain
    with **no** on-chain marker for any of them (a modified client pair
    skipped routine posting). Then file markers 3, 4, 5 **in
    sequence**, each co-filed with its matching receipt for continuity
    (catch-up needs no dispute per decision 5, so this can run with or
    without one open). Assert **all three are accepted** (`liveHand()`
    ends at 5) — this is the *acceptance* case `test_F11_3` doesn't
    cover (F11.3 only tests rejection of duplicates/out-of-order
    markers); this fixture is the positive counterpart.

**Verification probe:**

    ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts --match-contract ChannelV2Test -vv

YES/NO: all tests pass (happy path from task 8 plus every test added
here); zero `require` in `ChannelV2.sol` lacks a corresponding
`vm.expectRevert` test (spot-checkable via
`grep -c 'require(' contracts/src/ChannelV2.sol` vs. a count of
`vm.expectRevert` calls in the test file — they need not be 1:1
exactly, since some requires share a test, but a large gap is a signal
to re-check).

**Dispatch:** `agent (workhorse, high)` — long and exacting, follows
task 8's established helpers, but the fixture constructions
(especially `test_S_one_filing_perduty_bonds`'s structural no-strategy
assertion) need real care, not mechanical translation.

## Phase-boundary verification

All gates are `technical-auto` — every probe below is runnable as
written against this phase's own artifacts, with no dependency on P3 or
any later phase (P3's `NotYetBuilt` stubs are asserted *as reverts*,
which is a P2-local fact, not a claim about P3's eventual behavior).
**One exception, introduced by D16/D18 (fix round 1):** gate 7 depends
on P1's task-10 vector commit having landed in the poker repo — this is
a genuine cross-phase dependency the ruling accepts, not an oversight;
Open questions item 4 covers when to dispatch task 8 relative to it.

1. **Build.**

       ~/.foundry/bin/forge build --root /home/dev/projects/vault/contracts

   YES/NO: exits 0.

2. **Full test suite, both contracts.**

       ~/.foundry/bin/forge test --root /home/dev/projects/vault/contracts -vv

   YES/NO: exits 0; `Channel.t.sol`'s 26 existing tests still pass
   (V1 untouched — D11; a checker ran the suite and confirmed 26, not
   this doc's earlier miscount of 24) **and** every `ChannelV2.t.sol`
   test from tasks 8–9 passes.

3. **V1 file-level isolation** (D17, fix round 1: base-ref diff, not
   `--stat`, which is vacuous once committed — D13's flow).

       git -C /home/dev/projects/vault diff <PHASE-2-BASE-SHA>..HEAD -- contracts/src/Channel.sol contracts/test/Channel.t.sol contracts/script/Deploy.s.sol

   YES/NO: empty output (no changes to any V1 file since this phase's
   base commit — D11/D13 literally enforced, not just claimed).
   `<PHASE-2-BASE-SHA>` is recorded in the task-ordering note above.

4. **Stub surface exists and is named correctly** (fix round 1, P2-1: a
   bare occurrence count can pass while the one branch that matters is
   missing — checked per surface below, not by count).

       grep -n "NotYetBuilt" /home/dev/projects/vault/contracts/src/ChannelV2.sol

   YES/NO, confirmed individually, not as a total: `error
   NotYetBuilt();` is declared exactly once, and each of these four
   call sites reverts with it — `fileActions`, `postShares`,
   `phase2Act`, **and, named explicitly, `resolve()`'s
   `markedHand[session] > 0` branch** (grep for the literal
   `markedHand[session] > 0` line in the output above and confirm the
   next `revert` inside that branch is `NotYetBuilt()` — a stub that
   dropped the `resolve()` branch but padded a comment elsewhere would
   still clear a bare "≥4 occurrences" count, which is exactly the gap
   this reformulation closes).

5. **Fixture re-derivation report exists.** YES/NO: task 8's completion
   notes contain the enumerated diff against `fixtures-index.md`'s P2
   rows (present in the record even if the answer is "no drift found
   beyond what this doc already flagged").

6. **Gas sanity on the routine per-hand path (non-blocking, informational).**
   `forge test -vvvv --match-test test_happyPath` and read the gas
   report for the `fileMarkerWithReceipt` call; compare informally
   against §11.2(a)'s measured 61,740 gas for "marker + co-filed
   receipt calldata." Not a pass/fail gate — the prototype and this
   contract are different code — but a large divergence (order of
   magnitude) is worth a note to the operator before P7's live sweep.

7. **Vector parity (D16/D18, fix round 1 B4) — hard fail, no fallback.**

       cd /home/dev/projects/vault/contracts/test/vectors && sha256sum -c CHECKSUMS.sha256

   YES/NO: both `p1-vectors.json` and `Vectors.sol` report `OK` against
   the hashes P1 recorded in its task-10 commit message (task 8 step 1
   wrote them into `CHECKSUMS.sha256` at copy time). A mismatch, or
   either vector file or `CHECKSUMS.sha256` itself missing, is a gate
   **FAILURE** that halts the phase — this doc carries no fallback-pass
   wording anywhere anymore; `vm.sign` covers negative/mutation tests
   only (task 9 step 1), never a happy-path substitute for an
   unresolved vector file.

## Outputs to next phase

Mirrors P3 and P5's stated dependency on P2 (README.md's sequencing
table).

- **To P3 (disputes-evidence):** `ChannelV2.sol` with `openDispute`,
  the AF-4 zero-filings/per-duty branches at `markedHand == 0`
  (decision 7 — **not** a both-burn §1.3 branch, which is struck), and
  four `NotYetBuilt()`-reverting surfaces (`resolve`'s marked-live-hand
  branch, `fileActions`, `postShares`, `phase2Act`) whose signatures
  are frozen (`SharePost` spelled out verbatim in artifact-formats §9;
  `Act` derived from §5's field list — a decision-level note, not a §9
  literal). P3 replaces the stub *bodies* only — no interface churn,
  per the phase brief's explicit requirement. P3 also inherits
  `receiptAt`, `markedHand`, `hostFiledInWindow`/`guestFiledInWindow`
  (AF-4's per-duty presence tracking — P3's own duty tracking for
  markers/actions/shares can extend the same pattern rather than
  inventing a new one), `_burnBond`, `credits`, `paidOut`, and `burned`
  as the storage surface its consolidation and resolution-table logic
  reads and writes.
- **To P5 (buyin-ui):** the Session interface exactly as
  artifact-formats §9 pinned it (no additions beyond
  `fileMarkerWithReceipt`, itself additive, not a breaking change to
  the pinned shapes), the bond formula (decision 1, for the "show the
  bond with its consequence attached" UI obligation, spec §2.1), and
  **the two-transaction good-ending flow** (decision 4: file the
  `final`, then call `resolve()` — P5's UI needs to drive both, not
  assume V1's single-call `closeCooperative` pattern carries over).
- **Contract address / ABI:** none yet — deployment is P7 only (D11/
  D13). P5 builds against the compiled ABI in `contracts/out/` after
  this phase's `forge build` succeeds.
- **`TBD-P1-VECTORS`:** live dependency, not unused (corrected, fix
  round 1 B4 — this doc originally said the opposite). P2 owns the
  D16/D18 copy (task 8 step 1, `contracts/test/vectors/`) and its
  `sha256sum -c` gate (phase-boundary gate 7); P3 consumes **P2's
  landed copy**, re-running the same `sha256sum -c` check per D18 —
  P3 does not re-copy from the poker repo itself.

## Open questions

1. **RESOLVED 2026-08-17 via `review-findings.md` AF-4 (orchestrator
   ruling).** This doc originally left the `200/1800` fixture-citation
   drift (decision 7) as an open question for task 8's re-derivation to
   settle. The orchestrator's ruling settled the substantive question
   it was standing in for — not just the numbers, but the *branch* they
   described (spec §1.3's both-burn unwind) is unreachable dead code in
   V2 and is replaced by the zero-filings/per-duty branch in decision 7.
   Task 8's re-derivation (step 3) still runs in full — AF-4 resolved
   this specific drift, not the general obligation to re-derive the
   whole fixture class.
2. **Two-transaction good ending (decision 4) vs. a single combined
   `fileReceiptAndResolve` convenience function.** Default: ship the
   two-call version as specified — it matches the interface doc's
   `resolve()` semantics literally and keeps `fileReceipt` a pure
   store-and-verify function, simplifying every other task's reasoning
   about what filing can and cannot do. **Overrules:** the operator, if
   P5's UX work finds the two-call round trip materially worse than
   expected once real wallet-confirmation latency is felt — P5 can
   still call `fileReceipt` then `resolve()` back-to-back in one UI
   flow without a contract change, so this is a low-cost default to
   revisit later, not a one-way door.
3. **`credits` as a global (not per-session) mapping.** Default: as
   designed (decision 6/step 1) — simpler, and the per-session
   *invariant* still holds because `paidOut`/`burned` are per-session
   and computed without ever reading `address(this).balance`.
   **Overrules:** the operator, only if a concrete cross-session
   accounting bug surfaces during P3/P4's work that a per-session
   ledger would have caught structurally.
4. **D16/D18 vector-file landing order — no fallback, per fix round 1.**
   Task 8/9's construction depends on P1's vector generator (D16) being
   synced into this repo, and P2 now owns copying and gating that
   parity itself (D18: task 8 step 1's copy, phase-boundary gate 7's
   `sha256sum -c`). There is **no** fallback path anymore — a missing
   or mismatched vector file when this task is dispatched is a gate
   **failure** that halts the phase, not a `vm.sign`-built substitute
   (this doc's earlier fallback wording is struck, per D18). Default:
   dispatch task 8 only once P1's task 10 (the vector-generator commit)
   has actually landed in the poker repo — check before dispatching,
   don't discover the gap at gate 7. **Overrules:** the operator, only
   to decide *when* to dispatch task 8 relative to P1's progress; the
   no-fallback rule itself is D18 and is not open to a phase-level
   override.

## Recovery

If this phase is interrupted mid-task: tasks 1–6 build strictly on
each other's storage additions (task 1's struct is meant to be
declared complete up front, per task 1 step 3, precisely so a
half-finished task 4 doesn't force a task 1 storage rewrite). A resumed
session should `~/.foundry/bin/forge build --root
/home/dev/projects/vault/contracts` first — a clean build tells you
which of tasks 1–7 landed; then `grep -n "function \|error \|struct "
contracts/src/ChannelV2.sol` against this doc's task list to find the
first missing surface. Tasks 8–9 are additive to the test file only and
can restart from a clean `forge test` run regardless of where they
stopped — no test-file state depends on partial completion of another
test. If `contracts/src/Channel.sol`, `contracts/test/Channel.t.sol`,
or `contracts/script/Deploy.s.sol` show *any* diff
(`git status --short -- contracts/src/Channel.sol
contracts/test/Channel.t.sol contracts/script/Deploy.s.sol`), stop and
ask — D11/D13's untouched-V1 boundary was violated and that is a
revert-the-edit conversation, not a continue-working one.
