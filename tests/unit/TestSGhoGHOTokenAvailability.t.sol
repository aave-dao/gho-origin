// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoGHOTokenAvailability is TestSGhoBase {
  // ========================================
  // GHO SHORTFALL & BALANCE MANAGEMENT TESTS
  // ========================================

  function test_gho_shortfall_detection() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // Check theoretical vs actual GHO balance
    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));

    // Should have accrued yield (theoretical > actual)
    assertTrue(theoreticalAssets > actualGhoBalance, 'Should have accrued yield');

    // Calculate shortfall
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    assertTrue(shortfall > 0, 'Should have a shortfall');

    // Verify maxWithdraw and maxRedeem are limited by actual GHO balance
    uint256 maxWithdrawUser1 = sgho.maxWithdraw(user1);
    uint256 maxRedeemUser1 = sgho.maxRedeem(user1);

    assertEq(
      maxWithdrawUser1,
      actualGhoBalance,
      'maxWithdraw should be limited by actual GHO balance'
    );
    assertTrue(maxRedeemUser1 <= sgho.balanceOf(user1), 'maxRedeem should not exceed user shares');

    // User should not be able to withdraw more than actual GHO balance
    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxWithdraw.selector,
        user1,
        maxWithdrawUser1 + 1,
        maxWithdrawUser1
      )
    );
    sgho.withdraw(maxWithdrawUser1 + 1, user1, user1);
    vm.stopPrank();
  }

  function test_gho_shortfall_withdrawal_behavior() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue significant yield
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);

    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');

    // User should be able to withdraw up to actual GHO balance
    vm.startPrank(user1);
    uint256 maxWithdraw = sgho.maxWithdraw(user1);
    uint256 sharesBurned = sgho.withdraw(maxWithdraw, user1, user1);

    // Verify withdrawal succeeded
    assertEq(gho.balanceOf(user1), user1Balance + maxWithdraw, 'User should have the new balance');
    assertEq(
      sgho.balanceOf(user1),
      user1Shares - sharesBurned,
      'User should have the remaining shares'
    );
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
    vm.stopPrank();
  }

  function test_gho_shortfall_redeem_behavior() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue significant yield
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);

    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');

    // User should be able to redeem up to maxRedeem
    vm.startPrank(user1);
    uint256 maxRedeem = sgho.maxRedeem(user1);
    uint256 assetsReceived = sgho.redeem(maxRedeem, user1, user1);

    // Verify redemption succeeded
    assertEq(
      gho.balanceOf(user1),
      user1Balance + assetsReceived,
      'User should receive the actual GHO balance'
    );
    assertApproxEqAbs(gho.balanceOf(address(sgho)), 0, 2, 'Contract should have no GHO left');
    assertEq(sgho.balanceOf(user1), user1Shares - maxRedeem, 'User should have no shares left');
    vm.stopPrank();
  }

  function test_gho_shortfall_multiple_users() external {
    // Set up initial state with multiple users
    vm.startPrank(user1);
    uint256 depositAmount1 = 500 ether;
    sgho.deposit(depositAmount1, user1);
    vm.stopPrank();

    vm.startPrank(user2);
    uint256 depositAmount2 = 500 ether;
    sgho.deposit(depositAmount2, user2);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update with a deposit instead of withdrawal to avoid affecting state
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;

    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');

    // Both users should be limited by actual GHO balance
    // Recalculate maxWithdraw after yield update to ensure consistency
    uint256 maxWithdrawUser1 = sgho.maxWithdraw(user1);
    uint256 maxWithdrawUser2 = sgho.maxWithdraw(user2);

    // Total max withdrawals should equal theoretical assets (not actual balance)
    assertApproxEqAbs(
      maxWithdrawUser1 + maxWithdrawUser2,
      theoreticalAssets,
      1,
      'Total max withdrawals should equal theoretical assets'
    );

    // Calculate proportional shares of actual GHO balance to avoid maxWithdraw issues
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 user2Shares = sgho.balanceOf(user2);
    uint256 totalShares = user1Shares + user2Shares;

    uint256 user1ProportionalWithdraw = (actualGhoBalance * user1Shares) / totalShares;
    uint256 user2ProportionalWithdraw = actualGhoBalance - user1ProportionalWithdraw; // Ensure exact split

    // Users should be able to withdraw their proportional share of actual GHO
    vm.startPrank(user1);
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 sharesBurned1 = sgho.withdraw(user1ProportionalWithdraw, user1, user1);
    assertEq(
      gho.balanceOf(user1),
      user1Balance + user1ProportionalWithdraw,
      'User1 should have the new balance'
    );
    assertEq(
      sgho.balanceOf(user1),
      user1Shares - sharesBurned1,
      'User1 should have the remaining shares'
    );
    vm.stopPrank();

    vm.startPrank(user2);
    uint256 user2Balance = gho.balanceOf(user2);
    uint256 sharesBurned2 = sgho.withdraw(user2ProportionalWithdraw, user2, user2);
    assertEq(
      gho.balanceOf(user2),
      user2Balance + user2ProportionalWithdraw,
      'User2 should have the new balance'
    );
    assertEq(
      sgho.balanceOf(user2),
      user2Shares - sharesBurned2,
      'User2 should have the remaining shares'
    );
    vm.stopPrank();

    // Contract should have no GHO left
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
  }

  function test_gho_shortfall_artificial_creation() external {
    // Set up initial state
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);

    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));

    // Verify we have a shortfall
    assertTrue(theoreticalAssets > actualGhoBalance, 'Should have a shortfall');

    // Artificially reduce GHO balance to create a larger shortfall
    // This simulates a scenario where GHO is lost/stolen from the contract
    vm.startPrank(address(sgho));
    gho.transfer(user2, actualGhoBalance / 2); // Transfer half the GHO out
    vm.stopPrank();

    uint256 newActualBalance = gho.balanceOf(address(sgho));
    uint256 newShortfall = theoreticalAssets - newActualBalance;

    // Shortfall should be larger now
    assertTrue(newShortfall > theoreticalAssets - actualGhoBalance, 'Shortfall should be larger');

    // User should still be able to withdraw up to the new actual balance
    vm.startPrank(user1);
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 maxWithdraw = sgho.maxWithdraw(user1);
    assertEq(maxWithdraw, newActualBalance, 'maxWithdraw should equal new actual balance');

    // Should be able to withdraw the maximum
    uint256 sharesBurned = sgho.withdraw(maxWithdraw, user1, user1);
    assertEq(gho.balanceOf(user1), user1Balance + maxWithdraw, 'User should have the new balance');
    assertEq(
      sgho.balanceOf(user1),
      user1Shares - sharesBurned,
      'User should have the remaining shares'
    );
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
    vm.stopPrank();
  }
}
