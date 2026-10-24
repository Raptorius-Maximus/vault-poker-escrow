// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// Copied from prototypes/dispute-gas/src/Dleq.sol, 2026-08-17 — see that file's README for the differential-testing chain that validated it.

import {Ristretto} from "./Ristretto.sol";

/**
 * Chaum-Pedersen DLEQ verification over ristretto255, keccak challenge.
 *
 * Mirrors poker/src/core/proofs.ts verifyDleq: recompute
 *   t1 = G*s - pub*c ; t2 = base2*s - point2*c
 * and check the Fiat-Shamir challenge over the five wire encodings.
 * The challenge hash is keccak256 (spec amendment for chain verifiability;
 * the client's sha512 challenge is replaced for V2 artefacts) with wide
 * 512-bit reduction mod L to kill bias — mirrored bit-for-bit in gen.mts.
 */
library Dleq {
    uint256 private constant L = Ristretto.L;
    uint256 private constant TWO256_MOD_L =
        7237005577332262213973186563042994240413239274941949949428319933631315875101;

    function challenge(bytes32 pub, bytes32 base2, bytes32 point2, bytes32 t1, bytes32 t2)
        internal
        pure
        returns (uint256)
    {
        bytes memory payload = abi.encodePacked(pub, base2, point2, t1, t2);
        uint256 h1 = uint256(keccak256(abi.encodePacked(uint8(1), "vault/dleq/keccak-v1", payload)));
        uint256 h2 = uint256(keccak256(abi.encodePacked(uint8(2), "vault/dleq/keccak-v1", payload)));
        return addmod(mulmod(h1 % L, TWO256_MOD_L, L), h2 % L, L);
    }

    function verify(bytes32 pubEnc, bytes32 base2Enc, bytes32 point2Enc, uint256 c, uint256 s)
        internal
        view
        returns (bool)
    {
        if (c >= L || s >= L) return false;
        (bool ok1, Ristretto.Pt memory pub) = Ristretto.decode(pubEnc);
        (bool ok2, Ristretto.Pt memory base2) = Ristretto.decode(base2Enc);
        (bool ok3, Ristretto.Pt memory point2) = Ristretto.decode(point2Enc);
        if (!ok1 || !ok2 || !ok3) return false;

        Ristretto.Pt memory t1 =
            Ristretto.add(Ristretto.mul(Ristretto.base(), s), Ristretto.neg(Ristretto.mul(pub, c)));
        Ristretto.Pt memory t2 =
            Ristretto.add(Ristretto.mul(base2, s), Ristretto.neg(Ristretto.mul(point2, c)));

        return challenge(pubEnc, base2Enc, point2Enc, Ristretto.encode(t1), Ristretto.encode(t2)) == c;
    }
}
