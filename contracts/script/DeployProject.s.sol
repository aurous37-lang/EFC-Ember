// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberFactory.sol";
import "../src/IERC20Token.sol";
import "../src/IEmber.sol";
import "../src/MaintenancePool.sol";

/// @notice Deploys one ERC-EMBER project through an already seeded EmberFactory.
contract DeployProject is Script {
    uint256 private constant MAX_GOVERNANCE_MODE = uint256(type(MaintenancePool.GovernanceMode).max);
    uint256 private constant MIN_POOL_TIMELOCK_DELAY = 1 days;
    uint256 private constant MAX_POOL_TIMELOCK_DELAY = 30 days;

    struct ProjectConfig {
        EmberFactory factory;
        string name;
        string symbol;
        uint256 initialSupply;
        address dApp;
        bytes32 originalCommitment;
        string originalEncryptedCID;
        IEmber.SourceManifest manifest;
        address usdc;
        uint256 basePrice;
        uint256 slope;
        bool spawnMaintenancePool;
        uint256 poolModeRaw;
        address poolGovernor;
        uint256 poolTimelockDelay;
        bytes32 parentDeployment;
    }

    function run() external returns (address ember, address pool) {
        uint256 projectDeployerPrivateKey = vm.envUint("PROJECT_DEPLOYER_PRIVATE_KEY");
        ProjectConfig memory cfg = _loadConfig();

        _checkTopLevel(projectDeployerPrivateKey, cfg);
        _checkProjectMetadata(cfg);
        _checkPoolConfig(cfg);

        vm.startBroadcast(projectDeployerPrivateKey);
        (ember, pool) = _deploy(cfg);
        vm.stopBroadcast();
    }

    function _loadConfig() internal view returns (ProjectConfig memory cfg) {
        cfg.factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        cfg.name = vm.envString("PROJECT_NAME");
        cfg.symbol = vm.envString("PROJECT_SYMBOL");
        cfg.initialSupply = vm.envUint("INITIAL_SUPPLY");
        cfg.dApp = vm.envAddress("DAPP");
        cfg.originalCommitment = vm.envBytes32("ORIGINAL_COMMITMENT");
        cfg.originalEncryptedCID = vm.envString("ORIGINAL_ENCRYPTED_CID");
        cfg.manifest = IEmber.SourceManifest({
            archiveHash: vm.envBytes32("ARCHIVE_HASH"),
            fileTreeMerkleRoot: vm.envBytes32("FILE_TREE_MERKLE_ROOT"),
            lockfileHash: vm.envBytes32("LOCKFILE_HASH"),
            buildArtifactHash: vm.envBytes32("BUILD_ARTIFACT_HASH"),
            spdxLicense: vm.envString("SPDX_LICENSE"),
            manifestCID: vm.envString("MANIFEST_CID")
        });
        cfg.usdc = vm.envAddress("USDC");
        cfg.basePrice = vm.envUint("BASE_PRICE");
        cfg.slope = vm.envUint("SLOPE");
        cfg.spawnMaintenancePool = vm.envBool("SPAWN_MAINTENANCE_POOL");
        cfg.poolModeRaw = vm.envUint("POOL_MODE");
        cfg.poolGovernor = vm.envAddress("POOL_GOVERNOR");
        cfg.poolTimelockDelay = vm.envUint("POOL_TIMELOCK_DELAY");
        cfg.parentDeployment = vm.envBytes32("PARENT_DEPLOYMENT");
    }

    function _checkTopLevel(uint256 projectDeployerPrivateKey, ProjectConfig memory cfg) internal view {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");
        require(projectDeployerPrivateKey != 0, "PROJECT_DEPLOYER_PRIVATE_KEY is zero");
        require(vm.envAddress("PROJECT_DEVELOPER") == vm.addr(projectDeployerPrivateKey), "PROJECT_DEVELOPER mismatch");
        require(address(cfg.factory) != address(0), "EMBER_FACTORY is zero");
        require(address(cfg.factory).code.length != 0, "EMBER_FACTORY has no code");
        require(cfg.usdc != address(0), "USDC is zero");
        require(vm.envAddress("CANONICAL_USDC") != address(0), "CANONICAL_USDC is zero");
        require(cfg.usdc == vm.envAddress("CANONICAL_USDC"), "USDC not canonical");
        require(cfg.usdc.code.length != 0, "USDC has no code");
        require(IERC20Token(cfg.usdc).decimals() == 6, "USDC decimals");
    }

    function _checkProjectMetadata(ProjectConfig memory cfg) internal view {
        require(bytes(cfg.name).length != 0, "PROJECT_NAME is empty");
        require(bytes(cfg.symbol).length != 0, "PROJECT_SYMBOL is empty");
        require(cfg.initialSupply > 0, "INITIAL_SUPPLY is zero");
        require(cfg.dApp != address(0), "DAPP is zero");
        require(cfg.originalCommitment != bytes32(0), "ORIGINAL_COMMITMENT is zero");
        require(bytes(cfg.originalEncryptedCID).length != 0, "ORIGINAL_ENCRYPTED_CID is empty");
        require(cfg.basePrice > 0 || cfg.slope > 0, "no price");
        require(bytes(cfg.manifest.spdxLicense).length != 0, "SPDX_LICENSE is empty");
        require(cfg.factory.approvedLicense(keccak256(bytes(cfg.manifest.spdxLicense))), "license not approved");
        require(cfg.manifest.archiveHash != bytes32(0), "ARCHIVE_HASH is zero");
        require(cfg.manifest.fileTreeMerkleRoot != bytes32(0), "FILE_TREE_MERKLE_ROOT is zero");
        require(cfg.manifest.lockfileHash != bytes32(0), "LOCKFILE_HASH is zero");
        require(cfg.manifest.buildArtifactHash != bytes32(0), "BUILD_ARTIFACT_HASH is zero");
        require(bytes(cfg.manifest.manifestCID).length != 0, "MANIFEST_CID is empty");
    }

    function _checkPoolConfig(ProjectConfig memory cfg) internal pure {
        require(cfg.poolModeRaw <= MAX_GOVERNANCE_MODE, "POOL_MODE out of range");
        if (cfg.spawnMaintenancePool) {
            require(cfg.poolGovernor != address(0), "POOL_GOVERNOR is zero");
            require(
                cfg.poolTimelockDelay >= MIN_POOL_TIMELOCK_DELAY && cfg.poolTimelockDelay <= MAX_POOL_TIMELOCK_DELAY,
                "POOL_TIMELOCK_DELAY out of range"
            );
        } else {
            require(cfg.poolGovernor == address(0), "POOL_GOVERNOR unused");
        }
    }

    function _deploy(ProjectConfig memory cfg) internal returns (address ember, address pool) {
        return cfg.factory
            .deploy(
                cfg.name,
                cfg.symbol,
                cfg.initialSupply,
                cfg.dApp,
                cfg.originalCommitment,
                cfg.originalEncryptedCID,
                cfg.manifest,
                cfg.usdc,
                cfg.basePrice,
                cfg.slope,
                cfg.spawnMaintenancePool,
                MaintenancePool.GovernanceMode(cfg.poolModeRaw),
                cfg.poolGovernor,
                cfg.poolTimelockDelay,
                cfg.parentDeployment
            );
    }
}
