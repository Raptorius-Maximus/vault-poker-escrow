# Dispute-path gas prototypes

Measurement code for spec §11.2(b): what the V2 dispute path actually costs
on the EVM. **Prototype, not production** — written to be functionally
correct on differential vectors and honestly measurable, not audited.

## The validation chain

Nothing is trusted from memory, and nothing is compared against itself:

1. `gen/gen.mts` computes every curve constant (d, √−1, 1/√(a−d), the base
   point) **from first principles** in BigInt, and implements an independent
   mirror of ristretto255 (RFC 9496 decode/encode, extended-Edwards
   arithmetic).
2. The mirror is validated against **`@noble/curves`** — the poker client's
   own crypto library — on every run: 200 scalar-mul encodings, 100
   decode/encode round-trips, subtraction consistency. Sign ambiguities in
   the constants are resolved by search against noble, never assumed.
3. Only then does it emit `test/Vectors.sol`: DLEQ vectors (including a
   tampered one that must fail), 120 seven-card hands scored by the **actual
   client evaluator** (`gen/evaluator.mts` is copied verbatim from
   `poker/src/core/evaluator.ts`), a 20-action signed chain, and a 52-leaf
   Merkle proof.
4. `forge test` asserts the Solidity ports agree with every vector and emits
   per-op gas.

Regenerate + run:

```
node --experimental-strip-types gen/gen.mts > test/Vectors.sol
forge test -vvvv | grep "emit Gas"
```

## Measured 2026-08-17 (solc 0.8.35, optimizer 200, Cancun)

| Operation | Gas |
|---|---|
| DLEQ verify, one share (4 scalar muls, naive double-and-add) | **2,969,269** |
| ristretto decode | 5,783 |
| ristretto encode | 5,337 |
| scalar mul + encode | 524,157 |
| 7-card evaluate (worst of 120 hands) | 227,814 |
| 20-action signed chain (ecrecover each) | 107,742 (~5.4k/action) |
| Merkle inclusion, 52 leaves | 3,786 |

**Worst-case dispute** (preflop all-in showdown: 9 cards, 18 shares):
18 × ~3.0M ≈ **53M gas**, naturally split across the two players' filings
(~27M each). At Base's 0.005–0.1 gwei that is roughly **$0.50–$10 per
filing** — dispute-only, and chargeable to the party whose refusal caused it.
A typical showdown dispute (4 hole shares ×2 sides at the river) is
8 × ~3.0M ≈ 24M ≈ **$0.20–$4 per side**.

The parking doc's old "~10M gas" line was a literature estimate for two
cards; this replaces it with measurement. Two figures still need the live
network (spec §11.2(a)): real Base Sepolia gas *price* and, critically, the
**marker confirmation latency** that sits between hands via §4's deal gate.
Gas *units* above are exact EVM facts and do not change on the live chain.

**Optimization headroom, deliberately unspent:** the scalar mul is plain
double-and-add. A Strauss/Shamir combined multiplication computes
`G·s − P·c` in one pass (halves each DLEQ to ~1.5M), a 4-bit window cuts
further, and batch verification over all of a filing's shares would
amortise more. The naive number is the ceiling, not the floor.

## Layout

- `src/Ristretto.sol` — field + extended-Edwards + RFC 9496 decode/encode
- `src/Dleq.sol` — Chaum–Pedersen verify, keccak challenge (spec amendment:
  chain-verifiable artefacts use keccak256, not the client's sha512)
- `src/Evaluator7.sol` — best-of-21 evaluator, port of `evaluator.ts`,
  packed-score comparable
- `src/Bench.sol` — signed action chain, Merkle inclusion
- `gen/` — generator + verbatim evaluator copy
- `test/` — vectors (generated) + assertions + gas events
