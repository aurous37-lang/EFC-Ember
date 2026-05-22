// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 18-decimal token used to verify EmberFactory rejects non-6-decimal
///         sale tokens. Implements only the IERC20Token surface the factory touches.
contract MockToken18 {
    uint8 public constant decimals = 18;

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}
