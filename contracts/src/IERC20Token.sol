// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal USDC-style ERC20 surface used by EmberCore / MaintenancePool.
interface IERC20Token {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function decimals() external view returns (uint8);
}
