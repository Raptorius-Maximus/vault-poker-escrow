# Artifact formats — every signed byte, both repos

**Normative.** The poker client signs these bytes; `Channel.sol` V2
verifies them; neither improvises a field (D1). Conforms to spec revision
8; where this document tightens a prototype convention, the prototype's
vectors regenerate (differences listed in §Prototype deltas). Changes to
this file are dated amendments, and every amendment's blast radius is
**re-derived, never re-worded**, in the phase docs that cite it.

## 1. Conventions

- **Hash** = `keccak256` over the exact concatenation (`abi.encodePacked`
  semantics) of the fields in the order listed. No length prefixes;
  every field is fixed-width.
- **Preimage prefix** = 1-byte format tag, then the ASCII domain string.
  Tags and domains are registry §2; a type tag is what makes a receipt
  preimage unmistakable for any other signed artefact (spec §1.1).
- **Universal binding rule: every signed artefact binds
  `contract (20 bytes) ‖ chainid (32 bytes) ‖ session (32 bytes)`,
  immediately after its domain string. No exceptions** — uniformity is
  cheaper to verify than per-artefact reasoning about which bindings are
  transitively safe (finding D lineage).
- **Integers** big-endian fixed width: `hand` uint64, `seq` uint64,
  `subseq` uint32, chip amounts / stacks / deposits / blinds uint256.
  Chips are integers (200bb buy-in, integer blinds — spec §3); canonical
  action amounts are post-clamp integers (D7).
- **Amendment, 2026-08-17 (B1, fix round 1) — two unit domains, not one:**
  §3's receipt fields (`hostStack`, `guestStack`, `hostDeposit`,
  `guestDeposit`) are **wei**. §4's marker fields (`sb`, `bb`) and §5's
  signed-action `amount` are **chips** — the engine's native unit,
  unconverted, because chain-side betting replay (P3) runs in chip-space
  seeded from the marker. The receipt is the one artefact that crosses
  between the two spaces: the client fixes `wei_per_chip = deposit_wei /
  starting_chips` once, at receipt `(0,0)`, and never recomputes it for the
  match — this is the seam D1 exists for, so it is recorded here rather
  than left to two independent implementations to agree on by chance. Every
  other integer field's unit is exactly what §1's base rule already implied
  before this amendment (uint256 said nothing about which space); this
  amendment does not change any field's width, order, or tag, only which
  space each one's uint256 counts in.
- **Ristretto encodings** are the 32-byte wire form (RFC 9496
  little-endian field element) — used verbatim inside preimages, never
  re-serialized.
- **Signatures.** Session-key artefacts (receipt, marker, action) are
  65-byte `r ‖ s ‖ v` secp256k1 signatures **over the raw keccak digest**
  — the session key lives in client code, no wallet is involved, no
  EIP-191 prefix. Wallet-signed artefacts (session-key registration) go
  through `personal_sign`, so the contract recovers them **with** the
  EIP-191 `"\x19Ethereum Signed Message:\n32"` prefix over the digest.
  Low-s enforced everywhere (`s ≤ N/2`, as V1's `_recover` already
  checks). **Note for P2/P3: V1's `_recover` applies the EIP-191 prefix to
  every signature — V1 has no raw-digest path at all. The session-key
  recovery routine is new code, not a reuse of `_recover`** (AF-2).
- **"Both-signed"** = host's 65 bytes then guest's 65 bytes, in that
  fixed order.

## 2. Tag and domain registry

| Tag | Domain | Artefact |
|---|---|---|
| `0x01` | `vault/receipt/v2` | receipt (incl. `final`) |
| `0x02` | `vault/marker/v2` | hand-start marker |
| `0x03` | `vault/act/v2` | signed action |
| `0x04` | `vault/sessionkey/v2` | session-key registration (wallet) |
| `0x05` | `vault/shareleaf/v1` | share-tree leaf |
| `0x06` | `vault/deckleaf/v1` | deck-tree leaf |
| `0x01`/`0x02` inner | `vault/dleq/keccak-v1` | DLEQ challenge halves |

## 3. Receipt

    0x01 ‖ "vault/receipt/v2" ‖ contract(20) ‖ chainid(32) ‖ session(32)
         ‖ hand(8) ‖ subseq(4)
         ‖ hostStack(32) ‖ guestStack(32)
         ‖ hostDeposit(32) ‖ guestDeposit(32)
         ‖ final(1)            # 0x00 or 0x01, nothing else

`receiptHash = keccak256(preimage)`. Both-signed by **session keys**.
Total order `(hand, subseq)`; receipt `(0,0)` is mandatory before hand 1
and carries the opening stacks = opening deposits (spec §1.1). Settlement
asserts `hostStack + guestStack == hostDeposit + guestDeposit` and each
deposit ≤ received. `final` receipts settle only at/above the floor;
highest `(hand, subseq)` final wins; terminal (D5).

## 4. Hand-start marker

    0x02 ‖ "vault/marker/v2" ‖ contract(20) ‖ chainid(32) ‖ session(32)
         ‖ hand(8)
         ‖ receiptHash(32)     # highest-subseq receipt at hand−1 (D6)
         ‖ deckRoot(32)        # §7 tree over the 52 post-shuffle ciphertexts
         ‖ hostShareRoot(32)   # §7 tree over host's 52 decryption shares
         ‖ guestShareRoot(32)
         ‖ hostCardPk(32)      # ristretto encoding, from the hello (spec §4)
         ‖ guestCardPk(32)
         ‖ button(1)           # 0x00 = host on the button, 0x01 = guest
         ‖ sb(32) ‖ bb(32)
         ‖ startingChips(32)   # AF-32: the both-signed chip↔wei anchor;
                               # weiPerChip = (0,0).deposit / startingChips.
                               # Client sets it to its real starting stack
                               # (200); contract MUST NOT re-derive it from
                               # bb (the `200*bb` guess disagreed — AF-32).

`markerHash = keccak256(preimage)`. Both-signed by session keys. The
contract rejects a second marker per hand, verifies `receiptHash`
continuity, and admits a first marker during a dispute window (spec §4).
An honest client signs only after shuffle proofs verify AND both cardPks
match the hello it received (load-bearing, D14).

## 5. Signed action

    0x03 ‖ "vault/act/v2" ‖ contract(20) ‖ chainid(32) ‖ session(32)
         ‖ hand(8) ‖ seq(8)
         ‖ action(1)           # 0x00 fold · 0x01 check · 0x02 call · 0x03 bet
         ‖ amount(32)          # canonical post-clamp integer; MUST be 0
                               # for fold/check/call (spec §5.3)
         ‖ prev(32)            # actionHash of seq−1; for seq 0:
                               # prev = markerHash of this hand

`actionHash = keccak256(preimage)`. Signed by the **actor's** session key
only — **the replayed betting state machine determines the unique legal
actor at every node; never derive the signer from seq parity.** Within a
street action alternates (`betting.ts:169`), but the same seat
legitimately acts at consecutive seqs across a street boundary — button
first preflop (`betting.ts:56`), non-button first postflop
(`betting.ts:196`) — so a parity-based validator rejects honest chains
(AF-2). Single-key-per-node holds regardless, so cross-key forks remain
impossible and the equivocation definition is unaffected (consecutive
own-actions differ in `seq` and `prev`). `prev₀ = markerHash`
binds the whole chain to the exact deck, keys, button, and blinds it was
played under; a chain can never be replayed against a different marker.
**Equivocation** = two valid signatures from one key over preimages equal
in everything except `action ‖ amount` (spec §5.1 "distinct"); admissible
as burn proof only if both are on file inside phase 1 (D8).

## 6. Session-key registration (wallet-signed)

    0x04 ‖ "vault/sessionkey/v2" ‖ contract(20) ‖ chainid(32) ‖ session(32)
         ‖ player(20)           # the wallet address being bound
         ‖ sessionKey(20)       # address form of the session public key

Signed by the **wallet** via `personal_sign` (EIP-191 at recovery — the
one artefact where the prefix applies). Registered at open/join (D2);
`sessionKey[session][player]` is immutable once set for the session.

## 7. Merkle trees (deck and shares)

- **Leaves are position-bound** — sorted-pair hashing is commutative and
  proves membership, not index, so the index lives inside the leaf:

      shareLeaf(p) = keccak256(0x05 ‖ "vault/shareleaf/v1" ‖ uint8(p) ‖ shareEnc(32))
      deckLeaf(p)  = keccak256(0x06 ‖ "vault/deckleaf/v1"  ‖ uint8(p) ‖ c1Enc(32) ‖ c2Enc(32))

  `p` ∈ 0..51 is the deck position. This supersedes the prototype's
  unbound `keccak(shareEnc)` leaf (§Prototype deltas).
- **Interior nodes**: sorted-pair `keccak256(min(a,b) ‖ max(a,b))`
  (byte-lexicographic = numeric order on bytes32). Odd node at a level
  pairs with itself — the prototype's rule, kept.
- 52 leaves → proofs are 6 hashes. The triple check (D10) is:
  `shareLeaf(p)`→`shareRoot`, `deckLeaf(p)`→`deckRoot` (same `p`, and the
  ciphertext is taken from this proof — never from the filer's word),
  then DLEQ (§8) against the marker's cardPk and that ciphertext's `c1`.

## 8. DLEQ challenge (chain-verifiable shares)

Statement: `share = c1 · x` where `cardPk = G · x`. Proof `(c, s)` with
challenge computed exactly as the measured prototype
(`prototypes/dispute-gas/gen/gen.mts`):

    payload = cardPkEnc ‖ c1Enc ‖ shareEnc ‖ t1Enc ‖ t2Enc     # 5 × 32 bytes
    h1 = keccak256(0x01 ‖ "vault/dleq/keccak-v1" ‖ payload)
    h2 = keccak256(0x02 ‖ "vault/dleq/keccak-v1" ‖ payload)
    c  = (h1 · 2²⁵⁶ + h2) mod L        # wide reduction, no bias

Verifier recomputes `t1 = G·s − cardPk·c`, `t2 = c1·s − share·c`
(prototype `Dleq.verify`, measured ~3.0M gas). The client emits this
keccak variant for every postable share (D3); wire-only proofs keep
sha512.

## 9. Dispute-filing interface (AF-1 change 2 — what P5/P6 build against)

Function shapes, pinned here so UI work parallelises; exact ABI/nat-spec
belongs to P3's implementation, which may add fields but not remove or
re-type these:

    openDispute(bytes32 session)
    fileReceipt(bytes32 session, Receipt r, bytes hostSig, bytes guestSig)   // also files finals
    fileMarker(bytes32 session, Marker m, bytes hostSig, bytes guestSig)
    fileActions(bytes32 session, Act[] acts, bytes[] sigs)                    // any segment, any order
    postShares(bytes32 session, SharePost[] posts)
        // SharePost = { uint8 pos; bytes32 shareEnc; uint256 c; uint256 s;
        //               bytes32[] shareProof; bytes32 c1Enc; bytes32 c2Enc;
        //               bytes32[] deckProof }
    phase2Act(bytes32 session, Act a, bytes sig)      // reverts out-of-turn/illegal (spec §5.3)
    resolve(bytes32 session)                          // lazy: consolidates + settles when due
    withdraw()                                        // pull-payment (D9)

Struct field names follow §3–§5's field order. Duration parameters
(window, bank, grace) are constructor args per D15.

**Session interface** (AF-2: §6's registration needed a pinned home; these
are P2's surface, which P5 also builds against). The host proposes the
whole table — both declared maxes — and the guest accepts by joining;
that is the "agreed at the door" of spec §2 made concrete:

    open(bytes32 session, address opponent, uint256 maxHost,
         uint256 maxGuest, address sessionKey, bytes walletSig) payable
        // msg.value = host buy-in + bond_host; walletSig per §6
    join(bytes32 session, address sessionKey, bytes walletSig) payable
        // msg.value = guest buy-in + bond_guest, derived from stored maxes
    cancelOpen(bytes32 session)          // pre-join escape, V1 parity
    deposit(bytes32 session) payable     // rebuy; chips only via receipt (D4)

## 10. Prototype deltas — regenerate before P3 consumes vectors

The measured prototypes are reference implementations (D3), but this
document tightens three conventions; `gen.mts` regenerates in P3 task 1:

1. **Action domain `vault/act/v1` → `v2`**, adding `contract ‖ chainid`
   after the domain (universal binding rule) — the prototype bound
   session only.
2. **`prev₀` = markerHash**, not `bytes32(0)`.
3. **Merkle leaves position-bound** (§7) — the prototype's
   `keccak(shareEnc)` leaf does not bind the index under sorted pairs,
   which D10 requires.

Gas impact of all three ≈ noise (larger preimages, same operation
counts); the measured conclusions stand. *Also informational (AF-2): the
prototype's action vectors pick the signer by `seq % 2` — vector content
only, and a wrong model of turn order (see §5); regenerated vectors must
derive signers from the replayed state.*
