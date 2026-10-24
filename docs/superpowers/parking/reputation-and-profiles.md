# Profiles and reputation — a community around the table

Parked 2026-08-16, out of the V2 cash-settlement design conversation
([spec](../specs/2026-08-16-v2-cash-settlement-consolidated.md),
[history](v2-cash-game-settlement.md)). Operator's proposal.

Lands mostly in **vault** — the reputation counter is contract state and is
tightly coupled to V2's settlement outcomes — plus gating in **poker** and a
new service for profiles and chat.

## Why this is arc-shaped

- **Spec required.** Identity and reputation are product design, not code you
  can just start writing.
- **Cross-cutting decisions.** Identity model, Sybil resistance, moderation,
  what is public, where data lives, how a profile relates to a wallet. Well
  past five.
- **Multi-phase.** On-chain counter → profiles → gating → chat, each shippable
  and each leaving the system runnable.
- **Verification per phase.** The counter is testable on chain; the gating is
  testable in the client; the social layer needs real people.
- **Amendments expected.** Reputation systems are gamed the moment they matter.
- **Post-arc review warranted.** It sits next to money and next to personal
  data.

## Scope sketch

**The insight that makes it cheap: the chain already knows the only fact
needed.** It cannot tell who caused a dispute — that is the problem V2 spent
eight passes on — but it knows perfectly well whether a session ended with
both signatures or ended in dispute. That is not a claim anyone makes; it is
what happened.

So the contract keeps two numbers per wallet: **sessions settled cleanly** and
**sessions ended in dispute**. No reviews to write, no judgement, nobody
deciding who lied.

**Why that is enough.** In one game you cannot tell who caused a dispute.
Across twenty you do not need to — an honest player is almost never in one, a
cheat is in most. The signal separates from the noise without anybody
adjudicating anything.

**Why it matters for V2.** It converts a one-shot game into a repeated one. In
a one-shot game cheating is rational whenever it pays; in a repeated game the
cheat is not spending a bond, they are spending an identity they took weeks to
build. That is the same mechanism that makes eBay work without verifying a
single transaction.

**Gating, operator's scoping and a good one:** a profile is required to play
**cash games** only. **Freezeout and play money stay open to anyone.** That
keeps the barrier where the money and the unsolved settlement risk are, and
leaves the front door unlocked for newcomers and casual play.

## Open questions for the design passes

- **Sybil resistance.** Wallets are free; a flagged one is discarded in ten
  seconds. Reputation only bites if a fresh wallet is worth little — which is
  enforced by *culture* (players declining unknowns) unless something scarce
  backs identity. What, if anything, should that be? A stake? Time? An
  introduction from an existing player? Each has a cost in unwelcomeness.
- **Does the counter live on chain or in the service?** On chain it is
  trustless and permanent; in the service it is editable and deniable. On
  chain also means permanent public linkage of a wallet to a dispute record,
  which cannot be undone.
- **What does a profile contain**, and how does it link to a wallet without
  becoming a permanent public identity graph?
- **Moderation.** A chat between strangers with money at stake will need it.
  Who does it, and what is the appeal path?
- **Does a dispute count distinguish "no mutual receipt" from "actively
  contested"?** V2 currently treats a wifi dropout and a refusal identically —
  a reputation system probably should not.
- **What does the honest victim of a first-time cheat get?** Nothing, under
  this design. Reputation deters future harm and never compensates past harm.
  Is that acceptable, and is it said out loud in the UI?
- **Interaction with V2's mechanical floor.** Could reputation let two trusted
  players *relax* the cap and bond by agreement — code guaranteeing a safe
  default, people choosing how far above it to trust each other? That is the
  same shape as the bond slider and may be the best use of it.

## Not in scope

- Anything that lets reputation *decide a settlement*. The chain still cannot
  tell who cheated, and a reputation-weighted payout would be exactly the
  unattestable adjudication V2 spent eight passes refusing to build.
- Replacing V2's mechanical protections. This is a complement. Cap-and-bond
  makes cheating *provably* unprofitable; reputation makes it *probably*
  unprofitable, and only if the community is real.

## Blocked on

**A letter to ops.** A profile and chat service is server-side storage, which
the server admin's hosting grant explicitly gates: *"No server-side storage without a new
letter... include your thinking on size caps and expiry."* Same precondition as
V2's encrypted backup. Personal data raises the stakes of that letter beyond
what the backup needed.

## Trigger

V2 cash settlement is shipped and running. There is nothing to build a
reputation about until real matches are settling.

## Related

- [V2 cash settlement](v2-cash-game-settlement.md) — the eight-pass history,
  and the reason a reputation layer is attractive
- [V2 consolidated spec](../specs/2026-08-16-v2-cash-settlement-consolidated.md)
- [Watchtower](v2-watchtower.md) — also waiting on neutral hosting
