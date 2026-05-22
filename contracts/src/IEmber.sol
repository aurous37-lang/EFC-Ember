// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IERC165.sol";

/// @title IEmber — ERC-EMBER interface (Layer 1, neutral standard)
/// @notice Neutral, fee-free, confiscation-free surface for the burn-to-bloom
///         standard. The interface and the burn → Ember Phase → release/slash/
///         termination lifecycle are normative; pricing curve, sale mechanics,
///         storage backend, fee/treasury policy, and maintenance funding are
///         implementation-defined. Optional abandoned-capital recovery is NOT
///         part of this interface — see the `IEmberRecovery` extension.
interface IEmber is IERC165 {
    // === Source manifest ===
    struct SourceManifest {
        bytes32 archiveHash;
        bytes32 fileTreeMerkleRoot;
        bytes32 lockfileHash;
        bytes32 buildArtifactHash;
        string spdxLicense;
        string manifestCID;
    }

    // === Events ===
    event TokensBurnedForUse(address indexed user, uint256 amount, uint256 totalBurned);
    event SourceUpdated(uint256 indexed version, bytes32 commitment, string encryptedCID);
    event EmberPhase(uint256 deadline);
    event SourceReleased(string[] decryptionKeys);
    event ContractTerminated(uint256 finalBurned, uint256 timestamp);
    event Redeemed(address indexed holder, uint256 tokens, uint256 usdc);
    event ReserveSlashed(uint256 usdcAmount);

    // === Read functions ===
    function INITIAL_SUPPLY() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function released() external view returns (bool);
    function slashed() external view returns (bool);
    function terminated() external view returns (bool);
    function manifest() external view returns (SourceManifest memory);
    function sellOutTimestamp() external view returns (uint256);
    function releaseDeadline() external view returns (uint256);
    function devClaimable() external view returns (uint256);
    function redemptionQuote(uint256 amount) external view returns (uint256);

    // === State-changing functions ===
    function buy(uint256 amount, uint256 maxCost) external;
    function useApp(address user, uint256 amount) external returns (bool);
    function forceEmberPhase() external;
    function release(string[] calldata decryptionKeys) external;
    function slashReserve() external;
    function redeem(uint256 amount) external;
    function withdrawDev() external;
}
