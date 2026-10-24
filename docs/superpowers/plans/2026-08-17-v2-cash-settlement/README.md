# V2 cash settlement — arc plan

Build the cash game the ratified design describes: buy-ins escrowed on
chain, settlement by final stacks, rebuys, and a dispute path sixteen cold
checks could not break. **Spec:**
`docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`
(revision 8, READY WITH DECLARED DEFERRALS, sixteenth check 2026-08-17).
**History:** `docs/superpowers/parking/v2-cash-game-settlement.md`.
Full arc: this README + `decisions.md` + `artifact-formats.md` +
`review-findings.md` + seven phase docs.

## Prerequisites (operator-side)

- [ ] **Base Sepolia top-up** for `0x99507E2c…` — letter to ops sent
      2026-08-17. Needed by P7 at the latest; unblocks the §11.2(a)
      20-sample latency rerun any time.
- [x] **Old trigger overridden, recorded:** the pre-design HANDOVER line
      gated V2 on "V1 run by two people on two machines". The operator
      drove the V2 design and build forward 2026-08-17 regardless; P7's
      live sweep is the natural moment to satisfy the old trigger's
      substance.
- [ ] **P7 live sweep needs a second human + second machine** for the
      real two-seat matches (same need V1 still has open).

## Sequencing

| Phase | Repo | Ships | Depends on |
|---|---|---|---|
| P1 protocol-substrate | poker | hand number, button fix, signed action chains, write-ahead, receipt/marker wire exchange + persistence | formats doc |
| P2 money-frame | vault | Channel V2: keys, depths+bonds, deposits/rebuys, receipts+final, marker acceptance+gate, §1.3, pre-play cancel, pull-payment | formats doc |
| P3 disputes-evidence | vault | window, duties, consolidation+equivocation, **the betting-replay engine (AF-1: legality lives here, P4 reuses it)**, fold/cards/muck/fourth rows, triple check, DLEQ+evaluator on chain | P2 (P1 vectors) |
| P4 disputes-continuation | vault | phase-2 play: action acceptance, banks, graces, bank-fold, symmetric muck | P3 |
| P5 buyin-ui | vault | declared-depth handshake, deposit/rebuy, bond display, auto-filing duties, recovery page | P2 (P3/P4 for dispute UI) |
| P6 client-chain | poker | chain awareness, marker posting+gate, share lifecycle, session keys+encryption, decision clock, four forfeit sites | P1, P2 (P3/P4 for dispute duties) |
| P7 deploy-live-sweep | both | Sepolia deploy (stop-and-ask), live endings sweep, V1 side-by-side check | all |

Cross-doc dependency edges for drafting waves: `artifact-formats.md` →
{P1, P2} → {P3, P5} → {P4, P6} → P7.

## Status

- **Outcome:** V2 cash game playable end to end on Base Sepolia per spec
  §11 — `docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`.
- **Phase:** Phase 7 of 7 — **PREP COMPLETE to the deploy line; awaiting
  operator.** P1–P6 built; P5+P6 automated floors GREEN (poker 486, tsc 0,
  vault build+isolation, forge 144). Everything remaining is operator-gated:
  two local smokes, the real deploy (stop-and-ask), the two-human live sweep.
- **Next authorized action:** OPERATOR — follow `operator-runbook.md`:
  Stage 1 (local P5 + P6 smokes, no real money) → Stage 2 (Base Sepolia
  deploy, STOP-AND-ASK, chain 84532 printed) → Stage 3 (two-human live sweep).
  AF-44 DECIDED (accept as-is, 2026-08-18) — no open operator decisions remain pre-deploy.
- **Lane:** main checkout, both repos. `~/projects/poker` master @ `7ff9b59`.
  `~/projects/vault` master @ (this commit). No worktrees.
- **Last verification:** P7 pre-flight GREEN (no network touched): top-up
  GRANTED 0.00330223 ETH (ops RPC-verified), deploy key file OK (masked),
  `DeployV2.s.sol` compiles, P2–P6 landed. AF-46 caught+fixed (seeding
  rescaled to fit 0.0033). P5/P6 floors green (see `review-findings.md`).
- **Effects crossed:** none (no real-network transaction has been sent by
  this arc; the pre-arc MarkerBench deploy on 84532 was throwaway).
- **Decisions:** `decisions.md`, current through 2026-08-18 (D1–D18 + amendments).
- **Open findings:** AF-43 RESOLVED (live shares). **AF-44 DECIDED** (2026-08-18, accept as-is — signing stays sync, best-effort restore). AF-45 residual
  test flake (HANDOVER followup). **AF-46 RESOLVED** (P7 seeding rescaled to
  the real 0.0033 balance). AF-40/41 advisories. See `review-findings.md`.
- **In-flight:** —
- **Pause:** 2026-08-18. **waiting-on:** operator (+ a second human for the
  live sweep) to run `operator-runbook.md` Stages 1–3, and to decide AF-44.
  All autonomous, non-live work for this arc is complete; the detached run has
  reached its authorized ceiling (real-network + two-human steps are HELD).
