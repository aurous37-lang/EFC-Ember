// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberCore.sol";
import "../src/IEmber.sol";
import "../src/IEmberRecovery.sol";
import "../src/IERC165.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/ReentrantToken.sol";

/// @notice Invariant suite for the v0.3 redemption / freeze / slash mechanics.
/// @dev    Flat bonding curve (slope = 0), no fee, so totalRaised = SUPPLY * BASE_PRICE = 1e10.
contract EmberCoreTest is Test {
    EmberCore ember;
    MockUSDC usdc;

    address developer = makeAddr("developer");
    address dapp = makeAddr("dapp");
    address buyer = makeAddr("buyer");
    address treasury = makeAddr("treasury");
    address commission = makeAddr("commission");

    uint256 constant SUPPLY = 1_000_000;
    uint256 constant BASE_PRICE = 10_000; // 0.01 USDC (6 decimals)
    uint256 constant RAISED = SUPPLY * BASE_PRICE; // 1e10 base units = $10,000
    string constant KEY0 = "genesis-decryption-key";

    function setUp() public {
        usdc = new MockUSDC();
        IEmber.SourceManifest memory m = IEmber.SourceManifest({
            archiveHash: keccak256("archive"),
            fileTreeMerkleRoot: keccak256("tree"),
            lockfileHash: keccak256("lock"),
            buildArtifactHash: keccak256("build"),
            spdxLicense: "MIT",
            manifestCID: "ipfs://manifest"
        });
        ember = new EmberCore(
            "Ember Test",
            "EMBR",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            m,
            address(usdc),
            BASE_PRICE,
            0, // slope = 0
            address(0), // no fee recipient
            0, // feeBps = 0 (direct deploy)
            address(0), // recovery disabled for direct deploy
            address(0)
        );
    }

    // ---------- helpers ----------
    function _buyAll() internal {
        uint256 cost = ember.quote(SUPPLY);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(ember), cost);
        ember.buy(SUPPLY);
        vm.stopPrank();
    }

    function _burn(address user, uint256 amount) internal {
        vm.prank(dapp);
        ember.useApp(user, amount);
    }

    function _toQuorum() internal {
        _buyAll();
        _burn(buyer, 800_000); // 80% burned
        vm.warp(block.timestamp + ember.RELEASE_TIMEOUT() + 1);
        ember.forceEmberPhase();
    }

    function _keys() internal pure returns (string[] memory k) {
        k = new string[](1);
        k[0] = KEY0;
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

    function _recoverableEmber(uint256 supply, uint256 basePrice) internal returns (EmberCore recoverable) {
        recoverable = new EmberCore(
            "Recoverable",
            "RCV",
            supply,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            _manifest(),
            address(usdc),
            basePrice,
            0,
            address(0),
            0,
            treasury,
            commission
        );
    }

    function test_ConstructorRejectsZeroPrice() public {
        IEmber.SourceManifest memory m = IEmber.SourceManifest({
            archiveHash: keccak256("archive"),
            fileTreeMerkleRoot: keccak256("tree"),
            lockfileHash: keccak256("lock"),
            buildArtifactHash: keccak256("build"),
            spdxLicense: "MIT",
            manifestCID: "ipfs://manifest"
        });

        vm.expectRevert(bytes("no price"));
        new EmberCore(
            "Zero Price",
            "ZERO",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            m,
            address(usdc),
            0,
            0,
            address(0),
            0,
            address(0),
            address(0)
        );
    }

    function test_ConstructorRejectsNonContractUsdc() public {
        IEmber.SourceManifest memory m = _manifest();
        vm.expectRevert(bytes("USDC not contract"));
        new EmberCore(
            "No Code USDC",
            "NCU",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            m,
            address(0xBEEF), // non-zero EOA, no code
            BASE_PRICE,
            0,
            address(0),
            0,
            address(0),
            address(0)
        );
    }

    function test_BuySlippageGuardRejectsHighCost() public {
        uint256 amount = 10;
        uint256 cost = ember.quote(amount);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(ember), cost);
        vm.expectRevert(bytes("slippage"));
        ember.buy(amount, cost - 1); // max below curve cost
        vm.stopPrank();
        assertEq(ember.balanceOf(buyer), 0, "no tokens minted on revert");
    }

    function test_BuySlippageGuardAllowsWithinMax() public {
        uint256 amount = 10;
        uint256 cost = ember.quote(amount);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(ember), cost);
        ember.buy(amount, cost); // exactly at max succeeds
        vm.stopPrank();
        assertEq(ember.balanceOf(buyer), amount, "tokens delivered");
        assertEq(ember.tokensSold(), amount, "sale recorded");
    }

    // A sloped curve: a front-runner who moves the price makes the victim's fixed
    // max-cost revert instead of overpaying.
    function test_BuySlippageGuardProtectsAgainstSandwich() public {
        EmberCore sloped = new EmberCore(
            "Sloped",
            "SLP",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            _manifest(),
            address(usdc),
            BASE_PRICE,
            1, // slope > 0 => price impact
            address(0),
            0,
            address(0),
            address(0)
        );

        uint256 victimMax = sloped.quote(100); // quote at current state

        // front-runner buys first, pushing tokensSold (and the curve) up
        address attacker = makeAddr("attacker");
        uint256 attackCost = sloped.quote(1_000);
        usdc.mint(attacker, attackCost);
        vm.startPrank(attacker);
        usdc.approve(address(sloped), attackCost);
        sloped.buy(1_000);
        vm.stopPrank();

        // victim's cost for the same size is now higher than their accepted max
        assertGt(sloped.quote(100), victimMax, "price moved up");
        usdc.mint(buyer, victimMax * 2);
        vm.startPrank(buyer);
        usdc.approve(address(sloped), victimMax * 2);
        vm.expectRevert(bytes("slippage"));
        sloped.buy(100, victimMax);
        vm.stopPrank();
    }

    // 1. Full burn release: no redemption pool forms.
    function test_FullBurn_NoRedemptionPool() public {
        _buyAll();
        _burn(buyer, SUPPLY); // last burn auto-opens Ember Phase
        assertGt(ember.releaseDeadline(), 0, "ember phase opened");
        assertEq(ember.redemptionPoolTotal(), 0, "no pool");
        assertEq(ember.redemptionSupplyTotal(), 0, "no outstanding supply");

        vm.expectRevert(bytes("no redemption pool"));
        ember.redeem(1);

        ember.release(_keys());
        assertTrue(ember.released());
        assertTrue(ember.terminated());
        // dev earns the full raise once released (100% progress).
        assertEq(ember.devClaimable(), RAISED);
    }

    // 2. 80% quorum trigger produces the correct redemption snapshot.
    function test_QuorumTrigger_RedemptionPool() public {
        _toQuorum();

        uint256 devEarned = (RAISED * 800_000) / SUPPLY; // 0.8 * raise
        assertEq(ember.totalRaised(), RAISED);
        assertEq(ember.triggerBurned(), 800_000);
        assertEq(ember.reservedAtTrigger(), (devEarned * 20) / 100);
        assertEq(ember.redemptionPoolTotal(), RAISED - devEarned); // 0.2 * raise
        assertEq(ember.redemptionSupplyTotal(), 200_000);
        // each outstanding token redeems its equal share of the raise.
        assertEq(ember.redemptionQuote(200_000), RAISED - devEarned);
        assertEq(ember.redemptionQuote(1), (RAISED - devEarned) / 200_000);
    }

    // 3. useApp() and updateSource() are frozen once the Ember Phase opens.
    function test_FreezeAfterEmberPhase() public {
        _toQuorum();

        vm.prank(dapp);
        vm.expectRevert(bytes("ember phase: burns frozen"));
        ember.useApp(buyer, 1);

        vm.prank(developer);
        vm.expectRevert(bytes("ember phase: frozen"));
        ember.updateSource(keccak256("k1"), "ipfs://x", keccak256("m1"));
    }

    // 4. Redemption never pays out more than the snapshotted pool.
    function test_RedeemBoundedByPool() public {
        _toQuorum();
        uint256 pool = ember.redemptionPoolTotal();
        assertEq(ember.balanceOf(buyer), 200_000);

        // cannot redeem more than held
        vm.prank(buyer);
        vm.expectRevert(bytes("bad amount"));
        ember.redeem(200_001);

        // redeeming the entire outstanding supply drains exactly the pool, never more
        vm.prank(buyer);
        ember.redeem(200_000);
        assertEq(ember.redemptionPaid(), pool, "paid == pool");
        assertLe(ember.redemptionPaid(), ember.redemptionPoolTotal(), "never exceeds pool");
        assertEq(usdc.balanceOf(buyer), pool, "holder received the pool");
    }

    function test_ERC20TransferRejectsZeroAddress() public {
        _buyAll();

        vm.prank(buyer);
        vm.expectRevert(bytes("zero address"));
        bool ok = ember.transfer(address(0), 1);
        assertFalse(ok);
    }

    function test_ReentrantPaymentTokenCannotReenterBuy() public {
        ReentrantToken token = new ReentrantToken();
        EmberCore guarded = new EmberCore(
            "Guarded",
            "GRD",
            SUPPLY,
            developer,
            dapp,
            keccak256(bytes(KEY0)),
            "ipfs://encrypted",
            _manifest(),
            address(token),
            BASE_PRICE,
            0,
            address(0),
            0,
            address(0),
            address(0)
        );

        uint256 cost = guarded.quote(10);
        token.mint(buyer, cost);
        token.setReentry(address(guarded), abi.encodeWithSignature("buy(uint256)", 1));

        vm.startPrank(buyer);
        token.approve(address(guarded), cost);
        guarded.buy(10);
        vm.stopPrank();

        assertTrue(token.attemptedReentry(), "reentry attempted");
        assertFalse(token.reentrySucceeded(), "guard blocked reentry");
        assertEq(guarded.balanceOf(buyer), 10, "outer buy still succeeds");
    }

    // 5. Slash burns ONLY the reserved tranche; redemption pool + dev unreserved survive.
    function test_SlashBurnsOnlyReserved() public {
        _toQuorum();
        uint256 reserved = ember.reservedAtTrigger();
        uint256 balBefore = usdc.balanceOf(address(ember));

        vm.warp(block.timestamp + ember.EMBER_WINDOW() + 1); // past deadline
        ember.slashReserve();

        assertTrue(ember.slashed());
        assertEq(usdc.balanceOf(address(0xdEaD)), reserved, "only reserved burned");
        assertEq(usdc.balanceOf(address(ember)), balBefore - reserved, "rest untouched");

        // redemption pool still fully claimable
        vm.prank(buyer);
        ember.redeem(200_000);
        assertEq(usdc.balanceOf(buyer), ember.redemptionPoolTotal());

        // dev still draws the unreserved portion (reserved stays locked since not released)
        uint256 devClaim = ember.devClaimable();
        assertEq(devClaim, (RAISED * 800_000 * 80) / (SUPPLY * 100)); // 0.8 * 0.8 * raise
        vm.prank(developer);
        ember.withdrawDev();
        assertEq(usdc.balanceOf(developer), devClaim);
    }

    // 6a. Late release works as long as nobody has slashed yet (grace until slashed).
    function test_LateRelease_BeforeSlash() public {
        _toQuorum();
        vm.warp(block.timestamp + ember.EMBER_WINDOW() + 5); // PAST the deadline
        ember.release(_keys()); // still accepted
        assertTrue(ember.released());
        assertFalse(ember.slashed());
    }

    // 6b. Once slashed, release() is rejected.
    function test_Release_FailsAfterSlash() public {
        _toQuorum();
        vm.warp(block.timestamp + ember.EMBER_WINDOW() + 1);
        ember.slashReserve();
        vm.expectRevert(bytes("terminal"));
        ember.release(_keys());
    }

    // Extra: happy-path quorum release unlocks reserved, redemption pool stays whole.
    function test_QuorumRelease_UnlocksReserved_PoolIntact() public {
        _toQuorum();
        ember.release(_keys());
        assertEq(ember.devClaimable(), RAISED * 800_000 / SUPPLY); // full 0.8 * raise
        vm.prank(developer);
        ember.withdrawDev();
        vm.prank(buyer);
        ember.redeem(200_000);
        assertEq(usdc.balanceOf(buyer), ember.redemptionPoolTotal());
        // contract fully settled (dust aside).
        assertLe(usdc.balanceOf(address(ember)), 1);
    }

    function test_AbandonedRecovery_DisabledForDirectDeploy() public {
        _buyAll();
        vm.warp(block.timestamp + ember.ABANDONMENT_TIMEOUT() + 1);
        vm.expectRevert(bytes("recovery disabled"));
        ember.recoverAbandonedCapital();
    }

    function test_AbandonedRecovery_RoutesIdleCapital() public {
        EmberCore recoverable = _recoverableEmber(SUPPLY, BASE_PRICE);

        uint256 cost = recoverable.quote(SUPPLY);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(recoverable), cost);
        recoverable.buy(SUPPLY);
        vm.stopPrank();

        vm.warp(block.timestamp + recoverable.ABANDONMENT_TIMEOUT() + 1);
        recoverable.recoverAbandonedCapital();

        assertTrue(recoverable.abandonedRecovered());
        assertTrue(recoverable.terminated());
        assertEq(usdc.balanceOf(treasury), (RAISED * 90) / 100);
        assertEq(usdc.balanceOf(commission), (RAISED * 10) / 100);

        vm.prank(dapp);
        vm.expectRevert(bytes("abandoned"));
        recoverable.useApp(buyer, 1);
    }

    function test_AbandonedRecovery_PreservesRedemptionReserve() public {
        EmberCore recoverable = _recoverableEmber(SUPPLY, BASE_PRICE);

        uint256 cost = recoverable.quote(SUPPLY);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(recoverable), cost);
        recoverable.buy(SUPPLY);
        vm.stopPrank();

        vm.prank(dapp);
        recoverable.useApp(buyer, 800_000);
        vm.warp(block.timestamp + recoverable.RELEASE_TIMEOUT() + 1);
        recoverable.forceEmberPhase();

        uint256 redemptionReserve = recoverable.redemptionReserveRemaining();
        assertEq(redemptionReserve, recoverable.redemptionPoolTotal());

        vm.warp(block.timestamp + recoverable.ABANDONMENT_TIMEOUT() + 1);
        recoverable.recoverAbandonedCapital();

        uint256 recoverableCapital = RAISED - redemptionReserve;
        assertEq(usdc.balanceOf(treasury), (recoverableCapital * 90) / 100);
        assertEq(usdc.balanceOf(commission), (recoverableCapital * 10) / 100);
        assertEq(usdc.balanceOf(address(recoverable)), redemptionReserve);

        vm.prank(buyer);
        recoverable.redeem(200_000);
        assertEq(usdc.balanceOf(buyer), redemptionReserve);
    }

    function testFuzz_QuorumReleaseSettlementDoesNotOverpay(uint96 rawSupply, uint96 rawPrice) public {
        uint256 supply = bound(uint256(rawSupply), 5, 1_000_000);
        uint256 basePrice = bound(uint256(rawPrice), 1, 1_000_000);
        uint256 burnAmount = (supply * 8_000 + 9_999) / 10_000;
        vm.assume(burnAmount < supply);

        EmberCore fuzzEmber = _recoverableEmber(supply, basePrice);
        uint256 cost = fuzzEmber.quote(supply);
        usdc.mint(buyer, cost);
        vm.startPrank(buyer);
        usdc.approve(address(fuzzEmber), cost);
        fuzzEmber.buy(supply);
        vm.stopPrank();

        vm.prank(dapp);
        fuzzEmber.useApp(buyer, burnAmount);
        vm.warp(block.timestamp + fuzzEmber.RELEASE_TIMEOUT() + 1);
        fuzzEmber.forceEmberPhase();
        fuzzEmber.release(_keys());

        vm.prank(developer);
        fuzzEmber.withdrawDev();
        vm.prank(buyer);
        fuzzEmber.redeem(supply - burnAmount);

        uint256 paidOut = usdc.balanceOf(developer) + usdc.balanceOf(buyer);
        assertLe(paidOut, cost, "settlement overpaid");
    }

    // ERC-165: advertises the neutral interface, the recovery extension, and 165 itself.
    function test_SupportsInterface() public view {
        assertTrue(ember.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(ember.supportsInterface(type(IEmber).interfaceId), "IEmber");
        assertTrue(ember.supportsInterface(type(IEmberRecovery).interfaceId), "IEmberRecovery");
        assertFalse(ember.supportsInterface(0xffffffff), "0xffffffff must be false per ERC-165");
        assertFalse(ember.supportsInterface(0xdeadbeef), "random id false");
    }
}
