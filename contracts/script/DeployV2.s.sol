// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChannelV2} from "../src/ChannelV2.sol";

/// Deploys ChannelV2.sol. Mirrors V1's deploy script's chain-id refusal
/// exactly (D11) — refuses to run on any chain ID except Base Sepolia
/// (84532) or a local anvil node (31337, for dry runs). This file is new
/// and standalone — it does not import or reference V1's contract or its
/// own deploy script at all (D11's untouched-V1 boundary, enforced at the
/// file level).
///
/// D15: window/bank/grace are constructor parameters, never inlined. The
/// spec's values (24h/6h/6h) are the only production-legal durations —
/// this script refuses to deploy any other combination unless
/// `TEST_DURATIONS=true` is set in the environment. The phase brief's
/// literal wording ("unless an explicit `--test-durations` flag is
/// passed") is implemented as an env var instead: `forge script` has no
/// custom-flag parser, and V1's own deploy script already reads its
/// window override (`WINDOW_SECONDS`) exactly this way — same spirit,
/// same mechanism, no new deploy-tooling surface (task 7 step 4).
contract DeployV2 is Script {
    uint256 constant BASE_SEPOLIA = 84532;
    uint256 constant ANVIL_LOCAL = 31337;

    uint256 constant WINDOW_DEFAULT = 24 hours;
    uint256 constant BANK_DEFAULT = 6 hours;
    uint256 constant GRACE_DEFAULT = 6 hours;

    string constant NON_SPEC_DURATIONS_ERR = "refusing to deploy non-spec durations without TEST_DURATIONS=true";

    function run() external {
        require(
            block.chainid == BASE_SEPOLIA || block.chainid == ANVIL_LOCAL,
            "refusing to deploy: chain id is not Base Sepolia (84532) or local anvil (31337)"
        );

        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 windowSeconds = vm.envOr("WINDOW_SECONDS", WINDOW_DEFAULT);
        uint256 bankSeconds = vm.envOr("BANK_SECONDS", BANK_DEFAULT);
        uint256 graceSeconds = vm.envOr("GRACE_SECONDS", GRACE_DEFAULT);
        bool testDurations = vm.envOr("TEST_DURATIONS", false);

        if (!testDurations) {
            require(
                windowSeconds == WINDOW_DEFAULT && bankSeconds == BANK_DEFAULT && graceSeconds == GRACE_DEFAULT,
                NON_SPEC_DURATIONS_ERR
            );
        }

        address deployer = vm.addr(pk);

        console2.log("Chain ID              :", block.chainid);
        console2.log("Deployer address      :", deployer);
        console2.log("Deployer balance      :", deployer.balance);
        console2.log("Dispute window (s)    :", windowSeconds);
        console2.log("Bank duration (s)     :", bankSeconds);
        console2.log("Grace duration (s)    :", graceSeconds);
        console2.log("TEST_DURATIONS        :", testDurations);

        vm.startBroadcast(pk);
        ChannelV2 channel = new ChannelV2(windowSeconds, bankSeconds, graceSeconds);
        vm.stopBroadcast();

        console2.log("ChannelV2 deployed at :", address(channel));
    }
}
