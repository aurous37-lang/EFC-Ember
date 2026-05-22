// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/IERC20Token.sol";

/// @notice Read-only check for the launch-approved sale token address.
contract CheckCanonicalUSDC is Script {
    function run() external view {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        address usdc = vm.envAddress("USDC");
        address canonicalUsdc = vm.envAddress("CANONICAL_USDC");

        require(block.chainid == expectedChainId, "chain id mismatch");
        require(usdc != address(0), "USDC is zero");
        require(canonicalUsdc != address(0), "CANONICAL_USDC is zero");
        require(usdc == canonicalUsdc, "USDC not canonical");
        require(usdc.code.length != 0, "USDC has no code");
        require(IERC20Token(usdc).decimals() == 6, "USDC decimals");
    }
}
