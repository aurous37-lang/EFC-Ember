// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/EmberCore.sol";
import "../src/EmberFactory.sol";
import "../src/IERC20Token.sol";
import "../src/IEmber.sol";
import "../src/MaintenancePool.sol";

/// @notice Read-only launch check for one project deployed through EmberFactory.
contract CheckProjectDeployment is Script {
    uint256 private constant MAX_GOVERNANCE_MODE = uint256(type(MaintenancePool.GovernanceMode).max);
    uint256 private constant MIN_POOL_TIMELOCK_DELAY = 1 days;
    uint256 private constant MAX_POOL_TIMELOCK_DELAY = 30 days;

    function run() external view {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");

        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        EmberCore ember = EmberCore(vm.envAddress("EMBER_PROJECT"));

        _checkTopLevel(factory, ember);
        _checkCore(factory, ember);
        _checkManifest(factory, ember);
        _checkRegistry(factory, address(ember));
        _checkPool(address(ember));
    }

    function _checkTopLevel(EmberFactory factory, EmberCore ember) internal view {
        address usdc = vm.envAddress("USDC");
        address canonicalUsdc = vm.envAddress("CANONICAL_USDC");

        require(address(factory) != address(0), "EMBER_FACTORY is zero");
        require(address(factory).code.length != 0, "EMBER_FACTORY has no code");
        require(address(ember) != address(0), "EMBER_PROJECT is zero");
        require(address(ember).code.length != 0, "EMBER_PROJECT has no code");
        require(vm.envAddress("PROJECT_DEVELOPER") != address(0), "PROJECT_DEVELOPER is zero");
        require(usdc != address(0), "USDC is zero");
        require(canonicalUsdc != address(0), "CANONICAL_USDC is zero");
        require(usdc == canonicalUsdc, "USDC not canonical");
        require(usdc.code.length != 0, "USDC has no code");
        require(IERC20Token(usdc).decimals() == 6, "USDC decimals");
        require(vm.envUint("POOL_MODE") <= MAX_GOVERNANCE_MODE, "POOL_MODE out of range");
    }

    function _checkCore(EmberFactory factory, EmberCore ember) internal view {
        require(keccak256(bytes(ember.name())) == keccak256(bytes(vm.envString("PROJECT_NAME"))), "name mismatch");
        require(keccak256(bytes(ember.symbol())) == keccak256(bytes(vm.envString("PROJECT_SYMBOL"))), "symbol mismatch");
        require(ember.decimals() == 0, "decimals mismatch");
        require(ember.INITIAL_SUPPLY() == vm.envUint("INITIAL_SUPPLY"), "supply mismatch");
        require(ember.developer() == vm.envAddress("PROJECT_DEVELOPER"), "developer mismatch");
        require(ember.dApp() == vm.envAddress("DAPP"), "dApp mismatch");
        require(ember.originalCommitment() == vm.envBytes32("ORIGINAL_COMMITMENT"), "commitment mismatch");
        require(
            keccak256(bytes(ember.originalEncryptedCID())) == keccak256(bytes(vm.envString("ORIGINAL_ENCRYPTED_CID"))),
            "encrypted CID mismatch"
        );
        require(address(ember.USDC()) == vm.envAddress("USDC"), "USDC mismatch");
        require(ember.basePrice() == vm.envUint("BASE_PRICE"), "base price mismatch");
        require(ember.slope() == vm.envUint("SLOPE"), "slope mismatch");
        require(ember.feeRecipient() == factory.STANDARD_AUTHOR(), "fee recipient mismatch");
        require(ember.feeBps() == factory.FACTORY_FEE_BPS(), "fee bps mismatch");
        require(ember.recoveryTreasury() == factory.RECOVERY_TREASURY(), "recovery treasury mismatch");
        require(ember.recoveryCommissionRecipient() == factory.STANDARD_AUTHOR(), "recovery commission mismatch");
    }

    function _checkManifest(EmberFactory factory, EmberCore ember) internal view {
        IEmber.SourceManifest memory manifest = ember.manifest();

        require(factory.approvedLicense(keccak256(bytes(manifest.spdxLicense))), "license not approved");
        require(manifest.archiveHash == vm.envBytes32("ARCHIVE_HASH"), "archive hash mismatch");
        require(manifest.fileTreeMerkleRoot == vm.envBytes32("FILE_TREE_MERKLE_ROOT"), "tree root mismatch");
        require(manifest.lockfileHash == vm.envBytes32("LOCKFILE_HASH"), "lockfile hash mismatch");
        require(manifest.buildArtifactHash == vm.envBytes32("BUILD_ARTIFACT_HASH"), "artifact hash mismatch");
        require(
            keccak256(bytes(manifest.spdxLicense)) == keccak256(bytes(vm.envString("SPDX_LICENSE"))), "license mismatch"
        );
        require(
            keccak256(bytes(manifest.manifestCID)) == keccak256(bytes(vm.envString("MANIFEST_CID"))),
            "manifest CID mismatch"
        );
    }

    function _checkRegistry(EmberFactory factory, address ember) internal view {
        (address developer,, address maintenancePool, bytes32 parentDeployment, bool licenseVerified) =
            factory.info(ember);

        require(developer == vm.envAddress("PROJECT_DEVELOPER"), "registry developer mismatch");
        require(maintenancePool == vm.envAddress("EMBER_PROJECT_MAINTENANCE_POOL"), "registry pool mismatch");
        require(parentDeployment == vm.envBytes32("PARENT_DEPLOYMENT"), "parent mismatch");
        require(licenseVerified, "license not verified");
    }

    function _checkPool(address ember) internal view {
        address expectedPool = vm.envAddress("EMBER_PROJECT_MAINTENANCE_POOL");

        if (vm.envBool("SPAWN_MAINTENANCE_POOL")) {
            require(expectedPool != address(0), "expected pool is zero");
            require(expectedPool.code.length != 0, "pool has no code");
            require(
                vm.envUint("POOL_TIMELOCK_DELAY") >= MIN_POOL_TIMELOCK_DELAY
                    && vm.envUint("POOL_TIMELOCK_DELAY") <= MAX_POOL_TIMELOCK_DELAY,
                "POOL_TIMELOCK_DELAY out of range"
            );

            MaintenancePool pool = MaintenancePool(expectedPool);
            require(pool.emberToken() == ember, "pool ember mismatch");
            require(address(pool.USDC()) == vm.envAddress("USDC"), "pool USDC mismatch");
            require(uint256(pool.governanceMode()) == vm.envUint("POOL_MODE"), "pool mode mismatch");
            require(pool.governor() == vm.envAddress("POOL_GOVERNOR"), "pool governor mismatch");
            require(pool.timelockDelay() == vm.envUint("POOL_TIMELOCK_DELAY"), "pool delay mismatch");
        } else {
            require(expectedPool == address(0), "unexpected pool");
        }
    }
}
