// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";

/// @notice Read-only launch check for an already deployed EmberFactory.
contract CheckFactoryDeployment is Script {
    function run() external view {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        address expectedStandardAuthor = vm.envAddress("STANDARD_AUTHOR");
        address expectedRecoveryTreasury = vm.envAddress("RECOVERY_TREASURY");
        address expectedPoolFactory = vm.envAddress("MAINTENANCE_POOL_FACTORY");
        address expectedOwner = vm.envAddress("EXPECTED_FACTORY_OWNER");
        address expectedPendingOwner = vm.envAddress("EXPECTED_PENDING_FACTORY_OWNER");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(expectedStandardAuthor != address(0), "STANDARD_AUTHOR is zero");
        require(expectedRecoveryTreasury != address(0), "RECOVERY_TREASURY is zero");
        require(expectedPoolFactory != address(0), "MAINTENANCE_POOL_FACTORY is zero");
        require(expectedPoolFactory.code.length != 0, "pool factory has no code");
        require(expectedOwner != address(0), "EXPECTED_FACTORY_OWNER is zero");
        require(factory.STANDARD_AUTHOR() == expectedStandardAuthor, "standard author mismatch");
        require(factory.RECOVERY_TREASURY() == expectedRecoveryTreasury, "recovery treasury mismatch");
        require(address(factory.POOL_FACTORY()) == expectedPoolFactory, "pool factory mismatch");
        require(factory.owner() == expectedOwner, "owner mismatch");
        require(factory.pendingOwner() == expectedPendingOwner, "pending owner mismatch");
    }
}
