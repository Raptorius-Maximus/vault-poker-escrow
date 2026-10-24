# V2 deploy-day runbook — the parts held for Raptor

Everything in Phases 1–6 is **built and machine-verified**. What is left can
only be done by a person at a keyboard with a browser, a wallet, and (for the
last stage) a second human — so it was held for you. This is the one page that
sequences it. Detailed step lists live in the phase docs; this page is the
order to do them in, the numbers that changed, and the points where you must
**stop and decide**.

Work top to bottom. Each stage proves the one before it was real, so don't skip
ahead.

---

## Before you start — one decision and one check

- **Decision (AF-44): session-key encryption — DECIDED 2026-08-18: accept
  as-is.** Raptor chose to keep the current encrypt-at-rest + best-effort
  restore (signing stays synchronous; no async rework this arc). Nothing to do
  here — revisit only if a local smoke shows a signing hiccup right after a
  reload. Full reasoning: `review-findings.md`, AF-44.

- **Check: the money is where it should be.** The deploy key
  `0x99507E2c…` was funded to **0.00330223 ETH** on Base Sepolia (the server admin, via
  faucet — `~/letterbox/inbox/2026-08-17-base-sepolia-topup-reply.md`). There
  is **no second top-up this arc**; the plan fits inside this balance with room
  to spare (see Stage 3). Base Sepolia is test money only — nothing here can
  ever touch real funds.

---

## Stage 1 — Local smokes (no real money, no deploy)

**Goal:** prove the two new apps actually work by clicking through them against
a fake local chain (`anvil`) on your own machine. This is where bugs are cheap.
Do both smokes here before spending a single real testnet transaction.

1. **Buyin UI smoke (Phase 5).** Full step-by-step: `phase-5-buyin-ui.md`,
   the "Phase-boundary verification" section, **steps 1–14**. In short: start
   `anvil`, deploy `ChannelV2` to it with short durations, add a local `31337`
   entry to `src/deploymentsV2.js` by hand, `npm run build`, `npm start`, then
   open two browser tabs (host + guest) and walk: set the table → open → join →
   Active → rebuy → over-max refusal → open a dispute. Step 14 is the important
   one — it re-deploys with a *different* dispute-window number to prove the
   screen reads the deadline from the chain, not a hardcoded value.

2. **Poker client ↔ chain smoke (Phase 6).** Full step list:
   `phase-6-client-chain.md`, "Phase-boundary verification", **gate 7 (a–g)**.
   It reuses Stage 1's local anvil + deployed contract, plus a poker tab. What
   you're proving: a hand deals through the "waiting for the chain" pause (not a
   forfeit), a marker actually posts and confirms, and — the one that matters
   most — **when you kill anvil mid-hand, nobody's stack changes and nobody is
   forfeited** (it just pauses). Then "open a dispute" makes the poker tab hand
   its evidence, including real card-proof shares, to Buyin's auto-filer.

> If either smoke misbehaves, **stop here** and tell me what you saw — it's far
> cheaper to fix before touching Base Sepolia. Local anvil is free and
> unlimited; the real deploy is not.

---

## Stage 2 — The real deploy (STOP-AND-ASK)

**Goal:** put `ChannelV2` on Base Sepolia for real. This is the first
irreversible, on-a-real-network step. Full detail: `phase-7-deploy-live-sweep.md`,
Task 1 (pre-flight) then Tasks 2–3 (the two deploys).

**This is a hard stop.** Before any deploy command runs, we confirm together,
out loud, and the command **prints the chain ID (84532)** so there's no doubt
which network it's hitting. I will not run a real-network deploy on my own —
that's your GO, every time, per the repo's own rule.

Two things Task 1 makes you do first, both quick:
- Re-check the live balance and gas price (`cast balance` / `cast gas-price`
  against `https://sepolia.base.org`). If the balance reads well under 0.0033,
  stop — something's off.
- **Seed the two player wallets** from the deploy key. **These numbers changed**
  (the plan originally assumed ~0.0062 ETH; you have 0.0033 — AF-46):

      baseline buy-in per wallet: 0.0008 ETH
      host player wallet seed:    0.0015 ETH   (cast send … --value 0.0015ether)
      guest player wallet seed:   0.0009 ETH   (cast send … --value 0.0009ether)
      total seeded:               0.0024 ETH
      deploy-key left afterward:  ~0.00089 ETH (~27% reserve)

  When you set the table in the handshake, declare the depths at this smaller
  scale (both "max" ≈ 0.0008, "put in now" ≈ 0.0004). The mechanics are
  identical at half size; this just keeps the whole evening inside the budget.

Then the two deploys (Task 2 = real durations, Task 3 = short durations for the
dispute demo), each printing chain ID 84532, each your explicit GO. After each,
you add its `84532` address to `src/deploymentsV2.js`.

---

## Stage 3 — The two-human live sweep (needs a second person)

**Goal:** the real thing — two separate people, two machines, playing real
testnet hands to their real endings, on the deployed contract. Full script:
`phase-7-deploy-live-sweep.md`, Tasks 4–9 (the five endings) and the V1
side-by-side check. This is also the moment the old "V1 must run for two real
people" trigger finally gets satisfied for real.

You can't do this one alone — it needs the second human on the second machine
for the guest seat. When you have them lined up, tell me and we'll walk the five
endings together: a clean win, an absentee-burns-their-bond dispute, a disputed
hand that plays out on-chain, the big worst-case dispute filing, and the
never-started full refund.

> **Never a mainnet path.** If V2 ever gets pointed at Base *mainnet* or real
> value, that's a **new letter to the server admin first**, before any code assumes it —
> ops re-stated this in the top-up reply, and it's the one rule the letter
> process exists to catch. Everything above is Base Sepolia (chain 84532),
> inside the fence.

---

## Where the detail lives

| You want… | Read |
|---|---|
| The 14-step Buyin smoke | `phase-5-buyin-ui.md` → Phase-boundary verification |
| The poker↔chain smoke (gate 7) | `phase-6-client-chain.md` → Phase-boundary verification |
| Pre-flight, seeding, the two deploys, the five endings | `phase-7-deploy-live-sweep.md` |
| Why any number or decision is what it is | `review-findings.md` (AF-43/44/45/46), `decisions.md` |
| Current arc status at a glance | `README.md` → Status block |
