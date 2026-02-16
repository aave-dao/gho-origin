// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoYield is TestSGhoBase {
  // ========================================
  // YIELD ACCRUAL & INTEGRATION TESTS
  // ========================================

  function test_yield_claimSavingsIntegration(uint256 depositAmount, uint64 timeSkip) external {
    depositAmount = uint256(bound(depositAmount, 1 ether, 100_000 ether));
    timeSkip = uint64(bound(timeSkip, 1, 30 days)); // No minimum time requirement in new implementation

    // Initial deposit
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);

    assertEq(sgho.totalAssets(), depositAmount, 'Initial totalAssets');

    // Skip time and trigger _updateVault via another deposit
    vm.warp(block.timestamp + timeSkip);
    uint256 depositAmount2 = 1 ether;
    deal(address(gho), user1, depositAmount2, true); // Ensure user1 has more GHO
    gho.approve(address(sgho), depositAmount2);
    sgho.deposit(depositAmount2, user1); // This deposit triggers _updateVault

    // Calculate expected yield based on time elapsed and target rate
    uint256 expectedYield = (depositAmount * sgho.ratePerSecond() * timeSkip) / RAY;
    uint256 expectedAssets = depositAmount + expectedYield + depositAmount2;

    assertApproxEqAbs(
      sgho.totalAssets(),
      expectedAssets,
      1,
      'totalAssets mismatch after yield claim'
    );

    // Check if withdraw/redeem reflects yield (share price > 1)
    uint256 shares = sgho.balanceOf(user1);
    uint256 expectedWithdrawAssets = sgho.previewRedeem(shares);
    assertTrue(
      expectedWithdrawAssets > depositAmount + depositAmount2,
      'Assets per share should increase with yield'
    );
    assertApproxEqAbs(
      expectedWithdrawAssets,
      expectedAssets,
      1,
      'Preview redeem should equal total assets'
    ); // Single depositor case
    vm.stopPrank();
  }

  function test_yield_10_percent_one_year() external {
    // Set target rate to 10% APR
    vm.startPrank(yManager);
    sgho.setTargetRate(1000); // 10% APR is 1000 bps
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);

    assertEq(sgho.totalAssets(), depositAmount, 'Initial total assets should be deposit amount');

    // User2 deposits 500 GHO
    uint256 depositAmount2 = 500 ether;
    vm.startPrank(user2);
    sgho.deposit(depositAmount2, user2);
    vm.stopPrank();

    // Skip time by 365 days
    uint256 timeSkip = 365 days;
    vm.warp(block.timestamp + timeSkip);

    // Trigger yield update by redeeming all of user2 shares
    // Any state-changing action that calls `_updateVault` would work.
    vm.startPrank(user2);
    uint256 user2Shares = sgho.balanceOf(user2);
    sgho.redeem(user2Shares, user2, user2);
    assertEq(sgho.balanceOf(user2), 0, 'User2 should have no shares after redeeming');
    vm.stopPrank();

    // After 1 year at 10% APR, the 100 GHO should have become ~110 GHO.
    // The total assets will be ~110 GHO + the small deposit.
    uint256 expectedYield = ((depositAmount) * 1000) / 10000;
    uint256 expectedTotalAssets = depositAmount + expectedYield;

    assertApproxEqAbs(
      sgho.totalAssets(),
      expectedTotalAssets,
      2,
      'Total assets should reflect 10% yield after 1 year'
    );

    // Also check the value of user1's shares
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 user1Assets = sgho.previewRedeem(user1Shares);
    assertApproxEqAbs(
      user1Assets,
      expectedTotalAssets,
      2,
      'User asset value should reflect 10% yield'
    );
    vm.stopPrank();
  }

  function test_yield_is_compounded_with_intermediate_update(uint16 rate) external {
    rate = uint16(bound(rate, 100, 5000));
    vm.startPrank(yManager);
    sgho.setTargetRate(rate);
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Warp time and trigger updates daily to simulate compounding
    for (uint i = 0; i < 365; i++) {
      vm.warp(block.timestamp + 1 days);
      vm.prank(yManager);
      sgho.setTargetRate(rate); // Re-setting the rate triggers the update
      vm.stopPrank();
    }
    // --- Verification ---
    // Get the current value of user1's shares
    uint256 user1FinalAssets = sgho.previewRedeem(user1Shares);

    // Calculate what the assets would be with simple (non-compounded) interest over 365 days
    uint256 simpleYield = (depositAmount * rate) / 10000;
    uint256 simpleInterestAssets = depositAmount + simpleYield;

    // Calculate the expected assets with daily compounding.
    // Each daily update applies linear interest for that day, but builds on the previous index
    // APY = (1 + APR/n)^n - 1, where n=365 for daily.
    uint256 WAD = 1e18;
    uint256 aprWad = (rate * WAD) / 10000;
    uint256 dailyCompoundingTerm = WAD + (aprWad / 365);

    // Calculate (1 + apr/365)^365 using a helper for WAD math to prevent overflow
    uint256 compoundedMultiplier = _wadPow(dailyCompoundingTerm, 365);
    uint256 expectedAssets = (depositAmount * compoundedMultiplier) / WAD;

    assertApproxEqAbs(
      user1FinalAssets,
      expectedAssets,
      1e6, // Use a tolerance for small differences from ideal calculation
      'Final assets should be close to theoretical daily compounded value'
    );

    // With compounding due to the intermediate updates, user1's final assets should be greater than with simple interest.
    assertTrue(
      user1FinalAssets > simpleInterestAssets,
      'Daily compounded assets for user1 should be greater than simple interest assets'
    );
  }

  // ========================================
  // YIELD EDGE CASES & BOUNDARY TESTS
  // ========================================

  function test_yield_zeroTargetRate() external {
    // Set target rate to 0
    vm.startPrank(yManager);
    sgho.setTargetRate(0);
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Skip time - no yield should accrue
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // User1 should have the same assets value
    vm.startPrank(user1);
    uint256 finalAssets = sgho.previewRedeem(initialShares);
    assertEq(finalAssets, depositAmount, 'Assets should remain unchanged with zero target rate');
    vm.stopPrank();
  }

  function test_yield_zeroTimeSinceLastUpdate() external {
    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Don't skip time - timeSinceLastUpdate should be 0
    // Trigger another operation immediately
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // User1 should have the same assets value (no time passed)
    vm.startPrank(user1);
    uint256 finalAssets = sgho.previewRedeem(initialShares);
    assertEq(
      finalAssets,
      depositAmount,
      'Assets should remain unchanged with zero time since last update'
    );
    vm.stopPrank();
  }

  function test_yield_index_edgeCases() external {
    // Test with very small amounts and very large amounts
    uint256 smallAmount = 1; // 1 wei
    uint256 largeAmount = SUPPLY_CAP - 1 ether;

    vm.startPrank(user1);

    // Test small amount
    sgho.deposit(smallAmount, user1);
    uint256 smallShares = sgho.balanceOf(user1);
    assertEq(smallShares, smallAmount, 'Small amount should convert 1:1 initially');

    // Test large amount
    deal(address(gho), user1, largeAmount, true);
    gho.approve(address(sgho), largeAmount);
    sgho.deposit(largeAmount, user1);
    uint256 largeShares = sgho.balanceOf(user1);
    assertEq(largeShares, smallShares + largeAmount, 'Large amount should convert 1:1 initially');

    vm.stopPrank();
  }

  function test_yield_accrual_atSupplyCap() external {
    // Set a higher target rate to ensure significant yield accrual
    vm.startPrank(yManager);
    sgho.setTargetRate(5000); // 50% APR to ensure significant yield
    vm.stopPrank();

    // Fill the vault to supply cap
    vm.startPrank(user1);
    sgho.deposit(SUPPLY_CAP, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Check that yield accrual still works even at supply cap
    uint256 totalAssetsBefore = sgho.totalAssets();
    uint256 yieldIndexBefore = sgho.yieldIndex();

    // Skip time to accrue yield (use a longer period to ensure significant yield)
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update by withdrawing 1 wei (any state-changing operation would work)
    vm.startPrank(user1);
    sgho.withdraw(1, user1, user1);
    vm.stopPrank();

    uint256 totalAssetsAfter = sgho.totalAssets();
    uint256 yieldIndexAfter = sgho.yieldIndex();

    // Yield should have accrued even at supply cap
    // The total assets after should be greater than before minus the withdrawal amount
    // because yield accrual should offset the withdrawal
    assertTrue(totalAssetsAfter > totalAssetsBefore - 1, 'Yield should accrue even at supply cap');
    assertTrue(
      yieldIndexAfter > yieldIndexBefore,
      'Yield index should increase even at supply cap'
    );

    // User's share value should have increased (accounting for the 1 wei withdrawal)
    vm.startPrank(user1);
    uint256 userAssetsAfter = sgho.previewRedeem(initialShares - sgho.convertToShares(1));
    assertTrue(
      userAssetsAfter > SUPPLY_CAP - 1,
      'User assets should increase with yield even at supply cap'
    );
    vm.stopPrank();
  }

  function test_maxDeposit_withYieldAccrual() external {
    // Set up initial state with some deposits
    vm.startPrank(user1);
    uint256 initialDeposit = SUPPLY_CAP / 2;
    sgho.deposit(initialDeposit, user1);
    vm.stopPrank();

    // Check maxDeposit before any yield update
    uint256 maxDepositBefore = sgho.maxDeposit(user2);
    uint256 totalAssetsBefore = sgho.totalAssets();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 30 days);

    // The maxDeposit should account for the fact that the deposit itself will trigger yield update
    // and potentially increase totalAssets beyond the current calculation

    // The maxDeposit should account for the fact that the deposit itself will trigger yield update
    // and potentially increase totalAssets beyond the current calculation
    assertTrue(
      maxDepositBefore <= SUPPLY_CAP - totalAssetsBefore,
      'maxDeposit should not exceed remaining capacity'
    );

    // Now trigger a yield update by withdrawing 1 wei from user1
    vm.startPrank(user1);
    sgho.withdraw(1, user1, user1);
    vm.stopPrank();

    uint256 totalAssetsAfter = sgho.totalAssets();
    uint256 maxDepositAfter = sgho.maxDeposit(user2);

    // The total assets should have increased due to yield accrual (minus the 1 wei withdrawal)
    assertTrue(
      totalAssetsAfter > totalAssetsBefore - 1,
      'Total assets should increase due to yield despite withdrawal'
    );

    // The new maxDeposit should be accurate after the yield update
    assertEq(
      maxDepositAfter,
      SUPPLY_CAP - totalAssetsAfter,
      'maxDeposit should be accurate after yield update'
    );

    // Verify that the maxDeposit calculation is correct by attempting to deposit exactly that amount
    vm.startPrank(user2);
    deal(address(gho), user2, maxDepositAfter, true);
    gho.approve(address(sgho), maxDepositAfter);
    sgho.deposit(maxDepositAfter, user2);
    vm.stopPrank();

    // Should now be at supply cap
    assertEq(
      sgho.totalAssets(),
      SUPPLY_CAP,
      'Should be at supply cap after depositing maxDeposit amount'
    );
  }

  // ========================================
  // PRECISION & MATHEMATICAL ACCURACY TESTS
  // ========================================

  function test_precision_yieldIndex_smallValues() external pure {
    // Small values for prevYieldIndex, targetRate, and time
    uint256 prevYieldIndex = 1; // 1 wei
    uint16 targetRate = 1; // 0.01%
    uint256 timeSinceLastUpdate = 1; // 1 second
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);
    assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
  }

  function test_precision_yieldIndex_largeValues() external pure {
    // Large values for prevYieldIndex, targetRate, and time
    uint256 prevYieldIndex = 1e30; // Large but safe value
    uint16 targetRate = 5000; // Max safe rate
    uint256 timeSinceLastUpdate = 365 days; // 1 year
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);
    assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
    assertTrue(newYieldIndex <= type(uint256).max, 'Yield index should not overflow');
  }

  function test_precision_yieldIndex_realisticValues() external pure {
    // Test with realistic starting values
    uint256 prevYieldIndex = 1e27; // Start from RAY (1e27)
    uint16 targetRate = 1000; // 10% APR
    uint256 timeSinceLastUpdate = 365 days; // 1 year
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);

    // After 1 year at 10%, index should be approximately 1.1 * RAY
    uint256 expectedIndex = (1e27 * 11) / 10; // 1.1 * RAY
    assertApproxEqRel(
      newYieldIndex,
      expectedIndex,
      0.01e18,
      'Yield index should approximate 10% growth'
    ); // 1% tolerance
    assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
  }

  function test_precision_yieldIndex_granularTime() external pure {
    // Test with very small time increments
    uint256 prevYieldIndex = 1e27;
    uint16 targetRate = 1000; // 10% APR

    // Test 1 second increment
    uint256 newYieldIndex1s = _emulateYieldIndex(prevYieldIndex, targetRate, 1);
    assertTrue(newYieldIndex1s > prevYieldIndex, 'Should accrue yield even for 1 second');

    // Test 1 minute increment
    uint256 newYieldIndex1m = _emulateYieldIndex(prevYieldIndex, targetRate, 60);
    assertTrue(newYieldIndex1m > newYieldIndex1s, 'More time should yield more index growth');

    // Test 1 hour increment
    uint256 newYieldIndex1h = _emulateYieldIndex(prevYieldIndex, targetRate, 3600);
    assertTrue(newYieldIndex1h > newYieldIndex1m, 'More time should yield more index growth');
  }

  function test_precision_yieldIndex_cumulativePrecision() external pure {
    // Test cumulative precision loss over multiple small updates vs one large update
    uint256 prevYieldIndex = RAY;
    uint16 targetRate = 1000; // 10% APR
    uint256 totalTime = 30 days;

    // Single large update
    uint256 singleUpdate = _emulateYieldIndex(prevYieldIndex, targetRate, totalTime);

    // Multiple small updates (simulate daily updates)
    uint256 cumulativeIndex = prevYieldIndex;
    uint256 dailyTime = 1 days;
    for (uint256 i = 0; i < 30; i++) {
      cumulativeIndex = _emulateYieldIndex(cumulativeIndex, targetRate, dailyTime);
    }

    // Cumulative should be slightly higher due to compounding
    assertTrue(cumulativeIndex >= singleUpdate, 'Cumulative updates should compound yield');

    // But the difference should be small (within 0.1% for reasonable rates)
    assertApproxEqRel(cumulativeIndex, singleUpdate, 0.001e18, 'Precision loss should be minimal');
  }

  function test_precision_yieldIndex_edgeCases() external pure {
    // Test minimum non-zero yield index
    uint256 minYieldIndex = _emulateYieldIndex(1, 1, 1);
    assertTrue(minYieldIndex >= 1, 'Should not underflow with minimum values');

    // Test with yield index exactly at RAY
    uint256 rayYieldIndex = _emulateYieldIndex(RAY, 1000, 1 days);
    assertTrue(rayYieldIndex > RAY, 'Should grow from RAY baseline');

    // Test maximum safe rate for extended period
    uint256 maxRateIndex = _emulateYieldIndex(RAY, MAX_SAFE_RATE, 365 days);
    assertTrue(maxRateIndex > RAY, 'Should handle max rate without overflow');
    assertTrue(maxRateIndex < RAY * 2, 'Max rate for 1 year should not double the index');
  }

  function test_precision_yieldIndex_fuzz(uint256 timeSkip, uint16 rate) external pure {
    // Bound inputs to reasonable ranges
    timeSkip = bound(timeSkip, 1, 365 days * 10); // 1 second to 10 years
    rate = uint16(bound(rate, 1, MAX_SAFE_RATE)); // 0.01% to 50%

    uint256 prevYieldIndex = RAY;
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);

    // Basic invariants
    assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should never decrease');
    assertTrue(newYieldIndex <= type(uint256).max, 'Should not overflow');

    // Reasonable growth bounds (max 50% per year * 10 years = 500% max theoretical)
    assertTrue(
      newYieldIndex <= prevYieldIndex * 6,
      'Growth should be bounded by reasonable limits'
    );
  }

  function test_precision_yieldIndex_zeroRateOrTime() external pure {
    uint256 prevYieldIndex = RAY;
    // Zero target rate
    assertEq(
      _emulateYieldIndex(prevYieldIndex, 0, 1000),
      prevYieldIndex,
      'Zero rate should not change index'
    );
    // Zero time
    assertEq(
      _emulateYieldIndex(prevYieldIndex, 1000, 0),
      prevYieldIndex,
      'Zero time should not change index'
    );
  }

  function test_precision_yieldIndex_consistency() external {
    // Compare contract's yieldIndex calculation to _emulateYieldIndex for a real scenario
    uint256 prevYieldIndex = sgho.yieldIndex();
    uint16 rate = sgho.targetRate();
    uint256 timeSkip = 1 days;
    // Warp time and trigger yield update
    vm.warp(block.timestamp + timeSkip);
    // Call a state-changing function to update yieldIndex
    vm.startPrank(user1);
    sgho.deposit(1 ether, user1);
    vm.stopPrank();
    uint256 contractYieldIndex = sgho.yieldIndex();
    uint256 emulatedYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);
    // Allow for 1 wei rounding error
    assertApproxEqAbs(
      contractYieldIndex,
      emulatedYieldIndex,
      1,
      'Yield index calculation mismatch'
    );
  }

  function test_precision_yieldIndex_monotonic() external pure {
    // Test that yield index is always monotonically increasing
    uint256 prevYieldIndex = RAY;
    uint16 targetRate = 1000;

    uint256 index1 = _emulateYieldIndex(prevYieldIndex, targetRate, 1 days);
    uint256 index2 = _emulateYieldIndex(index1, targetRate, 1 days);
    uint256 index3 = _emulateYieldIndex(index2, targetRate, 1 days);

    assertTrue(index1 > prevYieldIndex, 'First update should increase index');
    assertTrue(index2 > index1, 'Second update should increase index');
    assertTrue(index3 > index2, 'Third update should increase index');

    // Growth should be roughly equal for equal time periods (compound growth)
    uint256 growth1 = index1 - prevYieldIndex;
    uint256 growth2 = index2 - index1;
    uint256 growth3 = index3 - index2;

    assertTrue(growth2 > growth1, 'Compound growth should accelerate');
    assertTrue(growth3 > growth2, 'Compound growth should continue accelerating');
  }

  function test_precision_ratePerSecond_maxRate() external {
    // Set target rate to max safe rate
    vm.startPrank(yManager);
    sgho.setTargetRate(MAX_SAFE_RATE);
    vm.stopPrank();

    // Rate per second should be calculated correctly
    uint96 expectedRatePerSecond = sgho.ratePerSecond();

    uint256 annualRateRay = (MAX_SAFE_RATE * RAY) / 10000; // 0.5e27
    uint256 ratePerSecond = (annualRateRay * RAY) / 365 days;
    uint256 expectedRatePerSecondCalc = ratePerSecond / RAY;

    assertEq(
      expectedRatePerSecond,
      uint96(expectedRatePerSecondCalc),
      'ratePerSecond should match calculated value for max rate'
    );
  }

  function test_precision_ratePerSecond_rateChange() external {
    // Get initial rate per second
    uint96 initialRatePerSecond = sgho.ratePerSecond();

    // Change target rate
    vm.startPrank(yManager);
    sgho.setTargetRate(2000); // 20% APR
    vm.stopPrank();

    // Get new rate per second
    uint96 newRatePerSecond = sgho.ratePerSecond();

    // New rate should be different and higher
    assertTrue(newRatePerSecond > initialRatePerSecond, 'New rate per second should be higher');

    // Verify calculation
    uint256 annualRateRay = (2000 * 1e27) / 10000; // 0.2e27
    uint256 ratePerSecond = (annualRateRay * RAY) / 365 days;
    uint256 expectedRatePerSecondCalc = ratePerSecond / RAY;

    assertEq(
      newRatePerSecond,
      uint96(expectedRatePerSecondCalc),
      'New rate per second should match calculated value'
    );
  }

  // ========================================
  // EVENT TESTS
  // ========================================

  function test_ExchangeRateUpdatedEvent_basic() external {
    // Set a target rate to ensure yield accrual
    vm.startPrank(yManager);
    sgho.setTargetRate(1000); // 10% APR
    vm.stopPrank();

    // Initial state
    uint256 initialYieldIndex = sgho.yieldIndex();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 30 days);

    uint256 emulatedYieldIndex = _emulateYieldIndex(initialYieldIndex, 1000, 30 days);

    // Trigger yield update by depositing - should emit event
    vm.startPrank(user1);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(block.timestamp, emulatedYieldIndex);
    sgho.deposit(100 ether, user1);
    vm.stopPrank();

    // Verify yield index has increased
    uint256 newYieldIndex = sgho.yieldIndex();
    assertTrue(newYieldIndex > initialYieldIndex, 'Yield index should increase after time passes');
    assertEq(sgho.lastUpdate(), block.timestamp, 'Last update should be current timestamp');
  }
}
