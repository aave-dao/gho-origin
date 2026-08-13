// SPDX-License-Identifier: agpl-3

pragma solidity ^0.8.19;

import {TestnetProcedures, TestnetERC20} from 'lib/aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {sGho} from '../../src/contracts/sgho/sGho.sol';
import {sGhoInstance} from '../../src/contracts/sgho/instances/sGhoInstance.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

/**
 * @title sGhoPrecisionTest
 * @notice Tests precision loss in sGho yield index calculations using actual compiled contract
 * @dev This test suite measures the difference between contract calculations and exact mathematical results
 *
 * Test Categories:
 * 1. Rate Per Second Tests - Verify perfect precision in rate calculations
 * 2. Yield Index Update Tests - Measure precision loss in yield accrual
 * 3. Asset/Share Conversion Tests - Test precision in ERC-4626 conversions
 * 4. Edge Case Tests - Validate behavior with extreme values
 * 5. Actual Measurement Tests - Output real precision loss values for analysis
 */
contract TestSGhoPrecision is TestnetProcedures {
  using Math for uint256;

  // Constants for precision calculations
  uint256 private constant RAY = 1e27;
  uint256 private constant SECONDS_IN_YEAR = 365 days;

  // Contracts
  sGho internal sgho;
  sGhoInstance internal sghoImpl;
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
  uint40 internal constant SUPPLY_CAP_UNITS = 1_000_000; // 1M GHO (whole units, no decimals)

  function setUp() public {
    // Setup users
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    admin = makeAddr('admin');
    yieldManager = makeAddr('yieldManager');
    fundsAdmin = makeAddr('fundsAdmin');

    // Deploy GHO token
    gho = new TestnetERC20('GHO', 'GHO', 18, address(this));

    // Deploy sGho implementation
    sghoImpl = new sGhoInstance();

    // Deploy proxy
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(sghoImpl),
      address(this),
      ''
    );

    sgho = sGho(address(proxy));

    // Initialize sGho
    sGhoInstance(address(sgho)).initialize(address(gho), SUPPLY_CAP_UNITS, admin);

    vm.startPrank(admin);
    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), yieldManager);
    sgho.grantRole(sgho.TOKEN_RESCUER_ROLE(), fundsAdmin);
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

        uint256 initialIndex = sgho.yieldIndex();

        vm.warp(block.timestamp + timePeriod);

        // Re-setting the rate checkpoints the accrued index
        vm.prank(yieldManager);
        sgho.setTargetRate(rate);

        // Linear accrual is exact: newIndex = initialIndex + targetRate * time / year
        assertEq(
          sgho.yieldIndex(),
          initialIndex + calculateAccruedRate(rate, timePeriod),
          'Yield index accrual mismatch'
        );
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
    uint256 intervals = totalTime / updateInterval;

    // Checkpoint the index on every interval
    for (uint256 i = 0; i < intervals; i++) {
      vm.warp(block.timestamp + updateInterval);
      vm.prank(yieldManager);
      sgho.setTargetRate(rate);
    }

    // Each checkpoint accrues one interval; the sum is the contract's exact total
    assertEq(
      sgho.yieldIndex(),
      initialIndex + intervals * calculateAccruedRate(rate, updateInterval),
      'Multiple updates should match the per-interval accrual'
    );
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

    uint256 shares = sgho.balanceOf(user1);

    // Fast forward and check yield accrual
    vm.warp(block.timestamp + 604800); // 1 week

    // Linear growth of the deposited assets over one week, exact to the wei
    uint256 expectedIndex = RAY + calculateAccruedRate(rate, 604800);
    assertEq(
      sgho.previewRedeem(shares),
      (depositAmount * expectedIndex) / RAY,
      'Yield accrual mismatch'
    );
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
    vm.prank(yieldManager);
    sgho.setTargetRate(5000);
    uint256 oneSecondIndex = sgho.yieldIndex();

    // Test 1 minute
    vm.warp(block.timestamp + 59); // Total 60 seconds
    vm.prank(yieldManager);
    sgho.setTargetRate(5000);
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

        // Fast forward and checkpoint
        vm.warp(block.timestamp + periods[p]);
        vm.prank(yieldManager);
        sgho.setTargetRate(rates[r]);

        uint256 finalIndex = sgho.yieldIndex();
        uint256 expectedIndex = initialIndex + calculateAccruedRate(rates[r], periods[p]);
        uint256 precisionLoss = calculatePrecisionLoss(finalIndex, expectedIndex);

        emit log_named_uint('Rate (bps)', rates[r]);
        emit log_named_uint('Period (sec)', periods[p]);
        emit log_named_uint('Contract Index', finalIndex);
        emit log_named_uint('Expected Index', expectedIndex);
        emit log_named_uint('Precision Loss (bps)', precisionLoss);
        emit log('---');
      }
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

  /// @dev Mirrors sGho._getCurrentYieldIndex(): the index accrued over a period at a fixed APR
  function calculateAccruedRate(
    uint16 rateBps,
    uint256 timeSeconds
  ) internal pure returns (uint256) {
    return (uint256(rateBps) * RAY * timeSeconds) / (10000 * SECONDS_IN_YEAR);
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
