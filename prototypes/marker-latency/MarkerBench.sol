// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Marker-latency measurement stand-in for spec §11.2(a).
///
/// Mimics the real hand-start marker's write shape — one storage slot per
/// hand plus an event over marker-sized calldata, with the co-filed receipt
/// bytes included per the thirteenth check's 7d — so the latency and fee
/// measured here transfer to the real thing. Refuses to run anywhere but
/// Base Sepolia (84532) or a local anvil (31337), same guard as Deploy.s.sol.
contract MarkerBench {
    uint256 constant BASE_SEPOLIA = 84532;
    uint256 constant ANVIL = 31337;

    mapping(bytes32 => mapping(uint64 => bytes32)) public marker;

    event Marker(bytes32 indexed session, uint64 indexed hand, bytes32 digest);

    constructor() {
        require(
            block.chainid == BASE_SEPOLIA || block.chainid == ANVIL,
            "wrong chain"
        );
    }

    /// One marker + its co-filed receipt, as calldata of realistic size.
    /// markerBlob ~= the signed tuple (11 fields + 2 sigs ~= 500 bytes);
    /// receiptBlob ~= a signed receipt (~360 bytes).
    function post(
        bytes32 session,
        uint64 hand,
        bytes calldata markerBlob,
        bytes calldata receiptBlob
    ) external {
        require(marker[session][hand] == bytes32(0), "duplicate marker");
        bytes32 digest = keccak256(abi.encodePacked(markerBlob, receiptBlob));
        marker[session][hand] = digest;
        emit Marker(session, hand, digest);
    }
}
