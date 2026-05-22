// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";

/// @notice Starts the two-step factory ownership handoff to the operations owner.
///         The new owner must call `acceptOwnership()` separately.
contract StartFactoryOwnershipTransfer is Script {
    function run() external {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        address newOwner = vm.envAddress("NEW_FACTORY_OWNER");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(deployerPrivateKey != 0, "DEPLOYER_PRIVATE_KEY is zero");
        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(newOwner != address(0), "NEW_FACTORY_OWNER is zero");
        require(newOwner != factory.owner(), "new owner is current owner");

        vm.startBroadcast(deployerPrivateKey);
        factory.transferOwnership(newOwner);
        vm.stopBroadcast();
    }
}
