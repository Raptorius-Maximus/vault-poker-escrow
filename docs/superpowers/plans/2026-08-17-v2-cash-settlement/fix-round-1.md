# Fix round 1 — cold review (AF-11 Reader 1 + AF-12 Reader 2)

Both readers: FIX FIRST. Findings consolidated, deduped, assigned. Two
cross-cutting rulings decided as D17 (base-ref git diffs) and D18 (D16
ownership + hard-fail parity). Each doc's drafter applies its row; the
orchestrator verifies the blockers by construction before GO.

| # | Finding(s) | Doc | Fix |
|---|---|---|---|
| B1 | AF-11.1 | P1+P2 | **Chip/wei denomination.** Ruling: receipt stack/deposit fields are **wei**; the client's chip engine converts at `wei_per_chip = deposit_wei / starting_chips` fixed at `(0,0)`. P1: receipt builder takes wei, converts engine chips→wei at build; marker sb/bb carried in **chips** (replay is chip-space), receipt stacks in **wei**; state both unit domains explicitly. P2: unchanged (already wei) — add a one-line unit note. P3 replay: seed `BettingReplay` from **chip-space** (marker sb/bb + a chips view), settle overlay in wei via the `(0,0)` rate; state the two-space split. This is the seam D1 exists for — record it in artifact-formats §1 as an amendment. |
| B2 | AF-11.2 | P3+P4 | **dueAt arity.** P3: make `dueAt(session, completingFiledAt)` two-arg (the caller supplies the birth), OR P4 passes through `_resolveTerminal` which already carries it. Pick two-arg `dueAt`; P4's calls become correct; delete P4 open-question-1's wrong-symbol reasoning. |
| B3 | AF-11.3 | P6 | **Buyin V2 executor side unowned.** P6 owns BOTH ends of its new message pairs: add tasks for Buyin-side receivers of `vault:derive-key-v2`/`vault:post-marker-v2` and their `-result-v2` senders (vault repo — lift P6's side-effect boundary for these specific vault files, or split into a P6-vault addendum task). Without it session-key encryption + marker post have no executor. |
| B4 | AF-11.4, AF-12 X-1 | P1,P2,P3 | **D16 per D18.** Apply D18 verbatim: P2 owns copy+gate, hard-fail, delete fallback-passes. |
| B5 | AF-12 X-2, P3-1 | all | **git-diff gates per D17.** Every isolation gate gets a base ref; the two P3 `--stat|grep phase2Act` gates become content-greps; P7 close-out uses non-empty form. |
| B6 | AF-11.2/P4-1, P4-2, P4-3 | P4 | **readyTime coverage.** Add a ≥3-action alternating-`phase2Act` fixture with real elapsed time asserting each actor's bank measures from the PREVIOUS action's filedAt (handoff baseline); a late-counterparty-posting fixture asserting readyTime moves to the posting ts; a two-player attribution fixture. |
| B7 | P2-2, P7-4 | P2+P7 | **D15 guard fires.** P2: a forge test asserting DeployV2's non-spec-duration `require` reverts with its exact string, + complement. P7: three `cast call` duration read-backs against Deploy A. |
| B8 | P6-1 | P6 | **Gate 1 threshold** pinned to P1's shipped count + a stated per-task minimum, not "summed at completion." |
| M1 | P3-2 | P3 | Out-of-turn candidate fixture (signer ≠ replayed toAct → skipped/chain stops). |
| M2 | P3-4 | P3 | Contract-side Merkle leaf-shape fixture (omit uint8(pos) → root differs → real postShares fails) + position-mismatch negative (share@p, deck@q). |
| M3 | P7-1,P7-2,P7-3 | P7(+P2) | Record expected winner/split BEFORE resolve() for endings 1&4; swap seat roles in ending 2 (and P2's test_S_one_filing fixture) so per-duty is tested both directions; make ending-1 hands lopsided. |
| M4 | P7-5 | P7 | `--root .../contracts` (+`--json`) on all 6 forge inspect sites. |
| M5 | P6-3, P1-4 | P1+P6 | Distinct D14 markers per rule (`load-bearing — do not relax (D14: <rule>)`); grep the marker not the count; fixes P1's exact-2 audit collision. |
| M6 | AF-8 open items, P4-4/5/6, P4 C10 | P4 | Gate 6 runnable (path-scoped or drop); make short-duration bank≠grace (30/45) to catch a swap. |
| m* | AF-11.10-14, P5-1/2/3, P6-4, P7-6, P3-3/5/6, P2-1 | resp. | Minors: AF-4 rationale reworded to §5.4-precedence; message-name drift; marker-persistence owner; symbol mis-attributions; disputeOpenedAt==0 guard; P5 window-readback fixture at a distinctive duration; copy-grep→render; P6 RPC blacklist widened; P7 reserve threshold numeric; P3 laziness/human-read/payout-assert gates tightened. |
