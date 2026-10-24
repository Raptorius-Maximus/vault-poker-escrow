// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vectors} from "./vectors/Vectors.sol";

/// Phase 3 task 2 -- re-verifies the vector copy P2 already landed
/// (D18: P2 owns the copy plus its own `sha256sum -c` gate; this phase does
/// not copy anything and does not own a second copy mechanism). Per D18, a
/// missing or mismatched copy is a hard gate FAILURE for this task, never a
/// fallback -- so this test's own sha256 check inside `forge test` is a
/// second, executable instance of the same gate the shell-level
/// `sha256sum -c test/vectors/CHECKSUMS.sha256` command (this task's own
/// verification probe) already runs. Recorded hashes below are copied
/// verbatim from `test/vectors/CHECKSUMS.sha256` (itself sha256-identical
/// to P1's task-10 commit in the poker repo, re-recorded once by the AF-26
/// fix commit -- JSON hash unchanged, Vectors.sol hash updated when the
/// emitter started checksumming addresses so solc would accept it).
///
/// Second half: consumes one vector from `Vectors.sol` directly (AF-26:
/// now compiling, unlike at P2's time -- see ChannelV2.t.sol's header for
/// the historical skip/vm.readFile workaround, which this file does not
/// need since it imports `Vectors.sol` the way `Evidence.t.sol` already
/// does).
contract VectorsIntegrityTest is Test {
    // AF-32: regenerated after the marker gained its signed `startingChips`
    // field (formats §4 amendment) -- new hashes, as D18 expects.
    bytes32 constant EXPECTED_JSON_SHA256 = 0x24c74564992aac766213a771adc2af5a05889fef1de0a0fed611b2d3a3b499c0;
    bytes32 constant EXPECTED_VECTORS_SOL_SHA256 = 0x52d8959ef89582043f53e38ae267fb3031ccd1dfaf30b1c7d6f02100e3219e9f;

    function test_p1VectorsJson_sha256Matches() public view {
        bytes memory data = vm.readFileBinary("test/vectors/p1-vectors.json");
        assertEq(sha256(data), EXPECTED_JSON_SHA256, "p1-vectors.json sha256 mismatch (D18 hard gate)");
    }

    function test_vectorsSol_sha256Matches() public view {
        bytes memory data = vm.readFileBinary("test/vectors/Vectors.sol");
        assertEq(sha256(data), EXPECTED_VECTORS_SOL_SHA256, "Vectors.sol sha256 mismatch (D18 hard gate)");
    }

    /// AF-26: Vectors.sol now compiles (checksummed address literals) --
    /// consume one vector from it directly, as the dispatch note names.
    function test_consumesOneVectorFromVectorsSol() public pure {
        Vectors.Receipt memory r0 = Vectors.receipt(0);
        assertEq(r0.hand, 0);
        assertEq(r0.subseq, 0);
        assertFalse(r0.final_);
        assertEq(r0.hostStack, 200000000000000000);
        assertEq(r0.guestStack, 200000000000000000);
        assertEq(r0.hostStack + r0.guestStack, r0.hostDeposit + r0.guestDeposit);

        assertEq(Vectors.HOST, vm.addr(1001));
        assertEq(Vectors.GUEST, vm.addr(2002));
    }
}
