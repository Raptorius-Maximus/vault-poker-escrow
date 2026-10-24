# Vision

## The problem

Two people want to play heads-up poker for real stakes, using Loke's existing
poker client, without either of them holding the other's money and without
trusting a third party to decide who won. Doing this by hand — Venmo before,
Venmo after, trust — breaks the moment either side has a reason to stall.

## What this is trying to be

A standalone local app that escrows a crypto buy-in for a heads-up session and
settles it afterwards, preserving the poker client's own forfeit rule: since
the deck is fixed by the shuffle before any card is dealt, quitting can only
concede an outcome, never change one. Vault's job is to carry that guarantee
onto a chain without weakening it — specifically, without ever letting one
player treat "disconnect" as a cheaper option than "lose the hand."

## Principles

- **The forfeit rule is the constitution.** Every mechanism (dispute windows,
  bonds, cooperative close) exists to preserve "quitting is worth what folding
  is worth" — nothing overrides it, including convenience.
- **Blast radius stays separated.** Vault holds a key that spends money; the
  poker client holds a key that opens cards and is deliberately volatile.
  Different lifetimes, different processes, different origins, always.
- **Nobody custodies anyone's funds, ever** — not Vault, not a relay, not an
  operator. Two people, two wallets, a contract, local only.

## Non-goals

- **Mainnet, ever, until an independent audit exists.** Testnet (Base Sepolia)
  only for the lifetime of this project as currently scoped.
- **A hosted or shared deployment.** No server that holds state for both
  players; each runs Vault locally.
- **Anything that touches a seed phrase.** Signing goes through the user's own
  wallet; Vault never sees, stores, or transmits key material beyond a raw
  testnet deploy key kept out of the poker client's process entirely.
- **Solving V2's cash-game settlement before V1 (winner-takes-all) ships and
  runs.** V2 is real added complexity, not a formality — see OVERVIEW.md.

## Amendment — 2026-09-09: the last non-goal was overtaken

Recorded rather than deleted, because the reasoning behind it was sound and
the reason it stopped applying is worth knowing.

That non-goal held V2 back until V1 had **shipped and run**. What happened
instead: V1 shipped, V2 was built to green automated floors (P1–P6, 2026-08-18)
— and V1 has still not *run*, in the sense the non-goal meant. The live sweep,
two humans playing a session to completion, is P7 and is held for the operator.

So the sequencing changed shape rather than being abandoned. One live sweep now
gates **both** channels instead of V1's sweep gating V2's start. The substance
of the non-goal survives — nothing about V2 was allowed to be a formality, and
its dispute engine carries 85 of the repository's 144 contract tests — but the
order it prescribed is no longer what the project is doing, and pretending
otherwise is how a written-once document turns into a misleading one.

**What is still binding from the list above:** every other non-goal, unchanged.
Mainnet without an audit, hosted deployment, and anything touching a seed
phrase remain refused.
