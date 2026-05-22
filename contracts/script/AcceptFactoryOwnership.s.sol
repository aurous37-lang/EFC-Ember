// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";

/// @notice Accepts the two-step factory ownership handoff for EOA owners.
///         Multisig/Safe owners should execute `acceptOwnership()` from the Safe.
contract AcceptFactoryOwnership is Script {
    function run() external {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        uint256 newOwnerPrivateKey = vm.envUint("NEW_FACTORY_OWNER_PRIVATE_KEY");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        address newOwner = vm.addr(newOwnerPrivateKey);

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(newOwnerPrivateKey != 0, "NEW_FACTORY_OWNER_PRIVATE_KEY is zero");
        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(factory.pendingOwner() == newOwner, "not pending owner");

        vm.startBroadcast(newOwnerPrivateKey);
        factory.acceptOwnership();
        vm.stopBroadcast();
    }
}
