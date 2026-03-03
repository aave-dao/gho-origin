// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoERC20 is TestSGhoBase {
  // ========================================
  // ERC20 STANDARD FUNCTIONALITY TESTS
  // ========================================

  function test_transfer() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    uint256 transferAmount = 50 ether;
    bool success = sgho.transfer(user2, transferAmount);

    assertTrue(success, 'Transfer should succeed');
    assertEq(
      sgho.balanceOf(user1),
      depositAmount - transferAmount,
      'Sender balance should decrease'
    );
    assertEq(sgho.balanceOf(user2), transferAmount, 'Receiver balance should increase');
    vm.stopPrank();
  }

  function test_transfer_zeroAmount() external {
    vm.startPrank(user1);
    sgho.deposit(100 ether, user1);
    bool success = sgho.transfer(user2, 0);
    assertTrue(success, 'transfer of 0 should succeed');
    vm.stopPrank();
  }

  function test_transferFrom() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    uint256 approveAmount = 50 ether;
    sgho.approve(user2, approveAmount);
    vm.stopPrank();

    vm.startPrank(user2);
    uint256 transferAmount = 30 ether;
    bool success = sgho.transferFrom(user1, user2, transferAmount);

    assertTrue(success, 'TransferFrom should succeed');
    assertEq(
      sgho.balanceOf(user1),
      depositAmount - transferAmount,
      'Owner balance should decrease'
    );
    assertEq(sgho.balanceOf(user2), transferAmount, 'Receiver balance should increase');
    assertEq(
      sgho.allowance(user1, user2),
      approveAmount - transferAmount,
      'Allowance should decrease'
    );
    vm.stopPrank();
  }

  function test_transferFrom_zeroAmount() external {
    vm.startPrank(user1);
    sgho.deposit(100 ether, user1);
    sgho.approve(user2, 100 ether);
    vm.stopPrank();
    vm.startPrank(user2);
    bool success = sgho.transferFrom(user1, user2, 0);
    assertTrue(success, 'transferFrom of 0 should succeed');
    vm.stopPrank();
  }

  function test_approve() external {
    vm.startPrank(user1);
    uint256 approveAmount = 100 ether;
    bool success = sgho.approve(user2, approveAmount);

    assertTrue(success, 'Approve should succeed');
    assertEq(sgho.allowance(user1, user2), approveAmount, 'Allowance should be set correctly');
    vm.stopPrank();
  }

  function test_approve_zeroAmount() external {
    vm.startPrank(user1);
    bool success = sgho.approve(user2, 0);
    assertTrue(success, 'approve of 0 should succeed');
    assertEq(sgho.allowance(user1, user2), 0, 'allowance should be 0');
    vm.stopPrank();
  }

  function test_transfer_maxType() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    // Try to transfer max uint256 - should revert due to insufficient balance
    vm.expectRevert();
    sgho.transfer(user2, type(uint256).max);
    vm.stopPrank();
  }

  function test_transferFrom_maxType() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    sgho.approve(user2, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(user2);
    // Try to transferFrom max uint256 - should revert due to insufficient balance
    vm.expectRevert();
    sgho.transferFrom(user1, user2, type(uint256).max);
    vm.stopPrank();
  }

  function test_approve_maxType() external {
    vm.startPrank(user1);
    // Approve max uint256 should succeed
    bool success = sgho.approve(user2, type(uint256).max);
    assertTrue(success, 'approve of max uint256 should succeed');
    assertEq(sgho.allowance(user1, user2), type(uint256).max, 'allowance should be max uint256');
    vm.stopPrank();
  }

  function test_allowance() external {
    vm.startPrank(user1);
    uint256 approveAmount = 100 ether;
    sgho.approve(user2, approveAmount);
    vm.stopPrank();

    assertEq(sgho.allowance(user1, user2), approveAmount, 'Allowance should return correct amount');
    assertEq(sgho.allowance(user1, user1), 0, 'Self allowance should be zero');
  }
}
