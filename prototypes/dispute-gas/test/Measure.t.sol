// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ristretto} from "../src/Ristretto.sol";
import {Dleq} from "../src/Dleq.sol";
import {Evaluator7} from "../src/Evaluator7.sol";
import {Bench} from "../src/Bench.sol";
import {Vectors} from "./Vectors.sol";

/// External wrappers so `forge test --gas-report` prices each op.
contract Harness {
    function dleqVerify(bytes32 p, bytes32 b, bytes32 q, uint256 c, uint256 s)
        external
        view
        returns (bool)
    {
        return Dleq.verify(p, b, q, c, s);
    }

    function decode(bytes32 e) external view returns (bool ok) {
        (ok,) = Ristretto.decode(e);
    }

    function scalarMulBase(uint256 k) external view returns (bytes32) {
        return Ristretto.encode(Ristretto.mul(Ristretto.base(), k));
    }

    function evaluate(uint8[7] calldata cards) external pure returns (uint256) {
        return Evaluator7.evaluate(cards);
    }

    function chain(bytes32 session, address host, address guest, Bench.Act[] calldata acts)
        external
        pure
        returns (bytes32)
    {
        Bench.Act[] memory m = acts;
        return Bench.verifyChain(session, host, guest, m);
    }

    function merkle(bytes32 leaf, bytes32[] calldata proof, bytes32 root)
        external
        pure
        returns (bool)
    {
        return Bench.merkleVerify(leaf, proof, root);
    }
}

contract MeasureTest {
    event Gas(string op, uint256 used);

    Harness h = new Harness();

    function test_dleq_vectors_and_gas() public {
        uint256 n = Vectors.dleqCount();
        for (uint256 i = 0; i < n; i++) {
            Vectors.Dleq memory v = Vectors.dleq(i);
            uint256 g0 = gasleft();
            bool ok = h.dleqVerify(bytes32(v.pub), bytes32(v.base2), bytes32(v.point2), v.c, v.s);
            uint256 used = g0 - gasleft();
            require(ok == v.ok, "dleq verdict mismatch");
            if (i == 0) emit Gas("dleqVerify (one share)", used);
        }
        emit Gas("dispute showdown: 4 hole shares x2 sides", 0); // context marker
    }

    function test_ristretto_roundtrip_and_gas() public {
        Vectors.Dleq memory v = Vectors.dleq(0);
        uint256 g0 = gasleft();
        (bool ok, Ristretto.Pt memory p) = Ristretto.decode(bytes32(v.pub));
        emit Gas("decode", g0 - gasleft());
        require(ok, "decode failed");
        g0 = gasleft();
        bytes32 e = Ristretto.encode(p);
        emit Gas("encode", g0 - gasleft());
        require(e == bytes32(v.pub), "roundtrip");
        g0 = gasleft();
        h.scalarMulBase(12345678901234567890);
        emit Gas("scalarMul+encode (via call)", g0 - gasleft());
    }

    function test_evaluator_vectors_and_gas() public {
        uint256 n = Vectors.evalCount();
        uint256 worst;
        for (uint256 i = 0; i < n; i++) {
            (uint8[7] memory cards, uint256 want) = Vectors.evalVec(i);
            uint256 g0 = gasleft();
            uint256 got = h.evaluate(cards);
            uint256 used = g0 - gasleft();
            if (used > worst) worst = used;
            require(got == want, "evaluator mismatch");
        }
        emit Gas("evaluate 7-card (worst of 120)", worst);
    }

    function test_action_chain_and_merkle() public {
        uint256 n = Vectors.actCount();
        Bench.Act[] memory acts = new Bench.Act[](n);
        for (uint256 i = 0; i < n; i++) {
            Vectors.Act memory a = Vectors.act(i);
            acts[i] = Bench.Act(a.hand, a.seq, a.action, a.amount, a.v, a.r, a.s);
        }
        uint256 g0 = gasleft();
        h.chain(Vectors.SESSION, Vectors.HOST, Vectors.GUEST, acts);
        emit Gas("verify 20-action signed chain", g0 - gasleft());

        bytes32[] memory proof = Vectors.merkleProof();
        g0 = gasleft();
        bool ok = h.merkle(Vectors.MERKLE_LEAF_SHARE_HASH, proof, Vectors.MERKLE_ROOT);
        emit Gas("merkle proof (52 leaves)", g0 - gasleft());
        require(ok, "merkle");
    }
}
