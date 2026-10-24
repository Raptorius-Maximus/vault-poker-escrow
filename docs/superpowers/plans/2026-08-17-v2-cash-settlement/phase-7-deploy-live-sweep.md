# Phase 7 — deploy-live-sweep (both repos, Base Sepolia)

## Goal

Two live deploys of `ChannelV2` to Base Sepolia — one at the spec's real
durations (the contract that survives past this arc), one at short test
durations (the contract this phase spends) — a one-probe confirmation that
V1 sits beside it untouched, and a live sweep of five endings against the
short-duration instance: mutual final, window settlement with per-duty
bonds, fold-terminal dispute, cards-decide dispute, and zero-filings full
refund. Every deploy is a typed HALT (D11: "P7 deploys are stop-and-ask
with the chain id printed"); the sweep itself is the phase-boundary gate,
not a separate probe above it. This phase writes no contract code and no
client code — P2 through P6 shipped everything it exercises. What it adds
is: two real transactions that create production authority, and a human
proving, on the real network, that the six phases' promises hold together.

**Budget is finite and not renewable this arc.** The deploy key
`0x99507E2c…` (full address in `~/projects/.secrets/vault-deploy.env`,
never read into this doc or any chat) holds **~0.0062 test ETH**; ops has
stated no second top-up. Task 1 below turns that into an explicit
gas-budget table before any transaction is sent, not an assumption.

## Inputs from previous phase

**Plan-not-shipped framing.** As of this doc's drafting, P2 through P6 are
plan documents with checker verdicts of REVISE-IN-REVISION (AF-3
through AF-8) — none has actually landed code yet (`README.md`'s Status:
"planning (0 of 7)"). Every artifact this phase reads — `ChannelV2.sol`'s
functions, `DeployV2.s.sol`'s env vars, `src/deploymentsV2.js`'s shape,
`src/mainV2.js`'s message types — is cited from the **phase docs**, not
from source this doc has read directly. **Dispatch-time re-verification is
mandatory**: before running task 2 (the first deploy), re-confirm against
the actually-shipped `contracts/src/ChannelV2.sol` and
`contracts/script/DeployV2.s.sol` that function signatures, revert
strings, and env var names match what this doc assumes. Where P2/P3
themselves still carry an inert token (`TBD-P1-VECTORS`), this doc
inherits the obligation to resolve it before citing byte-exact values, not
to resolve it here.

- **From P2 (`phase-2-money-frame.md`), Outputs to P5 / this phase's own
  read:** `ChannelV2.sol`'s Session interface (`open`/`join`/`cancelOpen`/
  `deposit`), the bond formula (D4: `bond_i = ceilDiv(11 × max(ceilDiv(Mh+Mg,2),
  Mi), 10)`), the two-transaction good ending (file `final`, then call
  `resolve()`), and `DeployV2.s.sol`'s exact interface (task 7): chain-id
  guard identical to `Deploy.s.sol`'s, `PRIVATE_KEY` read via
  `vm.envUint`, `WINDOW_SECONDS`/`BANK_SECONDS`/`GRACE_SECONDS` via
  `vm.envOr`, and the `TEST_DURATIONS=true` override required to deploy
  any non-spec duration set (D15) — **this is the exact form AF-5
  corrected**: no forge `--private-key` flag, the script reads the
  environment variable directly.
- **From P3 (`phase-3-disputes-evidence.md`), Outputs to P4 / this
  phase:** the five-row terminal resolution table
  (`fold` / `cards-decide` / `one-sided muck` / `symmetric muck` /
  `fourth row`), the dispute-filing interface's `fileActions`/
  `postShares` shapes, and the measured worst-case dispute-filing gas
  figure this doc's budget table depends on directly.
- **From P4 (`phase-4-disputes-continuation.md`), Outputs to P7:** the
  additional phase-2-born endings (open fold, bank-fold, live-continuation
  showdown, phase-2-duty muck) exist and are sweep-exercisable against the
  short-duration instance — **this phase's five chosen endings do not
  include any of them**; see Open questions item 2 for why, and the
  descope is stated honestly rather than silently.
- **From P5 (`phase-5-buyin-ui.md`), Outputs to P7 — the exact seam this
  phase uses:** `src/deploymentsV2.js` is "the one file P7 edits to go
  live — add the real Base Sepolia entry under key `84532`, same shape
  V1's `src/deployments.js` already uses." The local-anvil operator floor
  (steps 1–13) is this phase's own deploy-and-smoke pattern, graduated
  from `http://localhost:8545` to `https://sepolia.base.org` — task 2/3
  below reuse its exact deploy-command shape (AF-5's fixed env-var form),
  not a rederivation.
- **From P6 (`phase-6-client-chain.md`), Outputs to P7:** "the two-tab
  smoke P7's live sweep graduates from local anvil to Base Sepolia — same
  steps, real gas, real confirmation latency (already measured,
  RESULTS.md)"; the `?vault=2` URL convention this phase's invite links
  carry forward; and a named vault-repo gap (`mainV2.js` needs a
  `liveHand` field added to its hello message) that P5's shipped scope
  doesn't yet cover — flagged there for "whoever revises P5 next," not
  this phase's to fix, but this phase's task 5 (deal-gate confirmation
  during real play) should watch for whether that gap actually blocked
  anything and note it if so.
- **`prototypes/marker-latency/RESULTS.md`** (live measurement, same deploy
  key, chain 84532): full-size marker+receipt post = **61,740 gas**,
  measured send→confirm 0.7–2.9 s (n=3), then a 20-sample rerun once
  funded: **median 792 ms, p95 1,261 ms, max 2,767 ms** — "§11.2(a) is
  closed." **Operational finding, load-bearing for this phase's task
  design:** 17 of 20 first-attempt sends failed transiently
  (`sepolia.base.org` is load-balanced; nodes lag each other on nonce
  state); **a single retry after 2 s fixed every one (17/17).** Every
  cast/forge command in this phase's tasks assumes this — a failed send
  is the expected common case, not a fault, and the fix is retry-once,
  not diagnose.
- **`docs/arc-history.md`'s V1 entry**: deployed to Base Sepolia at
  `0xF41A685C7e260397Be07cC75008D29A7457481f6`, dispute window 1800 s (30
  min); closing sentence: "Not yet run by two separate people on two
  separate machines — that's V2's trigger condition, still open." Task 9
  (ending 1) satisfies this; task 10 amends the sentence.
- **`contracts/script/Deploy.s.sol`** (V1's shipped deploy script, read
  directly — this file exists today, unlike `DeployV2.s.sol`): the exact
  pattern `DeployV2.s.sol` mirrors — `BASE_SEPOLIA = 84532`,
  `ANVIL_LOCAL = 31337` chain-id guard, `vm.envUint("PRIVATE_KEY")`,
  `console2.log` of chain id / deployer / balance / window before
  `vm.startBroadcast`. `Channel.sol:44`'s `uint256 public immutable
  defaultWindow` is this phase's V1 smoke probe target (task 4) — a free
  `cast call`, no gas, no wallet.
- **Spec** (`docs/superpowers/specs/2026-08-16-v2-cash-settlement-consolidated.md`,
  revision 8): §7 ("V1 and V2 run side by side... testnet only... no
  server-side storage without a further letter"), §11.7 ("Deploy is a
  stop-and-ask, with the chain id printed"), §5 (the two-phase dispute
  this sweep exercises), §8 items 1/2/6 (a dispute is a legal way to end
  a session early; absence burns a bond; gas is a precondition for
  defending yourself — all three are what this sweep is proving, not
  just building).
- **`decisions.md`**: D11 (testnet-only, chain-id guard, V1 untouched,
  P7 deploys are stop-and-ask), D13 (deploys happen only in P7), D15
  (durations are deploy parameters; spec values are the only
  production-legal ones; P7 deploys a short-duration instance alongside
  the real one specifically for this sweep).
- **`review-findings.md`**: AF-1 confirmed D15 as the resolution to "P7's
  live dispute sweep vs. the 24-hour window was undecided"; AF-4's
  orchestrator ruling (zero-filings full refund / one-or-more-filings
  per-duty bond fate, **not** a both-burn) is exactly ending 2 and 5's
  contract-level behavior, cited by fixture name below.
- **`README.md`'s Prerequisites**: the Base Sepolia top-up is "needed by
  P7 at the latest" (checked off as satisfied — see budget note above);
  the old HANDOVER trigger override is recorded, and "P7's live sweep is
  the natural moment to satisfy the old trigger's substance" — task 9
  does this; "P7 live sweep needs a second human + second machine" — every
  task below that needs two live seats says so explicitly.

## Files touched

**Vault repo:**
- `src/deploymentsV2.js` — new entries under chain id `84532`: the
  production (Deploy A) address permanently, temporarily repointed to the
  sweep (Deploy B) address for tasks 5–9, reverted to Deploy A in task 10.
- `HANDOVER.md` — the "V2 cash settlement" row under Ongoing arcs updated
  (task 10); one orphaned stale-trigger line removed (task 10).
- `docs/arc-history.md` — a new V2 entry (draft, for the arc-end review to
  confirm); V1's entry's closing sentence amended (task 10).
- No edits anywhere under `contracts/` — this phase deploys and calls an
  already-built contract; D11/D13's untouched-V1 boundary and P2–P4's
  already-closed phase gates mean there is no contract source for this
  phase to touch.

**Poker repo:** none edited. Used live, unmodified, via its already-shipped
P1/P6 code, for the actual hand play in tasks 5, 7, and 8.

## Tasks

**Task-ordering note.** Tasks 2–3 (the two deploys) and 4 (V1 smoke) must
run before any of tasks 5–9 (the sweep), since the sweep targets Deploy
B's address. Tasks 5–9 have no strict ordering dependency on each other
in principle — each opens its own fresh session — **with one exception:
task 1's seeding step sizes the host wallet's buffer (≥0.0027 ETH) on
the assumption that task 6 (ending 2, the only ending that burns a bond)
runs somewhere in this numeric sequence and every later task's `open()`/
`join()` recycles the same, fully-returning 0.0016 ETH baseline
afterward.** Running tasks 5–9 out of this numeric order is safe without
resizing anything (the math only depends on the burn happening once,
not on where); skipping task 6 entirely, or running it more than once,
is not — re-check task 1's seeding arithmetic first if either is
considered. Task 10 is last by construction (it records what happened).

**Phase-base SHA (D17).** Record it once, at dispatch, before task 1
starts, so task 10's own isolation gate has a base to diff against:

    git -C /home/dev/projects/vault rev-parse HEAD

Write the resulting SHA down in the session record as `PHASE-7-BASE-SHA`
— task 10's verification probe below diffs against it, never against
`--stat` alone (D17: `--stat` compares worktree to index and reads empty
once a commit lands, which is vacuous under this repo's commit-to-master
flow).

---

### Task 1 — Pre-flight: gas budget arithmetic and prerequisite sign-off

> **AMENDMENT 2026-08-18 (AF-46) — real balance is 0.0033 ETH, not ~0.0062;
> seeding rescaled to fit.** The top-up came back GRANTED
> (`~/letterbox/inbox/2026-08-17-base-sepolia-topup-reply.md`, RPC-verified by
> ops): deploy key `0x99507E2c…` holds **0.00330223 ETH**, and there is **no
> second top-up this arc**. Every ~0.0062 figure in the steps below is stale.
> The seeding plan (host 0.0029 + guest 0.0018 = 0.0047) does NOT fit 0.0033.
> The buy-in amounts are symbolic test wagers, so scale them ×0.5 (all
> mechanics work identically at half size; gas is negligible either way — ops
> priced the whole ~20-tx plan at <0.00001 ETH):
>
>     baseline buy-in per wallet: 0.0008 ETH   (was 0.0016)
>     host wallet seed:  0.0015 ETH            (was 0.0029 — buy-in + burned bond + gas)
>     guest wallet seed: 0.0009 ETH            (was 0.0018 — buy-in + gas)
>     total seeded:      0.0024 ETH            (was 0.0047)
>     deploy-key reserve after 2 deploys: 0.0033 − 0.0024 − 0.0000042 ≈ 0.00089 ETH (~27%)
>
> So in step 5 send `--value 0.0015ether` to the host player wallet and
> `--value 0.0009ether` to the guest, and in the handshake declare depths at
> the 0.0008-scale (e.g. both "max" ≈ 0.0008, "put in now" ≈ 0.0004). Step 1
> still re-confirms the balance live with `cast balance` before anything is
> sent — if it reads materially below 0.0033, stop. Everything else in Task 1
> (the gas ceiling table, the sensitivity thresholds, the payer split, the
> deploy-key-never-msg.sender rule) stands unchanged; only the value-transfer
> figures move. Gas was never the binding constraint — the wagered principal
> is, and it now fits with ~27% headroom.


**Goal:** turn the "no second top-up" constraint into an explicit,
written-down number before any transaction is sent, and confirm every
`README.md` prerequisite this phase depends on is actually true right now.

**Steps:**
1. Confirm the balance directly rather than trusting the README's `~0.0062`
   figure as current:

       cast balance 0x99507E2c... --rpc-url https://sepolia.base.org

   (Use the address in full from `~/projects/.secrets/vault-deploy.env` —
   `grep PRIVATE_KEY` never; read the address only, e.g. via
   `cast wallet address --private-key $PRIVATE_KEY` after sourcing the
   file, or from the operator's own record of it. Never print the private
   key.)
2. **Gas budget table — a deliberate worst-case ceiling, not the real
   payer breakdown.** This table charges every transaction in the sweep
   against a single pool, as if one wallet funded all of it. It does
   **not** reflect who actually signs each transaction — Open Question 1
   below states the default payer split explicitly (player wallets pay
   for `open`/`join`/`deposit`/markers/`resolve`/`withdraw`, and, per
   task 8's own design, each player posts their own shares from their
   own wallet too — **the deploy key never appears as `msg.sender` for
   any of this sweep's dispute-filing or session transactions**, matching
   this repo's own working agreement that the deploy key and any
   session/player key must never share a variable, file, or process).
   This ceiling table exists so the sensitivity check in step 3 answers
   "could the whole sweep's worth of gas be covered from one balance if
   it had to be" — the actual gate on the deploy key's own balance is the
   much smaller **deploy-key-only** figure directly below the table.

   Every figure below is either directly measured (marked M) or a rough,
   unmeasured estimate scaled from a measured figure (marked E,
   informational, matching P2/P3's own "non-blocking, informational"
   gas-comparison convention). Effective gas price used throughout:
   **0.006 gwei** (M, RESULTS.md's measured run-time price; flagged
   explicitly as a single historical sample, not a floor — step 3 covers
   the risk if it's wrong):

   | Item | Count | Gas each | Subtotal gas | Basis |
   |---|---:|---:|---:|---|
   | Contract deploy | 2 (A + B) | 350,000 | 700,000 | E (per-deploy figure given) |
   | `open()` + `join()` | 5 endings × 2 calls | ~135,000 avg | 1,350,000 | E |
   | `fileMarkerWithReceipt` (routine per-hand) | ~10 hands (tasks 5 and 7 only — endings 1 and 3; task 8's disputed hand is filed as evidence, never a routine marker close, and task 9 plays no hand at all) | 61,740 | 617,400 | **M** |
   | `openDispute()` | 4 (endings 2, 3, 4, 5 — tasks 6, 7, 8, 9) | ~50,000 | 200,000 | E |
   | Evidence filings (`fileReceipt`/`fileActions`, non-showdown) | ~10 calls | ~50,000 avg | 500,000 | E |
   | Ending 4's (task 8) full dispute filing (actions + 18 shares to river + evaluator) | 1 | 27,000,000 | 27,000,000 | **M** (spec §11.2(b), worst-case measured) |
   | `resolve()` | 5 | ~100,000 avg | 500,000 | E |
   | `withdraw()` | 10 (2 per ending) | ~50,000 | 500,000 | E |
   | **Ceiling total** | | | **~31,367,400 gas** | |

   Cost at 0.006 gwei: `31,367,400 × 0.006×10⁻⁹ ≈ 0.000188 ETH`.

   **Deploy-key-only figure (the one that actually gates this key's
   balance, given the payer split above):** the two deploys —
   **700,000 gas ≈ 0.0000042 ETH** at 0.006 gwei — **plus the player-
   wallet seeding value transfers task 1 step 5 sends (AF-10/AF-11.9):
   0.0047 ETH** (0.0029 ETH to the wallet that will end up
   absent-and-burned in task 6, 0.0018 ETH to the other; the transfers'
   own gas is two plain sends, ~21,000 gas each, ≈0.00000025 ETH,
   negligible). **Total deploy-key spend ≈ 0.0047042 ETH**, against a
   ~0.0062 ETH balance: **reserve ≈ 0.0015 ETH (~24%)** — thinner than
   the deploys alone would suggest, but still positive with margin, and
   the number gate 3 (Phase-boundary verification) checks against
   directly. Unlike the deploys, this figure is *not* insensitive to
   price risk in the same way — the seeding is a value transfer, not
   gas-denominated, so a price spike doesn't move the 0.0047 ETH itself,
   only the ~0.00000025 ETH of transfer gas riding alongside it; the
   dominant remaining price risk stays where step 3 puts it, in the
   sweep's own gas spend, which player wallets carry, not this key.
3. **The ceiling table's own sensitivity — relevant only if a single
   pool really does have to cover the whole sweep** (the overrule case
   above, or simply as a stress-test of "what if"). Gas *price* is the
   dominant risk, not gas *units* — units are mostly measured EVM facts
   (P3's own `forge snapshot`, task 13 of that phase, will pin this
   exactly once P3 ships); price is a single historical sample from a
   calm network. Three totals, each with its own breakeven multiple
   against a 0.0062 ETH pool (baseline 0.006 gwei = 1×):

   | Scope | Total gas | Cost @ 1× (0.006 gwei) | Breakeven multiple |
   |---|---:|---:|---:|
   | Full ceiling (all 5 endings, ending 4 full river) | 31,367,400 | 0.000188 ETH | **~33×** (~0.20 gwei) |
   | Flop-only ending 4 (7 required positions, 14 shares — see caveat below) | 25,367,400 | 0.000152 ETH | **~41×** (~0.24 gwei) |
   | Ending 4 dropped entirely (4 endings only) | 4,367,400 | 0.0000262 ETH | **~237×** (~1.4 gwei) |

   Ending 4's dispute filing is the whole story: 27M of the 31.4M-gas
   ceiling (~86%), and dropping it takes the breakeven from ~33× to
   ~237×. **This is threshold-gated, not two equal alternatives:**
   - **At or below ~33× baseline (roughly ≤0.2 gwei):** the full ceiling
     fits; no trimming needed.
   - **Between ~33× and ~41× (roughly 0.2–0.24 gwei):** the full ceiling
     no longer fits, but the flop-only trim does — use it.
   - **Above ~41× (roughly >0.24 gwei):** flop-only *also* overshoots
     (checked directly: at 100× baseline, flop-only costs ~0.0152 ETH
     against a 0.0062 ETH pool — over by ~0.009 ETH). The only fit left
     is dropping ending 4 entirely and running the other four, or
     pausing and writing a letter rather than stretching a budget the
     arithmetic says won't cover it.

   **Caveat on the flop-only trim:** task 8's default construction (an
   all-in preflop hand, checked to river) is the simplest way to reach
   the contract's `COMPLETE` termkind, and per that task's own citation
   of P3's task 10 comment, an all-in runout "still reaches River" by
   construction — whether a genuine `COMPLETE` dispute can terminate at
   flop instead (7 positions, not 9) depends on facts about
   `_resolveTerminal`'s street-determination logic that this doc cannot
   confirm until P3 actually ships. Re-verify against the shipped
   `ChannelV2.sol` before relying on the flop-only row above; if it turns
   out `COMPLETE` only ever resolves at river in the shipped contract,
   the only trim available above ~33× is dropping ending 4 outright, and
   the ~33×/~237× rows still stand on their own.

   Run task 1 step 4's live price check again immediately before task 8
   specifically (not just once at the start of the evening) — this
   table's thresholds are what that re-check is compared against.
4. Check current gas price live, right before task 2:

       cast gas-price --rpc-url https://sepolia.base.org

   YES/NO: printed price is within an order of magnitude of 0.006 gwei
   (i.e., below ~0.06 gwei). If not, stop and re-run step 3's sensitivity
   table with the real number before proceeding to any deploy.
5. **Seed the two player wallets from the deploy key (AF-10's coherence-
   pass ruling — see the amendment block at the end of this doc for the
   original finding; this step is where it actually executes, corrected
   for the per-wallet peak bug AF-11.9 caught).** Neither player wallet
   has a stated funding source otherwise, and a beginner operator would
   otherwise hit "insufficient funds" cold at **task 5** (ending 1's
   `open()` call — the sweep's first player-wallet transaction, not task
   4, which spends nothing from either player wallet). A plain value
   transfer is not key-sharing (the deploy-key/session-key segregation
   rule governs keys living in the same variable/file/process, not one
   key funding another's balance), and clicking a testnet faucet
   repeatedly is explicitly rejected as the funding method (ops' sizing
   lesson, letterbox 2026-08-17 — the same lesson this key's own earlier
   dry-run taught).

   **Burn-aware sizing, not a flat split (AF-11.9's fix):** every ending
   except ending 2 (task 6) fully returns each wallet's principal via
   `resolve()` + `withdraw()` — one wallet only needs the recycled
   0.0016 ETH baseline sitting available at a time. Ending 2 is the one
   exception: per M3/P7-2's swapped seat (task 6), the **host** wallet is
   the one that goes absent and burns its bond there, permanently losing
   0.0011 ETH it never gets back. If the host wallet is seeded with only
   the flat 0.0016 ETH baseline, it has just 0.0005 ETH left after task
   6 — short of the 0.0016 ETH task 7 and task 8 each need next. Seed
   the host wallet with **0.0016 + 0.0011 = 0.0027 ETH minimum**; round
   up for gas headroom across the whole sweep's worth of transactions
   from that wallet (~0.0002 ETH, matching this doc's own per-tx gas
   estimates, task 1 step 2's table):

       host wallet seed:  0.0016 + 0.0011 + 0.0002 (gas) = 0.0029 ETH
       guest wallet seed: 0.0016 + 0.0002 (gas)           = 0.0018 ETH
       total seeded:       0.0047 ETH

   Two transfers, before task 5, each a plain value send (never a
   contract call, never the two keys touching the same process):

       cast send <host player wallet address>  --value 0.0029ether --rpc-url https://sepolia.base.org --private-key $PRIVATE_KEY
       cast send <guest player wallet address> --value 0.0018ether --rpc-url https://sepolia.base.org --private-key $PRIVATE_KEY

   ($PRIVATE_KEY is still the deploy key, sourced in step 1 above — the
   *only* place in this whole phase it signs anything besides the two
   deploys.) After both sends: deploy key balance ≈ `0.0062 − 0.0047
   (seeding) − 0.0000042 (two deploys, task 1 step 2's table) ≈ 0.0015
   ETH` remaining — thin, matches gate 3's numeric reserve threshold
   (Phase-boundary verification) with margin, and needs no second
   top-up. **YES/NO: both transfers confirmed**
   (`cast balance <address> --rpc-url https://sepolia.base.org` on each
   player wallet shows the seeded amount, before task 5 begins).
6. **Prerequisite sign-off**, each YES/NO, read aloud to the operator:
   - The second human is available for this session (tasks 5, 7's Buyin
     tabs, and every ending that needs two live seats) — README.md
     Prerequisites, third item.
   - `~/projects/.secrets/vault-deploy.env` exists and, when sourced,
     populates `$PRIVATE_KEY` (verify via masked prefix only —
     `echo ${PRIVATE_KEY:0:6}` after `source`, never the full value; if
     empty, stop, this is not a "try again" situation, it's "find the
     right file first").
   - P2 through P6 have actually landed code in `contracts/` and `src/`/
     `poker/src` — re-confirm against a real `git log`/`forge build`
     right now, not against this doc's own "Plan-not-shipped" framing
     above, which was true only at drafting time.

**Verification probe:** step 2's table exists in the session record with
a real balance from step 1 substituted in; step 4's YES; step 5's YES
(both seed transfers confirmed); step 6 all YES.

**Dispatch:** `inline (orchestrator)` — mostly arithmetic and file/env
checks; step 5 is the one live-network write in this task (two plain
value transfers, deploy key to the operator's own two player wallets) —
lower stakes than a contract deploy (nothing irreversible, no new
production authority created) so it doesn't carry its own typed-HALT
block, but it is real spend and belongs in the session record like every
other transaction this phase sends.

---

### Task 2 — Deploy A: production instance, spec durations

**Goal:** the `ChannelV2` deployment meant to outlive this arc — spec's
real 24h window / 6h bank / 6h grace (D15), recorded permanently in
`src/deploymentsV2.js`.

**Typed HALT — production authority + live effect. Read this whole block
before running anything.** This transaction deploys a new contract to
**Base Sepolia, chain id 84532**, spending real (test) ETH from the
budget task 1 just computed, and the resulting address is what every real
V2 cash game this arc enables will use going forward. It cannot be undone
— a bad deploy means a second deploy and an abandoned address, not a fix.
**Do not run step 2 until the operator has explicitly said to proceed,
having read the chain id and duration values this step's dry-run prints.**

**Steps:**
1. `source ~/projects/.secrets/vault-deploy.env` — loads `PRIVATE_KEY`
   into this shell only; never typed, never pasted, never echoed in full.
2. Dry-run first (no `--broadcast`) to see the console output without
   spending anything:

       ~/.foundry/bin/forge script contracts/script/DeployV2.s.sol \
         --root /home/dev/projects/vault/contracts \
         --rpc-url https://sepolia.base.org

   Read the printed `Chain ID`, `Deployer balance`, and duration lines.
   **YES/NO, out loud: Chain ID reads 84532, and the three duration lines
   read 86400 / 21600 / 21600 (24h/6h/6h) with no `TEST_DURATIONS` line
   set.** If either is wrong, stop — do not proceed to step 3.
3. **Operator's explicit go-ahead, in chat, required here** — not
   inferred from an earlier "let's do P7."
4. Broadcast:

       ~/.foundry/bin/forge script contracts/script/DeployV2.s.sol \
         --root /home/dev/projects/vault/contracts \
         --rpc-url https://sepolia.base.org \
         --broadcast

   If the send fails transiently (RESULTS.md's 17/20 finding — expected,
   not a fault): wait 2 s, re-run the identical command. `forge script`
   is safe to re-run after a failed *send* (nothing was broadcast); if
   partway through the run it's unclear whether a transaction actually
   confirmed, check `cast code <address> --rpc-url https://sepolia.base.org`
   for the address `console2.log`'d in the last successful run — nonzero
   bytecode means it landed.
5. Record the deployed address. Edit `src/deploymentsV2.js`:

       export const DEPLOYMENTS_V2 = {
         84532: { address: '<Deploy A address>', name: 'Base Sepolia (V2 production)', explorer: 'https://sepolia.basescan.org/address/<address>' },
       };

**Verification probe:**

    cast code <Deploy A address> --rpc-url https://sepolia.base.org

YES/NO: returns nonzero bytecode (not `0x`).

**Duration read-back (B7/P7-4) — free, no gas, and the actual gate on
D15 for the contract that outlives this arc.** The dry-run print in step
2 confirms what the *script* intended to deploy; it does not confirm what
actually got stored on chain — a constructor-argument-order bug (e.g.
`bank` and `grace` swapped, both defaulting to the same 21600 s value,
so the D15 assertion in `DeployV2.s.sol` cannot catch it either, since
both sides of that specific swap read as equal) would ship a wrong
duration silently and nothing else in this doc would ever notice, since
Deploy A may not face a real dispute for months. Three independent reads,
immediately after step 5:

    cast call <Deploy A address> "window()(uint256)" --root /home/dev/projects/vault/contracts --rpc-url https://sepolia.base.org
    cast call <Deploy A address> "bank()(uint256)"   --root /home/dev/projects/vault/contracts --rpc-url https://sepolia.base.org
    cast call <Deploy A address> "grace()(uint256)"  --root /home/dev/projects/vault/contracts --rpc-url https://sepolia.base.org

`TBD-P7-ABI` (a seventh decision point, additional to the six Open
Question 4 enumerates for the sweep tasks — this one belongs to the
deploy task itself): confirm the exact public-getter names first via
`~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
if P2's task 1 named the immutables differently than `window`/`bank`/
`grace`. **YES/NO, all three:** `window() == 86400`, `bank() == 21600`,
`grace() == 21600` — not just "some value," the exact spec figures,
read directly off the deployed bytecode rather than trusted from the
simulation.

**Dispatch:** `operator-run (typed HALT — production authority + live
effect)`.

---

### Task 3 — Deploy B: sweep instance, short test durations

**Goal:** the throwaway instance the whole sweep runs against —
`WINDOW_SECONDS=120 BANK_SECONDS=60 GRACE_SECONDS=60` (D15, matching P5's
own local-anvil floor exactly, now on the real network).

**Typed HALT — production authority + live effect**, same standing as
task 2. This instance is disposable by design (D15's whole point — a
sweep against real 24h/6h/6h costs days of calendar time), but it is
still a real Base Sepolia deploy spending real budget, and every dispute
this phase files against it is a real transaction with real gas, not a
rehearsal.

**Steps:**
1. `source ~/projects/.secrets/vault-deploy.env` (same shell, key already
   loaded from task 2 if run in the same session — re-source if not).
2. Dry-run:

       TEST_DURATIONS=true WINDOW_SECONDS=120 BANK_SECONDS=60 GRACE_SECONDS=60 \
       ~/.foundry/bin/forge script contracts/script/DeployV2.s.sol \
         --root /home/dev/projects/vault/contracts \
         --rpc-url https://sepolia.base.org

   **YES/NO, out loud: Chain ID reads 84532, and the duration lines read
   120 / 60 / 60 with `TEST_DURATIONS: true` logged.**
3. **Operator's explicit go-ahead, in chat, required here.**
4. Broadcast (same command plus `--broadcast`; same retry-after-2s
   recovery as task 2 step 4).
5. Repoint `src/deploymentsV2.js` at Deploy B **temporarily**, for the
   sweep only:

       export const DEPLOYMENTS_V2 = {
         84532: { address: '<Deploy B address>', name: 'Base Sepolia (V2 sweep — SHORT DURATIONS, throwaway)', explorer: 'https://sepolia.basescan.org/address/<address>' },
       };

   `npm run build`. **This is reverted back to Deploy A in task 10** —
   until then, anyone opening Buyin against V2 on Base Sepolia is talking
   to the short-duration sweep instance, not the production one. Note
   this out loud so the second human doesn't get confused if they check
   the deployed address against task 2's.

**Verification probe:** `cast code <Deploy B address> --rpc-url
https://sepolia.base.org` returns nonzero bytecode; `grep -n "84532"
src/deploymentsV2.js` shows Deploy B's address, not Deploy A's.

**Dispatch:** `operator-run (typed HALT — production authority + live
effect)`.

---

### Task 4 — V1 side-by-side check

**Goal:** confirm V1 at `0xF41A685C7e260397Be07cC75008D29A7457481f6`
is untouched and still functional, satisfying spec §7's "V1 and V2 run
side by side" as a checked fact, not an assumption.

**Steps:**
1. Free, no-gas, no-wallet read:

       cast call 0xF41A685C7e260397Be07cC75008D29A7457481f6 "defaultWindow()(uint256)" --rpc-url https://sepolia.base.org

   YES/NO: returns `1800` (30 min, `Channel.sol:44`, `arc-history.md`'s
   recorded deploy value — this is an `immutable` set once at
   construction, so any value other than 1800 means either the wrong
   address or a chain reorg/state corruption serious enough to stop and
   write a letter, not continue).
2. Optional, if time allows and does not touch the sweep budget: open
   Buyin's existing V1 page (`http://localhost:8790/?session=<any fresh
   id>&seat=host`) and confirm it still renders the V1 open-a-session
   screen against the same contract address it always has. This is a UI
   smoke, not a chain write — skip if the evening is short; step 1 alone
   already proves the contract itself is alive.

**Verification probe:** step 1's YES.

**Dispatch:** `operator-run` (a single free command; no HALT needed — no
value moves, nothing is written).

---

### Task 5 — Ending 1: mutual final happy path

**Goal:** two humans, two machines, a real hand or several, a signed
`final`, and `resolve()` + `withdraw()` on both sides. This also
satisfies V1's old "run by two people on two machines" trigger — task 10
records that.

**Typed HALT — production authority + live effect. Read this whole block
before starting step 1.** This task's `open()` call is the sweep's first
transaction against Deploy B (task 3) — the first point real (test) ETH
from two live human wallets gets locked into a session on the real
network, and the first point this phase's budget arithmetic (task 1)
stops being a table and starts being an actual spend. Every ending from
here through task 9 follows the same standing: a fresh session, real
gas, real confirmations. **Do not open the first Buyin tab (step 1)
until the operator has confirmed, out loud: both humans are ready, the
chain id showing in each Buyin tab reads 84532, and Deploy B's address
(task 3) is the one `src/deploymentsV2.js` currently points at** (task 3
step 5 — if task 10's revert already ran by mistake, this task is
pointed at production Deploy A instead, which is the wrong contract for
a throwaway sweep session; check before proceeding, not after).

**Setup (shared across tasks 5–9 — declared depths and bond, worked once
here, reused by every later ending's table):** `maxHost = maxGuest =
0.001 ETH`. Per D4 (`avgCeil = ceilDiv(Mh+Mg,2)`, `base_i =
max(avgCeil, Mi)`, `bond_i = ceilDiv(11·base_i, 10)`):

    avgCeil = ceilDiv(0.001 + 0.001, 2) = 0.001 ETH
    base_host = base_guest = max(0.001, 0.001) = 0.001 ETH
    bond_host = bond_guest = ceilDiv(11 × 0.001, 10) = 0.0011 ETH

Initial deposit `0.0005 ETH` each (`msg.value = 0.0016 ETH` at `open()`
and `join()`, split into `0.0011` bond + `0.0005` deposit per the
contract's own arithmetic, P2 decision 3). **Total pool per session:
`2 × (0.0005 + 0.0011) = 0.0032 ETH`** — every ending below settles this
same 0.0032 ETH, which is a built-in check: whatever a resolve credits
plus whatever it burns must sum to exactly 0.0032 ETH, every time. Reuse
these numbers for endings 6–9 too (fresh session each time — the same two
wallets can reuse the same round figures without confusion).

**Operator-run, two humans required:**
1. Both machines: `cd poker && npm run dev`; open
   `http://localhost:5173/?vault=2&room=<fresh id>` — one host, one guest
   — per P6's task 1. Each Buyin-opening button now opens `v2.html`
   against Deploy B (task 3's temporary repoint).
2. Complete the declared-depth handshake in each Buyin tab using the
   numbers above (P5's floor, steps 6–9, session-key now supplied
   automatically via `vault:sessionkey-v2`, P6's task 2). **YES/NO: both
   tabs reach `Status: Active`.**
3. Play at least two real hands to completion, **playing deliberately
   lopsided rather than close (M3/P7-3)** — agree beforehand that one
   seat pushes for a clearly larger stack than the other (e.g. win at
   least one hand outright with a real bet, not just blinds trickling
   back and forth), rather than letting the hands land near-even by
   chance. Pace is normal poker pace; the per-hand marker-post pause (P6
   task 6 step 5) is now against a real Base Sepolia confirmation, expect
   ~0.7–2.8 s per hand (measured, RESULTS.md), not the local-anvil
   instant confirm. **Why lopsided matters here:** a sum-only check
   (payouts add up to the pool) is invariant under a host/guest
   stack-swap bug — swapped labels still sum to the same total. A
   *close* split makes a swap additionally hard to notice by eye (both
   numbers look similar either way); a *lopsided* split makes a swap
   obvious the moment the wrong wallet receives the small payout.
4. **Record the expected split before doing anything else (M3/P7-1),
   same discipline as task 8 step 2a — write it down now, not after
   `resolve()`.** Once both hands are done, both humans read the poker
   client's own on-screen stacks and agree, out loud, on the final
   `hostStack`/`guestStack` numbers. Write this pair down in the session
   record. **YES/NO: both humans agree on the same numbers, and the two
   numbers are clearly different from each other** (the lopsided
   condition from step 3 — if they came out close by accident, play one
   more hand before proceeding, don't sign `final` on a near-even split).
5. Both players sign a `final` receipt via the normal cooperative-close
   UI flow (P2 decision 4's two-transaction ending: file, then resolve —
   P5's UI drives both). **YES/NO: both tabs report `Status: Closed`.**
6. Both players click Withdraw. **YES/NO: each wallet's balance increased
   by the payout implied by step 4's *pre-recorded* numbers** — compute
   `hostPayout = finalHostStack + unaccountedHost + bondHost` (P2's
   actual field name, `resolve()`'s `finalEligible` branch), symmetric
   for guest, per P2 decision 7's `resolve()` arithmetic, using step 4's
   written-down `finalHostStack`/`finalGuestStack` as the input — **not**
   a number derived after the fact from whatever the chain paid out,
   which is exactly the check a labels-swapped bug would pass anyway.

**Verification probe:** step 6's YES on both wallets, each checked
against step 4's independently pre-recorded numbers (not merely a sum
check — see step 3's reasoning: a same-total, swapped-labels result must
fail this probe, and only does if the probe compares against the
pre-resolve record rather than re-deriving expectations afterward).

**Dispatch:** `operator-run (typed HALT — production authority + live
effect; second human required)`.

---

### Task 6 — Ending 2: window settlement, per-duty bonds

**Goal:** open and join, never play a hand, one side files `(0,0)`
inside the window, the other files nothing at all, window lapses,
`resolve()` splits bond fate per-duty (AF-4; `test_S_one_filing_perduty_bonds`).

**Seat, deliberately chosen (M3/P7-2): the guest files, the host is
absent and burns.** The obvious default (host files, host is the
`open()`-calling seat) would test AF-4's per-duty ruling in only one
direction, and every other ending in this sweep already has the host
in the "active/favored" role — so this is the one ending that puts the
*guest* in the filing seat and the *host* in the absent one, giving the
sweep at least one live data point in each direction rather than a
single, seat-biased sample. (P2's own unit-test suite carries the
mirror-direction fixture in code; this live ending covers the direction
that suite doesn't.)

**Expected balances (worked from the shared setup above):**
`(0,0)`'s `stack == deposit` for both (P2 task 3 step 3's invariant, the
only receipt reachable at `markedHand == 0`) — settling it is a wash,
not a redistribution:

    guest credits = 0.0005 (deposit) + 0.0011 (own bond, filed the duty) = 0.0016 ETH
    host credits  = 0.0005 (deposit) only — bond burned (absent the full window)
    burned         = 0.0011 ETH
    check: 0.0016 + 0.0005 + 0.0011 = 0.0032 ✓

**Operator-run, one human sufficient — no second person needs to be
present for this ending, even though two distinct wallets/keys are used;
the operator holds both and simply doesn't act on the host's behalf
(the second human, if present, can watch or sit this one out — this is
not one of the two-live-seat endings):**
1. Fresh session, `open()`/`join()` against Deploy B with the shared
   setup's numbers. **Funding note (see task 1's seeding step): the host
   wallet here is the one seeded with the ≥0.0027 ETH burn-aware buffer,
   not the flat 0.0016 baseline — confirm the right wallet is being used
   as host before calling `open()`, or this ending's own arithmetic and
   the next endings' funding both drift.**
2. **Do not play any hand.** `openDispute()` from either seat.
3. Within the 120 s window, from the **guest's** wallet only, file
   `(0,0)` — the client auto-files this on dispute open (P5's task 5
   `autofileV2.plan()`) normally; for this ending, confirm it fired, or
   file it manually if the automation didn't (this is the one place a
   manual `cast send` fallback matters even on the "honest" side —
   `TBD-P7-ABI`, confirm `fileReceipt`'s exact ABI via
   `~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
   before writing the literal command if the UI path doesn't produce it).
4. **Host deliberately does nothing** — do not open the host's Buyin tab
   again, do not let its client auto-file anything, for the rest of the
   window. This is the one ending that requires *withholding* normal
   client behavior, stated plainly.
5. Wait out the 120 s window (`sleep`-free wait — just let the clock run;
   confirm via `cast block --field timestamp --rpc-url
   https://sepolia.base.org` if unsure — the explicit `--rpc-url` matters
   here specifically: a stray local `anvil` left running from an earlier
   phase's floor would otherwise answer this call silently, with a
   different clock, on a decision that gates real money).
6. Call `resolve()` (from either wallet, or via the UI's resolve button).
7. Both withdraw.

**Verification probe:** guest's balance increased by 0.0016 ETH minus
gas; host's balance increased by 0.0005 ETH minus gas (not 0.0016) —
this specific pairing (favored seat burns, not the usual host-favored
default) is the check that actually exercises the swapped direction, not
just a repeat of a same-shaped assertion with labels renamed. `TBD-P7-ABI`:
confirm the exact getter name (`burned`, or whatever P2/P3 shipped) via
`~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`,
then

    cast call <Deploy B> "burned(bytes32)(uint256)" <session> --rpc-url https://sepolia.base.org

reads `0.0011 ETH`'s wei equivalent.

**Dispatch:** `operator-run`.

---

### Task 7 — Ending 3: fold-terminal dispute via evidence filing

**Goal:** play a hand or two normally, then a hand whose signed action
chain ends in a fold; force a dispute instead of a cooperative close;
file the evidence; let it resolve on chain. Confirms the fold row returns
**both** bonds (P3 task 10 step 1 — the row most likely to be miscoded as
a burn by analogy with the muck rows, per that task's own dispatch note;
this sweep is the row's live proof, not just its unit test).

**Expected balances:** baseline receipt (hand N−1) at `hostStack =
guestStack = 0.0005 ETH` (no rebuys, invariant trivially holds — matches
the shared deposits). Hand N: blinds/betting move `0.0001 ETH` from each
into the pot (`0.0002` total), guest folds. `excess = 0` (equal
investment); pot to host:

    host stack after  = 0.0005 + 0.0001 = 0.0006 ETH
    guest stack after = 0.0005 − 0.0001 = 0.0004 ETH
    host credits  = 0.0006 + 0.0011 (bond returns — fold is a completed decision, not misconduct) = 0.0017 ETH
    guest credits = 0.0004 + 0.0011 (bond also returns) = 0.0015 ETH
    check: 0.0017 + 0.0015 = 0.0032 ✓  burned = 0

**Operator-run, two humans for the play, one for the dispute filing:**
1. Fresh session, `open()`/`join()`, shared setup. Play one hand to a
   normal close (marker confirms, receipt filed) to establish the
   baseline at `(N−1, *)`.
2. Play a second hand where the guest folds to a bet — a real fold, in
   the normal client UI, not a scripted one. Do **not** let the clients
   sign and file a cooperative `final` for this hand — instead:
3. `openDispute()` from either seat.
4. The action chain for the disputed hand is already write-ahead
   persisted locally by both clients (D7); the client's own duty
   auto-filer (P5 task 5) should file it via `fileActions` as evidence.
   Confirm it landed — **not** via `liveHand()`, which only advances on
   *marker* filings and would read the same value whether or not this
   `fileActions` call succeeded (a false YES/NO either way, since this
   ending deliberately files no new marker). Two checks instead:

       cast receipt <fileActions tx hash> --rpc-url https://sepolia.base.org

   confirms status `0x1` (the call itself didn't revert), and, once P3's
   exact storage/event shape is confirmed via
   `~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
   (`TBD-P7-ABI`), a direct read of the filed action chain — the
   analogous per-hand action mapping P4's Outputs-to-P6 section calls out
   (`phase2ActionsAt`'s array-append shape, or P3's own `actionsAt`,
   whichever the shipped contract uses) — or the emitted filing event via
   `cast logs --address <Deploy B> --rpc-url https://sepolia.base.org`.
   Either confirms the *chain itself landed*, not just that some
   transaction succeeded.

   If the UI path doesn't produce the filing (this row is dispute-only
   and less exercised than the happy path — a real possibility this
   early in the arc's life), fall back to a manual `cast send` using the
   persisted action chain pulled from local storage, mirroring the
   `node -e` extraction pattern P5's tasks 2/3/5/7 established for
   reading persisted client state. `TBD-P7-ABI`: confirm `fileActions`'s
   exact tuple encoding via
   `~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
   before writing the literal command.
5. Wait for `dueAt` (P3 task 11 step 1: `max(disputeOpenedAt + window,
   completingFiledAt + grace)` — with the fold itself as the completing
   action, this is `disputeOpenedAt + 120s` unless the fold landed in the
   last 60 s of the window, in which case it's `foldFiledAt + 60s`).
6. `resolve()`. Both withdraw.

**Verification probe:** host's balance change matches `0.0017 ETH` minus
gas; guest's matches `0.0015 ETH` minus gas; **neither** bond shows in
`burned(session)` — this is the specific assertion the fold row's own
unit test (`test_F11_1_fold_is_final_decision`) makes, now checked live.

**Dispatch:** `operator-run (second human for the play portion; the
dispute-filing and resolve steps can run solo)`.

---

### Task 8 — Ending 4: cards-decide dispute via scripted share posting

**Goal:** a hand reaches full showdown (preflop all-in, checked through
to river — the simplest construction that reaches `COMPLETE`, and, not
coincidentally, the gas-worst-case one: 9 required positions, 18 shares).
Neither side signs a cooperative `final`; instead the dispute path
decodes both hands from posted shares and the on-chain evaluator picks
the winner. **This is the sweep's single largest gas spend (task 1's
budget table) — check `cast gas-price` again immediately before step 4
below, per task 1 step 3's recovery note, before committing to it.**

**Which artifacts, and how:** this ending uses **a real played hand's
persisted local artifacts**, not the P1 vector generator's synthetic
ones — the point of this ending is proving the real client's real
output survives a real dispute, not exercising a known-good fixture a
second time (P2/P3's own test suites already do that with vectors). Both
clients' share stores (P6 task 2/D2, persisted per-hand) hold every
position's decryption share the moment the completing action fires;
extract them via the same `node -e` pattern P5 established, format as
`SharePost` tuples per artifact-formats §7/§9's exact field order
(`pos`, `shareEnc`, `c`, `s`, `shareProof[]`, `c1Enc`, `c2Enc`,
`deckProof[]`), and post via `cast send`. If a played hand's local
artifacts prove awkward to extract at execution time, the documented
fallback is P1's vector generator (D16, deterministic fixed keys) —
state explicitly in the session record which path was actually used,
per this task's own instruction, not silently.

**Expected balances:** baseline `hostStack = guestStack = 0.0005 ETH`
(fresh session, no prior hands — simplest to set up). Hand N: preflop
all-in, host bets `0.0005` (full stack), guest calls `0.0005` (full
stack); `excess = 0` (equal investment); pot `0.001 ETH` contested.
Evaluator decides — say host's hand wins (pick whichever hand the actual
deal produces; the arithmetic is symmetric):

    host stack after  = 0.0005 + 0.0005 = 0.0010 ETH   (won the whole pot)
    guest stack after  = 0
    host credits  = 0.0010 + 0.0011 (bond returns — cards-decide never burns) = 0.0021 ETH
    guest credits = 0 + 0.0011 (bond also returns) = 0.0011 ETH
    check: 0.0021 + 0.0011 = 0.0032 ✓  burned = 0

(If the actual deal produces a split pot, both sides recompute
symmetrically — `Evaluator7`'s tie branch, P3 task 10 step 3 — and the
check still holds.)

**Operator-run, two humans for the play, both for the manual filing
(each posts their own shares — presence tracking doesn't gate this row,
but having each player post their own confirms the real, distinct session
keys, not one operator acting for both):**
1. Fresh session, shared setup, `open()`/`join()`.
2. Play the all-in hand — host bets the whole stack preflop, guest calls
   the whole stack. **Do not** sign a cooperative `final`. (If the
   budget check in the preamble above suggests trimming: stop the hand's
   forced action after the flop instead of running to river — 7 required
   positions instead of 9, 14 shares instead of 18, ~78% of the cost —
   and adjust the expected-balance arithmetic's pot accordingly; state
   this substitution explicitly in the session record if used.)
2a. **Record the expected winner and split before doing anything else
   (M3/P7-1) — write it down now, not after `resolve()`.** Both humans
   read the poker client's own on-screen showdown result (it shows both
   hands and the winner once the all-in runs out, independent of
   anything this contract will later compute) and agree, out loud, on:
   which seat won, and the resulting `hostStack`/`guestStack` numbers.
   Write this pair down in the session record **now**. **YES/NO: both
   humans agree on the same winner and the same numbers.** This step
   exists because the two admissible failure modes here — "the correct
   winner, correct numbers" and "host and guest swapped, same numbers
   under the wrong labels" — are indistinguishable by the sum-reconciliation
   check alone (`0.0021 + 0.0011 = 0.0032` holds either way); only an
   independent, pre-resolve, human-observed record can catch a swap. Once
   `resolve()` actually runs (step 7), the on-chain credits are checked
   against *this* recorded pair, not against a number computed after the
   fact from whatever the chain says.
3. `openDispute()`.
4. **Check gas price again** (task 1 step 3's recovery note) before
   proceeding.
5. Both players post their shares for every required position via
   `cast send` (or the UI's dispute-filing surface if P5's shipped scope
   covers scripted posting by the time this runs — confirm at execution
   time). **Command template**, one call per required position (repeat
   for all 9, each side posting their own — 18 calls total; `TBD-P7-ABI`:
   confirm the exact function signature via
   `~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
   before the first real call, since `SharePost`'s tuple encoding — the order and Solidity types of
   `pos`/`shareEnc`/`c`/`s`/`shareProof[]`/`c1Enc`/`c2Enc`/`deckProof[]` —
   is only pinned as a *preimage* field order in artifact-formats §7/§9,
   not yet as a shipped ABI):

       cast send <Deploy B address> \
         "postShares(bytes32,(uint8,bytes32,uint256,uint256,bytes32[],bytes32,bytes32,bytes32[])[])" \
         <session> \
         "[(<pos>,<shareEnc>,<c>,<s>,[<shareProof...>],<c1Enc>,<c2Enc>,[<deckProof...>])]" \
         --rpc-url https://sepolia.base.org \
         --private-key $PLAYER_PRIVATE_KEY

   **Where each value comes from:** `<session>` is this task's own
   session id (step 1); `<pos>` is the deck position being posted (0–51,
   per artifact-formats §7); `<shareEnc>`/`<c>`/`<s>` are the player's own
   decryption share and DLEQ proof for that position, read out of that
   player's own client's local share store (the same `node -e` extraction
   this step's own paragraph above already points at); `<shareProof...>`/
   `<deckProof...>` are the two Merkle proofs (6 hashes each, §7) the
   client also persisted alongside the share; `<c1Enc>`/`<c2Enc>` are the
   deck ciphertext for that position, read from the confirmed marker
   (task 5/7's already-established pattern of reading persisted
   client state). `$PLAYER_PRIVATE_KEY` is **that player's own** wallet
   key (sourced the same masked-prefix way as task 1 step 5 — never the
   deploy key; Open Question 1 above is explicit that the deploy key
   never signs a sweep transaction).
   **If the second human cannot comfortably run a terminal command
   themselves:** screen-share dictation is an acceptable substitute — the
   operator reads the templated command with that player's own values
   filled in, over a screen share, and the second human runs it (or
   watches the operator run it against a wallet only the second human
   holds the key to, if even that much terminal use is more than they
   want) — the requirement is that the *key* stays with its owner, not
   that the owner personally types the command.
6. Wait for `dueAt` if not already past (the completing action here is
   the guest's call, so the same birth-anchored formula as task 7 step 5
   applies).
7. `resolve()`. Both withdraw.

**Verification probe:** balances match **step 2a's pre-recorded winner
and numbers** (or its flop-only variant, adjusted per step 2's note),
not merely the table above re-derived after the fact — the pre-resolve
record is the actual check, the table is the template it was built from.
`burned(session) == 0`.

**Dispatch:** `operator-run (second human required — both players post
their own shares)`.

---

### Task 9 — Ending 5: zero-filings full refund

**Goal:** the AF-4 never-started row — fresh session, both players walk
away, nobody files anything at all, window lapses, `resolve()` returns
every deposit and every bond in full (`test_S_zero_filings_full_refund`).
This is the cheapest ending to run and a good one to end the sweep on if
the budget check ran tight at task 8.

**Expected balances:**

    host credits  = 0.0005 + 0.0011 = 0.0016 ETH
    guest credits = 0.0005 + 0.0011 = 0.0016 ETH
    check: 0.0016 + 0.0016 = 0.0032 ✓  burned = 0

**Operator-run, one human sufficient:**
1. Fresh session, `open()`/`join()`, shared setup.
2. `openDispute()` immediately — no hand played, no marker ever confirms
   (`markedHand` stays 0 for this session).
3. **File nothing.** Not even `(0,0)` — this is what distinguishes this
   ending from task 6's; both duty-autofilers must be prevented from
   firing (close both Buyin tabs, or don't open them at all after
   `openDispute`).
4. Wait out the 120 s window.
5. `resolve()`. Both withdraw.

**Verification probe:** both balances increase by `0.0016 ETH` minus
gas; `everReceipted(session) == false` before `resolve()` is called.
`TBD-P7-ABI`: confirm the getter is exposed (and its exact name) via
`~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`,
then `cast call <Deploy B> "everReceipted(bytes32)(bool)" <session>
--rpc-url https://sepolia.base.org`; `burned(session) == 0` after.

**Dispatch:** `operator-run`.

---

### Task 10 — Arc close-out

**Goal:** leave the artifacts the arc-end cold review needs, without
performing that review here — arc-run owns its own mechanics (weight-
scaled, cold, four-verdict) and this task's job is inputs, not the
verdict.

**Steps:**
1. Revert `src/deploymentsV2.js` to point at **Deploy A** (production)
   permanently — remove the "SHORT DURATIONS, throwaway" entry, restore
   the entry task 2 step 5 wrote. `npm run build`.
2. `docs/arc-history.md`: add a V2 entry, V1-entry style (one paragraph),
   naming both deployed addresses, the five endings swept, and the two
   real humans/machines that ran task 5. **Mark it explicitly as a draft
   for the arc-end review to confirm**, not a final ratified record — the
   arc-end review is the actual close, this is its input.
3. Amend V1's own `arc-history.md` entry's closing sentence — "Not yet
   run by two separate people on two separate machines — that's V2's
   trigger condition, still open" — to record that task 5 satisfied it,
   with the date.
4. `HANDOVER.md`: update the "V2 cash settlement" row under Ongoing arcs
   — from "design READY WITH DECLARED DEFERRALS" to "built and live-swept
   on Base Sepolia, [date]; shipped pending arc-end cold review." Do
   **not** delete the row yet — that's the arc-end review's own act, once
   it ratifies.
5. Remove the orphaned stale-trigger line — the un-bulleted line reading
   "V2: cash game buy-ins and rebuys — trigger: V1 has actually run for
   real, with two separate people on two separate machines, not before →
   [docs/superpowers/plans/v2-cash-game-rebuys.md]" (the file itself
   still exists — this is a stale/superseded pointer, not a dead one:
   `docs/superpowers/plans/v2-cash-game-rebuys.md` predates this arc's
   actual scaffold and was superseded by it, and the line's own trigger
   condition is the exact one task 5 just satisfied). This is the "stale
   old-trigger line" this phase was scoped to flip.
6. **§11.2(a) congestion-tail note:** RESULTS.md's 20-sample run closed
   §11.2(a) under calm network conditions; a further stress test under
   genuine congestion never happened and isn't blocking anything this
   arc needs — record in the draft arc-history entry (step 2) that this
   rerun "remains optional post-arc," not a follow-up task anyone owes.
7. Leave, unmodified, for the arc-end reviewer to find: this doc's own
   filled-in Phase-boundary verification table (task-execution time, not
   drafting time), every transaction hash from tasks 2–9 (record them as
   each task runs, in the session's own working notes — this doc doesn't
   prescribe a separate ledger file; the on-chain record plus this doc's
   verification table is the artifact), and P2/P3's own gas-snapshot
   files (`contracts/.gas-snapshot`, once those phases actually ship) for
   comparison against this phase's live-measured numbers.

**Verification probe (D17 — base-ref form, asserting non-empty, not
`--stat`):** `--stat` compares worktree to index and reads empty once
these edits are committed — the normal end state for this task, which
would make a `--stat`-based gate vacuously pass whether or not anything
actually changed. Use the recorded `PHASE-7-BASE-SHA` (Task-ordering
note, above) instead:

    git -C /home/dev/projects/vault diff $PHASE-7-BASE-SHA..HEAD -- src/deploymentsV2.js HANDOVER.md docs/arc-history.md | wc -l

YES/NO: **non-empty** (a nonzero line count) — confirms steps 1–5
actually landed real edits since the phase began, committed or not. A
second check confirms the boundary held:

    git -C /home/dev/projects/vault diff $PHASE-7-BASE-SHA..HEAD -- contracts/ | wc -l

YES/NO: **empty** (zero) — nothing in `contracts/` changed this phase
(D11/D13), the inverse of the first check.

**Dispatch:** `inline (orchestrator)`.

## Phase-boundary verification

**Gate type: live effect + production authority — typed HALT for the
operator at each deploy (tasks 2, 3) and at sweep start (before task 5).
The sweep table below, filled in as tasks 5–9 actually run, IS the gate —
there is no separate automated probe standing in for it.**

| Ending | Task | Expected (host / guest) | Actual (host / guest) | Burned? | YES/NO |
|---|---|---|---|---|---|
| 1. Mutual final happy path | 5 | task 5 step 4's pre-recorded lopsided split (not derived after the fact) | — | expect none | |
| 2. Window settlement, per-duty bonds | 6 | 0.0005 / 0.0016 ETH (host absent & burned, guest filed — M3/P7-2's swapped seat) | — | expect host's 0.0011 | |
| 3. Fold-terminal dispute | 7 | 0.0017 / 0.0015 ETH | — | expect none | |
| 4. Cards-decide dispute | 8 | task 8 step 2a's pre-recorded winner + numbers (template: 0.0021 / 0.0011 ETH, symmetric on a guest win, split on a tie) | — | expect none | |
| 5. Zero-filings full refund | 9 | 0.0016 / 0.0016 ETH | — | expect none | |

Fill "Actual" and "YES/NO" during execution, minus gas each player spent
from their own wallet on their own transactions (gas is not part of the
contract's accounting invariant — `depositedHost + depositedGuest +
bondHost + bondGuest == paidOut[session] + burned[session]`, P2 task 6's
invariant, holds on the *contract's* numbers regardless of what either
wallet separately spent on gas to get there).

Additional gates, both required alongside the table above:

1. **Both deploys confirmed.** `cast code` nonzero at both addresses
   (tasks 2, 3's own probes) — YES/NO.
2. **V1 untouched and responsive.** Task 4's `defaultWindow() == 1800` —
   YES/NO.
3. **Budget held (P7-6 — a real threshold, not "≥ 0," which is true of
   any balance including a drained one).** Final
   `cast balance <deploy key address> --rpc-url https://sepolia.base.org`
   reads **≥ 0.0005 ETH** — chosen as comfortably above zero but well
   under the ~0.0015 ETH this doc's own arithmetic (task 1 step 5) expects
   to remain after seeding both player wallets and both deploys, so a
   threshold breach means something genuinely diverged from plan, not
   just that spending
   happened at all. YES/NO, and record the actual final balance for the
   arc-end review's own comparison against this doc's estimate.

## Outputs to next phase

**None — this is the arc's last phase.** What the arc-end cold review
consumes instead, left by task 10: the draft `arc-history.md` V2 entry,
the updated (not yet deleted) `HANDOVER.md` row, both deployed contract
addresses and every sweep transaction hash, this doc's own filled-in
Phase-boundary verification table, and the acknowledgment (task 1 step 5,
Open questions item 2 below) that P4's four additional phase-2-born
endings were never exercised live in this arc — a fact the review should
see stated plainly, not discover by omission.

## Open questions

1. **RESOLVED — AF-10 (coherence pass) + AF-11.9/fix-round-1 (the
   per-wallet peak bug), both 2026-08-17.** Originally an open question
   defaulting to "separately-funded player wallets, deploy key covers gas
   only." Now ruled: **the deploy key seeds both player wallets by plain
   value transfer, burn-aware and per-wallet** — task 1 step 5's two
   `cast send --value` calls (0.0029 ETH to whichever wallet ends up
   absent-and-burned in task 6, per M3/P7-2's swapped seat that's the
   **host**; 0.0018 ETH to the other). A plain value transfer is not
   key-sharing (CLAUDE.md's segregation rule governs keys sharing a
   variable/file/process, not one key funding another's balance) — the
   deploy key still never appears as `msg.sender` for `open()`/`join()`/
   `deposit()`/any dispute filing, only for the two deploys and these two
   seed transfers. No longer overrulable at execution time in the sense
   the original entry described (the "if unfunded, wire it over
   ad hoc" fallback) — it's the default now, not a fallback.
2. **P4's four additional sweep-exercisable endings (open fold,
   bank-fold, live-continuation showdown, phase-2-born-duty muck) are not
   part of this phase's five.** Default: descoped — the phase brief named
   exactly five endings, and the budget (task 1) is sized for five, with
   ending 8 alone consuming ~86% of the gas total; a sixth or seventh
   ending, especially a bank-fold (which needs a bank duration to
   actually lapse, D15's whole reason for existing) would add real
   calendar time on top of an "evening" scope. **Overrules:** the
   operator, if a future, separate live-sweep session is scoped
   specifically for P4's phase-2 endings — this doc's task 1 budget
   table and per-ending gas figures are directly reusable for scoping
   that session's own budget.
3. **Ending 4's exact winner (host or guest) is not fixed by this doc** —
   it depends on the actual cards dealt. Default: the arithmetic template
   in task 8 is symmetric and either operator or second human should
   simply substitute the real outcome at execution time, rather than this
   doc pre-committing to one. **Overrules:** nobody — this is inherent to
   using a real played hand rather than a rigged deck.
4. **`TBD-P7-ABI`** appears at six sites — task 6 (×2: the `fileReceipt`
   manual-fallback ABI, and the `burned()` getter its verification probe
   reads), task 7 (×2: the `fileActions`-landed read, and the
   `fileActions` manual-fallback tuple encoding), task 8 (×1:
   `postShares`'s tuple encoding), and task 9 (×1: the `everReceipted()`
   getter its verification probe reads) — every one a call against
   `ChannelV2.sol`'s actual shipped ABI, which does not exist at this
   doc's drafting time (P2/P3 are still REVISE-IN-REVISION). Default:
   resolve each at execution time via
   `~/.foundry/bin/forge inspect contracts/src/ChannelV2.sol:ChannelV2 abi --root /home/dev/projects/vault/contracts --json`
   (P7-5: `--root` and `--json` on every one of these six sites — it
   fails as written without `--root` when run from anywhere but the
   `contracts/` directory itself), per this doc's own dispatch-time
   re-verification framing (Inputs
   section). **Overrules:** nobody — this is the same category of
   forward reference P2/P3 themselves carried as `TBD-P1-VECTORS`, not a
   gap specific to this doc.

## Recovery

**Testnet sessions are disposable. If a sweep transaction fails mid-
ending, open a fresh session and start that ending over — never debug a
stuck transaction live with a human waiting on the other end.** This is
the single governing rule for this phase; everything below is detail
under it.

- **A failed `cast send` or `forge script` broadcast, first attempt:**
  expected, not a fault (RESULTS.md: 17/20 first-attempt sends failed
  transiently on `sepolia.base.org`'s load-balanced nodes). Wait 2 s,
  re-run the identical command. If it fails a second time, check
  `cast gas-price --rpc-url https://sepolia.base.org` and
  `cast balance <address> --rpc-url https://sepolia.base.org` before a
  third attempt — a drained budget or a stuck nonce look identical to
  "still transient" otherwise.
- **A deploy (task 2 or 3) that half-completes** (broadcast sent, unclear
  if confirmed): `cast code <address printed by the last console2.log>
  --rpc-url https://sepolia.base.org` — nonzero means it landed, don't
  redeploy; `0x` means it didn't, safe to retry from the dry-run step.
  There is no partial-deploy state to clean up (a `CREATE` either
  produces a contract or it doesn't).
- **A sweep ending that goes wrong mid-way** (e.g., an unexpected revert
  from a malformed manual `cast` call in task 8): do not attempt to
  "fix" the malformed call and resubmit against the same session — the
  session's on-chain state (a partial marker sequence, a half-posted
  share set) may now be inconsistent with this doc's expected-balance
  arithmetic in ways that are hard to reason about live. Open a fresh
  session (a new `bytes32 session` id costs nothing but the `open()`/
  `join()` gas already budgeted) and re-run the ending from task 1's
  clean starting numbers.
- **If the budget check (task 1 step 4, re-run before task 8) shows gas
  price has moved and the sensitivity table's 100× row is now live**:
  stop before task 8, do not attempt it at the full 9-position river
  showdown — either use the flop-only substitution (task 8's own note)
  or stop the sweep at four endings and write a letter to ops rather than
  attempting to stretch a budget the arithmetic says won't cover it. A
  short letter costs nothing; an out-of-gas revert mid-showdown costs the
  gas already spent on the shares that did post, for nothing.
- **If `src/deploymentsV2.js` is left pointed at Deploy B** (task 3's
  temporary state) because the session ended before task 10 ran: this is
  a live but harmless drift — anyone opening V2 Buyin on Base Sepolia
  between sessions talks to the short-duration sweep contract instead of
  production, which is confusing but not unsafe (D11's chain-id guard and
  D15's duration assertion are both already-deployed contract state, not
  something a stale client pointer can corrupt). Recovery is simply
  running task 10 step 1 whenever the session resumes, before anything
  else.

## Coherence-pass amendment — 2026-08-17 (AF-10)

**Player-wallet funding source, previously unstated.** The payer split
(task 1) has player wallets funding all deposits, bonds, and sweep gas —
but never said where their testnet ETH comes from. Ruled: **the deploy
key seeds both player wallets by plain transfer** (a value transfer is
not key-sharing; the segregation rule governs keys in processes, not
funding). Faucet-clicking repeatedly for player wallets is explicitly
rejected as the funding method (ops' sizing lesson, letterbox
2026-08-17). This amendment's original arithmetic (flat 0.0025 ETH per
player, "before task 4") is superseded by the correction directly below
— kept here, struck through in substance rather than deleted, per this
arc's own amendment discipline (`decisions.md`'s header: "amendments are
dated blocks under the original entry, never silent edits").

**Correction — fix round 1, 2026-08-17 (AF-11.9, "the per-wallet peak
bug").** The flat 0.0025-per-player split above is wrong: ending 2 (task
6) permanently burns one wallet's 0.0011 ETH bond, and a flat split
leaves that wallet short of the 0.0016 ETH the *next* ending needs.
Two further corrections, applied at Task 1 step 5 (not "task 4's
pre-flight" — task 4 is the V1 smoke probe and touches no player-wallet
funds; the actual pre-flight task is task 1, and the real trigger point
for "insufficient funds" if this were skipped is **task 5**, the sweep's
first player-wallet transaction): (1) size the seed **per wallet's
actual role**, not identically — 0.0029 ETH to whichever wallet ends up
absent-and-burned in task 6 (0.0016 baseline + 0.0011 burn buffer +
0.0002 gas), 0.0018 ETH to the other (0.0016 baseline + 0.0002 gas),
total 0.0047 ETH, not 0.0050; (2) because M3/P7-2 (task 6's own section)
also swapped which seat burns — guest files, **host** goes absent — the
larger seed goes to the **host** wallet specifically, not "either
player" as this amendment originally left unstated. Task 1 step 5 is the
corrected, executable version of this ruling; this block is the record
of why it changed.
