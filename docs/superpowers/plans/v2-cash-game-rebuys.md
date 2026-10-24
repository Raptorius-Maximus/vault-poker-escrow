# V2 proposal: cash game buy-ins and rebuys

**Status:** Proposal, not started. Written up instead of built, on purpose —
see "Why this waited" below.

## What was asked for

> Add cash game buy-in to Vault, where you can rebuy up to the chosen
> amount of bb the match started with — being equal to the amount chosen
> to be 200bb at the match start. So any amount deposited is 200bb, and it
> also says that amount in ETH.

In plain terms: pick an ETH amount at the start of a cash game session.
That amount is defined as 200bb (or whatever depth is chosen) for the
whole session. If you bust and want back in, you deposit that same ETH
amount again — a rebuy — and it's worth the same 200bb every time, with
the UI showing both the bb figure and its ETH equivalent so neither side
has to do the conversion in their head.

## Why this waited

This is genuinely V2 work, not a small extension of V1, for a reason the
original handover spec already worked through: **a sit-and-go has one
winner, so vanishing costs the entire buy-in — that penalty alone is what
makes V1 small.** A cash game has no single winner, only a stack balance
that moves every hand and can be topped up. Settling that on-chain needs
per-hand signed receipts and signed mid-hand actions (see the spec's own
V2 section) — meaningfully more surface than V1's single escrow-and-close.

Rebuys specifically add a second dimension V1's contract has no concept
of at all: **repeated deposits into the same session**, each one needing
to be attributed correctly if a dispute ever happens. Channel.sol's `open`
can only ever be called once per session id; there is no `topUp` today.

Building this means:
- A new or extended contract (new deploy, new address, new audit surface
  — everything OVERVIEW.md already says to take seriously before mainnet
  applies doubly here, since it's new logic, not the already-tested V1
  path).
- A real signed-receipt scheme for stack balances, per the spec's own
  design (highest hand number wins a dispute; publishing a
  beaten-and-superseded receipt forfeits the whole deposit).
- Real testing of the rebuy path specifically — multiple deposits, a
  rebuy mid-dispute, a rebuy after a bust but before resolution — none of
  which V1's 26-test suite covers, because none of it exists in V1.

The project's own staging said this waits until V1 has actually run for
real — a genuine second person, a genuine completed match, not solo
testing worked around one shared wallet. We're not there yet: today's
testing proved every individual mechanism works (deposits, signing, the
dispute path's logic), but always with one person operating both sides.
Shipping new financial contract logic on top of that, unsupervised,
isn't the right trade.

## A sketch, for when it's time

Not a spec — just enough shape to start the real design conversation from,
rather than a blank page.

**The bb-to-ETH rate.** Fixed once per session, at the first deposit:
`ratePerBB = firstDeposit / depth` (e.g. `0.02 ETH / 200bb = 0.0001
ETH/bb`). Every subsequent rebuy must be an exact multiple of that rate —
the contract can enforce this without knowing anything about poker itself,
just `require(msg.value % session.ratePerBB == 0)` and crediting
`msg.value / session.ratePerBB` bb to that player's on-chain balance.

**What the contract needs to add, roughly:**
- `rebuy(sessionId)` payable, callable only by an existing participant,
  only while the session is in whatever the "cash game, still open"
  status is.
- A per-player running total (bb or wei, either works if the rate is
  fixed) instead of V1's single fixed `buyIn`.
- The signed-receipt/highest-hand-number dispute mechanism the spec
  already describes for V2 generally — rebuys don't need their own
  separate dispute logic if the receipt scheme already carries current
  stacks.

**What the poker client needs to add:**
- A `rebuy` UI action already exists in-game (chips only, no crypto) —
  it would need to gate on an actual Vault rebuy transaction completing
  first, same shape as the funding-gate work done for V1 tonight
  (`beginMatch`'s enforcement is the direct precedent).
- The per-hand signed receipts themselves — new protocol messages, new
  signing logic, genuinely more than tonight's single-signature-at-
  match-end scheme.

**What Vault's UI needs to add:**
- Show both bb and ETH for every deposit and rebuy, using the session's
  fixed rate — this part is pure display logic once the rate exists
  on-chain, and is the one piece of tonight's request that's almost
  entirely UI, not new contract risk.

## Recommended next step

Read this together, confirm the shape above still matches the intent,
then treat it as a proper arc: design pass first (the harness's own
`arc-design`, since this genuinely has real open questions — exact
dispute-window lengths for a rebuy scenario, what happens to an
in-flight rebuy if the game ends mid-transaction, whether the rate
should be allowed to change between deposits or stay fixed for the
session's life), then plan, then build — same discipline V1 got, since
this holds real money the same way V1 does.
