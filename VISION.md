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
