// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";
import "../src/MaintenancePoolFactory.sol";

/// @notice Deploys the production distribution surface:
///         MaintenancePoolFactory first, then EmberFactory wired to it.
contract DeployFactory is Script {
    function run() external returns (MaintenancePoolFactory poolFactory, EmberFactory emberFactory) {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address standardAuthor = vm.envAddress("STANDARD_AUTHOR");
        address recoveryTreasury = vm.envAddress("RECOVERY_TREASURY");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(deployerPrivateKey != 0, "DEPLOYER_PRIVATE_KEY is zero");
        require(standardAuthor != address(0), "STANDARD_AUTHOR is zero");
        require(recoveryTreasury != address(0), "RECOVERY_TREASURY is zero");
        require(standardAuthor != recoveryTreasury, "recipients must differ");

        vm.startBroadcast(deployerPrivateKey);

        poolFactory = new MaintenancePoolFactory();
        emberFactory = new EmberFactory(standardAuthor, recoveryTreasury, address(poolFactory));

        vm.stopBroadcast();
    }
}
