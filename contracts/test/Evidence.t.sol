// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ristretto} from "../src/Ristretto.sol";
import {Dleq} from "../src/Dleq.sol";
import {Evaluator7} from "../src/Evaluator7.sol";
import {Evidence} from "../src/Evidence.sol";
import {Vectors} from "./vectors/Vectors.sol";

/// Merkle/DLEQ/decode/evaluator tests for the graduated crypto (task 1),
/// separate from the money-frame ChannelV2.t.sol. Task 9 extends this same
/// file/contract with the decode-and-match tests (per phase-3's Files
/// touched note); task 4 is postShares' own triple-check tests elsewhere.
contract EvidenceTest is Test {
    // ------------------------------------------------------------- helpers

    /// Evidence.merkleVerify's `proof` parameter is `calldata` (task 1 step
    /// 3, so `postShares` can pass a `SharePost[] calldata` element's proof
    /// straight through with no copy). Vectors.sol's accessors return
    /// `memory` arrays, so this wrapper's `external` boundary is what turns
    /// a memory-built proof into calldata for the call underneath — the
    /// standard Foundry pattern for exercising a calldata-typed library
    /// function from a test.
    function callMerkleVerify(bytes32 leaf, bytes32[] calldata proof, bytes32 root)
        external
        pure
        returns (bool)
    {
        return Evidence.merkleVerify(leaf, proof, root);
    }

    function _pairHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ------------------------------------------------------- §7 leaf shape

    function test_shareLeaf_matchesFormat() public pure {
        bytes32 shareEnc = bytes32(uint256(0x1234));
        bytes32 got = Evidence.shareLeaf(7, shareEnc);
        bytes32 want = keccak256(abi.encodePacked(bytes1(0x05), "vault/shareleaf/v1", uint8(7), shareEnc));
        assertEq(got, want);
    }

    function test_deckLeaf_matchesFormat() public pure {
        bytes32 c1 = bytes32(uint256(0xaaaa));
        bytes32 c2 = bytes32(uint256(0xbbbb));
        bytes32 got = Evidence.deckLeaf(9, c1, c2);
        bytes32 want = keccak256(abi.encodePacked(bytes1(0x06), "vault/deckleaf/v1", uint8(9), c1, c2));
        assertEq(got, want);
    }

    // ------------------------------------------------- AF-14 / M2 (step 6)

    /// M2 (fix round 1, P3-4): contract-side proof that position-binding
    /// actually changes the root, not just prose asserting it does. Build
    /// a small tree two ways from the SAME (pos, shareEnc) pairs — once via
    /// Evidence.shareLeaf (position-bound, §7), once via the prototype's
    /// superseded unbound shape (`keccak256(shareEnc)` alone, no tag, no
    /// position — §10's documented delta) — and assert the roots differ.
    /// AF-14: sorted-pair Merkle nodes are commutative, so membership alone
    /// never proves position; a filer who reuses the unbound leaf shape
    /// must fail a real Evidence.merkleVerify call against a position-bound
    /// root, which the second half of this test proves mechanically.
    function test_M2_positionBoundLeafChangesRoot() public view {
        bytes32[4] memory shareEncs = [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)), bytes32(uint256(4))];
        uint8[4] memory positions = [0, 1, 2, 3];

        bytes32[] memory boundLeaves = new bytes32[](4);
        bytes32[] memory unboundLeaves = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            boundLeaves[i] = Evidence.shareLeaf(positions[i], shareEncs[i]);
            unboundLeaves[i] = keccak256(abi.encodePacked(shareEncs[i])); // superseded prototype shape
        }

        bytes32 boundRoot = _pairHash(_pairHash(boundLeaves[0], boundLeaves[1]), _pairHash(boundLeaves[2], boundLeaves[3]));
        bytes32 unboundRoot =
            _pairHash(_pairHash(unboundLeaves[0], unboundLeaves[1]), _pairHash(unboundLeaves[2], unboundLeaves[3]));

        assertTrue(boundRoot != unboundRoot);

        // Mechanical: a proof valid against the unbound tree verifies
        // there, but fails against the position-bound root built from the
        // very same (pos, shareEnc) inputs.
        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = unboundLeaves[1];
        proof0[1] = _pairHash(unboundLeaves[2], unboundLeaves[3]);
        assertTrue(this.callMerkleVerify(unboundLeaves[0], proof0, unboundRoot));
        assertFalse(this.callMerkleVerify(unboundLeaves[0], proof0, boundRoot));
    }

    // ------------------------------------------------- generic merkleVerify

    function test_merkleVerify_sortedPairWalk_oddNodeSelfPairs() public view {
        // 3-leaf tree: odd node at a level pairs with itself (formats §7,
        // kept from the prototype).
        bytes32 leafA = keccak256("a");
        bytes32 leafB = keccak256("b");
        bytes32 leafC = keccak256("c");
        bytes32 h01 = _pairHash(leafA, leafB);
        bytes32 h22 = _pairHash(leafC, leafC);
        bytes32 root = _pairHash(h01, h22);

        bytes32[] memory proofA = new bytes32[](2);
        proofA[0] = leafB;
        proofA[1] = h22;
        assertTrue(this.callMerkleVerify(leafA, proofA, root));

        bytes32[] memory proofC = new bytes32[](2);
        proofC[0] = leafC;
        proofC[1] = h01;
        assertTrue(this.callMerkleVerify(leafC, proofC, root));

        assertFalse(this.callMerkleVerify(keccak256("z"), proofA, root));
    }

    // -------------------------------------------------- 52-card point table

    function test_cardPoints_countAndAllDistinct() public pure {
        bytes32[52] memory t = Evidence.CARD_POINTS();
        for (uint256 i = 0; i < 52; i++) {
            assertTrue(t[i] != bytes32(0));
            for (uint256 j = i + 1; j < 52; j++) {
                assertTrue(t[i] != t[j]);
            }
        }
    }

    /// Differential check (task 1 step 4 / verification probe): sampled
    /// indices (0, 1, 12, 25, 51) cross-checked via a node script importing
    /// the noble-curves ristretto255 implementation, computing
    /// BASE.multiply(i+1) for each sampled i and hex-encoding it, against
    /// poker/src/core/cards.ts:19's own formula, run against the poker
    /// repo's installed noble-curves package — see this task's completion
    /// notes for the exact command and its output. Nothing in `forge
    /// build` catches a transcription error in 52 hand-pasted constants;
    /// this is the check that does.
    function test_cardPoints_sampledAgainstNobleComputedValues() public pure {
        assertEq(Evidence.cardPoint(0), bytes32(0xe2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76));
        assertEq(Evidence.cardPoint(1), bytes32(0x6a493210f7499cd17fecb510ae0cea23a110e8d5b901f8acadd3095c73a3b919));
        assertEq(Evidence.cardPoint(12), bytes32(0xaa52e000df2e16f55fb1032fc33bc42742dad6bd5a8fc0be0167436c5948501f));
        assertEq(Evidence.cardPoint(25), bytes32(0x6cc0a929860a630dee3030be2f2ea4d5fbe3f1511cc0c1bc94c451fd61f36d7c));
        assertEq(Evidence.cardPoint(51), bytes32(0x30eb54ee0d290e0fd9f8a6c6cbc84e3a516645fe1be77429987375498aee8641));
    }

    function test_cardPoints_allDecodeCleanly() public view {
        // Every pasted constant must be a valid canonical ristretto255
        // encoding — decode() is the same check the contract runs at
        // combine/decode time (task 9).
        bytes32[52] memory t = Evidence.CARD_POINTS();
        for (uint256 i = 0; i < 52; i++) {
            (bool ok,) = Ristretto.decode(t[i]);
            assertTrue(ok);
        }
    }

    // ------------------------------------------------------------ Ristretto

    function test_ristretto_encodeDecodeRoundTrip_basePoint() public view {
        // The sound round-trip invariant is on the *wire encoding*, not
        // raw internal (x,y,z,t) equality: a ristretto element has four
        // equivalent extended-coordinate representatives, and decode()'s
        // canonical choice need not literally match the constructor's
        // input coordinates. re-encoding the decoded point must reproduce
        // the same 32 bytes.
        Ristretto.Pt memory base = Ristretto.base();
        bytes32 enc = Ristretto.encode(base);
        (bool ok, Ristretto.Pt memory dec) = Ristretto.decode(enc);
        assertTrue(ok);
        assertEq(Ristretto.encode(dec), enc);
    }

    // ------------------------------------------ combine (elgamal.ts:76-79)

    function test_combine_subtractsBothShares() public view {
        Ristretto.Pt memory g = Ristretto.base();
        Ristretto.Pt memory a = Ristretto.mul(g, 5);
        Ristretto.Pt memory hostShare = Ristretto.mul(g, 7);
        Ristretto.Pt memory guestShare = Ristretto.mul(g, 11);
        // c2 = a + hostShare + guestShare, so combine(c2, hostShare,
        // guestShare) must recover a — exactly combineShares' `c2 -
        // sum(shares)` (elgamal.ts:76-79).
        Ristretto.Pt memory c2 = Ristretto.add(Ristretto.add(a, hostShare), guestShare);
        Ristretto.Pt memory combined = Evidence.combine(c2, hostShare, guestShare);
        assertEq(Ristretto.encode(combined), Ristretto.encode(a));
    }

    // ------------------------------------------------------------ DLEQ

    function test_dleq_vectorsMatchExpected_includingTamperedNegative() public view {
        uint256 n = Vectors.dleqCount();
        for (uint256 i = 0; i < n; i++) {
            Vectors.Dleq memory d = Vectors.dleq(i);
            bool got = Dleq.verify(d.pub, d.base2, d.point2, d.c, d.s);
            assertEq(got, d.ok);
        }
    }

    function test_dleq_firstVector_verifiesTrue() public view {
        Vectors.Dleq memory d = Vectors.dleq(0);
        assertTrue(d.ok);
        assertTrue(Dleq.verify(d.pub, d.base2, d.point2, d.c, d.s));
    }

    // ------------------------------------------------ Merkle, real vectors

    function test_merkle_deckVectors_positionBound() public view {
        for (uint256 i = 0; i < Vectors.deckSampleCount(); i++) {
            (, bytes32 leaf) = Vectors.deckLeaf(i);
            bytes32[] memory proof = Vectors.deckProof(i);
            assertTrue(this.callMerkleVerify(leaf, proof, Vectors.DECK_ROOT));
        }
    }

    function test_merkle_hostShareVectors_positionBound() public view {
        for (uint256 i = 0; i < Vectors.host_shareSampleCount(); i++) {
            (, bytes32 leaf) = Vectors.host_shareLeaf(i);
            bytes32[] memory proof = Vectors.host_shareProof(i);
            assertTrue(this.callMerkleVerify(leaf, proof, Vectors.HOST_SHARE_ROOT));
        }
    }

    function test_merkle_guestShareVectors_positionBound() public view {
        for (uint256 i = 0; i < Vectors.guest_shareSampleCount(); i++) {
            (, bytes32 leaf) = Vectors.guest_shareLeaf(i);
            bytes32[] memory proof = Vectors.guest_shareProof(i);
            assertTrue(this.callMerkleVerify(leaf, proof, Vectors.GUEST_SHARE_ROOT));
        }
    }

    // -------------------------------------------------- Evaluator7, known hands

    /// Crafted 7-card hands: the same (cards, packed-score) pairs as
    /// prototypes/dispute-gas/test/Vectors.sol's evalVec(0..4), which that
    /// prototype's own gen/gen.mts produced by running
    /// poker/src/core/evaluator.ts verbatim (copied into
    /// gen/evaluator.mts) and packing its score array — the differential
    /// chain the prototype's README documents (D3: prototypes are
    /// reference implementations). Re-derived here by hand against
    /// Evaluator7.sol's own pack1/pack2/pack5 formulas as a second,
    /// independent check before trusting them in this file.
    function test_evaluator_knownHands() public pure {
        _assertHand([uint8(0), 1, 2, 3, 4, 18, 33], 8650752); // straight flush, 6-high
        _assertHand([uint8(12), 0, 1, 2, 3, 30, 44], 8585216); // wheel straight flush (A-2-3-4-5)
        _assertHand([uint8(5), 18, 31, 44, 7, 8, 9], 7704576); // quads (5s), 9 kicker
        _assertHand([uint8(5), 18, 31, 6, 19, 10, 24], 6643712); // full house, 5s over 6s
        _assertHand([uint8(0), 2, 4, 6, 9, 14, 27], 5858336); // flush
    }

    function _assertHand(uint8[7] memory cards, uint256 expectedPacked) internal pure {
        assertEq(Evaluator7.evaluate(cards), expectedPacked);
    }
}
