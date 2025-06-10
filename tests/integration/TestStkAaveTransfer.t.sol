// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {MockStakedToken} from '../mocks/MockStakedToken.sol';

contract TestStkAaveTransfer is TestnetProcedures {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  uint256 public constant COLLATERAL_AMOUNT = 1000e18;
  uint256 public constant BORROW_AMOUNT = 1000e18;
  uint256 public constant STK_AAVE_AMOUNT = 10e18;

  uint256 public discountRate;
  uint256 public ghoDiscountedPerDiscountToken;
  uint256 public minDiscountTokenBalance;

  function setUp() public override {
    super.setUp();

    discountRate = ghoContracts.ghoDiscountRateStrategy.DISCOUNT_RATE();
    ghoDiscountedPerDiscountToken = ghoContracts
      .ghoDiscountRateStrategy
      .GHO_DISCOUNTED_PER_DISCOUNT_TOKEN();
    minDiscountTokenBalance = ghoContracts.ghoDiscountRateStrategy.MIN_DISCOUNT_TOKEN_BALANCE();

    vm.startPrank(charlie);
    IERC20(tokenList.aave).approve(tokenList.stkAave, STK_AAVE_AMOUNT);
    MockStakedToken(tokenList.stkAave).stake(charlie, STK_AAVE_AMOUNT);
    vm.stopPrank();
  }

  function test_transfer_StkAaveToGhoBorrower() public {
    vm.startPrank(charlie);
    IERC20(tokenList.stkAave).transfer(bob, STK_AAVE_AMOUNT);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, charlie, 0);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, charlie);
    vm.stopPrank();

    uint256 debtBalanceBefore = ghoVariableDebtToken.balanceOf(charlie);

    vm.prank(bob);
    IERC20(tokenList.stkAave).transfer(charlie, STK_AAVE_AMOUNT);

    uint256 debtBalanceAfter = ghoVariableDebtToken.balanceOf(charlie);

    assertGe(debtBalanceAfter, debtBalanceBefore);
  }

  function test_transfer_StkAaveFromGhoHolderToNonGhoHolder() public {
    vm.startPrank(charlie);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, charlie, 0);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, charlie);
    vm.stopPrank();

    uint256 charlieScaledBefore = ghoVariableDebtToken.scaledBalanceOf(charlie);

    skip(365 days);

    uint256 charlieDiscountPercentBefore = ghoVariableDebtToken.getDiscountPercent(charlie);

    assertEq(ghoVariableDebtToken.getBalanceFromInterest(charlie), 0);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);

    vm.prank(charlie);
    IERC20(tokenList.stkAave).transfer(bob, STK_AAVE_AMOUNT);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 charlieExpectedBalanceNoDiscount = charlieScaledBefore.rayMul(expectedBorrowIndex);
    uint256 charlieBalanceIncrease = charlieExpectedBalanceNoDiscount - BORROW_AMOUNT;
    uint256 charlieExpectedDiscount = charlieBalanceIncrease.percentMul(
      charlieDiscountPercentBefore
    );
    uint256 charlieExpectedBalance = charlieExpectedBalanceNoDiscount - charlieExpectedDiscount;
    uint256 charlieBalanceIncreaseWithDiscount = charlieBalanceIncrease - charlieExpectedDiscount;

    assertEq(ghoVariableDebtToken.balanceOf(charlie), charlieExpectedBalance);

    assertEq(
      ghoVariableDebtToken.getBalanceFromInterest(charlie),
      charlieBalanceIncreaseWithDiscount
    );
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
  }
}
