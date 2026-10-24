# Watchtower — objecting on a player's behalf

Parked 2026-08-15, out of the V2 cash-settlement design conversation
([spec](../specs/2026-08-15-v2-cash-settlement-design.md), Pass 3).

## Trigger condition

V2 cash settlement is shipped and running, AND neutral hosting exists
(the same precondition D17's encrypted backup waits on).

## Scope sketch

V2 requires a player to *show up within 24 hours* to object to a stale state
(D7, D8). A watchtower removes that requirement: a service watches the chain
and raises the objection for you, so the window stops mattering and a player
who never reopens their browser is still protected.

Needs two things V2 deliberately does not have:

- **Neutral hosting.** A watchtower run by your opponent is worse than none —
  it can simply decline to act. See D17 for the same conflict.
- **A delegated dispute-only key.** Safe in principle: D8 already restricts
  objections to presenting a *higher-nonce* state both players signed, so a
  delegated key can only ever push the outcome toward the truth, never steal.
  Reveals balances to the operator unless built with the encrypted-blob
  trigger pattern, which is a good deal more work.

## Not in scope

Anything that lets the service move money, choose a payout address, or settle
on a player's behalf. Objection only.

## Related

- [V2 cash settlement design](../specs/2026-08-15-v2-cash-settlement-design.md) — D7, D8, D17
- [V2 parking doc](v2-cash-game-settlement.md)
