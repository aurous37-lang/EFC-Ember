// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MaintenancePool.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/ReentrantToken.sol";

/// @notice Unit suite for MaintenancePool's timelocked proposal governance.
contract MaintenancePoolTest is Test {
    MaintenancePool pool;
    MockUSDC usdc;

    address governor = makeAddr("governor");
    address stranger = makeAddr("stranger");
    address dev = makeAddr("dev");
    address recipient = makeAddr("recipient");
    address emberToken = makeAddr("emberToken");

    uint256 constant DELAY = 7 days;
    uint256 constant FUND = 1_000_000; // 1 USDC at 6 decimals

    function setUp() public {
        usdc = new MockUSDC();
        pool = new MaintenancePool(emberToken, governor, address(usdc), MaintenancePool.GovernanceMode.Steward, DELAY);
        usdc.mint(address(pool), FUND);
    }

    // ---------- constructor ----------
    function test_ConstructorRejectsDelayBelowMin() public {
        vm.expectRevert(bytes("bad delay"));
        new MaintenancePool(emberToken, governor, address(usdc), MaintenancePool.GovernanceMode.Steward, 1 days - 1);
    }

    function test_ConstructorRejectsDelayAboveMax() public {
        vm.expectRevert(bytes("bad delay"));
        new MaintenancePool(emberToken, governor, address(usdc), MaintenancePool.GovernanceMode.Steward, 30 days + 1);
    }

    function test_ConstructorAcceptsBounds() public {
        MaintenancePool lo =
            new MaintenancePool(emberToken, governor, address(usdc), MaintenancePool.GovernanceMode.Steward, 1 days);
        MaintenancePool hi =
            new MaintenancePool(emberToken, governor, address(usdc), MaintenancePool.GovernanceMode.Steward, 30 days);
        assertEq(lo.timelockDelay(), 1 days);
        assertEq(hi.timelockDelay(), 30 days);
    }

    function test_ConstructorRejectsNonContractUsdc() public {
        vm.expectRevert(bytes("USDC not contract"));
        new MaintenancePool(emberToken, governor, address(0xBEEF), MaintenancePool.GovernanceMode.Steward, DELAY);
    }

    function test_ConstructorRejectsZeroParams() public {
        vm.expectRevert(bytes("no governor"));
        new MaintenancePool(emberToken, address(0), address(usdc), MaintenancePool.GovernanceMode.Steward, DELAY);

        vm.expectRevert(bytes("bad params"));
        new MaintenancePool(address(0), governor, address(usdc), MaintenancePool.GovernanceMode.Steward, DELAY);
    }

    // ---------- queue / execute happy path ----------
    function test_QueueDrawAndExecuteAfterDelay() public {
        vm.prank(governor);
        uint256 id = pool.queueDraw(100, dev, "maintenance");
        assertEq(id, 1, "first id is 1");

        // before eta: cannot execute
        vm.expectRevert(bytes("timelock"));
        pool.execute(id);

        vm.warp(block.timestamp + DELAY);
        // permissionless execution
        vm.prank(stranger);
        pool.execute(id);

        assertEq(usdc.balanceOf(dev), 100, "draw paid out");
        assertEq(usdc.balanceOf(address(pool)), FUND - 100, "pool debited");
        assertEq(pool.lastDrawTimestamp(), block.timestamp, "activity clock reset");
    }

    function test_DoubleExecuteReverts() public {
        vm.prank(governor);
        uint256 id = pool.queueDraw(100, dev, "m");
        vm.warp(block.timestamp + DELAY);
        pool.execute(id);
        vm.expectRevert(bytes("executed"));
        pool.execute(id);
    }

    function test_ExecuteUnknownProposalReverts() public {
        vm.expectRevert(bytes("unknown proposal"));
        pool.execute(0);
        vm.expectRevert(bytes("unknown proposal"));
        pool.execute(99);
    }

    function test_DrawInsufficientBalanceReverts() public {
        vm.prank(governor);
        uint256 id = pool.queueDraw(FUND + 1, dev, "too much");
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(bytes("insufficient"));
        pool.execute(id);
    }

    function test_QueueDrawZeroChecks() public {
        vm.startPrank(governor);
        vm.expectRevert(bytes("zero amount"));
        pool.queueDraw(0, dev, "z");
        vm.expectRevert(bytes("zero recipient"));
        pool.queueDraw(1, address(0), "z");
        vm.stopPrank();
    }

    // ---------- authorization ----------
    function test_NonGovernorCannotQueueOrCancel() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("not governor"));
        pool.queueDraw(1, dev, "x");

        vm.prank(governor);
        uint256 id = pool.queueDraw(1, dev, "x");

        vm.prank(stranger);
        vm.expectRevert(bytes("not governor"));
        pool.cancel(id);
    }

    // ---------- cancel ----------
    function test_CancelBeforeEta() public {
        vm.prank(governor);
        uint256 id = pool.queueDraw(100, dev, "m");
        vm.prank(governor);
        pool.cancel(id);
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(bytes("canceled"));
        pool.execute(id);
    }

    function test_CancelAfterEta() public {
        vm.prank(governor);
        uint256 id = pool.queueDraw(100, dev, "m");
        vm.warp(block.timestamp + DELAY + 1); // stale, past eta, still unexecuted
        vm.prank(governor);
        pool.cancel(id);
        vm.expectRevert(bytes("canceled"));
        pool.execute(id);
    }

    // ---------- governor change ----------
    function test_GovernorChangeIsTimelocked() public {
        vm.prank(governor);
        uint256 id = pool.queueGovernorChange(stranger);

        // not yet effective
        assertEq(pool.governor(), governor);

        vm.warp(block.timestamp + DELAY);
        pool.execute(id);
        assertEq(pool.governor(), stranger, "governor rotated");

        // old governor lost rights
        vm.prank(governor);
        vm.expectRevert(bytes("not governor"));
        pool.queueDraw(1, dev, "x");

        // new governor works
        vm.prank(stranger);
        pool.queueDraw(1, dev, "x");
    }

    // ---------- funding ----------
    function test_TipAndForkRoyaltyAreInstant() public {
        usdc.mint(stranger, 500);
        vm.startPrank(stranger);
        usdc.approve(address(pool), 500);
        pool.tip(300, "thanks");
        pool.payForkRoyalty(200);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(pool)), FUND + 500, "funds received instantly");
    }

    function test_FundingZeroReverts() public {
        vm.expectRevert(bytes("zero amount"));
        pool.tip(0, "x");
        vm.expectRevert(bytes("zero amount"));
        pool.payForkRoyalty(0);
    }

    function test_ReentrantFundingTokenCannotReenterTip() public {
        ReentrantToken token = new ReentrantToken();
        MaintenancePool guarded =
            new MaintenancePool(emberToken, governor, address(token), MaintenancePool.GovernanceMode.Steward, DELAY);

        token.mint(stranger, 200);
        token.setReentry(address(guarded), abi.encodeWithSelector(MaintenancePool.tip.selector, 1, "nested"));

        vm.startPrank(stranger);
        token.approve(address(guarded), 200);
        guarded.tip(200, "outer");
        vm.stopPrank();

        assertTrue(token.attemptedReentry(), "reentry attempted");
        assertFalse(token.reentrySucceeded(), "guard blocked reentry");
        assertEq(token.balanceOf(address(guarded)), 200, "outer tip still succeeds");
    }

    // ---------- sunset ----------
    function test_SunsetBeforeInactivityReverts() public {
        vm.prank(governor);
        vm.expectRevert(bytes("still active"));
        pool.queueSunset(recipient, "wind down");
    }

    function test_TipDoesNotResetSunsetClock() public {
        // warp past inactivity since deploy
        vm.warp(block.timestamp + 365 days + 1);
        usdc.mint(stranger, 100);
        vm.startPrank(stranger);
        usdc.approve(address(pool), 100);
        pool.tip(100, "late tip");
        vm.stopPrank();
        // sunset still queueable: tip did not reset lastDrawTimestamp
        vm.prank(governor);
        uint256 id = pool.queueSunset(recipient, "wind down");
        assertEq(id, 1);
    }

    function test_SunsetHappyPathClosesAndSweeps() public {
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(governor);
        uint256 id = pool.queueSunset(recipient, "wind down");
        vm.warp(block.timestamp + DELAY);
        pool.execute(id);

        assertTrue(pool.closed(), "pool closed");
        assertEq(usdc.balanceOf(recipient), FUND, "full balance swept");
        assertEq(usdc.balanceOf(address(pool)), 0, "pool drained");
    }

    function test_SunsetReValidatedAtExecution() public {
        vm.warp(block.timestamp + 365 days + 1); // inactivity satisfied
        vm.startPrank(governor);
        uint256 sunsetId = pool.queueSunset(recipient, "wind down");
        uint256 drawId = pool.queueDraw(100, dev, "late maintenance");
        vm.stopPrank();

        vm.warp(block.timestamp + DELAY); // both etas reached
        // executing the draw resets the activity clock
        pool.execute(drawId);
        // sunset now fails re-validation
        vm.expectRevert(bytes("still active"));
        pool.execute(sunsetId);
    }

    function test_ClosedPoolRejectsOperations() public {
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(governor);
        uint256 id = pool.queueSunset(recipient, "wind down");
        vm.warp(block.timestamp + DELAY);
        pool.execute(id);

        vm.expectRevert(bytes("pool closed"));
        pool.tip(1, "x");
        vm.expectRevert(bytes("pool closed"));
        pool.payForkRoyalty(1);
        vm.prank(governor);
        vm.expectRevert(bytes("pool closed"));
        pool.queueDraw(1, dev, "x");
        vm.expectRevert(bytes("pool closed"));
        pool.execute(id);
    }

    // ---------- events ----------
    function test_QueueAndExecuteEmitEvents() public {
        uint256 expectedEta = block.timestamp + DELAY;
        vm.expectEmit(true, false, false, true, address(pool));
        emit MaintenancePool.ProposalQueued(1, MaintenancePool.ProposalType.Draw, dev, 100, expectedEta, "maintenance");
        vm.prank(governor);
        uint256 id = pool.queueDraw(100, dev, "maintenance");

        vm.warp(block.timestamp + DELAY);
        vm.expectEmit(true, false, false, true, address(pool));
        emit MaintenancePool.ProposalExecuted(id);
        pool.execute(id);
    }
}
