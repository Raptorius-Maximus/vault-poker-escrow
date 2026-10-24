# Handover

Pointer index for active and parked work. **Rows are one line each** — the
detail lives in the thing the row points at, never here.

This file is the shared bulletin board: it is the one artifact that is exempt
from worktree lane isolation, because other sessions need to read it *now*,
not at merge time. Row flips (born / paused / resumed / done) are atomic
one-line commits in the main checkout, in the same sitting as the transition.

## Live on chain — what the record actually shows

- **V1 HAS SETTLED REAL SESSIONS ON BASE SEPOLIA.** Read off the chain
  2026-09-09, not off any doc in this repo, because every doc here said P7 was
  pending and every doc here was wrong. `Channel` at
  `0xF41A685C7e260397Be07cC75008D29A7457481f6`, blocks 45,398,285–45,442,868:
  **10 sessions opened, 8 reached Active with both sides deposited, 2 settled
  via `ClosedCooperative`**, 1 cancelled before join (guest `0x…dead`, a solo
  test). Three distinct real addresses plus the burn address. The two settled
  sessions ran `0x99507e2c…` ↔ `0xf9e7aba8…` at a 100 gwei buy-in.
  **So "two parties have settled real sessions on a real chain" is TRUE and
  citable.**
- **THE DISPUTE PATH HAS NEVER RUN ON CHAIN, and this is the one to be precise
  about.** Zero `ClaimedByDefault`, zero `Refuted`, zero `Resolved` in the
  entire history — everything settled through the cooperative path, both
  parties agreeing and signing. The bonded liveness challenge, which is the
  actual novel contribution, exists only in the 26 tests. An auditor will ask
  about exactly this, and the five-ending sweep in the operator runbook is what
  was designed to close it.
- Consequence for the arc rows below: their "P7 pending" framing is about V2's
  deploy. It is accurate for V2 and misleading if read as "V1 has never run".

## Blocking

- **ChannelV2 exceeds EIP-170 and cannot deploy to Base Sepolia** — found
  2026-09-09 while building the Stage-1 smoke harness, which could not deploy
  to a stock anvil. Runtime bytecode measured at every setting Foundry offers:
  default 63,661 B · `--optimize` runs=200 40,447 B · runs=1 39,773 B ·
  runs=1 + `--via-ir` **34,061 B** — against a limit of **24,576 B**. A stock
  anvil rejects the best build with `CreateContractSizeLimit`; the same build
  deploys the instant `--disable-code-size-limit` is passed, which is the proof
  it is the limit and nothing else. **The 144-test suite never caught this
  because Foundry's test runner does not enforce the limit** — the contract is
  fully verified and undeployable at the same time. This blocks runbook Stage 2
  outright: no deploy, so no live sweep, so no P7. The fix is structural
  (external libraries via delegatecall, or splitting the contract) and needs a
  decision before any Base Sepolia gas is spent. →
  [smoke harness](test/smoke/smoke.mjs) carries the measurements in comments.

## Ongoing arcs

- **V2 cash settlement** — **BUILDING: P1–P6 built; P5/P6 automated floors
  GREEN, operator smokes + P7 deploy PENDING** 2026-08-18 (poker 486 tests,
  vault forge 144; dispute engine + client-chain wiring done, client posts
  real chain-verifiable shares). P7 = deploy + two-human live sweep, held for
  operator: **`operator-runbook.md`** sequences the held work (local smokes →
  deploy → two-human sweep). Open: AF-45 residual test flake (AF-44 decided:
  keep encryption as-is) —
  [runbook](docs/superpowers/plans/2026-08-17-v2-cash-settlement/operator-runbook.md) ·
  [plan](docs/superpowers/plans/2026-08-17-v2-cash-settlement/README.md) ·
  [spec](docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md) ·
  [parking](docs/superpowers/parking/v2-cash-game-settlement.md)

<!-- Row contract: <name> — <one-line state> → <pointer to scaffold> -->

*(none)*

## Future arcs

- **Profiles and reputation** — a community around the table; the chain already
  knows clean-vs-disputed per wallet, and a profile gates cash games only —
  trigger: V2 shipped AND an ops letter for server storage —
  [parking](docs/superpowers/parking/reputation-and-profiles.md)

- **Watchtower** — object to a stale state on a player'''s behalf, so nobody has
  to show up within 24h — trigger: V2 shipped AND neutral hosting exists —
  [parking](docs/superpowers/parking/v2-watchtower.md)


<!-- Same, plus a trigger condition: what has to become true before this starts. -->

V2: cash game buy-ins and rebuys — trigger: V1 has actually run for real, with two separate people on two separate machines, not before → [docs/superpowers/plans/v2-cash-game-rebuys.md](docs/superpowers/plans/v2-cash-game-rebuys.md)

Fill the missing Layer 2 docs (SCHEMA.md for Channel.sol's Session struct, API_CONTRACTS.md for the poker↔Buyin postMessage handshake, DEVELOPMENT.md, DEPLOYMENT.md for the Foundry deploy flow) — trigger: whenever V2 work starts, since that's the next time this repo gets substantial new development rather than upkeep

## Sidequests

<!-- One-liners. No body, no parking file. Soon-ish. If one accumulates more
     than a session or two of work, promote it to an arc. -->

*(none)*

## Small followups

*Reviewed through: 2026-08-17*

- `[agent-food]` **(poker repo) `reconnect.test.ts` is ~6% flaky under
  full-suite parallel load.** Pre-existing V1 infra: three real-relay
  integration tests (`reconnect`/`relay-caps`/`live`) spawn real
  `relay/server.mjs` children + real WS and get CPU-starved by the ~40
  crypto test files running in parallel, so the reconnect+outbox-replay is
  slow (product logic is correct — nothing is lost, just late; transport
  backoff retries forever). Partly mitigated 2026-08-18 (commit 7ff9b59:
  poll instead of fixed wait, ~17%→~6%). Real fix: a vitest workspace that
  runs the three real-relay integration tests in a sequential project so
  they don't compete with the crypto suite for CPU (measure the
  parallelism/runtime tradeoff). Surfaced by the V2 arc's P6 distrust gate
  (arc `review-findings.md` AF-45).

- `[decision]` **The cheat path still forfeits only the current hand's pot.**
  When abandonment was widened to the whole match (poker@d66a68a), the change
  was kept narrow on purpose: `Game.forfeit`'s default is unchanged, so a
  failed proof verification (`worker.ts`'s catch-all) still claims one pot.
  Arguably a caught cheat should lose the match too — `proofs.ts:41` reads that
  way — but that was never ratified. One call: widen it, or write down that
  the cheat path is deliberately gentler.

<!-- One-line index entry, body inline here. Days-to-weeks lifecycle.
     Every entry is binned:
       [decision]   — a one-call operator item
       [agent-food] — hygiene material for a sweep
     A note without a bin has no consumer (DOCTRINE.md §1.11). -->

*(none)*
