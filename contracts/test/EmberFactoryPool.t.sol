// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberFactory.sol";
import "../src/EmberCore.sol";
import "../src/MaintenancePool.sol";
import "../src/MaintenancePoolFactory.sol";
import "../src/IEmber.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockToken18.sol";

/// @notice Smoke tests for the production distribution surface (Layer 3 + 4):
///         license policy, deployment wiring, and pool governance guards.
contract EmberFactoryPoolTest is Test {
    EmberFactory factory;
    MaintenancePoolFactory poolFactory;
    MockUSDC usdc;

    uint256 constant POOL_DELAY = 7 days;

    address dev = makeAddr("dev");
    address dapp = makeAddr("dapp");
    address governor = makeAddr("governor");
    address stranger = makeAddr("stranger");
    address standardAuthor = makeAddr("standardAuthor");
    address recoveryTreasury = makeAddr("recoveryTreasury");
    address emberToken = makeAddr("emberToken");

    function setUp() public {
        poolFactory = new MaintenancePoolFactory();
        factory = new EmberFactory(standardAuthor, recoveryTreasury, address(poolFactory)); // test contract is owner
        poolFactory.setEmberFactory(address(factory));
        usdc = new MockUSDC();
        emberToken = address(this);
    }

    function _manifest(string memory lic) internal pure returns (IEmber.SourceManifest memory m) {
        m = IEmber.SourceManifest({
            archiveHash: keccak256("a"),
            fileTreeMerkleRoot: keccak256("t"),
            lockfileHash: keccak256("l"),
            buildArtifactHash: keccak256("b"),
            spdxLicense: lic,
            manifestCID: "ipfs://m"
        });
    }

    function _deploy(string memory lic, bool spawnPool, address poolGov)
        internal
        returns (address ember, address pool)
    {
        vm.prank(dev);
        (ember, pool) = factory.deploy(
            "T",
            "T",
            1_000_000,
            dapp,
            keccak256("key0"),
            "ipfs://enc",
            _manifest(lic),
            address(usdc),
            10_000,
            0,
            spawnPool,
            MaintenancePool.GovernanceMode.Multisig,
            poolGov,
            POOL_DELAY,
            bytes32(0)
        );
    }

    function test_FactoryRejectsZeroProductionRecipients() public {
        vm.expectRevert(bytes("no standard author"));
        new EmberFactory(address(0), recoveryTreasury, address(poolFactory));

        vm.expectRevert(bytes("no recovery treasury"));
        new EmberFactory(standardAuthor, address(0), address(poolFactory));

        vm.expectRevert(bytes("no pool factory"));
        new EmberFactory(standardAuthor, recoveryTreasury, address(0));

        vm.expectRevert(bytes("pool factory not contract"));
        new EmberFactory(standardAuthor, recoveryTreasury, makeAddr("notPoolFactory"));
    }

    function test_PoolFactoryOnlyConfiguredFactoryCanCreate() public {
        MaintenancePoolFactory restricted = new MaintenancePoolFactory();
        vm.expectRevert(bytes("not factory"));
        restricted.create(address(this), governor, address(usdc), MaintenancePool.GovernanceMode.Steward, POOL_DELAY);
    }

    // factory owner can approve a license
    function test_OwnerApprovesLicense() public {
        assertFalse(factory.approvedLicense(keccak256(bytes("MIT"))));
        factory.setLicenseApproval("MIT", true);
        assertTrue(factory.approvedLicense(keccak256(bytes("MIT"))));
    }

    // non-owner cannot approve
    function test_NonOwnerCannotApprove() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("not owner"));
        factory.setLicenseApproval("MIT", true);
    }

    function test_OwnerCanTransferOwnershipWithTwoStepHandoff() public {
        factory.transferOwnership(stranger);
        assertEq(factory.owner(), address(this));
        assertEq(factory.pendingOwner(), stranger);

        vm.expectRevert(bytes("not owner"));
        vm.prank(stranger);
        factory.setLicenseApproval("MIT", true);

        vm.prank(dev);
        vm.expectRevert(bytes("not pending owner"));
        factory.acceptOwnership();

        vm.prank(stranger);
        factory.acceptOwnership();
        assertEq(factory.owner(), stranger);
        assertEq(factory.pendingOwner(), address(0));

        vm.prank(stranger);
        factory.setLicenseApproval("MIT", true);
        assertTrue(factory.approvedLicense(keccak256(bytes("MIT"))));
    }

    function test_OwnerCannotTransferOwnershipToZero() public {
        vm.expectRevert(bytes("no owner"));
        factory.transferOwnership(address(0));
    }

    // deploy reverts on a zero dApp (explicit factory validation)
    function test_DeployRejectsZeroDApp() public {
        factory.setLicenseApproval("MIT", true);
        vm.prank(dev);
        vm.expectRevert(bytes("no dApp"));
        factory.deploy(
            "T",
            "T",
            1_000_000,
            address(0), // dApp
            keccak256("key0"),
            "ipfs://enc",
            _manifest("MIT"),
            address(usdc),
            10_000,
            0,
            false,
            MaintenancePool.GovernanceMode.Multisig,
            address(0),
            POOL_DELAY,
            bytes32(0)
        );
    }

    // deploy reverts on a zero usdc (explicit, ahead of the decimals() probe)
    function test_DeployRejectsZeroUsdc() public {
        factory.setLicenseApproval("MIT", true);
        vm.prank(dev);
        vm.expectRevert(bytes("no USDC"));
        factory.deploy(
            "T",
            "T",
            1_000_000,
            dapp,
            keccak256("key0"),
            "ipfs://enc",
            _manifest("MIT"),
            address(0), // usdc
            10_000,
            0,
            false,
            MaintenancePool.GovernanceMode.Multisig,
            address(0),
            POOL_DELAY,
            bytes32(0)
        );
    }

    // zero poolGovernor is allowed when no pool is spawned
    function test_DeployAllowsZeroPoolGovernorWhenNoPool() public {
        factory.setLicenseApproval("MIT", true);
        (address ember, address pool) = _deploy("MIT", false, address(0));
        assertTrue(ember != address(0), "ember deployed");
        assertEq(pool, address(0), "no pool spawned");
    }

    // zero poolGovernor is rejected when a pool is spawned
    function test_DeployRejectsZeroPoolGovernorWhenSpawning() public {
        factory.setLicenseApproval("MIT", true);
        vm.prank(dev);
        vm.expectRevert(bytes("no governor"));
        factory.deploy(
            "T",
            "T",
            1_000_000,
            dapp,
            keccak256("key0"),
            "ipfs://enc",
            _manifest("MIT"),
            address(usdc),
            10_000,
            0,
            true, // spawnMaintenancePool
            MaintenancePool.GovernanceMode.Multisig,
            address(0), // poolGovernor
            POOL_DELAY,
            bytes32(0)
        );
    }

    // deploy reverts for an unapproved license
    function test_DeployRevertsUnapprovedLicense() public {
        vm.expectRevert(bytes("license not OSI-approved"));
        _deploy("Custom-1.0", false, address(0));
    }

    // deploy reverts when the sale token is not 6-decimal USDC (factory policy)
    function test_DeployRejectsNon6DecimalToken() public {
        factory.setLicenseApproval("MIT", true);
        MockToken18 bad = new MockToken18();
        vm.prank(dev);
        vm.expectRevert(bytes("USDC decimals"));
        factory.deploy(
            "T",
            "T",
            1_000_000,
            dapp,
            keccak256("key0"),
            "ipfs://enc",
            _manifest("MIT"),
            address(bad),
            10_000,
            0,
            false,
            MaintenancePool.GovernanceMode.Multisig,
            address(0),
            POOL_DELAY,
            bytes32(0)
        );
    }

    // deploy succeeds for an approved license; licenseVerified == true; fee wired in
    function test_DeploySucceedsApprovedLicense() public {
        factory.setLicenseApproval("MIT", true);
        (address ember, address pool) = _deploy("MIT", false, address(0));

        assertTrue(ember != address(0), "ember deployed");
        assertEq(pool, address(0), "no pool requested");

        (address d,, address mp,, bool verified) = factory.info(ember);
        assertEq(d, dev, "developer recorded");
        assertEq(mp, address(0), "no pool recorded");
        assertTrue(verified, "licenseVerified == true");
        assertEq(factory.deploymentCount(), 1);

        assertEq(EmberCore(ember).feeBps(), factory.FACTORY_FEE_BPS(), "1.3% fee wired");
        assertEq(EmberCore(ember).developer(), dev, "dev is msg.sender");
        assertEq(EmberCore(ember).recoveryTreasury(), recoveryTreasury, "treasury wired");
        assertEq(EmberCore(ember).recoveryCommissionRecipient(), standardAuthor, "commission wired");
    }

    // optional pool deploys with the declared GovernanceMode
    function test_DeployWithPool() public {
        factory.setLicenseApproval("MIT", true);
        (address ember, address pool) = _deploy("MIT", true, governor);

        assertTrue(pool != address(0), "pool spawned");
        MaintenancePool mp = MaintenancePool(pool);
        assertEq(uint8(mp.governanceMode()), uint8(MaintenancePool.GovernanceMode.Multisig), "declared mode");
        assertEq(mp.governor(), governor);
        assertEq(mp.emberToken(), ember);
        assertEq(mp.timelockDelay(), POOL_DELAY, "timelock delay wired");

        (,, address poolAddr,,) = factory.info(ember);
        assertEq(poolAddr, address(0), "pool registry omitted to keep deploy CEI");
    }

    // pool rejects a zero governor — directly and through the factory
    function test_PoolRejectsZeroGovernor_Direct() public {
        vm.expectRevert(bytes("no governor"));
        new MaintenancePool(emberToken, address(0), address(usdc), MaintenancePool.GovernanceMode.Steward, POOL_DELAY);
    }

    function test_PoolRejectsZeroGovernor_ViaFactory() public {
        factory.setLicenseApproval("MIT", true);
        vm.expectRevert(bytes("no governor"));
        _deploy("MIT", true, address(0));
    }

    // Pool governance behavior (claim/governor rotation/zero-value/timelock) is
    // covered in test/MaintenancePool.t.sol.
}
