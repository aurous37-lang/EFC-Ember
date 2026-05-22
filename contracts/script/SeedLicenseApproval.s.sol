// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";

/// @notice Sets one SPDX identifier in the factory allowlist.
///         Re-run this script for each license the launch operator approves.
contract SeedLicenseApproval is Script {
    function run() external {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        string memory spdxLicense = vm.envString("SPDX_LICENSE");
        bool approved = vm.envBool("LICENSE_APPROVED");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(deployerPrivateKey != 0, "DEPLOYER_PRIVATE_KEY is zero");
        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(bytes(spdxLicense).length != 0, "SPDX_LICENSE is empty");

        vm.startBroadcast(deployerPrivateKey);
        factory.setLicenseApproval(spdxLicense, approved);
        vm.stopBroadcast();
    }
}
