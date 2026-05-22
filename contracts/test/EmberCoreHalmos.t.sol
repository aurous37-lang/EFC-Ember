// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberCore.sol";
import "../src/IEmber.sol";
import "./mocks/MockUSDC.sol";

/// @notice Small Halmos-oriented checks. Broader randomized coverage lives in
///         EmberCoreExtendedFuzz.t.sol and runs under Foundry fuzzing.
contract EmberCoreHalmosTest is Test {
    MockUSDC usdc;
    EmberCore ember;

    address developer = address(0x1001);
    address dapp = address(0x1002);
    address buyer = address(0x1003);
    address feeRecipient = address(0x1004);
    address treasury = address(0x1005);
    address commission = address(0x1006);

    uint256 constant SUPPLY = 100;
    uint256 constant BASE_PRICE = 10_000;
    string constant KEY0 = "genesis-decryption-key";

    function setUp() public {
        usdc = new MockUSDC();
        ember = new EmberCore(
            "Halmos Ember",
            "HEMB",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            IEmber.SourceManifest({
                archiveHash: keccak256("archive"),
                fileTreeMerkleRoot: keccak256("tree"),
                lockfileHash: keccak256("lock"),
                buildArtifactHash: keccak256("build"),
                spdxLicense: "MIT",
                manifestCID: "ipfs://manifest"
            }),
            address(usdc),
            BASE_PRICE,
            0,
            feeRecipient,
            130,
            treasury,
            commission
        );
    }

    function _buy(uint256 amount) internal {
        uint256 cost = ember.quote(amount);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(ember), cost);
        ember.buy(amount, cost);
        vm.stopPrank();
    }

    function _keys() internal pure returns (string[] memory k) {
        k = new string[](1);
        k[0] = KEY0;
    }

    function check_feeAccountingOnBuy() public {
        uint256 amount = 25;
        uint256 cost = ember.quote(amount);
        uint256 fee = (cost * ember.feeBps()) / 10_000;

        _buy(amount);

        assertEq(ember.totalFeesPaid(), fee);
        assertEq(ember.totalRaised(), cost - fee);
        assertEq(usdc.balanceOf(feeRecipient), fee);
        assertEq(ember.balanceOf(buyer), amount);
    }

    function check_quorumRedemptionDoesNotOverpay() public {
        _buy(SUPPLY);

        vm.prank(buyer);
        ember.approve(dapp, 80);
        vm.prank(dapp);
        ember.useApp(buyer, 80);
        vm.warp(block.timestamp + ember.RELEASE_TIMEOUT() + 1);
        ember.forceEmberPhase();
        ember.release(_keys());

        vm.prank(developer);
        ember.withdrawDev();
        vm.prank(buyer);
        ember.redeem(20);

        uint256 paidOut = usdc.balanceOf(developer) + usdc.balanceOf(buyer) + usdc.balanceOf(feeRecipient);
        assertLe(paidOut, ember.quote(SUPPLY));
        assertLe(ember.redemptionPaid(), ember.redemptionPoolTotal());
    }

    function check_zeroAddressTransferRejected() public {
        _buy(1);
        vm.prank(buyer);
        (bool ok,) = address(ember).call(abi.encodeWithSelector(ember.transfer.selector, address(0), 1));
        assertFalse(ok);
    }
}
