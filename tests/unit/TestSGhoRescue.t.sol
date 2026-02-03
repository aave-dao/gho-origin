// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoRescue is TestSGhoBase {
  // ========================================
  // EMERGENCY & RESCUE FUNCTIONALITY TESTS
  // ========================================

  function test_emergencyTokenTransfer() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 rescueAmount = 100 ether;

    // Transfer some tokens to sGho
    deal(address(mockToken), address(sgho), rescueAmount, true);

    // TOKEN_RESCUER_ROLE role is already granted to fundsAdmin in setUp()

    // Rescue tokens
    vm.startPrank(fundsAdmin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, rescueAmount);
    vm.stopPrank();

    assertEq(mockToken.balanceOf(user1), rescueAmount, 'Tokens not rescued correctly');
  }

  function test_emergencyTokenTransfer_amountGreaterThanBalance() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 initialAmount = 100 ether;
    uint256 rescueAmount = 200 ether;

    // Transfer some tokens to sGho
    deal(address(mockToken), address(sgho), initialAmount, true);

    // TOKEN_RESCUER_ROLE role is already granted to fundsAdmin in setUp()

    // Rescue tokens
    vm.startPrank(fundsAdmin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, rescueAmount);
    vm.stopPrank();

    assertEq(
      mockToken.balanceOf(user1),
      initialAmount,
      'Rescued amount should be capped at balance'
    );
  }

  function test_revert_emergencyTokenTransfer_notFundsAdmin() external {
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));

    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        user1,
        sgho.TOKEN_RESCUER_ROLE()
      )
    );
    sgho.emergencyTokenTransfer(address(mockToken), user1, 100 ether);
    vm.stopPrank();
  }

  function test_emergencyTokenTransfer_cannotRescueGHO() external {
    // TOKEN_RESCUER_ROLE role is already granted to fundsAdmin in setUp()

    uint256 initialBalance = gho.balanceOf(user1);

    vm.startPrank(fundsAdmin);
    // Should succeed but transfer 0 because maxRescue returns 0 for GHO
    sgho.emergencyTokenTransfer(address(gho), user1, 100 ether);
    vm.stopPrank();

    // Verify that no GHO was transferred
    assertEq(gho.balanceOf(user1), initialBalance, 'No GHO should be transferred');
  }

  function test_emergencyTokenTransfer_zeroAmount() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 initialAmount = 100 ether;

    // Transfer some tokens to sGho
    deal(address(mockToken), address(sgho), initialAmount, true);

    // TOKEN_RESCUER_ROLE role is already granted to fundsAdmin in setUp()

    // Rescue zero amount should be a no-op
    vm.startPrank(fundsAdmin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, 0);
    vm.stopPrank();

    // Token balances should remain unchanged
    assertEq(
      mockToken.balanceOf(address(sgho)),
      initialAmount,
      'Contract balance should remain unchanged'
    );
    assertEq(mockToken.balanceOf(user1), 0, 'User balance should remain unchanged');
  }

  function test_maxRescue() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 tokenAmount = 100 ether;

    // Transfer some tokens to sGho
    deal(address(mockToken), address(sgho), tokenAmount, true);

    // Test maxRescue for non-GHO token
    assertEq(
      sgho.maxRescue(address(mockToken)),
      tokenAmount,
      'maxRescue should return full balance for non-GHO tokens'
    );

    // Test maxRescue for GHO token
    assertEq(sgho.maxRescue(address(gho)), 0, 'maxRescue should return 0 for GHO tokens');
  }
}
