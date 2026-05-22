// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEmberRecovery — OPTIONAL abandoned-capital recovery extension
/// @notice NOT part of the neutral ERC-EMBER standard (`IEmber`). This is an
///         optional extension: if a deployment configures a recovery treasury and
///         commission recipient, idle USDC can be swept after a long inactivity
///         window. Direct deployments disable it by configuring no recipients;
///         distribution factories MAY wire it as product policy. Treasury and
///         commission routing are deliberately kept OUT of core ERC conformance.
interface IEmberRecovery {
    event AbandonedCapitalRecovered(uint256 treasuryAmount, uint256 commissionAmount);

    function abandonedRecovered() external view returns (bool);
    function lastProjectActivity() external view returns (uint256);
    function recoveryTreasury() external view returns (address);
    function recoveryCommissionRecipient() external view returns (address);
    function recoverAbandonedCapital() external;
}
