// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC-165 standard interface detection.
interface IERC165 {
    /// @notice Returns true if this contract implements `interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
