// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./EmberCore.sol";
import "./MaintenancePool.sol";
import "./MaintenancePoolFactory.sol";
import "./IEmber.sol";
import "./IERC20Token.sol";

/// @title EmberFactory — Material Synced's monetized distribution (Layer 3)
/// @notice Deploys EmberCore with the 1.3% fee wired in, enforces an OSI-approved
///         SPDX allowlist as a product policy, and registers deployments.
contract EmberFactory {
    address public immutable STANDARD_AUTHOR;
    address public immutable RECOVERY_TREASURY;
    MaintenancePoolFactory public immutable POOL_FACTORY;
    uint256 public constant FACTORY_FEE_BPS = 130; // 1.3%

    address public owner;
    address public pendingOwner;
    // Product policy: OSI-approved SPDX allowlist keyed by keccak256(identifier).
    mapping(bytes32 => bool) public approvedLicense;

    struct DeploymentInfo {
        address developer;
        uint256 deployedAt;
        address maintenancePool; // address(0) if none
        bytes32 parentDeployment; // for fork lineage; 0 if original
        bool licenseVerified;
    }

    address[] public deployments;
    mapping(address => DeploymentInfo) public info;
    mapping(address => address[]) public devProjects;

    event Deployed(
        address indexed token,
        address indexed developer,
        address maintenancePool,
        bytes32 parentDeployment,
        bool licenseVerified
    );
    event LicenseApprovalSet(bytes32 indexed licenseHash, bool approved);
    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address standardAuthor, address recoveryTreasury, address poolFactory) {
        require(standardAuthor != address(0), "no standard author");
        require(recoveryTreasury != address(0), "no recovery treasury");
        require(poolFactory != address(0), "no pool factory");
        STANDARD_AUTHOR = standardAuthor;
        RECOVERY_TREASURY = recoveryTreasury;
        POOL_FACTORY = MaintenancePoolFactory(poolFactory);
        owner = msg.sender;
    }

    /// @notice Material Synced curates the OSI-approved SPDX allowlist off-chain
    ///         and mirrors it here. Product policy, not part of the standard.
    function setLicenseApproval(string calldata spdx, bool approved) external onlyOwner {
        bytes32 h = keccak256(bytes(spdx));
        approvedLicense[h] = approved;
        emit LicenseApprovalSet(h, approved);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "no owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function deploy(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address dApp,
        bytes32 originalCommitment,
        string memory originalEncryptedCID,
        IEmber.SourceManifest memory srcManifest,
        address usdc,
        uint256 basePrice,
        uint256 slope,
        bool spawnMaintenancePool,
        MaintenancePool.GovernanceMode poolMode,
        address poolGovernor,
        uint256 poolTimelockDelay,
        bytes32 parentDeployment
    ) external returns (address ember, address pool) {
        // Product policy: factory deployments must carry an OSI-approved license.
        require(approvedLicense[keccak256(bytes(srcManifest.spdxLicense))], "license not OSI-approved");
        // Product policy: the sale token must be 6-decimal USDC (the bonding curve assumes 6 decimals).
        require(IERC20Token(usdc).decimals() == 6, "USDC decimals");

        ember = address(
            new EmberCore(
                name,
                symbol,
                initialSupply,
                msg.sender,
                dApp,
                originalCommitment,
                originalEncryptedCID,
                srcManifest,
                usdc,
                basePrice,
                slope,
                STANDARD_AUTHOR,
                FACTORY_FEE_BPS,
                RECOVERY_TREASURY,
                STANDARD_AUTHOR
            )
        );

        if (spawnMaintenancePool) {
            pool = POOL_FACTORY.create(ember, poolGovernor, usdc, poolMode, poolTimelockDelay);
        }

        deployments.push(ember);
        info[ember] = DeploymentInfo({
            developer: msg.sender,
            deployedAt: block.timestamp,
            maintenancePool: pool,
            parentDeployment: parentDeployment,
            licenseVerified: true
        });
        devProjects[msg.sender].push(ember);

        emit Deployed(ember, msg.sender, pool, parentDeployment, true);
    }

    function deploymentCount() external view returns (uint256) {
        return deployments.length;
    }

    function projectsByDeveloper(address dev) external view returns (address[] memory) {
        return devProjects[dev];
    }
}
