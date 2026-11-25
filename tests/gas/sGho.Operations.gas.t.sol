// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../unit/TestSGhoBase.t.sol';

/// forge-config: default.isolate = true
contract sGhoOperations_Gas_Tests is TestSGhoBase {
  uint256 internal constant AMOUNT = 1_000 ether;

  function setUp() public override {
    super.setUp();
    // Seed a position and let yield accrue so the measured actions hit the common, warm path
    vm.prank(user1);
    sgho.deposit(AMOUNT, user1);
    vm.warp(block.timestamp + 30 days);
  }

  function test_gas_deposit() external {
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit');
  }

  function test_gas_deposit_1Year() external {
    _warpSinceCheckpoint(365 days);
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: 1 year');
  }

  function test_gas_deposit_5Years() external {
    _warpSinceCheckpoint(5 * 365 days);
    _deposit();
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: 5 years');
  }

  function test_gas_mint() external {
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint');
  }

  function test_gas_mint_1Year() external {
    _warpSinceCheckpoint(365 days);
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint: 1 year');
  }

  function test_gas_mint_5Years() external {
    _warpSinceCheckpoint(5 * 365 days);
    _mint();
    vm.snapshotGasLastCall('sGho.Operations', 'mint: 5 years');
  }

  function test_gas_withdraw() external {
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw');
  }

  function test_gas_withdraw_1Year() external {
    _warpSinceCheckpoint(365 days);
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw: 1 year');
  }

  function test_gas_withdraw_5Years() external {
    _warpSinceCheckpoint(5 * 365 days);
    _withdraw();
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw: 5 years');
  }

  function test_gas_redeem() external {
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem');
  }

  function test_gas_redeem_1Year() external {
    _warpSinceCheckpoint(365 days);
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem: 1 year');
  }

  function test_gas_redeem_5Years() external {
    _warpSinceCheckpoint(5 * 365 days);
    _redeem();
    vm.snapshotGasLastCall('sGho.Operations', 'redeem: 5 years');
  }

  function test_gas_transfer() external {
    vm.prank(user1);
    sgho.transfer(user2, AMOUNT / 2);
    vm.snapshotGasLastCall('sGho.Operations', 'transfer');
  }

  function test_gas_setTargetRate() external {
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate');
  }

  function test_gas_setTargetRate_1Year() external {
    _warpSinceCheckpoint(365 days);
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: 1 year');
  }

  function test_gas_setTargetRate_5Years() external {
    _warpSinceCheckpoint(5 * 365 days);
    _setTargetRate();
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: 5 years');
  }

  /// @dev The measured actions read the index compounded over `elapsed` seconds.
  function _warpSinceCheckpoint(uint256 elapsed) internal {
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
    sgho.setTargetRate(2000);
  }
}
