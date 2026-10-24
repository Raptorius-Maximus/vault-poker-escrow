// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * The cheap dispute-path pieces: signed action chains and Merkle inclusion.
 */
library Bench {
    struct Act {
        uint64 hand;
        uint64 seq;
        uint8 action;
        uint256 amount;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// Verify an alternating signed action chain. Returns the final hash.
    function verifyChain(bytes32 session, address host, address guest, Act[] memory acts)
        internal
        pure
        returns (bytes32 prev)
    {
        for (uint256 i = 0; i < acts.length; i++) {
            Act memory a = acts[i];
            bytes32 h = keccak256(
                abi.encodePacked(
                    uint8(3), "vault/act/v1", session, a.hand, a.seq, a.action, a.amount, prev
                )
            );
            address signer = ecrecover(h, a.v, a.r, a.s);
            require(signer == (a.seq % 2 == 0 ? host : guest), "bad signer");
            prev = h;
        }
    }

    /// Sorted-pair keccak Merkle proof.
    function merkleVerify(bytes32 leaf, bytes32[] memory proof, bytes32 root)
        internal
        pure
        returns (bool)
    {
        bytes32 h = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            h = h <= p ? keccak256(abi.encodePacked(h, p)) : keccak256(abi.encodePacked(p, h));
        }
        return h == root;
    }
}
