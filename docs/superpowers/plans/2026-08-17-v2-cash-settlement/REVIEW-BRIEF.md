# Review brief — for the cold adversarial plan review

Written by the orchestrating session as the plan is built; consumed by
cold readers who inherit nothing. Attack what is listed as contested;
do not re-verify what is listed as already checked hard. **Status:
accumulating — final before the review dispatches.**

## Where to attack

1. **The P2/P3 seam.** P2 ships a dispute *shell* (openDispute, the
   zero-filings unwind, never-started) with every richer path reverting
   `NotYetBuilt`; P3 fills the bodies. Attack: can P2's boundary
   verification genuinely prove the shell (unwind timing, bond fate at
   the shell level) without P3's machinery? Is any P2 probe secretly a
   P3 probe? This is the closest thing the slicing has to a
   regime-collision risk, accepted knowingly at AF-1 time.
2. **The Outputs→Inputs mirror chain, walked fresh.** Especially
   P1→P6 (client substrate consumed two phases later, after P2-P4
   changed the contract ground under it) and formats→everything.
3. **Gate attack per phase:** for each boundary probe, construct the
   scenario where the probe PASSES while the capability is broken.
   Drafter-authored gates drift toward the case that works.
4. **Cross-repo byte parity.** P1's vitest golden vectors and P2/P3's
   forge-side hashing both cite artifact-formats.md — but nothing
   executable ties them together until integration. Attack whether the
   plan needs a shared-vector artefact (one generated file both suites
   consume) and which phase owns it.

## Contested rulings — attack these, with my reasoning laid out

- **D15 (parameterized durations).** Risk: shipping with a wrong
  constant. My reasoning: V1 already parameterises its window
  (deployed at 1800s); the deploy script asserts spec values unless a
  test flag is explicit. Alternative rejected: hardcoded durations +
  vm.warp-only testing, which leaves the live sweep unable to exercise
  dispute endings inside a human calendar.
- **prev₀ = markerHash** (formats §5) — goes beyond the spec's text,
  which never says what seq-0 chains to. My reasoning: binds every
  chain to the exact deck/keys/blinds; kills cross-marker replay
  classes without extra fields. Cost: prototype vector regeneration.
- **Universal binding rule in actions** (formats §1) — the spec's
  action tuple (§3) lists session but not contract/chainid; I added
  both. Reasoning: uniform rule beats per-artefact transitive-safety
  arguments; registration-binding made session-only arguably safe, but
  "arguably" is what checkers exist to kill.
- **Position-bound Merkle leaves** (formats §7) — supersedes the
  measured prototype's leaf. Reasoning: sorted-pair trees are
  commutative, so D10's same-index requirement is unmeetable without
  the index inside the leaf. Attack: is uint8(p) + tag enough, and is
  the odd-node self-pairing rule sound with position-bound leaves?
- **P2 stubs the dispute interface** (formats §9 shapes now, bodies
  P3). Reasoning: AF-1's fix for P5 parallelism. Attack: does stubbing
  freeze a shape P3 will need to break?

## Checked hard already — don't re-spend

- The design itself: sixteen cold checks, verdicts in the parking doc.
  The plan cites the spec; do not relitigate settled rules.
- artifact-formats.md vs live source: AF-2's checker ran 21 probes
  (DLEQ/Merkle/deltas/widths/domains/alphabet/spec field lists). The
  street-boundary turn-order fact is confirmed twice (checker + an
  independent orchestrator pre-read).
- Gas and latency: measured (`prototypes/*`); only the congestion-tail
  rerun is open, gated, with the ops letter sent.

## Orchestrator error record, this run

0. Authored `fixtures-index.md` with the tenth check's 200/1800 worked
   case for the §1.3 branch — stale since the marker rewrite made that
   state unreachable, and I transcribed it without re-deriving. Caught by
   the P2 checker (AF-4). Same lesson as the sixteenth check's identical
   stale citation: transcription is not derivation, even for the
   orchestrator's own index.
1. Wrote "turn alternation makes every node single-key" into formats §5
   — false rationale (same seat acts consecutively across street
   boundaries); the rule survived but the justification was wrong, and
   the same loose phrase sat in spec §3 since revision 4, plus a stale
   "longest-wins" in §9.20 since revision 5. Caught by AF-2's checker
   and an orchestrator pre-read, independently. Lesson the reviewers
   should generalize: **prose rationales attached to correct rules rot
   silently — attack every "because" clause, not just every rule.**
2. During the design arc (recorded in the parking doc, relevant to
   calibrating my blind spots): four consecutive revisions shipped with
   a flaw I believed sound — the fold gap, the live-machine gaps, the
   phase-label deadline, the final/burn composition. Pattern: I
   compose new machinery correctly and under-specify its interaction
   with the *oldest* machinery (finals, the window clock). The
   Outputs→Inputs walk should weight old-artefact × new-phase seams.

## Accumulated attack targets (updated as waves closed)

- **AF-4's branch ruling** (zero filings ⇒ full refund; §1.3 both-burn =
  dead code): re-derive it cold. If the reviewer finds a state where a
  begun session with zero filings is distinguishable on-chain, the ruling
  collapses.
- **AF-6's tiebreak ruling** (first-stored-wins subsumes lowest-hash):
  attack the premise that no genuine simultaneity survives to the
  contract.
- **The P2-extension seam** (P3 amends P2's fileReceipt and resolve():
  `receiptStacksAt`, `_crystallizeMaturedDuties`): two docs now co-own
  two functions. The coherence pass must produce ONE authoritative
  statement of resolve()'s final shape; the reviewers should verify the
  merge is stated in exactly one place.
- **The D16 sync gate**: the sha256sum equality check appears in P1, P2,
  P3 — verify all three describe the SAME file set and direction of
  sync.
- **P4's readyTime definition** (once drafted): the single subtlest
  definition in the plan; a second cold derivation from spec §5.3's
  words, compared against P4's, is worth a reader on its own.
- **P5↔P6 message-shape agreement**: P5 proposed, P6 disposes; verify
  the final shapes appear identically in both docs after P6's revision.

## Review dispatch instructions (final — docs complete)

Two cold readers, dispatched in parallel after the coherence pass
applies, each inheriting nothing from planning. Verdicts land as dated
AF-entries in `review-findings.md`; fixes apply as normal finding
rounds; then GO to the operator intent review.

**Reader 1 — the second chain walk.** Read the seven phase docs ONLY
(plus decisions.md and artifact-formats.md as law). Walk every
Outputs-to-next-phase → Inputs mirror from formats through P7,
re-deriving each claimed output from the producing doc's own tasks —
never trusting the Outputs section's summary of itself. Weight the
old-artefact × new-phase seams (error record #2) and the P2-extension
merge (P3 amends P2's resolve/fileReceipt; exactly one authoritative
final shape must exist). Also re-derive AF-4's branch ruling and AF-6's
tiebreak ruling cold from the spec.

**Reader 2 — the gate attack.** For every phase-boundary probe in all
seven docs: construct the concrete scenario where the probe PASSES
while the capability is broken. Special attention: P2's shell gate
(REVIEW-BRIEF attack 1), P3's Part-A gate (terminal routing provable
without Part B?), P4's bank-accounting probes (can a wrong readyTime
implementation pass them?), P7's sweep table (does each ending's
YES/NO actually discriminate the failure it claims to catch?), and the
D16 sha256sum gates (all three docs, same file set, same direction).

Both readers: findings numbered with severity and a constructed case
each; "verified sound" lists mandatory; enumerate any class before
verifying instances; do not relitigate the spec (sixteen checks) or the
per-doc checker verdicts (AF-2..AF-9) — attack what no single-doc
checker could see.
