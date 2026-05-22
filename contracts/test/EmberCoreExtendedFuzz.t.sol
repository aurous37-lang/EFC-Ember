// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberCore.sol";
import "../src/IEmber.sol";
import "./mocks/MockUSDC.sol";

/// @notice Extra launch-readiness fuzz coverage for pricing, fees, settlement,
///         transfers, and multi-holder redemption accounting.
contract EmberCoreExtendedFuzzTest is Test {
    MockUSDC usdc;

    address developer = makeAddr("developer");
    address dapp = makeAddr("dapp");
    address feeRecipient = makeAddr("feeRecipient");
    address treasury = makeAddr("treasury");
    address commission = makeAddr("commission");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant KEY0 = "genesis-decryption-key";

    function setUp() public {
        usdc = new MockUSDC();
    }

    function _manifest() internal pure returns (IEmber.SourceManifest memory m) {
        m = IEmber.SourceManifest({
            archiveHash: keccak256("archive"),
            fileTreeMerkleRoot: keccak256("tree"),
            lockfileHash: keccak256("lock"),
            buildArtifactHash: keccak256("build"),
            spdxLicense: "MIT",
            manifestCID: "ipfs://manifest"
        });
    }

    function _deploy(uint256 supply, uint256 basePrice, uint256 slope, uint256 feeBps)
        internal
        returns (EmberCore ember)
    {
        ember = new EmberCore(
            "Ember Fuzz",
            "EFZ",
            supply,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            _manifest(),
            address(usdc),
            basePrice,
            slope,
            feeRecipient,
            feeBps,
            treasury,
            commission
        );
    }

    function _buy(EmberCore ember, address buyer, uint256 amount) internal returns (uint256 cost) {
        cost = ember.quote(amount);
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

    function testFuzz_BondingCurveQuoteMonotonic(uint96 rawSupply, uint96 rawBase, uint96 rawSlope, uint96 rawBuy)
        public
    {
        vm.assume(rawSupply >= 3 && rawSupply <= 1_000_000);
        vm.assume(rawBase >= 1 && rawBase <= 1_000_000);
        vm.assume(rawSlope <= 1_000);
        vm.assume(rawBuy >= 1 && rawBuy < rawSupply);
        uint256 supply = uint256(rawSupply);
        uint256 basePrice = uint256(rawBase);
        uint256 slope = uint256(rawSlope);
        uint256 firstBuy = uint256(rawBuy);

        EmberCore ember = _deploy(supply, basePrice, slope, 0);
        uint256 beforeQuote = ember.quote(1);
        _buy(ember, alice, firstBuy);
        uint256 afterQuote = ember.quote(1);

        assertGe(afterQuote, beforeQuote, "quote decreased after sale");
    }

    function testFuzz_FeeAccountingConservesSaleValue(uint96 rawSupply, uint96 rawBase, uint16 rawFeeBps, uint96 rawBuy)
        public
    {
        vm.assume(rawSupply >= 2 && rawSupply <= 1_000_000);
        vm.assume(rawBase >= 1 && rawBase <= 1_000_000);
        vm.assume(rawFeeBps >= 1 && rawFeeBps <= 500);
        vm.assume(rawBuy >= 1 && rawBuy <= rawSupply);
        uint256 supply = uint256(rawSupply);
        uint256 basePrice = uint256(rawBase);
        uint256 feeBps = uint256(rawFeeBps);
        uint256 buyAmount = uint256(rawBuy);

        EmberCore ember = _deploy(supply, basePrice, 0, feeBps);
        uint256 cost = _buy(ember, alice, buyAmount);
        uint256 expectedFee = (cost * feeBps) / 10_000;

        assertEq(ember.tokensSold(), buyAmount, "tokens sold");
        assertEq(ember.totalFeesPaid(), expectedFee, "fee paid");
        assertEq(ember.totalRaised(), cost - expectedFee, "project raised");
        assertEq(usdc.balanceOf(feeRecipient), expectedFee, "recipient fee");
        assertEq(usdc.balanceOf(address(ember)), cost - expectedFee, "contract balance");
    }

    function testFuzz_TransferAndAllowancePreserveTokenSupply(uint96 rawSupply, uint96 rawBuy, uint96 rawTransfer)
        public
    {
        vm.assume(rawSupply >= 2 && rawSupply <= 1_000_000);
        vm.assume(rawBuy >= 1 && rawBuy <= rawSupply);
        vm.assume(rawTransfer >= 1 && rawTransfer <= rawBuy);
        uint256 supply = uint256(rawSupply);
        uint256 buyAmount = uint256(rawBuy);
        uint256 transferAmount = uint256(rawTransfer);

        EmberCore ember = _deploy(supply, 10_000, 0, 0);
        _buy(ember, alice, buyAmount);

        vm.prank(alice);
        ember.approve(bob, transferAmount);
        vm.prank(bob);
        bool ok = ember.transferFrom(alice, bob, transferAmount);
        assertTrue(ok, "transferFrom failed");

        assertEq(ember.totalSupply(), supply, "supply changed");
        assertEq(
            ember.balanceOf(alice) + ember.balanceOf(bob) + ember.balanceOf(address(ember)), supply, "bad balances"
        );
        assertEq(ember.allowance(alice, bob), 0, "allowance not spent");
    }

    function testFuzz_MultiHolderQuorumSettlementDoesNotOverpay(uint96 rawSupply, uint96 rawPrice) public {
        vm.assume(rawSupply >= 10 && rawSupply <= 1_000_000);
        vm.assume(rawPrice >= 1 && rawPrice <= 1_000_000);
        uint256 supply = uint256(rawSupply);
        uint256 basePrice = uint256(rawPrice);
        uint256 burnAmount = (supply * 8_000 + 9_999) / 10_000;
        vm.assume(burnAmount < supply);
        uint256 remainder = supply - burnAmount;

        EmberCore ember = _deploy(supply, basePrice, 0, 0);
        uint256 aliceCost = _buy(ember, alice, burnAmount);
        uint256 bobCost = _buy(ember, bob, remainder);

        vm.prank(alice);
        ember.approve(dapp, burnAmount);
        vm.prank(dapp);
        ember.useApp(alice, burnAmount);
        vm.warp(block.timestamp + ember.RELEASE_TIMEOUT() + 1);
        ember.forceEmberPhase();
        ember.release(_keys());

        vm.prank(developer);
        ember.withdrawDev();
        vm.prank(bob);
        ember.redeem(remainder);

        uint256 paidOut = usdc.balanceOf(developer) + usdc.balanceOf(bob);
        assertLe(paidOut, aliceCost + bobCost, "settlement overpaid");
        assertLe(usdc.balanceOf(address(ember)), supply, "unexpected dust");
    }
}
