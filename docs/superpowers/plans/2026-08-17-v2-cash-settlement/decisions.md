# V2 cash settlement — cross-cutting decisions ledger

Commitments that bind more than one phase. Amendments are dated blocks
under the original entry, never silent edits. Every implementation brief
cites the decisions that bind it; contradictions lose to this ledger,
and this ledger loses to the spec
(`docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`,
revision 8, READY WITH DECLARED DEFERRALS — sixteenth cold check).

---

**D1 — One formats document owns every signed byte.**
Decision: `artifact-formats.md` (this scaffold) is the single normative
home for the preimage layouts of receipts, markers, and signed actions —
field order, widths, type tags, domain strings, hashing.
Why: the formats are the seam where two repos must agree with no shared
code; sixteen checks' history says seams nobody owns are where defects
live. Every artefact binds `(contract, chainid, session)` (finding D) and
a distinct type tag.
Implication: P1 (client signs) and P2/P3/P4 (contract verifies) conform;
neither may improvise a field. Changes are amendments there, and their
blast radius re-derives (never re-words) dependent docs.

**D2 — Session keys are secp256k1, registered on chain, and sign every
artefact.**
Decision: per-match session keypair; registered at open/join via a wallet
signature (`sessionKey[player]`, spec §9.4/§9.12); receipts, markers, and
actions verify via `ecrecover` against the registered key.
Why: gasless per-hand UX is impossible with wallet popups; `ecrecover` is
the only cheap signature check the EVM has.
Implication: P1 generates and uses the keypair (registration mocked); P2
implements registration + binding; P6 adds §6's encrypted persistence and
the wallet-determinism probe.

**D3 — Card crypto stays ristretto255; chain-verifiable proofs use the
keccak-challenge DLEQ; the measured prototypes are reference
implementations.**
Decision: `prototypes/dispute-gas/` (differential-tested against noble +
the verbatim client evaluator; DLEQ ~3.0M gas) is the basis for P3's
on-chain verification; the client's V2 artefacts use the keccak challenge
mirrored there (spec amendment; sha512 stays for wire-only proofs).
Why: measured, vector-locked; sha512 has no EVM precompile.
Implication: P1/P6 client emits keccak-challenge DLEQs for postable
shares; P3 imports/adapts the prototype libraries rather than rewriting.

**D4 — Declared-depth bonds, fixed at the door.**
Decision: each player declares max deposits `M_i` at open;
`bond_i = 1.1 × max((M_h+M_g)/2, M_i)`; posted before receipt (0,0);
never recomputed; deposits refused past `M_i` (spec §2, §3).
Why: tenth-check-verified coverage evaluated at maxima; kills the rebuy
veto (twelfth finding 4 lineage).
Implication: P2 contract enforces; P5 UI runs the declared-depth
handshake and shows the bond with its consequence attached.

**D5 — Receipts as spec §1.1: total order `(hand, subseq)`, mandatory
`(0,0)`, `final` ordered and terminal, deposits invariant.**
Implication: P1 wire exchange + persistence (localStorage, both origins);
P2 settlement ordering, floor subjection, terminal close; P5/P6 filing.

**D6 — The marker is the checkpoint, the floor, and the anchor.**
Decision: 13-field tuple (spec §4) incl. deckRoot, both shareRoots, both
cardPks, button, blinds, receipt-N−1 hash; duplicate-rejected;
continuity-verified; first marker admissible during a dispute window;
**deal gate: hand N+1 deals only after marker N confirms — a pause,
never a forfeit.** Measured: 61,740 gas, 0.7–2.9 s confirm.
Implication: P1 builds the exchange (both-sign before hand 1 card);
P2 acceptance rules + gate read; P6 posting + gate behaviour.

**D7 — Actions: four-action alphabet, canonical amounts, hash-chained,
write-ahead.**
Decision: `fold|check|call|bet` (bet covers raises); the client signs the
**post-clamp effective integer amount** its engine applied (spec §9.18);
`amount = 0` for non-bet actions; each action signs over
`prevActionHash`; **persist before transmit**; a restored client
sends-or-files its persisted tip and never re-signs at or below it; a
client with cleared storage refuses to sign actions for that hand.
Why: exact on-chain replay parity with `betting.ts` (fifteenth check
verified the clamp reduces to an integer range check); the write-ahead
rule is what makes the equivocation burn proof of misconduct.
Implication: P1 implements all client rules; P3 consolidation and P4
validation enforce exact legality; the load-bearing client rules carry
tests + a spec-citation comment (never "improved" away).

**D8 — The two-phase dispute, exactly as spec §5.**
Decision: phase 1 `[open, open+24h)` evidence-only (finals excepted —
and **proven burns are irrevocable**: evidence window survives a final;
proof = the filings, not the computation event; equivocation pairs
admissible only if complete in-window). Lazy consolidation:
earliest-filed-per-node, lowest-hash same-block tie, distinct-pair
equivocation burn. Phase 2 from the frozen state: 6h cumulative decision
banks (only counterparty-side postings pause you; blind action legal;
standing instructions legal); every duty owes `max(hour 24, birth+6h)`;
muck price = bond; bank price = the hand. ~66h worst case.
Implication: P3 owns phase 1 + consolidation; P4 owns phase 2; P5/P6
clients auto-file duties at window-open and answer appointments.

**D9 — Resolution and accounting rows are closed-form.**
Decision: spec §5.3's seven-row table verbatim (fold / cards-decide /
one-sided muck / symmetric muck / fourth row / never-started / §1.3
unwind); precedence `final > receipt+overlay > §1.3`; per-session
accounting only; pull-payment (`credits` + `withdraw`); burns idempotent
per bond; a burned player may still win the pot; never read
`address(this).balance`.
Implication: P2 ships precedence + unwind + never-started; P3/P4 ship
their rows; every row lands with its adversarial fixture (D12).

**D10 — The triple share check, or nothing.**
Decision: a posted share is valid iff share→shareRoot@p (Merkle) AND
ciphertext→deckRoot@p (same leaf index — never taken from the filer) AND
DLEQ against the marker's cardPk. Decode failure under all-passing
checks routes to the fourth row; resolution is total, no revert path.
Implication: P3 only, but P1's marker construction must commit roots in
the exact leaf order the contract will verify.

**D11 — Testnet only; V1 untouched; no server-side anything.**
Decision: chain-id guard (84532 | 31337) in every deployable; V1 stays
live at `0xF41A685C…` beside V2; the encrypted backup and reputation are
other arcs, gated on the ops letter.
Implication: P7 deploys are stop-and-ask with the chain id printed; no
phase adds relay state or server storage.

**D12 — The sixteen checks are the test suite.**
Decision: every numbered finding in the parking doc that carries a
constructed case becomes a named adversarial fixture
(`test_F10_1_bargained_rescission`, `test_F14_1_sprung_duty`, …) in the
phase that ships its defence, plus every "verified sound" case worth
pinning.
Why: the arc's entire defect history becomes a permanent regression net;
nobody re-derives it.
Implication: P2/P3/P4 test tasks enumerate their fixture class from the
parking doc (re-derive the class, never just the list).

**D13 — Lane: main checkout, both repos.**
Decision: no worktrees; commits to master as today; only ongoing arc in
either repo (verified 2026-08-17: clean status, no worktrees, HANDOVER
shows this arc only). Deploys happen only in P7.

**D14 — Client rules that protect chain money are named, tested, and
marked load-bearing.**
Decision: write-ahead signing; refuse-on-cleared-storage; marker-pk
hello-match refusal; hole shares born only by a completing action; deal
gate pause. Each gets a test and a comment citing its spec section with
the words "load-bearing — do not relax" (sixteenth check, finding 2).
Implication: P1 and P6 carry them; the arc-end review checks the
comments exist.

**D15 — Durations are deploy parameters; the spec's values are the only
production-legal ones.**
Decision: window (24h), bank (6h), and grace (6h) are constructor
parameters, exactly as V1 parameterises its window (`_defaultWindow`,
deployed at 1800s). The deploy script asserts the spec values unless an
explicit `--test-durations` flag is passed; P7 deploys a short-duration
instance for the dispute-endings sweep alongside the real one.
Why: the bet review caught that a live dispute sweep against hardcoded
24h/6h costs the operator days of calendar time; parameterising is V1's
own precedent.
Implication: P2 takes durations as constructor args and never inlines
them; P3/P4 tests use short durations via the same parameters (no
vm.warp-only testing of paths the sweep will exercise); P7's deploy
prints which duration set each instance carries.

**D16 — Cross-repo byte parity is proven by one shared vector file, not
by two readings of the same prose.**
Decision: P1 ships a vector generator (pattern:
`prototypes/dispute-gas/gen/gen.mts` — noble-validated, deterministic
fixed keys) that emits the canonical artefact vectors — receipt, marker,
and action preimages + hashes + signatures, DLEQ proofs, both Merkle
trees with proofs — as committed files in the poker repo, in both JSON
and `Vectors.sol` renderings. The poker vitest suite asserts the client's
own produced bytes equal the vectors; the vault forge suites consume the
synced copy; the sync is a documented script step and the coherence gate
is `sha256sum` equality of the two copies.
Why: artifact-formats.md is prose, and prose parity is not executable.
Two independent implementations of the same layout drifting silently is
this arc's most predictable integration failure; one generated artefact
makes the drift a test failure instead.
Implication: P1 owns the generator (supersedes its brief's
"compute expected hashes in-test" — vectors are still computed with
noble, but emitted once and committed); P2/P3 test tasks consume, never
regenerate; the P1↔P2 revision round injects this (wave-1 drafters were
briefed before D16 existed).

**D17 — Every git-diff isolation gate carries a base ref; consolidation
diffs use content-greps, not `--stat`.** (Fix round 1, AF-11 X-2 / AF-12
X-2, P3-1.) `git diff --stat -- <paths>` compares worktree to index and
reads empty once committed — vacuous under D13's commit-to-master flow.
Ruling: every isolation/no-touch gate is
`git diff <phase-base-sha>..HEAD -- <paths>` with the phase-base SHA
recorded in the phase doc's own task-ordering note at dispatch; any gate
asserting a token is/absent uses `git diff <base>..HEAD -- <file> |
grep -c '^[-+].*<token>'`, never `--stat | grep`. P7's close-out gate
(which must show edits) uses the same form asserting non-empty.

**D18 — D16 parity is owned by P2, enforced by `sha256sum -c`, and a
missing/mismatched vector file is a gate FAILURE, never a fallback
pass.** (Fix round 1, AF-11.4 / AF-12 X-1.) Single owner: **P2** copies
`src/vectors/{p1-vectors.json,Vectors.sol}` from the poker repo into
`contracts/test/vectors/` as a task step, and its phase-boundary gate
runs `sha256sum -c` against the hashes P1 recorded in task 10's commit
message. P1's gate asserts the recorded hash equals the file's actual
hash (`sha256sum -c` on its own output), and that the three consuming
test files reference `p1-vectors.json` (grep) with a mutation probe
(corrupt one byte → those tests fail). P3 consumes P2's landed copy and
its gate re-runs `sha256sum -c`. **`vm.sign` is permitted only for
negative/mutation cases; a happy-path construction that cannot resolve
the vectors is a recorded gate FAILURE that halts the phase, not a
pass.** Delete every "still YES on drift/absence" and unconditional
`vm.sign` fallback wording.

**D9 amendment (2026-08-17, Phase 3 execution, AF-30).** P2 shipped
`_fileMarkerCore` verifying the marker's crypto fields against the signed
hash then storing only `markedHand[session]` — discarding deckRoot, both
shareRoots, both cardPks, button, sb, bb. P3's postShares triple-check and
consolidation require those on chain (the dispute functions take no marker
parameter, formats §9), so P3 added a **third disclosed contract
extension**: a `MarkerData` struct + `markerAt[session][hand]` mapping
written inside `_fileMarkerCore`. Orchestrator ruling: this is NECESSARY
and correct (re-derived: without the roots/pks on chain, a posted share
has nothing to verify against). Decision 7's "exactly two disclosed
extensions" is amended to THREE: (1) fileReceipt's receiptStacksAt cache,
(2) resolve's _crystallizeMaturedDuties (P3 Part B/task 12), (3) this
marker-field persistence. The Part A gate-3b `grep -c "P3 extension"`
count is re-scoped: it conflated a Part-A boundary with a whole-phase one
— at Part A it legitimately reads 4 (2 marker + 2 receipt-cache
occurrences); task 12's finalEligible extension lands in Part B. Task 8
updates the gate wording to match.

**D6 amendment (2026-08-17, AF-32 resolution — operator-approved).** The
chip↔wei rate needs a single both-signed source; three sources disagreed
(client 200 chips, contract `200*bb`, vector 200-flat mislabelled). Fix:
the marker gains a signed `startingChips(32)` field (formats §4). The
contract derives `weiPerChip = receiptAt[(0,0)].hostDeposit / startingChips`
and MUST NOT re-derive starting chips from bb. The client sets it to its
real starting stack (`format.ts`: 200 chips at BIG_BLIND=2, i.e. 100bb —
NOT spec §3's literal "200 big blinds"; the code is the truth, the marker
carries it, both sides agree by construction). Ripple (atomic change):
formats §4; poker `marker.ts` (+field) & `gen.mts` (regen → new marker/
vector hashes, D18 hashes update); vault vectors re-sync + CHECKSUMS;
ChannelV2 `_fileMarkerCore`/`markerAt` (store it) & `_chipBaseline` (use
it, drop `200*bb`); affected tests. P6 marker posting consumes it later.
