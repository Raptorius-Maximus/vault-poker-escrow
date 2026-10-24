# Adversarial fixtures index (D12)

Every numbered finding from cold checks 10–16 that carries a constructed
case, mapped to the phase that ships its defence and a canonical fixture
name. Drafters cite rows; test tasks **re-derive this class from the
parking doc** (grep `### Findings` from `## Tenth cold check` onward) and
diff against this index — if the re-derivation finds a case this index
lacks, that is a plan finding, not a silent addition. Money numbers in
fixtures come from the parking doc's own worked cases.

| ID | Constructed case (one line) | Phase | Fixture |
|---|---|---|---|
| F10.1 | Refuse lost showdown, offer fiction receipt; victim files chain+shares instead → cards decide, true result | P3 | `test_F10_1_fiction_dies_to_evidence` |
| F10.2 | File stale receipt N−1 against a marker for hand N → not a settlement, dispute overlay required | P2 | `test_F10_2_marker_blocks_stale_settlement` |
| F10.3 | Replay an old `final` after playing on → highest final wins; terminal; below-floor final rejected | P2 | `test_F10_3_final_ordered_terminal` |
| F10.4 | Rebuy past declared `M_i` refused; unmatched deposit changes nobody's bond; un-receipted deposit refunds | P2 | `test_F10_4_declared_depth_rebuys` |
| F10.5 | All-in, counterparty crashes at showdown; returns in window, posts shares → true result, no burn | P4 | `test_F10_5_crash_at_showdown_survivable` |
| F10.6 | Guest dies between deposit and (0,0): no marker, no receipt → deposits AND bonds return | P2 | `test_F10_6_never_started_full_refund` |
| F11.1 | Chain ends in signed fold; folder disputes → pot to non-folder, folder's bond returns | P3 | `test_F11_1_fold_is_final_decision` |
| F11.2 | Loser facing a raise disputes instead of folding → no cancel exists; on-chain options are poker's own | P4 | `test_F11_2_no_cancel_escape` |
| F11.3 | Duplicate marker at hand N rejected; continuity hash verified; live hand single-valued | P2 | `test_F11_3_marker_sequencing` |
| F12.1 | Truncate chain at own river bet, victim files fuller chain at hour 8 → fuller chain prevails at consolidation | P3 | `test_F12_1_truncation_loses_full_window` |
| F12.2 | Wrong-key shareRoot committed at marker; posted shares pass Merkle → DLEQ vs marker cardPk fails → muck | P3 | `test_F12_2_wrong_key_root_burns_owner` |
| F12.3 | Honest wire chain with clamped bet (raw 200 → clamped 120): canonical amounts replay exactly; illegal amount invalidates from that node | P3 | `test_F12_3_clamp_parity` (+ P1 client signing tests) |
| F12.4 | Betting completed on chain at 11pm, crash; shares posted hour 20 → duty met, no burn, no bank-fold | P4 | `test_F12_4_postings_are_window_duties` |
| F12.5 | Same refusal-to-show priced identically on-wire and on-chain (bond, both) | P4 | `test_F12_5_one_muck_price` |
| F12.6 | Dispute opened before marker N confirms; both-signed marker filed in window → live hand anchored, in-gap fold not refunded | P3 | `test_F12_6_first_marker_in_window` |
| F13.1 | Genuine action withheld and filed 23:55 → lands in frozen chain; counterparty answers at hour-24 appointment with full bank | P4 | `test_F13_1_no_private_deadlines` |
| F13.2 | Player withholds own postings to pause own clock → own postings never pause; bank runs | P4 | `test_F13_2_own_postings_never_pause` |
| F13.4 | Same-key distinct actions at one node → equivocator's bond burns; earliest-filed stands; identical duplicates dedup silently (F14.4) | P3 | `test_F13_4_equivocation_burn` |
| F13.6 | Both seats sign a malformed deck (52× same card); all checks pass, decode fails → fourth row, both burn, receipt baseline, **no revert** | P3 | `test_F13_6_fourth_row_total` |
| F13.7 | First empty bank folds and terminates → both-banks-empty state unreachable (structural assert) | P4 | `test_F13_7_banks_sequential` |
| F14.1 | Completing call filed at 23:59 → victim's hole-share duty born there, due 29:59; frozen-terminal resolves at last grace; no early muck | P3 | `test_F14_1_birth_anchored_deadline` |
| F14.3 | Two distinct same-node signatures where the second is filed after hour 24 → inadmissible as burn proof | P3 | `test_F14_3_pair_in_window_only` |
| F14.5 | Block at exactly open+24h is phase 2; filing in deadline block counts as met | P3 | `test_F14_5_boundary_conventions` |
| F15.1 | Equivocate, burn crystallises, then both sign a final → stacks settle per final, burned bond stays burned | P3 | `test_F15_1_burn_survives_final` |
| F15.2 | Chains auto-filed, both machines die → symmetric muck: both burn, receipt baseline | P3 | `test_F15_2_symmetric_muck` |
| F15.3 | One player accrues equivocation + missed grace → bond burns once; `depositsIn+bondsIn == paidOut+burned` | P2 | `test_F15_3_idempotent_burns` |
| F16.1 | Final lands before the equivocation pair is filed; pair filed before payout execution → bond still burns | P3 | `test_F16_1_evidence_window_survives_final` |
| F16.3 | Burn facts on chain before a final; computation runs after → burned (proof = filings) | P3 | `test_F16_3_lazy_crystallisation` |

**Verified-sound pins worth fixtures** (from the checks' held-attack lists):

| Case | Phase | Fixture |
|---|---|---|
| Zero filings at close ⇒ full refund incl. bonds (never-started semantics; AF-4: begun-ness is unattestable at zero filings, the §1.3 both-burn branch is unreachable dead code in V2) | P2 | `test_S_zero_filings_full_refund` |
| One filing (a lone `(0,0)`) ⇒ per-duty bonds: filer whole, full-window-absent side burns; no strategy beats honest at any Mh/Mg (no stack disparity reachable at markedHand==0) | P2 | `test_S_one_filing_perduty_bonds` |
| Legitimate multi-marker catch-up sequence is ACCEPTED under sequential acceptance (AF-4) | P2 | `test_S_marker_catchup` |
| Bond coverage at unequal declared maxima (1500/500 → 1650/1100) across branches | P2 | `test_S_bond_coverage_maxima` |
| Dead-man-switch: conditional silence at hour 23 still loses by the bond margin | P3 | `test_S_dead_man_switch` |
| Absentee ceiling: pot cannot grow against a bank-folded absentee; uncalled returns | P4 | `test_S_absentee_ceiling` |
| Desert-then-return: bank-folds the hand, duties met later → bond returns; full desertion burns | P4 | `test_S_desert_then_return` |
| Blind action legal at every node; no decision ever forced to wait on a card | P4 | `test_S_blind_action` |
| Phase-2 bets capped by receipt-baseline stacks; deposits invariant preserved through overlay | P4 | `test_S_continuation_accounting` |

Client-side (vitest, poker repo): F12.3's canonical-amount signing, F14.3's
write-ahead ordering (persist-then-send, never re-sign ≤ tip, send-or-file
tip on restore), D14's load-bearing rules — enumerated in P1/P6 docs.

Not fixtures: F10.7, F15.5, F16.2's wording halves (doc pins, already in
the spec); F14.2 (declared §8.11 behaviour — covered by bank-accounting
correctness, not a distinct attack).
