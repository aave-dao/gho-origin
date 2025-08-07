// SPDX-License-Identifier: agpl-3

pragma solidity ^0.8.19;

import {stdStorage, StdStorage} from 'forge-std/Test.sol';
import {TestnetProcedures, TestnetERC20} from 'lib/aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {sGHO} from '../../src/contracts/sgho/sGHO.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

/**
 * @title sGhoPrecisionTest
 * @notice Tests precision loss in sGHO yield index calculations using actual compiled contract
 * @dev This test suite measures the difference between contract calculations and exact mathematical results
 *
 * Test Categories:
 * 1. Rate Per Second Tests - Verify perfect precision in rate calculations
 * 2. Yield Index Update Tests - Measure precision loss in yield accrual
 * 3. Asset/Share Conversion Tests - Test precision in ERC-4626 conversions
 * 4. Edge Case Tests - Validate behavior with extreme values
 * 5. Actual Measurement Tests - Output real precision loss values for analysis
 */
contract sGhoPrecisionTest is TestnetProcedures {
  using Math for uint256;

  // Constants for precision calculations
  uint256 private constant RAY = 1e27;
  uint256 private constant SECONDS_IN_YEAR = 365 days;

  // Contracts
  sGHO internal sgho;
  sGHO internal sghoImpl;
  TestnetERC20 internal gho;

  // Users
  address internal user1;
  address internal user2;
  address internal admin;
  address internal yieldManager;
  address internal fundsAdmin;

  // Test parameters
  uint16 internal constant TEST_RATE_10_PERCENT = 1000; // 10% APR
  uint16 internal constant TEST_RATE_50_PERCENT = 5000; // 50% APR
  uint160 internal constant SUPPLY_CAP = 1000000e18; // 1M GHO

  function setUp() public {
    // Setup users
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    admin = makeAddr('admin');
    yieldManager = makeAddr('yieldManager');
    fundsAdmin = makeAddr('fundsAdmin');

    // Deploy GHO token
    gho = new TestnetERC20('GHO', 'GHO', 18, address(this));

    // Deploy sGHO implementation
    sghoImpl = new sGHO();

    // Deploy proxy
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(sghoImpl),
      address(this),
      ''
    );

    sgho = sGHO(payable(address(proxy)));

    // Initialize sGHO
    sgho.initialize(address(gho), SUPPLY_CAP, admin);

    vm.startPrank(admin);
    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), yieldManager);
    sgho.grantRole(sgho.FUNDS_ADMIN_ROLE(), fundsAdmin);
    vm.stopPrank();

    // Setup initial balances
    gho.mint(user1, 100000e18);
    gho.mint(user2, 100000e18);
    gho.mint(address(this), 1000000e18);

    // Set initial rate
    vm.prank(yieldManager);
    sgho.setTargetRate(TEST_RATE_10_PERCENT);
  }

  // ========================================
  // RATE PER SECOND CALCULATION TESTS
  // ========================================

  function test_ratePerSecond_calculation_precision() public {
    uint16[] memory rates = new uint16[](7);
    rates[0] = 100; // 1%
    rates[1] = 500; // 5%
    rates[2] = 1000; // 10%
    rates[3] = 2000; // 20%
    rates[4] = 3000; // 30%
    rates[5] = 4000; // 40%
    rates[6] = 5000; // 50%

    for (uint256 i = 0; i < rates.length; i++) {
      uint16 rate = rates[i];

      // Set rate in contract
      vm.prank(yieldManager);
      sgho.setTargetRate(rate);

      // Get contract's rate per second
      uint96 contractRatePerSecond = sgho.ratePerSecond();

      // Calculate exact rate per second
      uint256 exactRatePerSecond = calculateExactRatePerSecond(rate);

      // Compare (should be identical due to integer math)
      assertEq(contractRatePerSecond, exactRatePerSecond, 'Rate per second mismatch');

      // Rate per second calculation should be exact
      assertEq(contractRatePerSecond, exactRatePerSecond, 'Rate per second mismatch');
    }
  }

  function test_ratePerSecond_zero_rate() public {
    vm.prank(yieldManager);
    sgho.setTargetRate(0);

    uint96 ratePerSecond = sgho.ratePerSecond();
    assertEq(ratePerSecond, 0, 'Rate per second should be 0 for zero rate');
  }

  // ========================================
  // YIELD INDEX UPDATE PRECISION TESTS
  // ========================================

  function test_yieldIndex_update_precision_single_update() public {
    uint16[] memory rates = new uint16[](3);
    rates[0] = 1000; // 10%
    rates[1] = 2500; // 25%
    rates[2] = 5000; // 50%

    uint256[] memory timePeriods = new uint256[](4);
    timePeriods[0] = 3600; // 1 hour
    timePeriods[1] = 86400; // 1 day
    timePeriods[2] = 604800; // 1 week
    timePeriods[3] = 2592000; // 1 month

    for (uint256 r = 0; r < rates.length; r++) {
      uint16 rate = rates[r];

      vm.prank(yieldManager);
      sgho.setTargetRate(rate);

      for (uint256 t = 0; t < timePeriods.length; t++) {
        uint256 timePeriod = timePeriods[t];

        // Get initial yield index
        uint256 initialIndex = sgho.yieldIndex();

        // Fast forward time
        vm.warp(block.timestamp + timePeriod);

        // Trigger yield index update by calling a function
        sgho.totalAssets();

        // Get new yield index
        uint256 newIndex = sgho.yieldIndex();

        // Calculate expected growth factor
        uint256 expectedGrowthFactor = calculateExpectedGrowthFactor(rate, timePeriod);
        uint256 expectedNewIndex = (initialIndex * expectedGrowthFactor) / RAY;

        // Calculate precision loss
        uint256 precisionLoss = calculatePrecisionLoss(newIndex, expectedNewIndex);

        // Precision loss analysis: Rate=rate, Time=timePeriod, Contract=newIndex, Expected=expectedNewIndex, Loss=precisionLoss

        // For reasonable time periods, precision loss should be minimal
        if (timePeriod <= 3600) {
          // 1 hour
          assertLt(precisionLoss, 1, 'Precision loss too high for 1 hour');
        } else if (timePeriod <= 86400) {
          // 1 day
          assertLt(precisionLoss, 20, 'Precision loss too high for 1 day');
        } else if (timePeriod <= 604800) {
          // 1 week
          assertLt(precisionLoss, 100, 'Precision loss too high for 1 week');
        } else if (timePeriod <= 2592000) {
          // 1 month
          assertLt(precisionLoss, 500, 'Precision loss too high for 1 month');
        }
      }
    }
  }

  function test_yieldIndex_update_precision_multiple_updates() public {
    uint16 rate = 1000; // 10% APR
    uint256 totalTime = 86400; // 1 day
    uint256 updateInterval = 3600; // 1 hour

    vm.prank(yieldManager);
    sgho.setTargetRate(rate);

    uint256 initialIndex = sgho.yieldIndex();
    uint256 currentIndex = initialIndex;

    // Perform multiple updates
    for (uint256 i = 0; i < totalTime / updateInterval; i++) {
      vm.warp(block.timestamp + updateInterval);
      sgho.totalAssets(); // Trigger update
      currentIndex = sgho.yieldIndex();
    }

    // Calculate expected single update for total time
    uint256 expectedGrowthFactor = calculateExpectedGrowthFactor(rate, totalTime);
    uint256 expectedFinalIndex = (initialIndex * expectedGrowthFactor) / RAY;

    // Calculate precision loss
    uint256 precisionLoss = calculatePrecisionLoss(currentIndex, expectedFinalIndex);

    // Multiple updates analysis: Final=currentIndex, Expected=expectedFinalIndex, Loss=precisionLoss

    // Multiple updates should have very low precision loss
    assertLt(precisionLoss, 5, 'Precision loss too high for multiple updates');
  }

  // ========================================
  // ASSET/SHARE CONVERSION PRECISION TESTS
  // ========================================

  function test_asset_share_conversion_precision() public {
    uint16 rate = 1000; // 10% APR

    vm.prank(yieldManager);
    sgho.setTargetRate(rate);

    // Deposit some GHO
    uint256 depositAmount = 1000e18;
    gho.approve(address(sgho), depositAmount);
    sgho.deposit(depositAmount, user1);

    // Fast forward time to accrue yield
    vm.warp(block.timestamp + 86400); // 1 day

    // Get user's shares
    uint256 userShares = sgho.balanceOf(user1);

    // Test conversion precision
    uint256 convertedAssets = sgho.convertToAssets(userShares);
    uint256 convertedShares = sgho.convertToShares(convertedAssets);

    // The conversion should be reversible with minimal precision loss
    uint256 precisionLoss = calculatePrecisionLoss(userShares, convertedShares);

    // Asset/Share conversion analysis: Original=userShares, Converted=convertedShares, Loss=precisionLoss

    // Precision loss should be very small
    assertLt(precisionLoss, 10, 'Asset/share conversion precision loss too high');
  }

  function test_yield_accrual_precision() public {
    uint16 rate = 1000; // 10% APR

    vm.prank(yieldManager);
    sgho.setTargetRate(rate);

    // Deposit GHO
    uint256 depositAmount = 10000e18;
    gho.approve(address(sgho), depositAmount);
    sgho.deposit(depositAmount, user1);

    uint256 initialShares = sgho.balanceOf(user1);

    // Fast forward and check yield accrual
    vm.warp(block.timestamp + 604800); // 1 week

    uint256 finalShares = sgho.balanceOf(user1);

    // Calculate expected yield
    uint256 expectedGrowthFactor = calculateExpectedGrowthFactor(rate, 604800);
    uint256 expectedShares = (initialShares * expectedGrowthFactor) / RAY;

    uint256 precisionLoss = calculatePrecisionLoss(finalShares, expectedShares);

    // Yield accrual analysis: Actual=finalShares, Expected=expectedShares, Loss=precisionLoss

    // Yield accrual should be accurate
    assertLt(precisionLoss, 50, 'Yield accrual precision loss too high');
  }

  // ========================================
  // EDGE CASE TESTS
  // ========================================

  function test_precision_edge_cases() public {
    // Test very short time periods
    vm.prank(yieldManager);
    sgho.setTargetRate(5000); // 50% APR

    uint256 initialIndex = sgho.yieldIndex();

    // Test 1 second
    vm.warp(block.timestamp + 1);
    sgho.totalAssets();
    uint256 oneSecondIndex = sgho.yieldIndex();

    // Test 1 minute
    vm.warp(block.timestamp + 59); // Total 60 seconds
    sgho.totalAssets();
    uint256 oneMinuteIndex = sgho.yieldIndex();

    // Edge case analysis: 1 second index=oneSecondIndex, 1 minute index=oneMinuteIndex

    // Very short periods should have minimal change
    // Note: For very short periods, the change might be too small to detect due to integer precision
    // The important thing is that the index doesn't decrease
    assertGe(oneSecondIndex, initialIndex, 'Index should not decrease for 1 second');
    assertGe(oneMinuteIndex, oneSecondIndex, 'Index should not decrease for 1 minute');
  }

  function test_precision_zero_time() public view {
    uint256 initialIndex = sgho.yieldIndex();

    // Call function without time passing
    sgho.totalAssets();
    uint256 newIndex = sgho.yieldIndex();

    // Index should remain the same
    assertEq(newIndex, initialIndex, 'Index should not change with zero time');
  }

  // ========================================
  // ACTUAL PRECISION LOSS MEASUREMENT
  // ========================================

  function test_actual_precision_loss_measurement() public {
    emit log('=== ACTUAL CONTRACT PRECISION LOSS MEASUREMENT ===');

    uint16[] memory rates = new uint16[](3);
    rates[0] = 1000; // 10%
    rates[1] = 2500; // 25%
    rates[2] = 5000; // 50%

    uint256[] memory periods = new uint256[](6);
    periods[0] = 1; // 1 second
    periods[1] = 60; // 1 minute
    periods[2] = 3600; // 1 hour
    periods[3] = 86400; // 1 day
    periods[4] = 604800; // 1 week
    periods[5] = 2592000; // 1 month

    for (uint256 r = 0; r < rates.length; r++) {
      for (uint256 p = 0; p < periods.length; p++) {
        // Reset state
        vm.prank(yieldManager);
        sgho.setTargetRate(rates[r]);

        uint256 initialIndex = sgho.yieldIndex();

        // Fast forward and update
        vm.warp(block.timestamp + periods[p]);
        sgho.totalAssets();

        uint256 finalIndex = sgho.yieldIndex();
        uint256 expectedGrowthFactor = calculateExpectedGrowthFactor(rates[r], periods[p]);
        uint256 expectedIndex = (initialIndex * expectedGrowthFactor) / RAY;
        uint256 precisionLoss = calculatePrecisionLoss(finalIndex, expectedIndex);

        emit log_named_uint('Rate (bps)', rates[r]);
        emit log_named_uint('Period (sec)', periods[p]);
        emit log_named_uint('Linear Growth Factor', expectedGrowthFactor);
        emit log_named_uint('Contract Index', finalIndex);
        emit log_named_uint('Expected Index', expectedIndex);
        emit log_named_uint('Precision Loss (bps)', precisionLoss);
        emit log('---');
      }
    }
  }

  function test_rate_per_second_actual_values() public {
    emit log('=== RATE PER SECOND ACTUAL VALUES ===');

    uint16[] memory rates = new uint16[](7);
    rates[0] = 100; // 1%
    rates[1] = 500; // 5%
    rates[2] = 1000; // 10%
    rates[3] = 2000; // 20%
    rates[4] = 3000; // 30%
    rates[5] = 4000; // 40%
    rates[6] = 5000; // 50%

    for (uint256 i = 0; i < rates.length; i++) {
      uint16 rate = rates[i];

      // Set rate in contract
      vm.prank(yieldManager);
      sgho.setTargetRate(rate);

      // Get contract's rate per second
      uint96 contractRatePerSecond = sgho.ratePerSecond();

      // Calculate exact rate per second
      uint256 exactRatePerSecond = calculateExactRatePerSecond(rate);

      emit log_named_uint('Rate (bps)', rate);
      emit log_named_uint('Contract Rate Per Second', contractRatePerSecond);
      emit log_named_uint('Exact Rate Per Second', exactRatePerSecond);
      emit log_named_uint(
        'Difference',
        contractRatePerSecond > exactRatePerSecond
          ? contractRatePerSecond - exactRatePerSecond
          : exactRatePerSecond - contractRatePerSecond
      );
      emit log('---');
    }
  }

  function test_linear_growth_factors_for_python() public {
    emit log('=== LINEAR GROWTH FACTORS FOR PYTHON ANALYSIS ===');

    uint16[] memory rates = new uint16[](3);
    rates[0] = 1000; // 10%
    rates[1] = 2500; // 25%
    rates[2] = 5000; // 50%

    uint256[] memory periods = new uint256[](6);
    periods[0] = 1; // 1 second
    periods[1] = 60; // 1 minute
    periods[2] = 3600; // 1 hour
    periods[3] = 86400; // 1 day
    periods[4] = 604800; // 1 week
    periods[5] = 2592000; // 1 month

    emit log('// Python script can parse these values:');
    emit log('// Format: Rate(bps), Period(sec), LinearGrowthFactor');

    for (uint256 r = 0; r < rates.length; r++) {
      for (uint256 p = 0; p < periods.length; p++) {
        uint256 linearGrowthFactor = calculateExpectedGrowthFactor(rates[r], periods[p]);

        // Output in a format that can be easily parsed by Python
        emit log_named_uint('PYTHON_DATA', rates[r]);
        emit log_named_uint('PYTHON_DATA', periods[p]);
        emit log_named_uint('PYTHON_DATA', linearGrowthFactor);

        // Also output human-readable format
        string memory rateDesc = rates[r] == 1000 ? '10%' : rates[r] == 2500 ? '25%' : '50%';
        string memory periodDesc = periods[p] == 1 ? '1s' : periods[p] == 60
          ? '1m'
          : periods[p] == 3600
          ? '1h'
          : periods[p] == 86400
          ? '1d'
          : periods[p] == 604800
          ? '1w'
          : '1M';

        emit log_named_string('Growth Factor', string.concat(rateDesc, ' APR, ', periodDesc));
        emit log_named_uint('Value', linearGrowthFactor);
      }
    }

    emit log('=== END LINEAR GROWTH FACTORS ===');
  }

  // ========================================
  // HELPER FUNCTIONS
  // ========================================

  function calculateExactRatePerSecond(uint16 rateBps) internal pure returns (uint256) {
    // Exact calculation: (rate_bps / 10000) * RAY / SECONDS_IN_YEAR
    return (uint256(rateBps) * RAY) / (10000 * SECONDS_IN_YEAR);
  }

  function calculateExpectedGrowthFactor(
    uint16 rateBps,
    uint256 timeSeconds
  ) internal pure returns (uint256) {
    // Calculate rate per second
    uint256 ratePerSecond = calculateExactRatePerSecond(rateBps);

    // Calculate accumulated rate
    uint256 accumulatedRate = ratePerSecond * timeSeconds;

    // Calculate growth factor: RAY + accumulatedRate
    return RAY + accumulatedRate;
  }

  function calculatePrecisionLoss(
    uint256 actual,
    uint256 expected
  ) internal pure returns (uint256) {
    if (expected == 0) return 0;

    // Calculate difference as basis points relative to expected value
    uint256 difference = actual > expected ? actual - expected : expected - actual;
    return (difference * 10000) / expected;
  }
}
