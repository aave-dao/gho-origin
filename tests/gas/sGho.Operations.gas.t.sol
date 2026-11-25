// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../unit/TestSGhoBase.t.sol';

/// forge-config: default.isolate = true
contract sGhoOperations_Gas_Tests is TestSGhoBase {
  using SafeCast for uint256;

  uint256 internal constant AMOUNT = 1_000 ether;

  function setUp() public override {
    super.setUp();
    // Seed a position and let yield accrue so the measured actions hit the common, warm path
    vm.prank(user1);
    sgho.deposit(AMOUNT, user1);
    _warpSinceRateUpdate(30 days);
  }

  function test_gas_deposit_30Days() external {
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: 30 days since rate update');
  }

  function test_gas_deposit_1Year() external {
    _warpSinceRateUpdate(365 days);
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: 1 year since rate update');
  }

  function test_gas_deposit_5Years() external {
    _warpSinceRateUpdate(5 * 365 days);
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: 5 years since rate update');
  }

  function test_gas_mint_30Days() external {
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint: 30 days since rate update');
  }

  function test_gas_mint_1Year() external {
    _warpSinceRateUpdate(365 days);
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint: 1 year since rate update');
  }

  function test_gas_mint_5Years() external {
    _warpSinceRateUpdate(5 * 365 days);
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint: 5 years since rate update');
  }

  function test_gas_withdraw_30Days() external {
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw: 30 days since rate update');
  }

  function test_gas_withdraw_1Year() external {
    _warpSinceRateUpdate(365 days);
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw: 1 year since rate update');
  }

  function test_gas_withdraw_5Years() external {
    _warpSinceRateUpdate(5 * 365 days);
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw: 5 years since rate update');
  }

  function test_gas_redeem_30Days() external {
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem: 30 days since rate update');
  }

  function test_gas_redeem_1Year() external {
    _warpSinceRateUpdate(365 days);
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem: 1 year since rate update');
  }

  function test_gas_redeem_5Years() external {
    _warpSinceRateUpdate(5 * 365 days);
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem: 5 years since rate update');
  }

  function test_gas_transfer() external {
    vm.prank(user1);
    sgho.transfer(user2, AMOUNT / 2);
    vm.snapshotGasLastCall('sGho.Operations', 'transfer');
  }

  function test_gas_setTargetRate_30Days() external {
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: 30 days since rate update');
  }

  function test_gas_setTargetRate_1Year() external {
    _warpSinceRateUpdate(365 days);
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: 1 year since rate update');
  }

  function test_gas_setTargetRate_5Years() external {
    _warpSinceRateUpdate(5 * 365 days);
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: 5 years since rate update');
  }

  function test_gas_setTargetRate_schedule() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, (block.timestamp + 1 days).toUint40());
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: scheduled');
  }

  function test_gas_setTargetRate_scheduleApplied() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, (block.timestamp + 1 days).toUint40());
    vm.warp(block.timestamp + 2 days);
    vm.prank(yManager);
    sgho.setTargetRate(3000, (block.timestamp + 1 days).toUint40());
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: scheduled, previous applied');
  }

  function test_gas_deposit_pendingRateDue() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, (block.timestamp + 1 days).toUint40());
    vm.warp(block.timestamp + 2 days);
    vm.prank(user2);
    sgho.deposit(AMOUNT, user2);
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: scheduled rate due');
  }

  function test_gas_cancelPendingTargetRate() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, (block.timestamp + 1 days).toUint40());
    vm.prank(yManager);
    sgho.cancelPendingTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'cancelPendingTargetRate');
  }

  /// @dev Warps to `elapsed` seconds after the last rate update, the start of the current accrual.
  function _warpSinceRateUpdate(uint256 elapsed) internal {
    vm.warp(sgho.lastUpdate() + elapsed);
  }

  function _deposit() internal {
    vm.prank(user2);
    sgho.deposit(AMOUNT, user2);
  }

  function _mint() internal {
    vm.prank(user2);
    sgho.mint(AMOUNT, user2);
  }

  function _withdraw() internal {
    vm.prank(user1);
    sgho.withdraw(AMOUNT / 2, user1, user1);
  }

  function _redeem() internal {
    uint256 shares = sgho.balanceOf(user1) / 2;
    vm.prank(user1);
    sgho.redeem(shares, user1, user1);
  }

  function _setTargetRate() internal {
    vm.prank(yManager);
    sgho.setTargetRate(2000, block.timestamp.toUint40());
  }
}
