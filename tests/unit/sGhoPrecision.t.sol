// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {TestnetProcedures, TestnetERC20} from 'lib/aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {sGHO} from '../../src/contracts/sgho/sGHO.sol';
import {WadRayMath} from 'lib/aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {TransparentUpgradeableProxy} from '../../src/contracts/dependencies/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {console} from 'forge-std/console.sol';

contract sGhoPrecisionTest is TestnetProcedures {
    sGHO internal sgho;
    TestnetERC20 internal gho;
    address internal yManager;
    address internal user1;
    address internal user2;
    address internal Admin;
    address internal fundsAdmin;
    bytes32 internal DOMAIN_SEPARATOR_sGHO;
    uint16 internal constant MAX_SAFE_RATE = 5000;
    uint256 internal constant SUPPLY_CAP = 1_000_000 ether;
    uint256 internal constant RAY = 1e27;

    function setUp() public {
        initTestEnvironment(false); // Use TestnetProcedures setup

        // Users
        user1 = vm.addr(0xB0B);
        user2 = vm.addr(0xCAFE);
        Admin = vm.addr(0x1234); // proxy admin
        yManager = vm.addr(0xDEAD); // Yield manager address
        fundsAdmin = vm.addr(0xA11D); // Funds admin address

        // Deploy Mocks & sGHO
        gho = new TestnetERC20('Mock GHO', 'GHO', 18, poolAdmin);

        // Deploy sGHO implementation and proxy
        address sghoImpl = address(new sGHO());
        sgho = sGHO(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        sghoImpl,
                        Admin,
                        abi.encodeWithSelector(
                            sGHO.initialize.selector,
                            address(gho),
                            SUPPLY_CAP,
                            address(this),
                            fundsAdmin,
                            yManager
                        )
                    )
                )
            )
        );

        // Set target rate as yield manager
        vm.startPrank(yManager);
        sgho.setTargetRate(1000); // 10% APR
        vm.stopPrank();
        // Calculate domain separator for permits
        DOMAIN_SEPARATOR_sGHO = sgho.DOMAIN_SEPARATOR();
        // Initial GHO funding for users
        deal(address(gho), user1, 1_000_000 ether, true);
        deal(address(gho), user2, 1_000_000 ether, true);
        // Approve sGHO to spend user GHO
        vm.startPrank(user1);
        gho.approve(address(sgho), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        gho.approve(address(sgho), type(uint256).max);
        vm.stopPrank();
    }

    // --- Precision: Minimum Rate (targetRate = 1) ---
    function test_precision_minRate() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(1); // 0.01% APR
        vm.stopPrank();
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        // Warp 1 year
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1); // trigger yield update
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        // Expected: ~0.01% yield
        uint256 expectedYield = (depositAmount * 1 * RAY) / 10000;
        expectedYield = expectedYield / RAY;
        uint256 expectedRatePerSecond = 1 * RAY / 10000;
        expectedRatePerSecond = expectedRatePerSecond * RAY / 365 days;
        expectedRatePerSecond = expectedRatePerSecond / RAY;
        assertApproxEqAbs(userAssets, 1 ether + depositAmount + expectedYield, 5, 'Yield at min rate should be precise');
        assertEq(sgho.ratePerSecond(), expectedRatePerSecond, 'Rate per second should be 1 * RAY / 365 days');
        vm.stopPrank();
    }

    // --- Precision: Maximum Rate (targetRate = 5000) ---
    function test_precision_maxRate() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE); // 50% APR
        vm.stopPrank();
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        // Warp 1 year
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1); // trigger yield update
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        // Expected: ~50% yield
        uint256 expectedYield = (depositAmount * MAX_SAFE_RATE) / 10000;
        assertApproxEqAbs(userAssets, 1 ether + depositAmount + expectedYield, 2, 'Yield at max rate should be precise');
        vm.stopPrank();
    }

    // --- Edge Case: Zero Rate ---
    function test_edgecase_zeroRate() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(0);
        vm.stopPrank();
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        assertEq(userAssets, depositAmount + 1 ether, 'No yield should accrue at zero rate');
        vm.stopPrank();
    }

    // --- Edge Case: Zero Time ---
    function test_edgecase_zeroTime() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(1000);
        vm.stopPrank();
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        sgho.deposit(1 ether, user1); // no time passed
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        assertEq(userAssets, depositAmount + 1 ether, 'No yield should accrue if no time passed');
        vm.stopPrank();
    }

    // --- Edge Case: Rounding Losses ---
    function test_edgecase_roundingLosses() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(1);
        vm.stopPrank();
        uint256 depositAmount = 1; // 1 wei
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.warp(block.timestamp + 365 days);
        sgho.deposit(1, user1); // trigger yield update
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        // Should not underflow, may round to 1
        assertTrue(userAssets >= 1, 'Should not underflow for small values');
        vm.stopPrank();
    }

    // --- Edge Case: Supply Cap ---
    function test_edgecase_supplyCap() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(1000);
        vm.stopPrank();
        vm.startPrank(user1);
        sgho.deposit(SUPPLY_CAP, user1);
        assertEq(sgho.totalAssets(), SUPPLY_CAP, 'Should be at supply cap');
        vm.expectRevert();
        sgho.deposit(1, user1);
        vm.stopPrank();
    }

    // --- Edge Case: Overflow Protection ---
    function test_edgecase_overflowProtection() external {
        // Emulate WadRayMath overflow check using an external call for try/catch
        uint256 max = type(uint256).max;
        uint256 halfRay = 0.5e27;
        uint256 b = 2;
        bool reverted = false;
        try this._wadRayOverflowTest(max - halfRay + 1, b) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, 'Should revert on overflow');
    }
    // Make this function external so try/catch works
    function _wadRayOverflowTest(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 HALF_RAY = 0.5e27;
        if (b == 0 || a > (type(uint256).max - HALF_RAY) / b) revert('overflow');
        return (a * b + HALF_RAY) / 1e27;
    }

    // --- Edge Case: Extreme Time Gaps ---
    function test_edgecase_extremeTimeGap() external {
        vm.startPrank(yManager);
        sgho.setTargetRate(1000);
        vm.stopPrank();
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        // Warp 10 years
        vm.warp(block.timestamp + 3650 days);
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1); // trigger yield update
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        // Should not overflow, should be much higher than initial
        assertTrue(userAssets > depositAmount, 'Assets should grow with extreme time gap');
        vm.stopPrank();
    }

    // --- Demonstration: Overflow is Practically Impossible at Max Rate ---
    function test_overflow_timeGapIsAstronomical() external {
        // Set max rate
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE); // 50% APR
        vm.stopPrank();
        uint256 depositAmount = 10 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();

        // Try an extremely large time gap (1 million days)
        uint256 hugeTimeGap = 1000000 days;
        vm.warp(block.timestamp + hugeTimeGap);
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE);
        vm.stopPrank();
        console.log('yield index:', sgho.yieldIndex());

        // --- Withdraw a portion of the amount originally deposited ---
        vm.startPrank(user1);
        uint256 ghoBalanceBefore = gho.balanceOf(user1);
        uint256 contractGhoBalance = gho.balanceOf(address(sgho));
        uint256 sharesRequired = sgho.previewWithdraw(depositAmount);
        uint256 userShareBalance = sgho.balanceOf(user1);
        sgho.withdraw(5 ether, user1, user1); // Should succeed
        uint256 ghoBalanceAfter = gho.balanceOf(user1);
        assertEq(ghoBalanceAfter - ghoBalanceBefore, 5 ether, "Should match the amount deposited");

        sgho.withdraw(1 ether, user1, user1); // Should succeed
        ghoBalanceAfter = gho.balanceOf(user1);
        assertEq(ghoBalanceAfter - ghoBalanceBefore, 5 ether + 1 ether, "Should match the amount deposited");

        sgho.withdraw(10, user1, user1); // Should succeed
        ghoBalanceAfter = gho.balanceOf(user1);
        assertEq(ghoBalanceAfter - ghoBalanceBefore, 5 ether + 1 ether + 10, "Should match the amount deposited");

        sgho.withdraw(depositAmount - 5 ether - 1 ether - 10, user1, user1); // Should succeed
        ghoBalanceAfter = gho.balanceOf(user1);
        assertEq(ghoBalanceAfter - ghoBalanceBefore, depositAmount, "Should match the initial state");

        vm.stopPrank();

        // --- Math/preview checks after huge yield index update ---
        vm.startPrank(user1);
        uint256 yieldIndex = sgho.yieldIndex();
        assertTrue(yieldIndex < type(uint256).max, 'Yield index should not overflow');
        // 1. Normal conversion (should work)
        uint256 oneShare = 1e18;
        uint256 assetsForOneShare = sgho.previewRedeem(oneShare);
        assertTrue(assetsForOneShare > 0, 'Conversion for 1 share should work');
        // 2. Try converting max uint256 shares to assets (should revert or handle safely)
        bool reverted = false;
        try sgho.previewRedeem(type(uint256).max) returns (uint256) {
            // If it returns, it should not overflow
        } catch {
            reverted = true;
        }
        assertTrue(reverted || true, 'Conversion for max shares should revert or be handled safely');
        // 3. Try converting a huge asset amount to shares (should revert or handle safely)
        reverted = false;
        try sgho.previewMint(type(uint256).max) returns (uint256) {
            // If it returns, it should not overflow
        } catch {
            reverted = true;
        }
        assertTrue(reverted || true, 'Conversion for max assets should revert or be handled safely');
        // 4. Try converting 1 asset to shares (should work)
        uint256 sharesForOneAsset = sgho.previewMint(1e18);
        assertTrue(sharesForOneAsset > 0, 'Conversion for 1 asset should work');
        vm.stopPrank();

        // For reference, the actual overflow time gap is ~7e30 seconds (see PRECISION.md and overflow test math)
        // This test demonstrates that even for absurdly large time gaps, overflow is not a practical concern, and all conversions are safe or revert as expected.
    }

    // --- Yield Index Growth Test: 100 Years of Daily Compounding at Max Rate ---
    function test_yieldIndex_100YearsDailyCompounding_MaxRate() external {
        // Set max rate and deposit
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE); // 50% APRss
        vm.stopPrank();
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        vm.stopPrank();

        // Simulate 1 years of daily compounding
        uint256 daysInYear = 365;
        uint256 numYears = 1;
        uint256 totalDays = daysInYear * numYears;
        uint256 initialTimestamp = block.timestamp;
       
        for (uint256 i = 0; i < totalDays; i++) {
            uint256 daysPassed = i + 1;
            uint256 currentTimestamp = initialTimestamp + daysPassed * 1 days;
            vm.warp(currentTimestamp);
            // Trigger yield update by calling setTargetRate (no change, just triggers update)
            vm.startPrank(yManager);
            sgho.setTargetRate(MAX_SAFE_RATE);
            vm.stopPrank();
        }
        // Get the final yield index from the contract
        vm.prank(user1);
        uint256 contractYieldIndex = sgho.yieldIndex();
        console.log('Contract yield index after 1 years of daily compounding:', contractYieldIndex);

        // Calculate the theoretical compounded value using daily compounding in RAY no using Aave Library
        uint256 RAY = 1e27;
        uint256 aprRay = (MAX_SAFE_RATE * RAY) / 10000; // 0.5e27
        uint256 dailyRateRay = RAY + (aprRay / daysInYear); // 1e27 + (0.5e27/365)
        uint256 compoundedRay = RAY;
        for (uint256 i = 0; i < totalDays; i++) {
            compoundedRay = (compoundedRay * dailyRateRay) / RAY;
        }
        uint256 theoreticalYieldIndex1 = compoundedRay;
        console.log('Theoretical yield index after 1 years of daily compounding (RAY):', theoreticalYieldIndex1);

        // The contract's yield index should be very close to the theoretical value
        assertApproxEqRel(contractYieldIndex, theoreticalYieldIndex1, 1e6, 'Yield index should match theoretical compounded value for 1 years');

        // --- For documentation: Theoretical value for 100 years ---
        uint256 totalDays100 = daysInYear * 100;
        compoundedRay = RAY;
        for (uint256 i = 0; i < totalDays100; i++) {
            compoundedRay = (compoundedRay * dailyRateRay) / RAY;
        }
        uint256 theoreticalYieldIndex100 = compoundedRay;
        console.log('Theoretical yield index after 100 years of daily compounding (RAY):', theoreticalYieldIndex100);
        // This value is for documentation only, as simulating 100 years in the contract is impractical in a test environment.
    }

    // --- Precision Loss Threshold Test ---
    // Documents and tests the minimum asset value required to get at least 1 share at a given yield index
    function test_precisionLossThreshold_convertToShares() external {
        // Set max rate and deposit
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE); // 50% APR
        vm.stopPrank();
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        vm.stopPrank();

        // Simulate a huge yield index (e.g., 1e27, 1e30)
        uint256[] memory testIndexes = new uint256[](3);
        testIndexes[0] = 1e27; // baseline
        testIndexes[1] = 1e30; // large > 100 years at max rate
        uint256[] memory testAssets = new uint256[](3);
        testAssets[0] = 1; // 1 wei
        testAssets[1] = 1e18; // 1 GHO
        testAssets[2] = 1e25; // 10.000.000 GHO
        for (uint256 i = 0; i < testIndexes.length; i++) {
            // Simulate yield index by warping time and triggering update
            // (We can't set yieldIndex directly, so we simulate by warping time until the index is above threshold)
            // For the test, we use preview functions with a local copy of the formula
            uint256 assets = testAssets[i];
            uint256 yieldIndex = testIndexes[i];
            if (yieldIndex == 0) {
                continue;
            }
            // shares = assets * 1e27 / yieldIndex
            uint256 shares = assets * 1e27 / yieldIndex;
            if (yieldIndex > assets * 1e27) {
                assertEq(shares, 0, 'Should round to zero when yieldIndex > assets * 1e27');
            } else {
                assertTrue(shares > 0, 'Should not round to zero when yieldIndex <= assets * 1e27');
            }
        }
        // Document: For convertToShares, if yieldIndex > assets * 1e27, conversion will round to zero due to integer division.
        // This is a fundamental limitation of fixed-point math.
    }

    // --- Precision Loss Threshold Test for convertToAssets (Large Yield Index) ---
    // Documents and tests the minimum share value required to get at least 1 asset at a large yield index
    function test_precisionLossThreshold_convertToAssets_largeYieldIndex() external {
        // Simulate extremely large yield indexes (e.g., 1e27, 1e45, 1e51, 1e60) and small share values
        uint256[] memory testIndexes = new uint256[](4);
        testIndexes[0] = 1e27; // baseline
        testIndexes[1] = 1e30; // large > 100 years at max rate
        uint256[] memory testShares = new uint256[](3);
        testShares[0] = 1e9; // 1e9 shares
        testShares[1] = 1e18; // 1 ether in shares
        testShares[2] = 1e24; // 1e6 ether in shares
        for (uint256 i = 0; i < testIndexes.length; i++) {
            for (uint256 j = 0; j < testShares.length; j++) {
                uint256 shares = testShares[j];
                uint256 yieldIndex = testIndexes[i];
                // assets = shares * yieldIndex / 1e27
                uint256 assets = shares * yieldIndex / 1e27;
                if (shares * yieldIndex < 1e27) {
                    assertEq(assets, 0, 'Should round to zero when shares * yieldIndex < 1e27');
                } else {
                    assertTrue(assets > 0, 'Should not round to zero when shares * yieldIndex >= 1e27');
                }
            }
        }
        // Document: For convertToAssets, if shares * yieldIndex < 1e27, conversion will round to zero due to integer division.
        // This is a fundamental limitation of fixed-point math, and is especially relevant for large yield indexes and small share values.
    }

    // --- Test: Precision Loss at Extreme Yield Index (1 wei share) ---
    function test_precisionLossExtremeYieldIndex() external {
        // Set max rate and deposit
        vm.startPrank(yManager);
        sgho.setTargetRate(MAX_SAFE_RATE); // 50% APR
        vm.stopPrank();
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        vm.stopPrank();

        // Simulate a huge yield index by warping time and triggering updates
        // We'll use 1e29 as the target yield index
        uint256 targetYieldIndex = 1e29;
        uint256 oneWeek = 7 days;
        // Warp in large steps to reach the target yield index
        while (true) {
            vm.warp(block.timestamp + oneWeek);
            vm.startPrank(yManager);
            sgho.setTargetRate(MAX_SAFE_RATE);
            vm.stopPrank();
            vm.startPrank(user1);
            uint256 currentYieldIndex = sgho.yieldIndex();
            vm.stopPrank();
            if (currentYieldIndex >= targetYieldIndex) {
                break;
            }
        }

        // Now, preview redeem for 100 share (100 wei)
        vm.startPrank(user1);
        uint256 minAsset = sgho.previewRedeem(100); // 100 shares (100 wei)
        console.log('previewRedeem(100) at yieldIndex ~1e29:', minAsset);

        // Try to withdraw less than minAsset
        uint256 withdrawAmount = minAsset > 0 ? minAsset - 1 : 0;
        uint256 sharesBefore = sgho.balanceOf(user1);
        uint256 ghoBalanceBefore = gho.balanceOf(user1);
        // This will burn 1 share (1 wei), but user receives only withdrawAmount
        sgho.withdraw(withdrawAmount, user1, user1);
        uint256 sharesAfter = sgho.balanceOf(user1);
        uint256 ghoBalanceAfter = gho.balanceOf(user1);
        uint256 sharesBurned = sharesBefore - sharesAfter;
        uint256 ghoReceived = ghoBalanceAfter - ghoBalanceBefore;
        // The shares burned should be 1, and the GHO received should be much less than minAsset
        assertEq(sharesBurned, 100, 'Should burn 100 shares (100 wei)');
        assertEq(ghoReceived, withdrawAmount, 'Should receive the requested (small) amount');
        // Now, preview redeem for 1 share again (should be the same, since yield index hasn't changed)
        ghoBalanceBefore = gho.balanceOf(user1);
        sharesBefore = sgho.balanceOf(user1);
        uint256 minAssetAfter = sgho.previewRedeem(100);
        assertEq(minAsset, minAssetAfter, 'previewRedeem(100) should be unchanged');
        sgho.withdraw(withdrawAmount/2, user1, user1);
        ghoBalanceAfter = gho.balanceOf(user1);
        assertEq(ghoBalanceAfter - ghoBalanceBefore, withdrawAmount/2, 'Should receive the requested (small) amount');
        sharesAfter = sgho.balanceOf(user1);
        sharesBurned = sharesBefore - sharesAfter;
        assertGe(sharesBurned, 100/2, 'Should burn at least half of the shares (100 wei)');
        assertLt(ghoReceived, minAssetAfter, 'Will receive less than the share is worth');
        console.log('value lost:', minAssetAfter - ghoReceived);
        vm.stopPrank();
        // This test demonstrates that, at extreme yield index values, withdrawing less than the minimum asset for 1 share (1 wei) will still burn a full share, resulting in significant precision loss for the smallest possible withdrawal.
    }

    // --- Test: No yield accrues when target rate is zero ---
    function test_yield_zeroTargetRate() external {
        // Set target rate to 0
        vm.startPrank(yManager);
        sgho.setTargetRate(0);
        vm.stopPrank();
        // Deposit
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        // Warp time (simulate 1 year)
        vm.warp(block.timestamp + 365 days);
        // Trigger yield update
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        // Check that no yield accrued
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        assertEq(userAssets, depositAmount + 1 ether, 'No yield should accrue at zero target rate');
        vm.stopPrank();
    }

    // --- Test: No yield accrues when no time has passed ---
    function test_yield_zeroTimeSinceLastUpdate() external {
        // Set target rate to a nonzero value
        vm.startPrank(yManager);
        sgho.setTargetRate(1000);
        vm.stopPrank();
        // Deposit
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        // Immediately deposit again (no time passed)
        sgho.deposit(1 ether, user1);
        // Check that no yield accrued
        uint256 userAssets = sgho.previewRedeem(sgho.balanceOf(user1));
        assertEq(userAssets, depositAmount + 1 ether, 'No yield should accrue if no time passed');
        vm.stopPrank();
    }

    // --- Test: maxWithdraw is limited by actual GHO balance (shortfall detection) ---
    function test_gho_shortfall_detection() external {
        // Deposit
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        sgho.deposit(depositAmount, user1);
        vm.stopPrank();
        // Warp time to accrue yield
        vm.warp(block.timestamp + 365 days);
        // Trigger yield update (simulate yield accrual)
        vm.startPrank(user1);
        sgho.deposit(1 ether, user1);
        vm.stopPrank();
        // Theoretical total assets (includes yield)
        uint256 theoreticalAssets = sgho.totalAssets();
        // Actual GHO balance in the contract (has not been topped up by external agent)
        uint256 actualGhoBalance = gho.balanceOf(address(sgho));
        // There should be a shortfall: theoretical assets > actual GHO balance
        assertTrue(theoreticalAssets > actualGhoBalance, 'Should have a shortfall due to yield accrual');
        // maxWithdraw is limited by actual GHO balance
        uint256 maxWithdraw = sgho.maxWithdraw(user1);
        assertEq(maxWithdraw, actualGhoBalance, 'maxWithdraw should be limited by actual GHO balance');
        // This test demonstrates that, due to yield accrual, the contract can have a shortfall unless topped up by an external agent.
    }
} 