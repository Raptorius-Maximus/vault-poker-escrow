# V2 cash settlement — findings ledger

Numbered findings against this arc's plan and execution. Sources: the
cold bet review, phase-doc checkers, the cold adversarial plan review,
execution-time findings routed per arc-run, and the arc-end walkthrough.
Format: `AF-<n>` (arc finding), dated, with status.

**AF-1 — Cold bet review, 2026-08-17 — verdict: proceed with three named
changes.** Caught: (1) the betting-replay engine straddled P3/P4 — P3's
consolidation needs action legality, so P3 could not have passed its own
gate as sliced; now assigned to P3, reused by P4. (2) P5 was waved beside
P3 but needs P3's contract entry points — the dispute-filing interface is
now pinned in `artifact-formats.md` (its §Interface). (3) P7's live
dispute sweep vs the 24-hour window was undecided — resolved as D15
(parameterized durations, production values asserted at deploy). Also
confirmed: the slicing isolates the hard part; the strongest alternative
(happy-path first, disputes later) fails because every interim dispute
rule is one the checks already killed; D12 called "the best idea in the
plan". Cost: one agent run, ~2 minutes. Status: all three applied.

**AF-2 — Formats-doc checker, 2026-08-17 — verdict: PASS WITH FIXES (all
applied).** Caught: (1) "turn alternation makes every node single-key" was
a false rationale — same seat acts consecutively across street boundaries
(`betting.ts:56,169,196`); a parity-based validator would reject honest
chains, and the prototype vectors' `seq % 2` signer actively reinforced
the wrong model. Rule survives (unique actor per node via replay);
wording fixed in formats §5 and spec §3, which also carried the stale
"longest-wins" phrase from rev 3 in §9.20. (2) The interface section
omitted the open/join shapes carrying session-key registration — added
as the Session interface (host proposes both declared maxes; guest
accepts by joining). (3) V1's `_recover` prefixes every signature, so
the raw-digest session-key path is new code — noted so P2/P3 don't
"reuse" it. Confirmed exactly: DLEQ challenge, Merkle rules, the three
prototype deltas, alphabet/amount semantics, ciphertext shapes, spec
field lists, width arithmetic, domain non-collision. Cost: one agent
run, ~4 minutes.

**AF-3 — P1 checker, 2026-08-17 — verdict: REVISE (7 items, in revision).**
Factual layer fully clean: ~20 line citations exact, noble v2 v-first
layout independently reproduced over 300 signatures, MDN worker-storage
claim fetched and confirmed, all five format layouts field-exact, 278-test
baseline confirmed by the checker's own run. Catches: a wrong test-file
list in task 4 (two regex-test files named, the real `live.test.ts`
omitted); task 9's grep probe targeting a file no task instructs to
comment; a sequential-reading gap in task 7's comment instruction; two
doc-acknowledged-but-uncommitted forward references (tasks 4/5 → 8);
dual unreconciled baselines; one overclaiming citation. Plus the expected
D16 rewrite. Revision continuation sent to the original drafter.

**AF-4 — P2 checker + orchestrator ruling, 2026-08-17 — verdict: REVISE
(in revision).** Checker: one BLOCKER (task 5 calls `_burnBond` before
task 6 declares it — its own build probe cannot pass; resequence), two
citation/count fixes, task-1 tripwire confirmed split-feasible, the
marker catch-up path real-but-undocumented, plus the expected D16
rewrite. **Confirmed sound:** the drafter's derivation that §1.3 is
reachable only at markedHand==0; bond rounding never under-covers across
8 adversarial recomputations; sequential marker acceptance satisfies
both §4 rules. **Orchestrator ruling on the §1.3 branch** (supersedes
both the doc's reconstruction and the checker's proposed wording): at
zero filings, "session begun" is unattestable — zero filings ⇒ full
refund including bonds (never-started semantics); any filing ⇒ §5.4
settlement with per-duty bond fate. The spec's §1.3 both-burn branch is
unreachable dead code in V2's contract; no attack exists in either
direction (the ahead player's filing incentive was always the real
protection; a lone-(0,0) filer is made whole and only a full-window
absentee burns — the declared §8.2 cost). Fixtures-index rows replaced
accordingly. **Lineage note:** the sixteenth cold check's verified-sound
entry still cited the tenth check's pre-marker 200/1800 worked case —
a stale decoration on a conclusion that survives re-derivation (checker
and orchestrator re-derived independently, agreeing). Recorded in the
parking doc; the READY verdict is unaffected in substance. This is
REVIEW-BRIEF error-pattern #2 caught in the wild, by the layer built to
catch it.

**AF-5 — P5 checker, 2026-08-17 — verdict: REVISE (in revision).** One
BLOCKER: the operator-floor deploy command used forge's `--private-key`
flag, which the script never consumes (Deploy.s.sol reads
`vm.envUint("PRIVATE_KEY")` and broadcasts with an explicit key) — a
beginner operator would face an opaque cheatcode failure mid-smoke; fixed
to env-var form with a where-to-find-the-key sentence. Four MAJORs:
the "resent every hello cycle" justification overclaims (4 of 8 real
vault:* types resend; one type missed entirely) — **and the same
overclaim lives in V1's OVERVIEW.md:166-167, a pre-existing doc/code
drift now on record for the next docs-check sweep**; a bug-writeup
citation pointed at arc-history.md instead of the main.js code comment;
tasks 2‖3 claimed parallel while 3 reads 2's state in the same file; two
tasks disagreed over who adds the third build entry. Four minors
(citation pointers, one framing consistency, three uncited-but-true API
claims). Everything structural held: P2 call surface verbatim, AF-4
settlement states exact, evidence-bundle field orders exact, both new
TBD tokens judged correct handling.

**AF-6 — P3 checker, 2026-08-17 — verdict: REVISE (3 MAJOR, 4 MINOR, no
BLOCKER; in revision).** The plan's highest-stakes conformance HELD: the
betting-replay port verified line-by-line against betting.ts (blinds,
button order both streets, clamp block, short-all-in non-reopen,
check-raise, round closure), with the clamp→range-check translation
confirmed as a justified divergence. The Part A/B split ruling judged
sound; both disclosed P2 extensions confirmed genuinely necessary — the
checker independently established that P2's resolve() finalEligible
branch returns before the markedHand branch, making the F16.1/F16.3
composition gap real. MAJORs: a provenance overclaim ("as P2 shipped
them" — no ChannelV2.sol exists; P2 is a plan); combineShares cited at
elgamal.ts:71-74 three times (actual 76-79); D8's lowest-hash same-block
tiebreak unmapped. **Orchestrator ruling on the tiebreak:** first-stored-
wins subsumes it — EVM intra-block execution is strictly sequential, so
storage-arrival order is already total and no simultaneity survives to
the contract; the hash rule was written for consolidation conceived as
off-chain computation over timestamps. Stated as an explicit equivalence
note in the doc; no hash comparison implemented; the spec text stands
(the implementation is at least as deterministic). Four MINORs: line
count, remappings parenthetical, an overbroad split justification, and
the decode-fails-on-invalid-encoding edge now made explicit with its own
negative fixture.

**AF-7 — P6 checker, 2026-08-17 — verdict: REVISE (1 BLOCKER, 2 MAJOR,
4 MINOR; in revision).** BLOCKER: the phase's own `vaultVersion===2`
never enabled the vault seam — everything gates on `vaultOn`, which
`shouldEnableVault` returns only for `vault==='1'`, and task 1 both
forbade and (in Files-touched) claimed the fix; as specified, the
phase's entire message seam was dead code, including its own operator
floor step b. MAJORs: task 8's literal wording would have silently
reversed V1's operator-ratified whole-match grace-timeout rule
(poker@d66a68a) — caught against byte-for-byte parity; a false
jsdom/happy-dom claim for crypto.subtle (real source: Node ≥20 native
global; self-contradicted by task 4). Verified clean: all forfeit-site
citations, the vaultMaybeSign V1-only gate (all call sites covered, no
V2 path blocked), zero direct-RPC violations of the architecture rule,
P1/P5 conformance incl. TBD usage, the 278 baseline reproduced, the
retry mandate quoted verbatim, topology sound under the stated order.

**AF-8 — P4 checker, 2026-08-17 — verdict: REVISE (1 BLOCKER, 2 MAJOR,
2 MINOR; in revision).** The review's centerpiece HELD: the checker
derived readyTime cold from spec §5.2/§5.3 before reading the drafter's
definition, and the two derivations matched — including independent
first-principles confirmation that hole positions are correctly excluded
from the clock gate (gating on them would deadlock the bank clock, since
hole shares are unpostable until the completing action). BLOCKER: task 3
forward-references task 4/5 helpers — the same AF-4 pattern caught in
P2; resequencing ordered. MAJORs: the Recovery section's stated chain
inverted the true 3-vs-4/5 dependency; `required(street)` named three
different sets across two decisions and a task while citing "the
identical constant" — split into distinct helpers with the exclusion
stated explicitly. MINORs: one behavioral fixture for the
no-collision claim; the per-action full-replay cost note. Verified
clean: open-fold bypass (out-of-turn folds revert before the fold
branch; late-fold-vs-bank-fold explicitly resolved and
outcome-identical), boundary conventions uniform, birth-class reduction
lossless (single atomic event per class), all 11 fixtures with the
parking doc's exact numbers, P3 citations current post-revision (no
drift), concatenated-replay claim consistent with P3's pure
full-walk interface.

**AF-9 — P7 checker, 2026-08-17 — verdict: REVISE (7 MAJOR, 3 MINOR; in
revision).** The arithmetic core held completely: all five endings'
balances recomputed exact to the wei against D4's formula (pool
reconciles at 0.0032 ETH, no orphaned wei); the 31.37M-gas budget table
verified line by line; live probes confirmed the deploy-key balance
(0.006192 ETH) and current gas price (0.00725 gwei — inside the doc's
own gate). MAJORs, all operational-layer: whose-wallet ambiguity in the
budget framing; the flop-only fallback's real breakeven is ~41× (not
the 100× trigger it was offered for); a marker-gas row attributed to
endings that play no marker; a fileActions probe reading a getter that
cannot observe fileActions (false YES/NO); task 5 missing its declared
typed-HALT block; the second human's cast-send task with no command
template; one bare cast call that could silently read a stray local
chain during a live-money decision. MINORs: TBD count, "dead pointer"
wording, one field-name drift. Revision with the ending-4 wallet
decision requested.

**AF-10 — Cross-doc coherence pass, 2026-08-17 (orchestrator, all seven
docs + formats read against each other) — three gaps, all amended.**
The Outputs→Inputs mirror chain verified coherent at every major seam:
D16's vector sync described identically (direction, checksum gate,
commit-message hashes) across P1/P2/P3; P2→P3 stub freeze respected
(P3's Outputs confirm only `phase2Act` remained); P3→P4 handoff exact
(no renames, PendingContinuation as entry point, dueAt pattern reused);
P5↔P6 message shapes agreed post-AF-7 (P6's resolution of
TBD-P1-EVIDENCE-SHAPE supersedes P5's proposal, both docs say so).
Amended: (1) P5 gains the `liveHand` hello field + ABI getter P6
required but could not ship; (2) P6's three TBD-P4-CONTINUATION sites
resolved against closed P4's Outputs; (3) P7 gains the player-wallet
funding ruling (deploy-key seeding transfers, burn-aware arithmetic,
faucet-clicking rejected per ops' sizing lesson) — a prerequisite a
beginner operator would otherwise have hit as "insufficient funds" at
task 4. All three as dated amendment blocks, not silent edits.

**AF-11 — Cold review Reader 1 (chain walk), 2026-08-17 — verdict: FIX
FIRST (3 BLOCKER, 6 MAJOR, 5 MINOR).** The coherence pass (AF-10) and
the per-doc checkers both missed these — they are cross-doc seams only a
full chain re-derivation surfaces. 12 seams walked clean (formats byte
layout everywhere, P2→P3 stub freeze, BettingReplay reuse, bond formula
×3, D15 durations, V1 isolation, Part A/B seam). BLOCKERs: (1)
**receipts are chip-denominated by P1, wei-denominated by P2/P7 — no
doc owns the conversion**; either reading breaks (chips → loser refunded
in full; wei → replay rejects every honest bet). (2) **`dueAt` is
1-arg in P3, called 2-arg in P4** — P4's open-question-1 checked the
wrong symbol (`_resolveTerminal` not `dueAt`); premature muck 5h early.
(3) **Buyin's V2 request-executor side (`vault:derive-key-v2`,
`vault:post-marker-v2` receivers) is owned by no phase** — session-key
encryption never runs, marker post has no executor, P6/P7 gates can't
pass. MAJORs: (4) D16 vector *copy* owned by nobody, P2 Inputs vs
Outputs contradict — parity never executes; (5) no bond burns for total
window absence at markedHand>0 — the desert case for every session that
dealt a hand; (6) evidence bundle's share entries need 6 fields no
phase produces, P7 reads ciphertexts from a marker that lacks them; (7)
P5 ships no V2 hello sender though P6's whole send side rides it; (8)
AF-6 divergence: "earliest-filed" vs spec's "earliest-filed VALID" — a
signed-illegal action poisons a node. MINORs 10-14: AF-4 rationale
rotted (ruling survives via §5.4 precedence, not the stated premise),
message-name drift, marker-persistence owner, two symbol
mis-attributions, a disputeOpenedAt==0 guard. Reader 2 (gate attack)
still running; fixes consolidated across both before dispatch.

**AF-12 — Cold review Reader 2 (gate attack), 2026-08-17 — verdict: FIX
FIRST (4 BLOCKER, ~11 MAJOR, minors).** Attacked every phase-boundary
probe for "passes while the capability is broken." 10 gates survived
(forge build/test checkpoints, tsc, generator determinism, the
kill-anvil deal-gate probe — "the best-constructed probe in the plan",
the 0.0032 pool reconciliation, V1 defaultWindow read). Defect classes:
no-base-ref git diff (C1, five isolation gates + P7 inverse), vacuous
grep (C3, the two phase2Act stat-greps that CANNOT fail), self-defined
threshold (C2, P6 gate 1), self-consistent fixtures (C6), symmetry
blindness (C7, ending 2 host-only = AF-4's ruling tested one direction),
pass-on-failure (C5, D16). BLOCKERs: X-1 D16 gate vacuous end-to-end
(overlaps AF-11.4); X-2 C1 disables every isolation gate incl. D11 V1;
P3-1 the phase2Act stat-greps; P4-1 readyTime handoff-baseline branch
untested (overlaps AF-11.2); P2-2/P7-4 D15 duration guard never fires +
Deploy A durations never read back. MAJORs incl. P3-2 out-of-turn
acceptance unprobed, P3-4 Merkle leaf shape unprobed (→ every real
dispute becomes symmetric muck), P7-1/P7-2/P7-3 endings can't
discriminate wrong-winner/privileged-host/swapped-payout, P7-5 forge
inspect missing --root at 6 sites, P6-3 D14 marker count collision.
Both readers independently confirmed AF-4 holds via §5.4 precedence (not
its stated rationale) and AF-6 holds for ties (not the "valid" gap).

**Fix round 1 — COMPLETE, 2026-08-17.** All seven drafters applied their
AF-11/AF-12 rows + D17/D18. Orchestrator verified the six blockers by
grepping committed text (not trusting reports): B1 chip/wei two-space
split present in P1/P3/formats §1 with the converter defined; B2 dueAt
two-arg everywhere, no re-derivation site; B3 P6 task 11 owns the Buyin
executors; B4/D18 sha256sum -c in P2(owner)+P3(consumer), zero
drift-pass wording; B5/P3-1 both phase2Act gates now
`grep -c '^[-+].*phase2Act'`, all remaining --stat mentions
explanatory; B6 P4 handoff-baseline fixtures present; B7 P2 DeployV2.t.sol
guard test + P7 three cast-call duration readbacks. Both working trees
clean. **Plan complete — ready for operator intent review.**

**Phase 1 wave 1 (tasks 1-3) — shipped 2026-08-17, poker@aa8a653.**
Distrust gate: orchestrator re-ran all three probes + full suite = 314
passing (278 baseline + 36 new), tsc clean, only the 6 intended files
touched. Catch attribution:
- **AF-13 (from task 1, CRITICAL-class, fixed in-lane):** noble
  `secp256k1.sign` defaults `prehash:true` → without `{prehash:false}`
  every session-key signature covers `sha256(keccak256(preimage))`, not
  the raw digest formats §1 requires — and a self-consistent test passes
  anyway; only the contract's ecrecover would reject it (invisible until
  P2/P3). Fixed in signing.ts. **Fold into P1 task-doc step 4 wording.**
- **AF-14 (from task 2, cross-phase → P3 brief):** `verifyInclusion`'s
  `index` arg is vestigial for correctness — sorted-pair nodes are
  commutative, so position binding lives ENTIRELY in the leaf preimage.
  **P3's Solidity share-verifier must bind position in the leaf and must
  NOT rely on any index argument** — inject this into P3's dispatch brief.
- **AF-15 (from task 3, in-lane fixed + poker followup):** noble
  `Pt.multiply(0n)` throws; dleqKeccak added `mulSafe` so verify is total
  at c=0/s=0. Observation: V1's `proofs.ts` `verifyDleq` has a no-op
  ternary faking this same guard — `[agent-food]` for poker HANDOVER.

**Phase 1 task 8 — shipped 2026-08-17, poker@(task8 commit).** Distrust
gate: orchestrator re-ran suite = 343 (314+29), tsc 0, only 4 files.
Fixed a Vault-handshake deadlock mid-task (regression-pinned). Concerns
routed:
- **AF-16 (ruling):** non-Vault/free play exchanges NO receipts — receipts
  are settlement artefacts and free play never settles; task 8 step 3's
  placeholder-depositWei parenthetical is about task 10's *vectors*, not a
  mandate for live non-Vault exchange. Correct as shipped; no change.
- **AF-17 (→ task 6 brief):** task 8 needed peer session-pubkey exchange to
  verify receipt sigs and added a minimal `{t:'sessionpk', pk}` Msg. Task 6
  owns the hello-vs-new-field decision (its own open question) — task 6 must
  ADOPT `{t:'sessionpk'}` as shipped or reconcile it, not add a second
  mechanism. Injected into task 6's dispatch brief.

**Phase 1 task 6 — shipped 2026-08-17, poker@88c14e4.** Distrust gate:
suite 364 (343+21), tsc 0, scope files only. Self-fixed a real ordering
bug (verify peer action sig before mutating betting state). Notes:
- **AF-17 correction:** the `{t:'sessionpk'}` task 8 added is a loose
  `Envelope` bag in useGame.ts, NOT a typed entry in protocol.ts's `Msg`
  union (Transport's Envelope is `{t:string,[k]:unknown}`, so no type
  error ever surfaced). Task 6 correctly consumed the peer pubkey via its
  signing context without adding a second mechanism. If a future task
  wants sessionpk type-safe, promoting it into the `Msg` union is a clean
  `[agent-food]` follow-up — not required for correctness.
- **Sequencing note:** orchestrator ran 8→6 ahead of 4/5 (plan's
  suggested order is 8,4,5,6,7). Harmless: task 6 (like task 8) shipped a
  self-contained module taking markerHash/keys as inputs, signing made
  OPTIONAL on Game so all existing callers pass unchanged; real
  integration wiring (worker.ts init with live key + markerHash) is the
  deferred bucket tasks 5/7 close. Resuming planned order: 4→5→7→9→10.

**Phase 1 task 4 — shipped 2026-08-17, poker@0ab34d9.** Distrust gate:
suite 372 (364+8), tsc 0. Button now explicit+transmitted (kills §9.9
desync). Notes:
- **AF-18 (→ task 5 brief):** button/hand source-of-truth should become
  the MARKER once task 5 ships; task 4 left `buttonForHand`/`newhand.button`
  as the interim bridge. Task 5 supersedes them by reading the marker's
  button field.
- **AF-19 (→ task 7 brief):** the refuse-to-resume guard must extend to
  task 7's action-tip store (`recoverHandNumber`'s null-check idiom) —
  task 4 could not, the store didn't exist yet.
- **AF-20 (low, task-8 interaction, out of lane):** `nextHand` signs hand
  0's closing receipt at key (0,0), identical to the opening receipt, so a
  reload in the narrow post-showdown/pre-nextHand window resumes at hand 0
  not 1. Conservative + safe (never over-advances). Documented in
  `recoverHandNumber`'s doc comment. Revisit if it ever bites; not
  blocking.

**Phase 1 task 5 — shipped 2026-08-17, poker@7d074da.** Distrust gate: suite 401 (372+29), tsc 0, scope files only. Symmetric 2-round marker exchange (design call where the plan left room — each shareRoot is one-side-derivable). AF-18 resolved (marker authoritative for button). D14 pk-hello-match refusal shipped with its comment. No new findings beyond the AF-19 already queued for task 7.

**Phase 1 task 7 — shipped 2026-08-17, poker@f412704.** Distrust gate:
suite 417 (401+16), tsc 0, scope files only. Caught (by reading) that an
unconditional refuse-on-cleared-storage check would break every non-Vault
local game's first action — gated on vaultOn. AF-19 resolved (action-tip
refuse-to-resume reuses task 4's idiom). Distinct D14 markers shipped.
- **AF-21 (expected, → P6):** real session-key signing is NOT wired into
  worker.ts's live `new Game(...)` in any phase-1 task — Game is still
  constructed unsigned, so the write-ahead/marker/action paths are live
  code but no-op in production until activated. This is CORRECT and
  intended: the real session key comes from P6's wallet-derived flow
  (§6). Phase 1 delivers tested substrate; P6 activates it end-to-end.
  Every phase-1 module is tested against the real artefact shapes directly
  (bypassing worker.ts), so the contracts are proven; only the live wiring
  waits for P6. State this in the phase-boundary report.
- **AF-22 (poker `[agent-food]`):** `src/test/reconnect.test.ts`'s
  "queues while link down" test is timing-sensitive (`wait(3000)`) and
  flaked twice under full-suite CPU load (pre-existing, raw Transport, not
  this change; isolated reruns 8/8, full suite 417/417 clean on final
  runs). Could bite CI. Not blocking.

**Phase 1 task 9 — shipped 2026-08-17, poker@d2fd2c3.** Distrust gate: suite 425 (417+8), tsc 0, D14 audit grep re-run by orchestrator — all three distinct markers present. D12 re-derivation walked the parking doc's tenth-through-sixteenth findings independently and diffed clean against fixtures-index (no gap). No new findings.

**PHASE 1 COMPLETE — 2026-08-17.** All 10 tasks shipped to the poker repo,
each through its own distrust gate; phase-boundary gate run by the
orchestrator: full suite **435 green** (from a 278 baseline — 157 new
tests), tsc 0, vector generator deterministic (regen = zero diff), both
vector sha256sums confirmed, D14 audit found all three load-bearing
markers in source. Findings AF-13..AF-22 all recorded and routed (AF-14→P3,
AF-19 resolved in task 7, AF-21 = P6 activation by design, AF-22 =
pre-existing poker flaky test). Catch attribution across the phase: the
distrust discipline caught, at the foundation, a silent wrong-hash signing
bug (AF-13, noble prehash default) and two would-be non-Vault-play
breakages (tasks 7 & the receipt handshake) — none reachable by their own
self-consistent tests. Substrate is built and fully unit-tested against
real artefact shapes; live activation is P6's wallet-derived-key
integration (AF-21), as designed.

**Phase 2 contract (tasks 1-7) — shipped 2026-08-17, vault@(this commit).**
Distrust gate: forge build clean (only V1-parity block-timestamp lints),
V1's 26 tests intact, all 4 P3 stubs + the markedHand>0 branch present,
Channel.sol byte-identical. Concerns routed:
- **AF-23 (my brief error → test dispatch):** I over-narrowed the contract
  brief to 2 files, omitting task 7 step 7's `DeployV2.t.sol` (the B7 D15
  guard test). It belongs in the tests dispatch (8-9) — injected there.
- **AF-24 (→ P5, resolves TBD-P2-GETTER-ABI):** the 21-field Session
  struct exceeds legacy getter stack limits, so `sessions` is `internal`
  with grouped view fns (`sessionCore/Keys/Bonds/Deposits/
  DisputeOpenedAt/HighestFinal`). These ARE P5's read surface — P5's
  TBD-P2-GETTER-ABI resolves to this grouped-getter shape, not a single
  struct getter. Inject into P5's future brief.
- **AF-25 (confirmed correct):** `cancelOpen` uses pull-payment (credits+
  withdraw) not V1's push `_pay` — D9 uniform pull-payment; "V1 parity"
  read as amount-parity not mechanism. Better (no failed-transfer brick).
- Signature-check require strings self-chosen (task 9 reads from source);
  markedHand etc. are top-level mappings (gate-grep-driven, sound);
  Receipt.isFinal (final is reserved) — all fine.

**Phase 2 tests (tasks 8,9 + DeployV2.t) — shipped 2026-08-17.** Distrust
gate: forge test 69 green (26 V1 + 42 V2 + 1 deploy), both vector
checksums OK, contract + V1 byte-identical. D12 re-derivation zero drift.
Findings:
- **AF-26 (P1 defect → P3 PREREQUISITE, blocking):** P1's committed
  `Vectors.sol` does not compile under solc (error 9429 — lowercase
  40-hex address literals `HOST`/`GUEST`/`CONTRACT`, same class as the
  prototype's own early bug, fixed there via EIP-55 but re-introduced by
  task-10's generator; uncaught because the poker repo has no Solidity
  toolchain). P2 worked around it: consume the hash-identical
  `p1-vectors.json` via `vm.readFile` (D18 substance met — byte-identical,
  hash-gated, executable) + `skip = ["test/vectors/Vectors.sol"]` in
  foundry.toml. **P3 needs Vectors.sol to actually compile** (its DLEQ/
  Merkle/evaluator tests want the Solidity-native vectors). Fix at/before
  P3 start: patch poker `src/vectors/gen.mts` to emit EIP-55-checksummed
  addresses, regenerate, re-record BOTH hashes, re-sync the vault copy,
  remove the foundry.toml skip. Small deterministic fix.
- **AF-27 (→ P3/P4):** `_settlePerDutyBonds` credits a bond on
  `hostFiledInWindow`/`guestFiledInWindow`, not on the burned flags —
  safe in P2 (its only burn caller is itself), but P3/P4 add
  misconduct-driven burn callers; ensure none can fire before `resolve()`
  with `markedHand==0`, or a player is both burned and credited. Inject
  into P3/P4 briefs.
- Gas: `fileMarkerWithReceipt` 109,676 (~1.8× the 61,740 prototype
  figure, real-contract overhead, not order-of-magnitude) — noted for P7.

**PHASE 2 COMPLETE — 2026-08-17.** ChannelV2.sol (money frame) + full
suite shipped to the vault repo. Boundary gate (orchestrator-run): forge
test **69/69 green** (26 V1 untouched + 42 ChannelV2 + 1 DeployV2 guard),
D18 cross-repo vector parity executable via hash-gated p1-vectors.json,
D12 P2-fixture re-derivation zero drift, V1 + contract byte-identical
after the test round. AF-4's per-duty ruling tested BOTH directions.
Contract behavioral correctness proven by the fixtures (not just
compile). Open items routed forward: AF-26 (Vectors.sol compile → P3
prereq), AF-27 (burn-before-resolve → P3/P4), AF-24 (getter shape → P5).
Phase substrate: the contract's dispute surfaces are stubs (NotYetBuilt)
by design — P3/P4 fill them.

**Phase 3 Part A wave 1 (tasks 1, 5) — shipped 2026-08-17.** Distrust
gate: whole-project forge build + test 98 green (26 V1 + 42 ChannelV2 +
15 Evidence + 14 BettingReplay + 1 Deploy), checksums OK, contract/V1
untouched. Both modules verified against their oracles (Evidence vs D16
vectors + card table; BettingReplay differentially vs live betting.ts).
- **AF-28 (→ ChannelV2-extension brief, tasks 6/7):** the plan's
  `replay() → (…, address folder, …)` is unconstructible — replay is
  chip/seat-space pure and takes no addresses. Task 5 correctly returns
  `bool folderIsHost`; the consolidation/resolve wiring (task 6/7) must
  translate that bool to a wallet address via the session's host/guest
  storage. Not a betting semantic gap — an interface-completion fix.
- Minor (task 1): D16's merkle vectors carry precomputed leaf hashes +
  proofs but not raw pos/shareEnc/c1Enc/c2Enc preimages, so tasks 4/9
  assert each side matches the §7 formula independently rather than
  byte-equal to a committed client leaf. Acceptable; noted.

**AF-29 (test enhancement, operator-suggested 2026-08-17 → P6/P7):**
build an AUTOMATED two-bot end-to-end harness — two scripted client
instances driving the real poker client + Vault over the real transport
against a LOCAL test chain (anvil) — that plays hands and deliberately
triggers each adversarial path (disconnect mid-hand, desert, refuse to
file, crash-then-return, equivocate) and asserts the resulting on-chain
settlement. Value: far more thorough and repeatable than P7's manual
two-human sweep (seconds vs an evening), and it exercises the live
signing/settlement wiring that unit tests bypass. Dependency: needs P6
(client-chain signing) live before it can settle anything real. Slot it
into P6's boundary (as an integration gate) and/or P7 (alongside/ahead of
the manual sweep). Note: the in-process two-engine + forfeit/grace tests
(poker e2e/reconnect/grace) and the P2/P3/P4 desertion fixtures already
cover the LOGIC; this harness covers the LIVE end-to-end path they can't.

**Phase 3 Part A extension (tasks 2,3,4,6,7) — shipped 2026-08-17.**
Distrust gate: build clean, whole suite 98 pass / 3 fail — the 3 confirmed
by the orchestrator as exactly P2's stale stub-pinning placeholders now
reverting correct errors (PendingContinuation / "not disputed"), NOT
regressions; V1 untouched, phase2Act stub intact.
- **AF-30 (P2 gap, fixed in-lane, D9 amended):** P2 under-persisted the
  marker (discarded roots/pks/button/blinds). P3 added markerAt — a
  necessary third disclosed extension. Ruling + D9 amendment recorded.
- **AF-31 (→ task 8):** the 3 stale placeholder tests
  (test_fileActions/postShares_reverts_NotYetBuilt, test_F10_2) must be
  reconciled to the new behavior; and the Part-A gate-3b extension-count
  wording re-scoped (see D9 amendment). Task 8 owns both.

**AF-32 (CONFIRMED design-conflict, HALTS Part B, operator decision) —
2026-08-17.** The chip↔wei rate has no single both-signed source; three
sources disagree, orchestrator-re-derived from live code:
- client `format.ts`: BIG_BLIND=2, actual starting stack 200 chips
  (=100bb); e2e uses {200,200}.
- vector `gen.mts:213`: STARTING_CHIPS=200 (matches client) but comment
  mislabels "200bb"; RATE = DEPOSIT_WEI/200.
- contract `ChannelV2._chipBaseline:858`: startingChips = 200 * marker.bb
  → 400+ chips, ≠ 200. Different wei/chip rate than the client → Part B
  payout math would be built on a mismatch.
Root cause: B1/decision-3a seam under-specified how the CONTRACT learns
the chip scale; the marker (both-signed) carries sb/bb (chips) and the
(0,0) receipt carries stacks (wei), but NO both-signed startingChips.
**Recommended fix (operator go-ahead needed — ripples shipped P1):** add
an explicit both-signed `startingChips` field to the marker (formats §4);
contract derives weiPerChip = (0,0).hostDeposit / marker.startingChips;
client sets it to its real starting stack; drop the `200*bb` formula.
Ripple: formats §4, P1 marker.ts + vector regen/rehash (D18 hashes
change), P2/P3 marker verify + _chipBaseline, P6 marker posting. Part A
is otherwise complete (112 green); Part B is HELD pending this decision.

**AF-32 RESOLVED — 2026-08-18, atomic (poker@4acc658, vault@f64ea78).**
Signed `startingChips` added to the marker; contract reads it, `200*bb`
gone (comments only); both suites green (poker 435, vault 112); vectors
regenerated + re-synced (json 24c74564, Vectors.sol 52d8959e), checksums
OK; test_F12_3 strengthened with a white-box assertion that the chip
baseline now equals the vector's 200-chip convention (was 20000).
- **AF-33 (minor, gen.mts vector-quality, NOT blocking, NOT a contract
  bug → optional future polish):** the F12.3 vector's "raw 200 clamps to
  120" narrative assumes an asymmetric {200,120} baseline, but its (0,0)
  receipt is symmetric {200,200}, against which 120 is genuinely illegal
  (minRaise==maxRaise==200). So end-to-end clamp-through-the-contract
  can't be exercised via this vector — the clamp property IS covered at
  the BettingReplay unit level (task 5) and the baseline math white-box
  (task 8). Improvement: emit an asymmetric-baseline clamp vector. Low
  value; logged.

**PART A COMPLETE (confirmed post-AF-32) — 2026-08-18.** vault forge 112
green, V1 intact, crypto + replay engine + evidence machinery + routing
all shipped and gated. Part B unblocked.

**Phase 3 Part B contract (tasks 9-12) — shipped 2026-08-18.** Distrust
gate: build clean, 110/112 — the 2 fails confirmed by orchestrator as
exactly F12_1/F12_6 (stale Part-A placeholders that pinned the
_resolveTerminal NotYetBuilt stub; a terminal chain now resolves, so
"did not revert as expected" = correct). phase2Act sole remaining stub;
Evidence/BettingReplay/V1 byte-identical.
- **AF-34 (minor, my brief over-restricted):** task 9's decode logic
  lives in ChannelV2.decodeAt, not a standalone Evidence.decode() — my
  dispatch boundary forbade touching Evidence.sol while the phase doc
  named it as task 9's file. No functionality lost (uses Evidence's
  public surface); Evidence.sol byte-identical. If P4 wants a reusable
  Evidence.decode() entry point, promote it then. Not blocking.
- **AF-35 (→ task 13):** reconcile F12_1/F12_6 to the real resolving
  behavior + build the Part B fixtures + task-9 decode functional
  coverage. Task 13 owns ChannelV2.t.sol.
- **AF-36 (minor, cooperative-only):** task 12's crystallize call now runs
  _consolidate in resolve()'s final branch, adding a revert surface a
  both-signed sabotaged-startingChips marker could trip on a final
  payout. Follows the doc's task-12 step 1; narrow, both-parties-malicious
  edge. Flagged, not fixed.

**PHASE 3 COMPLETE — 2026-08-18.** Both parts shipped; boundary gate
(orchestrator-run): forge build clean, full suite **124/124 green** (V1 26
+ ChannelV2 65 + BettingReplay 14 + Evidence 15 + VectorsIntegrity 3 +
DeployV2 1), vector checksums OK, V1 byte-identical across the whole
phase, only `phase2Act` remains stubbed (P4). The sixteen cold checks are
now permanent CONTRACT tests. Findings AF-26..AF-36 all resolved/routed.
- **AF-37 (minor, citation only):** F10.1 "fiction dies to evidence" maps
  to a synthesis (rev-4 finish-on-chain + D9 precedence) not one numbered
  finding — property is sound and now fixture-covered; a citation nuance,
  not a gap.
- Gas note: Part B fixture per-function totals include test-side DLEQ
  proof GENERATION, so they read far above the ~53M on-chain-only
  worst-case — measurement artifact, not a regression (P7 measures
  on-chain-only live).
The two highest-risk pieces of the whole arc — the on-chain betting
replay matching betting.ts bit-for-bit, and the money-deciding resolution
rows — are both shipped and adversarially tested.

**Phase 4 contract (tasks 1-7) — shipped 2026-08-18.** Distrust gate:
build clean, 118/124 — 6 fails confirmed as stale-stub placeholders (5
old-PendingContinuation→Phase2InProgress, 1 phase2Act NotYetBuilt→"not
disputed"); no live NotYetBuilt; readyTime handoff-baseline IS a pure
on-chain function (the cold-review-scrutinized requirement met). Only
ChannelV2 changed. Notes:
- **AF-38 (re-verification adaptations, all sound, in-lane):** _resolveTerminal/
  _consolidate carry weiPerChip as a 6th value (doc said 5) — _consolidatePhase2
  threads it; disputeOpenedAt is a Session struct field not a top mapping;
  _markerHash widened calldata→memory for genesis prev₀ reconstruction
  (backward-compatible, in ChannelV2). readyTime shipped as
  (session,hand,forHost,baseline,street) resolving the doc's own
  Phase2Cand-vs-Cand parameter inconsistency.
- **AF-39 (→ P4 tests dispatch):** the phase doc folded test-writing into
  tasks 3 (readyTime adversarial fixtures) and 6 (test_streetRunoutBirths);
  src-only contract dispatch deferred them. The tasks 8-9 dispatch MUST
  build: task-3's readyTime/bank fixtures (handoff-baseline, own-postings-
  never-pause, attribution — REVIEW-BRIEF's key targets), task-6's
  streetRunout fixture, reconcile the 6 stale tests, plus tasks 8-9's own.

**Phase 4 test suite (tasks 8,9 + AF-39 deferrals) — shipped 2026-08-18,
Phase 4 CLOSED.** Distrust gate: orchestrator re-ran `forge test` itself —
**144 passed / 0 failed** across 6 suites (V1 26, ChannelV2 85, BettingReplay
14, Evidence 15, VectorsIntegrity 3, DeployV2 1). No src/ contract touched
(committed 039bc8f: only `contracts/test/ChannelV2.t.sol` + `.gas-snapshot`).
Catch record: the test agent found NO shipped-contract bug — the P4 logic
survived the handoff-baseline, bank-attribution, and street-runout fixtures
that were the cold review's key targets. AF-38, AF-39 resolved.
- **AF-40 (ADVISORY, doc hygiene — phase ships):** thirteenth cold check's
  finding 3 ("duties born after ~23:50 / during the extension have no
  coherent deadline") has no dedicated `F13.3` row in `fixtures-index.md`.
  Its property IS tested — folded into the `birthAt`/`showdownBirthAt` +
  `dueAt=max(hour24,birth+grace)` machinery that F14.1, test_streetRunoutBirths,
  test_F10_5, and test_F12_4 exercise. Coverage gap = none; naming gap =
  yes. Route: fixtures-index touch-up in a future doc pass. Not blocking.
- **AF-41 (ADVISORY, process — phase ships):** D17 requires the P4 base SHA
  recorded at task-1 dispatch; the phase doc still reads literal
  `<P4-BASE-SHA>`. The isolation gates (P4 contract + tests) used inferred
  `a0dacb1` (commit before `d659a9a "arc-run: Phase 4 begins"`), which is
  correct but unrecorded. Route: fill the doc's D17 note when P5/P6 base
  SHAs are stamped, so the pattern is consistent going forward.

**Phase 5 (buyin-ui) built + automated floor VERIFIED 2026-08-18** (commits
6c67661, d293d1a, 4b2af2c). Distrust gate: orchestrator re-ran the floor
itself — `npm run build` exit 0 (3 bundles); V1-isolation diff vs 1c10e9c
EMPTY (D11/D13 held); every pinned copy phrase present; `grep -c` = exactly
2; `bondFor(1500,500)=1650n`/`(500,1500)=1100n` (D1 worked case, money math
correct); `forge test` still 144/144 (no contract touched). Gate type is
**operator-run** — the two-tab smoke (boundary steps 1–14) HALTS for Raptor;
NOT autonomously verifiable (needs browser + wallet + live anvil). Phase is
built + floor-green, smoke PENDING — not yet fully shipped.
- **AF-42 (P5 contract-vs-doc reconciliations — the implementer holding
  contract+doc caught 6 stale drafting-time assumptions; all adapted to the
  SHIPPED contract as ground truth. BINDING ON P6/P7):**
  1. **No `sessions(bytes32)` struct getter (AF-24 confirmed live).** Read
     surface is grouped getters: `sessionCore / sessionKeys / sessionBonds /
     sessionDeposits / sessionDisputeOpenedAt / sessionHighestFinal`.
     `disputeOpenedAt` is a Session field (AF-38), not a top mapping.
  2. **`NotYetBuilt()` is DEAD — no live path throws it** (P3/P4 shipped).
     The real interim revert is **`Phase2InProgress()`** (thrown by
     `resolve()` during a phase-2 continuation); `PendingContinuation` also
     live. P5 kept a defensive `NotYetBuilt` decode branch only. **P6 must
     treat `Phase2InProgress`/`PendingContinuation`, not `NotYetBuilt`, as
     the "not yet resolvable" signal.**
  3. **These reads ARE public getters** (doc marked them `TBD`/absent):
     `everReceipted`, `markedHand`, `hostFiledInWindow`, `guestFiledInWindow`,
     `receiptAt`. Settlement/never-started/per-duty copy is driven by REAL
     reads, not blanket-degrade.
  4. **Marker carries `startingChips` (AF-32); receipt terminal byte is
     `isFinal`** (`final` reserved word). `vault:evidence-v2` bundle→tuple
     mapping in `autofileV2.js`: bundle `final`→struct `isFinal`, `startingChips`
     threaded. **P6's evidenceBundle.ts must emit these field names.**
  5. **Plan self-contradiction (resolved):** task-6 pinned copy said "…but
     your bond was burned…" (lowercase) while the boundary probe greps
     case-sensitively for "Your bond was burned". P5 reworded comma→period
     ("Your deposit is back. Your bond was burned — …"), verbatim-equivalent,
     count stays 2. ADVISORY: a pinned-copy vs pinned-probe mismatch the
     drafting/checking regime missed; caught by the implementer.
  6. **`TBD-P4-CONTINUATION` kept as honest placeholder** — P4's on-chain
     logic exists but per-duty birth-anchored appointment times aren't
     cleanly renderable without P6 client knowledge; a real `resolve()`
     "Settle now" button IS wired for window-closed. **P6 supplies the
     client-side appointment interpretation this UI will later render.**

**Phase 6 (client-chain) built + automated floor VERIFIED 2026-08-18**
(poker: 12 commits ending c64fc83; vault: 1 commit 9750d26). Distrust gate:
orchestrator re-ran the floor itself — poker `npm test` **482 passed** (was
435, +47), `tsc --noEmit` exit 0, V1 pure core files diff EMPTY vs 4acc658,
`forfeit()` unchanged; vault V1-isolation diff EMPTY vs 4b2af2c, `npm run
build` 0, task-11 four message strings present, `forge test` still 144/144.
Gate type: **technical-auto floor (PASSED) + operator-run smoke (PENDING for
Raptor)**. Money-safety (task 8) argued sound: `vaultMaybeSign` is V1-only
(the sole V1-money mechanism can't fire for V2); a done-view choke point
suppresses any forfeit-reasoned stack update for V2; V1 winner-takes-all is
behaviorally byte-identical (`decideForfeitOutcome(1,·)`→settle-locally). A
V2 stall is the worst case, never a wrong award. **CONFIRMED sound.**

Reconciliations #2/#4/#5/#6/#7/#8 verified sound (esp. #2, a money-bug
AVOIDED: shipped `autofileV2.js` reads bundle `final` and maps to struct
`isFinal` ITSELF, numeric `action`/`button`, `sigHost`/`sigGuest`, 0x-prefixed
binary — emitting `isFinal` from the bundle would have filed every final
receipt as non-final. AF-42.4 is hereby CORRECTED: the bundle emits `final`,
NOT `isFinal` — the consumer does the struct mapping). Catch: the implementer
holding bundle+consumer at once caught the field-name direction.

- **AF-43 (SUBSTANTIVE — open, continuation dispatched):** the live evidence
  bundle sends `shares: null` ALWAYS. Task 5 probe (a) + the P6 Inputs
  ("This phase is the first caller of `proveDleqKeccak`, when building the
  evidence bundle's shares field") REQUIRE real chain-verifiable SharePosts
  for a complete-action hand. The unit test passes only on SYNTHETIC full
  SharePosts; task 3's live share store (`{pos, shareEnc}`) lacks the DLEQ
  inputs (card secret scalar, deck c1) and Merkle proofs (shareProof→shareRoot,
  deckProof→deckRoot) a postable SharePost needs. IMPACT: in a card-reveal
  dispute this client cannot post shares → an honest player could have their
  bond BURNED for failing a §5.2 posting duty. Not a test failure (tests
  green) and not exercised by the operator smoke (happy-path), but a real
  client capability gap vs spec. Track: continuation to the P6 agent to
  assemble live SharePosts from shuffle-time state; if it requires a
  decision-level architecture change (not additive), it escalates to
  operator + arc-plan.
- **AF-44 (SUBSTANTIVE — DECIDED 2026-08-18: operator chose ACCEPT AS-IS):**
  RESOLUTION — Raptor ratified keeping the conservative session-key restore;
  signing stays SYNCHRONOUS, encryption remains encrypt-at-rest + best-effort
  restore-on-load (no key swap mid-session). No async-signing rework this arc.
  Revisit only if the live smoke shows a signing hiccup right after a reload.
  Do NOT reopen without a new operator instruction. Original finding:
  session-key restore-before-first-sign is not guaranteed. P1's signing path
  is SYNCHRONOUS; AES-GCM decrypt is ASYNC. P6 delivers encrypt-at-rest +
  determinism-probe + destroy-on-settlement + conservative restore (restores
  only when no key in memory, never swaps mid-session) — a strict improvement
  over shipped P1 (which regenerated the key each load = zero survival). A
  GUARANTEED restore needs the signing path made async, which ripples through
  P1's substrate — an architecture decision, not additive P6 work. Route:
  operator decides (accept the conservative restore as the arc's answer, or
  open a follow-up arc to make signing async). NOT auto-changed.

- **AF-45 (test-infra flake — RESOLVED to residual, tracked in HANDOVER):**
  distrust gate caught a flaky poker test the P6 agent's single run missed:
  `reconnect.test.ts > "queues outbound messages while the link is down"`
  failed ~17% under full-suite parallel load (never solo — 18+ clean solo
  runs). ROOT CAUSE (established by code+experiment): three real-relay
  integration tests (`reconnect`/`relay-caps`/`live`, each a real
  `relay/server.mjs` child + real WS, distinct ports — no collision) are
  CPU-starved by ~40 co-scheduled crypto test files; the transport's
  reconnect+outbox-replay is then slow. Product logic is CORRECT: outbox +
  infinite backoff (8s cap, `transport.ts:250-253`) = message delivered on
  eventual reconnect, never lost. PRE-EXISTING V1 infra (reconnect.test.ts +
  transport.ts untouched by P6, confirmed by diff); P6 only raised ambient
  load. Fix applied (commit 7ff9b59): poll for delivery (26s budget / 40s
  timeout) instead of a fixed wait(3000)+assert-once — asserts the real
  eventual-delivery guarantee; flake ~17%→~6%. RESIDUAL (~6% under severe
  starvation) is unbeatable by any poll budget alone → HANDOVER Small
  followup: isolate the 3 real-relay tests into a sequential vitest project.
  NOT a P6 regression, NOT a product bug, does NOT affect the live sweep
  (real dedicated relay, not starved). Catch attribution: distrust-gate
  re-run (orchestrator looped the suite 12× where the agent ran it once).

**Phase 7 PREP (deploy line, not crossed) — 2026-08-18, DETACHED.**
Prerequisites confirmed WITHOUT touching the network (sandbox can't): top-up
GRANTED, deploy key `0x99507E2c…` = **0.00330223 ETH** RPC-verified by ops
(`~/letterbox/inbox/2026-08-17-base-sepolia-topup-reply.md`); deploy key file
exists (mode 600, `$PRIVATE_KEY` populated, masked-prefix checked only);
`DeployV2.s.sol` compiles clean (`forge build` exit 0); P2–P6 all landed
(poker@7ff9b59, vault@2809bfc); `deploymentsV2.js` is the empty P7-fills-it
placeholder. Real-network deploys + value transfers + the two-human live
sweep remain HELD for operator GO (live-effect gates, D11/D13).
- **AF-46 (SUBSTANTIVE pre-flight catch — resolved by amendment):** Task 1's
  seeding arithmetic assumed ~0.0062 ETH; the actual grant is **0.0033 ETH**,
  and ops stated NO second top-up this arc. The seeding plan (0.0047 total)
  would have hit "insufficient funds" cold during the live sweep. Buy-ins are
  symbolic test wagers → rescaled ×0.5 (baseline 0.0008; host seed 0.0015,
  guest 0.0009, total 0.0024; reserve ~0.00089 ≈ 27%). Gas was never binding
  (ops priced the whole plan <0.00001 ETH). Amendment landed in phase-7 Task 1.
  Standing conditions re-stated by ops: testnet-only, no server storage, and
  any mainnet/real-value move needs a NEW letter BEFORE any code assumes it.
