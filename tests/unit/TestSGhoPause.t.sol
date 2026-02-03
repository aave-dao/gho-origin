// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoPause is TestSGhoBase {
  // ========================================
  // PAUSABILITY TESTS
  // ========================================

  function test_pausability_deposit_withdraw() external {
    address pauseGuardian = vm.addr(0xBAD);
    sgho.grantRole(sgho.PAUSE_GUARDIAN_ROLE(), pauseGuardian);

    // Pause the contract
    vm.prank(pauseGuardian);
    sgho.pause();

    // Try to deposit while paused
    vm.prank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, user1, 100 ether, 0)
    );
    sgho.deposit(100 ether, user1);

    // Unpause the contract
    vm.prank(pauseGuardian);
    sgho.unpause();

    // Deposit successfully
    vm.prank(user1);
    uint256 shares = sgho.deposit(100 ether, user1);
    assertEq(shares, 100 ether);

    // Pause again
    vm.prank(pauseGuardian);
    sgho.pause();

    // Try to withdraw while paused
    vm.prank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, user1, 50 ether, 0)
    );
    sgho.withdraw(50 ether, user1, user1);

    // Unpause and withdraw
    vm.prank(pauseGuardian);
    sgho.unpause();

    vm.prank(user1);
    sgho.withdraw(50 ether, user1, user1);

    assertEq(
      sgho.convertToAssets(sgho.balanceOf(user1)),
      50 ether,
      'User should have 50 GHO worth of sGho left'
    );
  }

  function test_pausability_admin_functions_work_while_paused() external {
    address pauseGuardian = vm.addr(0xBAD);
    sgho.grantRole(sgho.PAUSE_GUARDIAN_ROLE(), pauseGuardian);

    // Deploy a mock ERC20 token for rescue testing
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 rescueAmount = 100 ether;
    deal(address(mockToken), address(sgho), rescueAmount, true);

    // Pause the contract
    vm.prank(pauseGuardian);
    sgho.pause();

    // Verify contract is paused
    assertTrue(sgho.paused(), 'Contract should be paused');

    // Test 1: Set target rate while paused (should work)
    vm.startPrank(yManager);
    uint16 newRate = 2000; // 20% APR
    sgho.setTargetRate(newRate);
    assertEq(sgho.targetRate(), newRate, 'Target rate should be updated while paused');
    vm.stopPrank();

    // Test 2: Set supply cap while paused (should work)
    vm.startPrank(yManager);
    uint160 newSupplyCap = 2_000_000 ether;
    sgho.setSupplyCap(newSupplyCap);
    assertEq(sgho.supplyCap(), newSupplyCap, 'Supply cap should be updated while paused');
    vm.stopPrank();

    // Test 3: Rescue tokens while paused (should work)
    vm.startPrank(fundsAdmin);
    uint256 initialBalance = mockToken.balanceOf(user1);
    sgho.emergencyTokenTransfer(address(mockToken), user1, rescueAmount);
    assertEq(
      mockToken.balanceOf(user1),
      initialBalance + rescueAmount,
      'Tokens should be rescued while paused'
    );
    vm.stopPrank();

    // Test 4: Verify user operations are still blocked
    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, user1, 100 ether, 0)
    );
    sgho.deposit(100 ether, user1);
    vm.stopPrank();

    // Test 5: Unpause and verify everything works normally
    vm.prank(pauseGuardian);
    sgho.unpause();

    assertFalse(sgho.paused(), 'Contract should be unpaused');

    // User operations should work again
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
  }

  function test_pausability_max_functions_return_zero_when_paused() external {
    address pauseGuardian = vm.addr(0xBAD);
    sgho.grantRole(sgho.PAUSE_GUARDIAN_ROLE(), pauseGuardian);

    // First deposit some amount to have a balance
    vm.prank(user1);
    sgho.deposit(100 ether, user1);

    // Verify max functions return non-zero values when unpaused
    assertTrue(sgho.maxDeposit(user2) > 0, 'maxDeposit should be > 0 when unpaused');
    assertTrue(sgho.maxMint(user2) > 0, 'maxMint should be > 0 when unpaused');
    assertTrue(sgho.maxWithdraw(user1) > 0, 'maxWithdraw should be > 0 when unpaused');
    assertTrue(sgho.maxRedeem(user1) > 0, 'maxRedeem should be > 0 when unpaused');

    // Pause the contract
    vm.prank(pauseGuardian);
    sgho.pause();

    // Verify contract is paused
    assertTrue(sgho.paused(), 'Contract should be paused');

    // All max functions should return 0 when paused
    assertEq(sgho.maxDeposit(user2), 0, 'maxDeposit should return 0 when paused');
    assertEq(sgho.maxMint(user2), 0, 'maxMint should return 0 when paused');
    assertEq(sgho.maxWithdraw(user1), 0, 'maxWithdraw should return 0 when paused');
    assertEq(sgho.maxRedeem(user1), 0, 'maxRedeem should return 0 when paused');

    // Unpause the contract
    vm.prank(pauseGuardian);
    sgho.unpause();

    // Verify contract is unpaused
    assertFalse(sgho.paused(), 'Contract should be unpaused');

    // Max functions should return non-zero values again when unpaused
    assertTrue(sgho.maxDeposit(user2) > 0, 'maxDeposit should be > 0 when unpaused again');
    assertTrue(sgho.maxMint(user2) > 0, 'maxMint should be > 0 when unpaused again');
    assertTrue(sgho.maxWithdraw(user1) > 0, 'maxWithdraw should be > 0 when unpaused again');
    assertTrue(sgho.maxRedeem(user1) > 0, 'maxRedeem should be > 0 when unpaused again');
  }
}
