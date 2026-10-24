# Vault

**Status:** Maintenance

A standalone local app that escrows a crypto buy-in for a heads-up poker
session (played via Loke's separate poker client) and settles it afterwards —
no third party ever holds the money or decides who won. Two stages: V1
(winner-takes-all sit-and-go, small) and V2 (cash game, structurally harder,
not started until V1 runs). V1's design: `docs/superpowers/specs/vault-handover.md`.
V2's: `docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`.

## Working agreement

- Run `forge test` (or `npx hardhat test` if Foundry wasn't available) before
  claiming any contract change works. A claim about contract behavior is not
  verified until the test suite actually ran.
- Testnet (Base Sepolia) only. No mainnet path gets written, ever, without an
  explicit new instruction — see the spec's "Refuse to build" section.
- Never handle a seed phrase. A raw testnet deploy key only, and `.env` goes
  in `.gitignore` before the key file exists, not after.
- Before any deploy or any command that touches a real network, say so
  explicitly and print the chain ID — don't infer consent from an earlier
  "deploy" in the conversation.
- The deploy key and the poker client's session key must never end up in the
  same variable, file, or process. Different lifetimes, different blast
  radius — see OVERVIEW.md's design intent section.
- Say plainly, in every report, which parts were actually run (tests,
  builds) versus which parts cannot be executed in this sandbox (real RPC,
  real wallet, real deployment) — never blur the two.

## Documentation index

<!-- MANDATORY, case-sensitive header. docs-check walks this table to verify
     every doc in the repo is reachable; anything unreachable gets flagged as
     an orphan. Add a row whenever you add a doc. -->

| Document | Purpose |
|---|---|
| [README.md](README.md) | Human entry point and commands. |
| [VISION.md](VISION.md) | Why this exists. Written once; not a roadmap. |
| [OVERVIEW.md](OVERVIEW.md) | What is in here right now — the living map. |
| [HANDOVER.md](HANDOVER.md) | Pointer index for active and parked work. |
| [docs/superpowers/specs/vault-handover.md](docs/superpowers/specs/vault-handover.md) | The full design spec — V1, ops guidance. Source of truth **for V1**; its V2 signed-action section is superseded. |
| [docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md](docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md) | **V2's design as it stands** — build from this. Reasoning lives in the parking doc. |
| [docs/arc-history.md](docs/arc-history.md) | Shipped arcs, one paragraph each. |

## Subsystem scopes

<!-- MANDATORY, case-sensitive header. Points at nested CLAUDE.md files.
     Any subfolder with its own authored docs gets one (amendment 4). -->

No nested documentation scopes yet.

<!-- ## Excluded paths
     Optional. Project-specific artifact-shaped folders that the orphan walk
     should skip. Unions with the canonical exclusion list.

| Path | Reason |
|---|---|
| `fixtures/generated/` | Tool-regenerable from the schema. |
-->

<!-- CEILING: 150 lines, target under 100. If this file is growing, the cause
     is almost always a missing Layer 2 doc (DEVELOPMENT / DEPLOYMENT / SCHEMA
     / API_CONTRACTS / AUTH / DESIGN / STATE / HEALTH / OPERATIONS). Bloat is
     diagnostic, not cosmetic. -->
