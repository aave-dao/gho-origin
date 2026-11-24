// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoYield is TestSGhoBase {
  using SafeCast for uint256;

  // Growth factors `1 + x + x^2 / 2 + x^3 / 6` with `x = rate * years`, computed with exact
  // decimal arithmetic and rounded down to ray. Independent of the contract and of
  // `_emulateYieldIndex`.
  uint256 internal constant GROWTH_10_PERCENT_1_YEAR = 1105166666666666666666666666;
  uint256 internal constant GROWTH_10_PERCENT_2_YEARS = 1221333333333333333333333333;
  uint256 internal constant GROWTH_50_PERCENT_1_YEAR = 1645833333333333333333333333;
  // 1 year at 10%, then 1 year at 20%
  uint256 internal constant GROWTH_10_THEN_20_PERCENT = 1349776888888888888888888888;
  // 2 years at 50%, then 1 year at 10%
  uint256 internal constant GROWTH_50_THEN_10_PERCENT = 2947111111111111111111111111;

  /// @dev Every operation rounds down, so the contract never exceeds the exact polynomial. It stays
  /// within 8 ray units of it per period (measured); 100 leaves room for products of periods
  function _assertGrowth(uint256 actual, uint256 exact, string memory err) internal pure {
    assertLe(actual, exact, err);
    assertApproxEqAbs(actual, exact, 100, err);
  }

  /// @dev Value of `assets` after `growth`, allowing 1 wei for the final rounding
  function _assertAssetsGrown(
    uint256 actual,
    uint256 assets,
    uint256 growth,
    string memory err
  ) internal pure {
    assertApproxEqAbs(actual, (assets * growth) / RAY, 1, err);
  }

  /**
   * @dev Upper bound on the extra yield that `checkpoints` intermediate checkpoints add over a
   * single accrual of `x = rate * elapsed / year`. Checkpointing moves the result towards `e^x`,
   * which exceeds the approximation by at most `x^4 * e^x / 24`, below `x^4 / 4` for `x < 1.7`.
   * Each checkpoint also adds up to 9 ray units of rounding on an index below 6.
   */
  function _checkpointExcessBound(
    uint256 singleAccrual,
    uint256 rate,
    uint256 elapsed,
    uint256 checkpoints
  ) internal pure returns (uint256) {
    uint256 x = (rate * RAY * elapsed) / (10000 * 365 days);
    uint256 x4 = (((((x * x) / RAY) * x) / RAY) * x) / RAY;
    return (singleAccrual * x4) / (4 * RAY) + checkpoints * 6 * 9;
  }

  // ========================================
  // YIELD ACCRUAL & INTEGRATION TESTS
  // ========================================

  function test_yield_claimSavingsIntegration(uint256 depositAmount, uint64 timeSkip) external {
    depositAmount = uint256(bound(depositAmount, 1 ether, 100_000 ether));
    timeSkip = (bound(timeSkip, 1, 30 days)).toUint64();

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
    // Set target rate to 10% annual rate
    vm.startPrank(yManager);
    sgho.setTargetRate(1000, block.timestamp.toUint40()); // 10% annual rate is 1000 bps
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

    // One year at 10% compounded continuously: 100 GHO grows to about 110.517 GHO
    _assertAssetsGrown(
      sgho.totalAssets(),
      depositAmount,
      GROWTH_10_PERCENT_1_YEAR,
      'Total assets should reflect one year at 10%'
    );
    _assertAssetsGrown(
      sgho.previewRedeem(sgho.balanceOf(user1)),
      depositAmount,
      GROWTH_10_PERCENT_1_YEAR,
      'User asset value should reflect one year at 10%'
    );
  }

  function test_yield_checkpointsAddBoundedYield(uint16 rate) external {
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16();
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());

    uint256 depositAmount = 100 ether;
    vm.prank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 startIndex = sgho.yieldIndex();

    // Re-setting the same rate daily checkpoints the index 365 times
    for (uint256 i = 0; i < 365; i++) {
      vm.warp(block.timestamp + 1 days);
      vm.prank(yManager);
      sgho.setTargetRate(rate, block.timestamp.toUint40());
    }

    // Each checkpoint restarts the approximation, so checkpoints only ever add yield, and at most
    // the gap between the approximation and `e^x`
    uint256 singleAccrual = _emulateYieldIndex(startIndex, rate, 365 days);
    assertGe(sgho.yieldIndex() + 365 * 6 * 9, singleAccrual, 'Checkpoints removed yield');
    assertLe(
      sgho.yieldIndex(),
      singleAccrual + _checkpointExcessBound(singleAccrual, rate, 365 days, 365),
      'Checkpoints added too much yield'
    );
  }

  function test_yield_checkpointsAddBoundedYield_randomIntervals(
    uint16 rate,
    uint256 seed
  ) external {
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16();
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());
    uint256 startIndex = sgho.yieldIndex();

    // 20 checkpoints at random intervals of up to 60 days, alternating rate re-sets and no-ops
    uint256 elapsed;
    for (uint256 i = 0; i < 20; i++) {
      uint256 interval = bound(uint256(keccak256(abi.encode(seed, i))), 1, 60 days);
      vm.warp(block.timestamp + interval);
      elapsed += interval;
      if (i % 2 == 0) {
        vm.prank(yManager);
        sgho.setTargetRate(rate, block.timestamp.toUint40());
      }
    }
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());

    uint256 singleAccrual = _emulateYieldIndex(startIndex, rate, elapsed);
    assertGe(sgho.yieldIndex() + 11 * 6 * 9, singleAccrual, 'Checkpoints removed yield');
    assertLe(
      sgho.yieldIndex(),
      singleAccrual + _checkpointExcessBound(singleAccrual, rate, elapsed, 11),
      'Checkpoints added too much yield'
    );
  }

  // ========================================
  // CONTINUOUS COMPOUNDING TESTS
  // ========================================

  function test_yield_growthRoundsDown_oneYear() external {
    // One year at the 10% rate from setUp, checkpointed from RAY: the stored index is the growth
    // factor itself. Exactly 1.1051666...6, where half-up rounding (as in Aave v3) gives ...7
    vm.warp(block.timestamp + 365 days);
    vm.prank(yManager);
    sgho.setTargetRate(1000, block.timestamp.toUint40());
    assertEq(sgho.yieldIndex(), 1105166666666666666666666666, 'growth not rounded down');
  }

  function test_yield_growthRoundsDown_oneDay() external {
    vm.prank(yManager);
    sgho.setTargetRate(450, block.timestamp.toUint40());
    assertEq(sgho.yieldIndex(), RAY, 'index moved');

    // One day at 4.5% from RAY, where half-up rounding (as in Aave v3) gives ...977
    vm.warp(block.timestamp + 1 days);
    vm.prank(yManager);
    sgho.setTargetRate(450, block.timestamp.toUint40());
    assertEq(sgho.yieldIndex(), 1000123295271470141407701976, 'growth not rounded down');
  }

  function test_yield_growthRoundsDown_innerProduct() external {
    vm.prank(yManager);
    sgho.setTargetRate(450, block.timestamp.toUint40());

    // An elapsed time where only the inner `x * x / 6` product decides the last digit: rounding it
    // half up gives ...778
    vm.warp(block.timestamp + 36979993);
    vm.prank(yManager);
    sgho.setTargetRate(450, block.timestamp.toUint40());
    assertEq(sgho.yieldIndex(), 1054184987980041905847125777, 'inner product not rounded down');
  }

  function test_yield_growthMatchesModel_fuzz(uint16 rate, uint256 elapsed) external {
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16();
    elapsed = bound(elapsed, 1, 1000 * 365 days);
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());
    uint256 startIndex = sgho.yieldIndex();

    // Half-up rounding differs from the model for most inputs
    vm.warp(block.timestamp + elapsed);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(startIndex, rate, elapsed),
      'growth differs from the round-down model'
    );
  }

  /// @dev Over every timestamp a `uint40` can hold, the unchecked growth factor matches the
  /// model, which uses checked arithmetic, or the index overflows `uint120` and reverts
  function test_yield_growthMatchesModelOrReverts_fullRange_fuzz(
    uint16 rate,
    uint256 elapsed
  ) external {
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16();
    elapsed = bound(elapsed, 1, type(uint40).max - block.timestamp);
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());
    uint256 startIndex = sgho.yieldIndex();

    vm.warp(block.timestamp + elapsed);
    uint256 expected = _emulateYieldIndex(startIndex, rate, elapsed);
    if (expected > type(uint120).max) {
      vm.expectRevert(
        abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 120, expected)
      );
      sgho.convertToAssets(RAY);
    } else {
      assertEq(sgho.convertToAssets(RAY), expected, 'growth differs from the model');
    }
  }

  function test_yield_growthAtMaxTimestamp() external {
    uint256 elapsed = type(uint40).max - block.timestamp;

    // At 0.01% the index still fits in `uint120` at the last `uint40` timestamp
    vm.prank(yManager);
    sgho.setTargetRate(1, block.timestamp.toUint40());
    vm.warp(type(uint40).max);
    assertEq(sgho.convertToAssets(RAY), _emulateYieldIndex(RAY, 1, elapsed), 'growth mismatch');

    // At the maximum rate it does not, and conversions revert instead of wrapping
    vm.warp(block.timestamp - elapsed);
    vm.prank(yManager);
    sgho.setTargetRate(MAX_SAFE_RATE, block.timestamp.toUint40());
    vm.warp(type(uint40).max);
    uint256 expected = _emulateYieldIndex(sgho.yieldIndex(), MAX_SAFE_RATE, elapsed);
    vm.expectRevert(
      abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 120, expected)
    );
    sgho.convertToAssets(RAY);
  }

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

  function test_yield_oneYearAtTenPercent() external {
    // Rate is 10% (set in setUp)
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    vm.warp(block.timestamp + 365 days);

    _assertGrowth(sgho.convertToAssets(RAY), GROWTH_10_PERCENT_1_YEAR, 'index after one year');
    _assertAssetsGrown(
      sgho.previewRedeem(shares),
      100 ether,
      GROWTH_10_PERCENT_1_YEAR,
      'One year at 10% compounded continuously'
    );
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
    _assertAssetsGrown(
      sgho.previewRedeem(shares),
      100 ether,
      GROWTH_10_PERCENT_1_YEAR,
      'Many actions must not affect the applied rate'
    );
  }

  function test_yield_compoundsOverMultipleYears() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // Two years at 10% with no rate change compound to about 22.14%
    vm.warp(block.timestamp + 730 days);

    _assertGrowth(sgho.convertToAssets(RAY), GROWTH_10_PERCENT_2_YEARS, 'index after two years');
    _assertAssetsGrown(
      sgho.previewRedeem(shares),
      100 ether,
      GROWTH_10_PERCENT_2_YEARS,
      'Two years at 10% compounded continuously'
    );
  }

  function test_yield_rateChange() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // One year at the 10% rate set in setUp
    vm.warp(block.timestamp + 365 days);

    // Switch to 20% for another year
    vm.prank(yManager);
    sgho.setTargetRate(2000, block.timestamp.toUint40());
    vm.warp(block.timestamp + 365 days);

    // The growth of each period multiplies: (1 + 10% / year) ^ year * (1 + 20% / year) ^ year
    _assertGrowth(sgho.convertToAssets(RAY), GROWTH_10_THEN_20_PERCENT, 'index after rate change');
    _assertAssetsGrown(
      sgho.previewRedeem(shares),
      100 ether,
      GROWTH_10_THEN_20_PERCENT,
      'Each period must compound at its own rate'
    );
  }

  function test_yield_rateAppliesToValueAtDeposit() external {
    // Move the index well away from RAY: two years at 50%
    vm.prank(yManager);
    sgho.setTargetRate(5000, block.timestamp.toUint40());
    vm.warp(block.timestamp + 730 days);
    vm.prank(yManager);
    sgho.setTargetRate(1000, block.timestamp.toUint40());

    uint256 depositAmount = 100 ether;
    vm.prank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 shares = sgho.balanceOf(user1);

    vm.warp(block.timestamp + 365 days);

    // One year at 10% on 100 GHO, regardless of the index at deposit time. Shares round down on
    // deposit, which costs at most one share, worth about 3 wei at this index
    _assertGrowth(sgho.convertToAssets(RAY), GROWTH_50_THEN_10_PERCENT, 'index after three years');
    assertApproxEqAbs(
      sgho.previewRedeem(shares),
      (depositAmount * GROWTH_10_PERCENT_1_YEAR) / RAY,
      4,
      'Rate must apply to the deposited value'
    );
  }

  function test_yield_rateAppliesToValueAtCheckpoint_fuzz(
    uint16 rate,
    uint32 timeBeforeDeposit
  ) external {
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16();
    timeBeforeDeposit = (bound(timeBeforeDeposit, 0, 3650 days)).toUint32();

    // Let the index drift away from RAY at the 10% rate from setUp, then checkpoint at `rate`
    vm.warp(block.timestamp + timeBeforeDeposit);
    vm.prank(yManager);
    sgho.setTargetRate(rate, block.timestamp.toUint40());

    uint256 depositAmount = 100 ether;
    vm.prank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 shares = sgho.balanceOf(user1);
    uint256 assetsAtDeposit = sgho.previewRedeem(shares);

    vm.warp(block.timestamp + 365 days);

    // One year later the position grew by one year of `rate`, up to share rounding (at most the
    // growth factor, below 1.65, plus 1 wei)
    assertApproxEqAbs(
      sgho.previewRedeem(shares),
      (assetsAtDeposit * _emulateYieldIndex(RAY, rate, 365 days)) / RAY,
      3,
      'Rate must apply to the value at deposit'
    );
  }

  function test_yield_lateDepositorDrift_fuzz(uint32 delay) external {
    delay = (bound(delay, 1, 10 * 365 days)).toUint32();

    // A depositor right at the rate change, at the 10% rate from setUp
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 earlyShares = sgho.balanceOf(user1);
    uint256 earlyAtDeposit = sgho.previewRedeem(earlyShares);

    // A later depositor, with no checkpoint in between
    vm.warp(block.timestamp + delay);
    vm.prank(user2);
    sgho.deposit(100 ether, user2);
    uint256 lateShares = sgho.balanceOf(user2);
    uint256 lateAtDeposit = sgho.previewRedeem(lateShares);

    // The early depositor's first year, for comparison
    uint256 earlyAfterOneYear = (earlyAtDeposit * GROWTH_10_PERCENT_1_YEAR) / RAY;

    vm.warp(block.timestamp + 365 days);
    uint256 lateAfterOneYear = sgho.previewRedeem(lateShares);

    // The approximation falls further below `e^x` as `x` grows, so the late depositor's year earns
    // slightly less, never more, up to share rounding (at most the growth factor plus 1 wei)
    assertLe(
      lateAfterOneYear * earlyAtDeposit,
      (earlyAfterOneYear + 3) * lateAtDeposit,
      'Late depositor earned more'
    );
    // Depositing 10 years in, the worst case here, the year still grows by about 9.76% instead
    // of 10.52%
    assertGe(lateAfterOneYear, (lateAtDeposit * 1097) / 1000, 'Late depositor drift too large');
  }

  function test_yield_441bps_paysAtLeast4_5PercentApy_fuzz(uint32 delay) external {
    delay = (bound(delay, 0, 4 * 365 days)).toUint32();
    vm.prank(yManager);
    sgho.setTargetRate(441, block.timestamp.toUint40());

    // Deposit up to 4 years after the rate was set, with no checkpoint in between
    vm.warp(block.timestamp + delay);
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);
    uint256 assetsAtDeposit = sgho.previewRedeem(shares);

    vm.warp(block.timestamp + 365 days);

    // The worst case, depositing 4 years in, earns about 4.504% over the following year
    assertGe(
      sgho.previewRedeem(shares),
      (assetsAtDeposit * 10450) / 10000,
      'Year at 441 bps below 4.5%'
    );
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
    sgho.setTargetRate(2000, block.timestamp.toUint40());

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

  function test_yield_rateSetToZeroFreezesIndex() external {
    // Accrue at the 10% rate from setUp, then stop accrual
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    vm.warp(block.timestamp + 180 days);
    vm.prank(yManager);
    sgho.setTargetRate(0, block.timestamp.toUint40());

    // Setting the rate to 0 checkpoints the yield accrued so far
    uint256 frozenIndex = _emulateYieldIndex(RAY, 1000, 180 days);
    assertEq(sgho.yieldIndex(), frozenIndex, 'accrual not checkpointed');
    uint256 frozenAssets = sgho.previewRedeem(shares);

    // Nothing accrues afterwards
    vm.warp(block.timestamp + 365 days);
    assertEq(sgho.convertToAssets(RAY), frozenIndex, 'index moved at rate 0');
    assertEq(sgho.previewRedeem(shares), frozenAssets, 'value moved at rate 0');
  }

  function test_yield_longHorizonLiveness() external {
    vm.prank(yManager);
    sgho.setTargetRate(MAX_SAFE_RATE, block.timestamp.toUint40());
    vm.prank(user1);
    sgho.deposit(10 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // 100 years at the maximum rate without a checkpoint: the polynomial stays far below the
    // uint120 limit of the index, so conversions keep working
    vm.warp(block.timestamp + 100 * 365 days);
    uint256 index = _emulateYieldIndex(RAY, MAX_SAFE_RATE, 100 * 365 days);
    assertEq(sgho.convertToAssets(RAY), index, 'index mismatch');

    // Fund the accrued yield, then check deposits and redemptions still work
    deal(address(gho), address(sgho), sgho.totalAssets() + 1 ether, true);
    vm.prank(user2);
    sgho.deposit(1 ether, user2);
    assertGt(sgho.balanceOf(user2), 0, 'deposit minted no shares');

    vm.prank(user1);
    uint256 assets = sgho.redeem(shares, user1, user1);
    assertEq(assets, (shares * index) / RAY, 'redeemed assets mismatch');
  }

  function test_yield_zeroTargetRate() external {
    // Set target rate to 0
    vm.startPrank(yManager);
    sgho.setTargetRate(0, block.timestamp.toUint40());
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
    sgho.setTargetRate(5000, block.timestamp.toUint40()); // 50% annual rate to ensure significant yield
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

    // Yield accrues even at supply cap: one year at 50% compounded continuously
    assertTrue(
      sgho.totalAssets() > totalAssetsBefore - 1,
      'Yield should accrue even at supply cap'
    );
    _assertGrowth(sgho.convertToAssets(RAY), GROWTH_50_PERCENT_1_YEAR, 'index after a year at 50%');

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
    uint16 targetRate = 1000; // 10% annual rate
    uint256 timeSinceLastUpdate = 365 days; // 1 year
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);

    // One year at 10% compounded continuously
    _assertGrowth(newYieldIndex, GROWTH_10_PERCENT_1_YEAR, 'Yield index after one year at 10%');
  }

  function test_precision_yieldIndex_granularTime() external pure {
    // Test with very small time increments
    uint256 prevYieldIndex = 1e27;
    uint16 targetRate = 1000; // 10% annual rate

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
    uint16 targetRate = 1000; // 10% annual rate

    uint256 singleUpdate = _emulateYieldIndex(prevYieldIndex, targetRate, 30 days);

    uint256 cumulativeIndex = prevYieldIndex;
    for (uint256 i = 0; i < 30; i++) {
      cumulativeIndex = _emulateYieldIndex(cumulativeIndex, targetRate, 1 days);
    }

    // Checkpoints only add yield, by at most the gap between the approximation and `e^x`
    assertGe(cumulativeIndex + 30 * 6 * 9, singleUpdate, 'Checkpoints removed yield');
    assertLe(
      cumulativeIndex,
      singleUpdate + _checkpointExcessBound(singleUpdate, targetRate, 30 days, 30),
      'Checkpoints added too much yield'
    );
  }

  function test_precision_yieldIndex_edgeCases() external pure {
    // Test minimum non-zero yield index
    uint256 minYieldIndex = _emulateYieldIndex(1, 1, 1);
    assertTrue(minYieldIndex >= 1, 'Should not underflow with minimum values');

    // Test with yield index exactly at RAY
    uint256 rayYieldIndex = _emulateYieldIndex(RAY, 1000, 1 days);
    assertTrue(rayYieldIndex > RAY, 'Should grow from RAY baseline');

    // Maximum safe rate for a full year, compounded continuously
    uint256 maxRateIndex = _emulateYieldIndex(RAY, MAX_SAFE_RATE, 365 days);
    _assertGrowth(maxRateIndex, GROWTH_50_PERCENT_1_YEAR, 'Max rate for 1 year');
  }

  function test_precision_yieldIndex_fuzz(uint256 timeSkip, uint16 rate) external pure {
    // Bound inputs to reasonable ranges
    timeSkip = bound(timeSkip, 1, 365 days * 10); // 1 second to 10 years
    rate = (bound(rate, 1, MAX_SAFE_RATE)).toUint16(); // 0.01% to 50%

    uint256 prevYieldIndex = RAY;
    uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);

    // Basic invariants
    assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should never decrease');
    assertTrue(newYieldIndex <= type(uint256).max, 'Should not overflow');

    // Compounding grows at least as fast as simple interest, and at most like continuous
    // compounding: e^(50% * 10 years) is below 149, and the approximation stays below it
    assertGe(
      newYieldIndex,
      prevYieldIndex + (prevYieldIndex * rate * timeSkip) / (10000 * 365 days),
      'Growth below simple interest'
    );
    assertLe(newYieldIndex, prevYieldIndex * 149, 'Growth above continuous compounding');
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
    sgho.setTargetRate(rate, block.timestamp.toUint40());
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

    // Each checkpoint applies the rate to a higher base, so growth per period increases
    assertGt(growth2, growth1, 'Growth must increase with the base');
    assertGt(growth3, growth2, 'Growth must increase with the base');
  }

  // ========================================
  // EVENT TESTS
  // ========================================

  function test_ExchangeRateUpdatedEvent_basic() external {
    // Set a target rate to ensure yield accrual
    vm.startPrank(yManager);
    sgho.setTargetRate(1000, block.timestamp.toUint40()); // 10% annual rate
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
    sgho.setTargetRate(1000, block.timestamp.toUint40());

    // Verify yield index has increased
    uint256 newYieldIndex = sgho.yieldIndex();
    assertTrue(newYieldIndex > initialYieldIndex, 'Yield index should increase after time passes');
    assertEq(sgho.lastUpdate(), block.timestamp, 'Last update should be current timestamp');
  }
}
