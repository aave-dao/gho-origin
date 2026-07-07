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
    vm.prank(user2);
    sgho.deposit(AMOUNT, user2);
    vm.snapshotGasLastCall('sGho.Operations', 'deposit');
  }

  function test_gas_mint() external {
    vm.prank(user2);
    sgho.mint(AMOUNT, user2);
    vm.snapshotGasLastCall('sGho.Operations', 'mint');
  }

  function test_gas_withdraw() external {
    vm.prank(user1);
    sgho.withdraw(AMOUNT / 2, user1, user1);
    vm.snapshotGasLastCall('sGho.Operations', 'withdraw');
  }

  function test_gas_redeem() external {
    uint256 shares = sgho.balanceOf(user1) / 2;
    vm.prank(user1);
    sgho.redeem(shares, user1, user1);
    vm.snapshotGasLastCall('sGho.Operations', 'redeem');
  }

  function test_gas_transfer() external {
    vm.prank(user1);
    sgho.transfer(user2, AMOUNT / 2);
    vm.snapshotGasLastCall('sGho.Operations', 'transfer');
  }

  function test_gas_setTargetRate() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp));
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate');
  }

  function test_gas_setTargetRate_schedule() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp + 1 days));
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: scheduled');
  }

  function test_gas_setTargetRate_scheduleApplied() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp + 1 days));
    vm.warp(block.timestamp + 2 days);
    vm.prank(yManager);
    sgho.setTargetRate(3000, uint40(block.timestamp + 1 days));
    vm.snapshotGasLastCall('sGho.Operations', 'setTargetRate: scheduled, previous applied');
  }

  function test_gas_deposit_pendingRateDue() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp + 1 days));
    vm.warp(block.timestamp + 2 days);
    vm.prank(user2);
    sgho.deposit(AMOUNT, user2);
    vm.snapshotGasLastCall('sGho.Operations', 'deposit: scheduled rate due');
  }

  function test_gas_syncYieldIndex() external {
    sgho.syncYieldIndex(uint120(2 * RAY), uint40(block.timestamp - 1 days), 2000);
    vm.snapshotGasLastCall('sGho.Operations', 'syncYieldIndex');
  }
}
