// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Channel} from "../src/Channel.sol";

/// Deploys Channel.sol. Refuses to run on any chain ID except Base Sepolia
/// (84532) or a local anvil node (31337, for dry runs) — the single most
/// expensive mistake available here is an RPC URL that quietly points at a
/// real network, so this is a hard stop, not a warning.
contract Deploy is Script {
    uint256 constant BASE_SEPOLIA = 84532;
    uint256 constant ANVIL_LOCAL = 31337;

    function run() external {
        require(
            block.chainid == BASE_SEPOLIA || block.chainid == ANVIL_LOCAL,
            "refusing to deploy: chain id is not Base Sepolia (84532) or local anvil (31337)"
        );

        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 window = vm.envOr("WINDOW_SECONDS", uint256(30 minutes));
        address deployer = vm.addr(pk);

        console2.log("Chain ID           :", block.chainid);
        console2.log("Deployer address   :", deployer);
        console2.log("Deployer balance   :", deployer.balance);
        console2.log("Dispute window (s) :", window);

        vm.startBroadcast(pk);
        Channel channel = new Channel(window);
        vm.stopBroadcast();

        console2.log("Channel deployed at:", address(channel));
    }
}
