// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";

/// @notice Read-only check that one SPDX identifier has the expected allowlist state.
contract CheckLicenseApproval is Script {
    function run() external view {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        string memory spdxLicense = vm.envString("SPDX_LICENSE");
        bool expectedApproval = vm.envBool("LICENSE_APPROVED");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(bytes(spdxLicense).length != 0, "SPDX_LICENSE is empty");
        require(factory.approvedLicense(keccak256(bytes(spdxLicense))) == expectedApproval, "license approval mismatch");
    }
}
