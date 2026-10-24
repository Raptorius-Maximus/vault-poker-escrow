// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployV2} from "../script/DeployV2.s.sol";
import {ChannelV2} from "../src/ChannelV2.sol";

/// Task 7 step 7 (fix round 1, B7 / AF-23): the D15 duration guard test
/// this phase's earlier contract dispatch wrongly omitted. Asserts a
/// non-spec-duration deploy reverts with its exact string, and the
/// spec-duration complement succeeds and reads back the defaults.
contract DeployV2Test is Test {
    uint256 constant ANVIL_LOCAL = 31337;

    uint256 constant WINDOW_DEFAULT = 24 hours;
    uint256 constant BANK_DEFAULT = 6 hours;
    uint256 constant GRACE_DEFAULT = 6 hours;

    uint256 constant DEPLOYER_PK = 0xA11CE;

    function setUp() public {
        // Set explicitly rather than assumed from Foundry's default test
        // chain id (task 7 step 7's own instruction: this is the one place
        // this doc would otherwise make an unverified world-facing claim).
        vm.chainId(ANVIL_LOCAL);
        vm.deal(vm.addr(DEPLOYER_PK), 10 ether);
        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));
    }

    /// Both scenarios run inside ONE test function, sequentially, rather
    /// than as two separate `test_` functions. Reason (recorded, not
    /// obvious): `vm.setEnv` mutates the forge process's real OS
    /// environment, which is shared across every test in the suite; forge
    /// runs test functions concurrently by default, so two separate test
    /// functions each calling `vm.setEnv` on the same keys (WINDOW_SECONDS
    /// etc.) race each other non-deterministically — confirmed empirically
    /// during this dispatch (an earlier two-function version of this test
    /// intermittently failed scenario (b) with scenario (a)'s duration
    /// still set, depending on scheduling). Running both in one function
    /// closes the race entirely.
    ///
    /// (a) non-spec duration reverts with the exact string from
    /// DeployV2.s.sol step 4 — read via a harness that subclasses DeployV2
    /// purely to expose its internal NON_SPEC_DURATIONS_ERR constant
    /// (mirrors ChannelV2.t.sol's BurnHarness pattern), so this test
    /// references the same declared string instead of retyping it by hand.
    ///
    /// (b) the complement: spec defaults, TEST_DURATIONS unset (explicitly
    /// false here for determinism) -> run() succeeds; the deployed
    /// ChannelV2's constructor-stored durations read back the spec
    /// defaults via its public window()/bank()/grace() getters.
    function test_run_durationGuard() public {
        string memory expectedErr = new DeployV2ErrorExposer().nonSpecDurationsErr();

        // (a)
        vm.setEnv("WINDOW_SECONDS", vm.toString(uint256(3600))); // != WINDOW_DEFAULT
        vm.setEnv("BANK_SECONDS", vm.toString(BANK_DEFAULT));
        vm.setEnv("GRACE_SECONDS", vm.toString(GRACE_DEFAULT));
        vm.setEnv("TEST_DURATIONS", "false");

        DeployV2 scriptA = new DeployV2();
        vm.expectRevert(bytes(expectedErr));
        scriptA.run();

        // (b)
        vm.setEnv("WINDOW_SECONDS", vm.toString(WINDOW_DEFAULT));
        vm.setEnv("BANK_SECONDS", vm.toString(BANK_DEFAULT));
        vm.setEnv("GRACE_SECONDS", vm.toString(GRACE_DEFAULT));
        vm.setEnv("TEST_DURATIONS", "false");

        DeployV2 scriptB = new DeployV2();
        address deployer = vm.addr(DEPLOYER_PK);
        uint64 nonceBefore = vm.getNonce(deployer);

        scriptB.run();

        address deployed = vm.computeCreateAddress(deployer, nonceBefore);
        ChannelV2 channel = ChannelV2(deployed);
        assertEq(channel.window(), WINDOW_DEFAULT);
        assertEq(channel.bank(), BANK_DEFAULT);
        assertEq(channel.grace(), GRACE_DEFAULT);
    }
}

/// Test-only harness (mirrors ChannelV2.t.sol's BurnHarness pattern):
/// subclasses DeployV2 purely to expose its internal
/// NON_SPEC_DURATIONS_ERR constant, so the revert-string assertion above
/// references the same declared string instead of retyping it by hand
/// (task 7 step 7's explicit requirement) — without editing DeployV2.s.sol,
/// which is out of scope for this dispatch.
contract DeployV2ErrorExposer is DeployV2 {
    function nonSpecDurationsErr() external pure returns (string memory) {
        return NON_SPEC_DURATIONS_ERR;
    }
}
