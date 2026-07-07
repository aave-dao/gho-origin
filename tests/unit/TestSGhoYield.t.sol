// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoYield is TestSGhoBase {
  // ========================================
  // YIELD ACCRUAL & INTEGRATION TESTS
  // ========================================

  function test_yield_claimSavingsIntegration(uint256 depositAmount, uint64 timeSkip) external {
    depositAmount = uint256(bound(depositAmount, 1 ether, 100_000 ether));
    timeSkip = uint64(bound(timeSkip, 1, 30 days));

    // Initial deposit at the RAY index
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);

    assertEq(sgho.totalAssets(), depositAmount, 'Initial totalAssets');

    // Accrue yield, then deposit again at the higher index
    vm.warp(block.timestamp + timeSkip);
    uint256 depositAmount2 = 1 ether;
    deal(address(gho), user1, depositAmount2, true);
    gho.approve(address(sgho), depositAmount2);
    sgho.deposit(depositAmount2, user1);

    // Reconstruct the contract's exact accounting
    uint256 liveIndex = _emulateYieldIndex(RAY, sgho.targetRate(), timeSkip);
    uint256 shares2 = (depositAmount2 * RAY) / liveIndex;
    uint256 expectedAssets = ((depositAmount + shares2) * liveIndex) / RAY;

    assertEq(sgho.totalAssets(), expectedAssets, 'totalAssets mismatch after yield accrual');

    // Single depositor: redeem value equals total assets
    uint256 shares = sgho.balanceOf(user1);
    assertGt(
      sgho.previewRedeem(shares),
      depositAmount + depositAmount2,
      'Assets per share should increase with yield'
    );
    assertEq(
      sgho.previewRedeem(shares),
      expectedAssets,
      'Preview redeem should equal total assets'
    );
    vm.stopPrank();
  }

  function test_yield_10_percent_one_year() external {
    // Set target rate to 10% APR
    vm.startPrank(yManager);
    sgho.setTargetRate(1000, uint40(block.timestamp)); // 10% APR is 1000 bps
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
    vm.warp(block.timestamp + 365 days);

    // User2 redeems everything; user1's value must be unaffected
    vm.startPrank(user2);
    sgho.redeem(sgho.balanceOf(user2), user2, user2);
    assertEq(sgho.balanceOf(user2), 0, 'User2 should have no shares after redeeming');
    vm.stopPrank();

    // After exactly 1 year at 10% APR, user1's 100 GHO is worth exactly 110 GHO
    uint256 expectedTotalAssets = depositAmount + (depositAmount * 1000) / 10000;
    assertEq(sgho.totalAssets(), expectedTotalAssets, 'Total assets should reflect 10% yield');
    assertEq(
      sgho.previewRedeem(sgho.balanceOf(user1)),
      expectedTotalAssets,
      'User asset value should reflect 10% yield'
    );
  }

  function test_yield_isLinear_withIntermediateRateUpdates(uint16 rate) external {
    rate = uint16(bound(rate, 100, 5000));
    vm.startPrank(yManager);
    sgho.setTargetRate(rate, uint40(block.timestamp));
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Re-setting the rate daily checkpoints the index, but accrual must stay linear
    for (uint256 i = 0; i < 365; i++) {
      vm.warp(block.timestamp + 1 days);
      vm.prank(yManager);
      sgho.setTargetRate(rate, uint40(block.timestamp));
    }

    uint256 user1FinalAssets = sgho.previewRedeem(user1Shares);

    // Linear (APR) interest: 365 daily checkpoints accrue the same as a single year,
    // up to the dust lost when each checkpoint floors the accrued amount
    uint256 simpleInterestAssets = depositAmount + (depositAmount * rate) / 10000;
    assertApproxEqAbs(
      user1FinalAssets,
      simpleInterestAssets,
      1,
      'Intermediate rate updates should not compound yield'
    );

    // Daily compounding would have grown faster, confirming accrual is not compounding
    uint256 WAD = 1e18;
    uint256 aprWad = (rate * WAD) / 10000;
    uint256 dailyCompoundingTerm = WAD + (aprWad / 365);
    uint256 compoundedMultiplier = _wadPow(dailyCompoundingTerm, 365);
    uint256 compoundedAssets = (depositAmount * compoundedMultiplier) / WAD;
    assertLt(
      user1FinalAssets,
      compoundedAssets,
      'Linear accrual must stay below daily compounding'
    );
  }

  // ========================================
  // LINEAR ACCRUAL TESTS
  // ========================================

  function test_yield_storedIndexUnchangedByOperations() external {
    // Rate is set to 10% in setUp; the index is only checkpointed on rate changes
    uint256 storedIndex = sgho.yieldIndex();
    uint256 lastUpdateBefore = sgho.lastUpdate();

    vm.prank(user1);
    sgho.deposit(100 ether, user1);

    vm.warp(block.timestamp + 180 days);

    // Operations of every kind must not checkpoint the index
    vm.prank(user1);
    sgho.deposit(50 ether, user1);
    vm.prank(user1);
    sgho.withdraw(10 ether, user1, user1);
    vm.prank(user1);
    sgho.transfer(user2, 1 ether);

    assertEq(sgho.yieldIndex(), storedIndex, 'Stored index must not change on operations');
    assertEq(sgho.lastUpdate(), lastUpdateBefore, 'lastUpdate must not change on operations');

    // The live index still reflects the accrued yield
    assertGt(sgho.convertToAssets(RAY), storedIndex, 'Live index should reflect accrual');
  }

  function test_yield_exactFixedRateAfterOneYear() external {
    // Rate is 10% (set in setUp)
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    vm.warp(block.timestamp + 365 days);

    assertEq(sgho.previewRedeem(shares), 110 ether, 'One year at 10% should yield exactly 10%');
  }

  function test_yield_rateAppliedExactlyDespiteManyActions() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // Many real deposit/withdraw round-trips exercise the conversion paths; none checkpoint the index
    for (uint256 i = 0; i < 365; i++) {
      vm.warp(block.timestamp + 1 days);
      vm.startPrank(user2);
      sgho.deposit(1000 ether, user2);
      sgho.redeem(sgho.balanceOf(user2), user2, user2);
      vm.stopPrank();
    }

    // The applied rate depends only on elapsed time, never on the number of actions
    assertEq(
      sgho.previewRedeem(shares),
      110 ether,
      'Many actions must not affect the applied rate'
    );
  }

  function test_yield_linearOverMultipleYears() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // Two years at 10% APR with no rate change accrues exactly 20%, not 21% (no compounding)
    vm.warp(block.timestamp + 730 days);

    assertEq(sgho.previewRedeem(shares), 120 ether, 'Two years should yield exactly 20% linearly');
  }

  function test_yield_additiveAcrossRateChanges() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // One year at the 10% rate set in setUp
    vm.warp(block.timestamp + 365 days);

    // Switch to 20% for another year
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp));
    vm.warp(block.timestamp + 365 days);

    // Yield adds across rate periods: 10% + 20% = exactly 30%, not the 32% of compounding
    assertEq(sgho.previewRedeem(shares), 130 ether, 'Yield should add across rate periods');
  }

  function test_yield_rateChangeCheckpointsAccruedIndex() external {
    // Rate is 10% (set in setUp)
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    uint256 storedBefore = sgho.yieldIndex();

    vm.warp(block.timestamp + 180 days);

    // Regular time passing must not checkpoint the stored index
    assertEq(sgho.yieldIndex(), storedBefore, 'index checkpointed before rate change');

    // Changing the rate checkpoints accrual at the old rate (10% over 180 days)
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp));

    uint256 expectedIndex = _emulateYieldIndex(storedBefore, 1000, 180 days);
    assertEq(sgho.yieldIndex(), expectedIndex, 'index not checkpointed at the old rate');
    assertEq(sgho.lastUpdate(), block.timestamp, 'lastUpdate not advanced');

    // The share value is continuous across the rate change
    assertEq(
      sgho.previewRedeem(shares),
      (shares * expectedIndex) / RAY,
      'value jumped at rate change'
    );
  }

  // ========================================
  // YIELD EDGE CASES & BOUNDARY TESTS
  // ========================================

  function test_yield_zeroTargetRate() external {
    // Set target rate to 0
    vm.startPrank(yManager);
    sgho.setTargetRate(0, uint40(block.timestamp));
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
    sgho.setTargetRate(5000, uint40(block.timestamp)); // 50% APR to ensure significant yield
    vm.stopPrank();

    // Fill the vault to supply cap
    vm.startPrank(user1);
    sgho.deposit(SUPPLY_CAP, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Check that yield accrual still works even at supply cap
    uint256 totalAssetsBefore = sgho.totalAssets();

    // Skip time to accrue yield (use a longer period to ensure significant yield)
    vm.warp(block.timestamp + 365 days);

    // Withdraw 1 wei to confirm operations still work at supply cap
    vm.startPrank(user1);
    sgho.withdraw(1, user1, user1);
    vm.stopPrank();

    // Yield accrues even at supply cap: after a year at 50% the index is exactly 1.5x
    assertTrue(
      sgho.totalAssets() > totalAssetsBefore - 1,
      'Yield should accrue even at supply cap'
    );
    assertEq(sgho.convertToAssets(RAY), (15 * RAY) / 10, 'Index should be exactly 1.5x at 50% APR');

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

    assertTrue(
      maxDepositBefore <= SUPPLY_CAP - totalAssetsBefore,
      'maxDeposit should not exceed remaining capacity'
    );

    // Accrue into totalAssets by withdrawing 1 wei from user1
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

    // After exactly 1 year at 10%, the index is exactly 1.1 * RAY
    assertEq(newYieldIndex, (RAY * 11) / 10, 'Yield index should be exactly 10% growth');
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
    // Compare one update over the full period against 30 daily checkpoints
    uint256 prevYieldIndex = RAY;
    uint16 targetRate = 1000; // 10% APR

    uint256 singleUpdate = _emulateYieldIndex(prevYieldIndex, targetRate, 30 days);

    uint256 cumulativeIndex = prevYieldIndex;
    for (uint256 i = 0; i < 30; i++) {
      cumulativeIndex = _emulateYieldIndex(cumulativeIndex, targetRate, 1 days);
    }

    // Checkpointing more often only loses dust to flooring (one wei per checkpoint), never inflates
    assertLe(cumulativeIndex, singleUpdate, 'More checkpoints must not inflate the index');
    assertApproxEqAbs(
      cumulativeIndex,
      singleUpdate,
      30,
      'Flooring drift bounded by checkpoint count'
    );
  }

  function test_precision_yieldIndex_edgeCases() external pure {
    // Test minimum non-zero yield index
    uint256 minYieldIndex = _emulateYieldIndex(1, 1, 1);
    assertTrue(minYieldIndex >= 1, 'Should not underflow with minimum values');

    // Test with yield index exactly at RAY
    uint256 rayYieldIndex = _emulateYieldIndex(RAY, 1000, 1 days);
    assertTrue(rayYieldIndex > RAY, 'Should grow from RAY baseline');

    // Maximum safe rate for a full year is exactly 1.5 * RAY (50% APR)
    uint256 maxRateIndex = _emulateYieldIndex(RAY, MAX_SAFE_RATE, 365 days);
    assertEq(maxRateIndex, (RAY * 15) / 10, 'Max rate for 1 year should be exactly 1.5x');
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
    vm.warp(block.timestamp + timeSkip);
    // Re-setting the rate checkpoints the index
    vm.prank(yManager);
    sgho.setTargetRate(rate, uint40(block.timestamp));
    uint256 contractYieldIndex = sgho.yieldIndex();
    uint256 emulatedYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);
    assertEq(contractYieldIndex, emulatedYieldIndex, 'Yield index calculation mismatch');
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

    uint256 growth1 = index1 - prevYieldIndex;
    uint256 growth2 = index2 - index1;
    uint256 growth3 = index3 - index2;

    // Linear accrual: equal time periods produce equal growth
    assertEq(growth1, growth2, 'Linear growth should be constant');
    assertEq(growth2, growth3, 'Linear growth should be constant');
  }

  // ========================================
  // EVENT TESTS
  // ========================================

  function test_ExchangeRateUpdatedEvent_basic() external {
    // Set a target rate to ensure yield accrual
    vm.startPrank(yManager);
    sgho.setTargetRate(1000, uint40(block.timestamp)); // 10% APR
    vm.stopPrank();

    // Initial state
    uint256 initialYieldIndex = sgho.yieldIndex();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 30 days);

    uint256 emulatedYieldIndex = _emulateYieldIndex(initialYieldIndex, 1000, 30 days);

    // Changing the rate checkpoints the index and emits the event
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(block.timestamp, emulatedYieldIndex);
    vm.prank(yManager);
    sgho.setTargetRate(1000, uint40(block.timestamp));

    // Verify yield index has increased
    uint256 newYieldIndex = sgho.yieldIndex();
    assertTrue(newYieldIndex > initialYieldIndex, 'Yield index should increase after time passes');
    assertEq(sgho.lastUpdate(), block.timestamp, 'Last update should be current timestamp');
  }
}
