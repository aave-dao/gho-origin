// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IScaledBalanceToken} from 'aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol';
import {IGhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/interfaces/IGhoVariableDebtToken.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {IGhoFacilitator} from 'src/contracts/gho/interfaces/IGhoFacilitator.sol';
import {MockStakedToken} from '../mocks/MockStakedToken.sol';

contract TestDiscountBorrow is TestnetProcedures {
  using WadRayMath for uint256;

  uint256 public constant COLLATERAL_AMOUNT = 1000e18;
  uint256 public constant BORROW_AMOUNT = 1000e18;

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

    vm.prank(bob);
    IERC20(tokenList.aave).approve(tokenList.stkAave, 1000e18);

    vm.prank(bob);
    MockStakedToken(tokenList.stkAave).stake(bob, 10e18);
  }

  function test_Alice_DepositWethBorrowGho() public {
    vm.prank(alice);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, alice, 0);

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(alice, alice, BORROW_AMOUNT, 0, 1e27);

    vm.prank(alice);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), 0);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(alice), BORROW_AMOUNT);
  }

  function test_Alice_InterestAccruedAfter1Year() public {
    test_Alice_DepositWethBorrowGho();

    skip(365 days);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = ghoVariableDebtToken.scaledBalanceOf(alice).rayMul(
      expectedBorrowIndex
    );
    uint256 aliceYear1Debt = ghoVariableDebtToken.balanceOf(alice);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(aliceYear1Debt, aliceExpectedBalance);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
  }

  function test_Bob_DepositWethAfter1YearAndBorrowGho() public {
    test_Alice_InterestAccruedAfter1Year();
    uint256 discountPercentBefore = ghoVariableDebtToken.getDiscountPercent(bob);

    vm.prank(bob);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, bob, 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 discountTokenBalance = IERC20(tokenList.stkAave).balanceOf(bob);
    uint256 discountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      BORROW_AMOUNT,
      discountTokenBalance
    );

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountPercentUpdated(bob, discountPercentBefore, discountPercent);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), bob, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(bob, bob, BORROW_AMOUNT, 0, expectedBorrowIndex);

    vm.prank(bob);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, bob);

    assertEq(ghoVariableDebtToken.getDiscountPercent(bob), discountPercent);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
    assertEq(ghoVariableDebtToken.balanceOf(bob), BORROW_AMOUNT);
  }

  function test_Bob_Wait1MoreYearAndBorrowLessGhoThanDiscountAccrued() public {
    test_Bob_DepositWethAfter1YearAndBorrowGho(); // Bob has already borrowed

    uint256 debtBalanceBeforeTimeskip = ghoVariableDebtToken.balanceOf(bob);

    skip(365 days);

    uint256 balanceBeforeBorrow = ghoContracts.ghoToken.balanceOf(bob);
    uint256 debtBalanceAfterTimeskip = ghoVariableDebtToken.balanceOf(bob);

    uint256 debtIncrease = debtBalanceAfterTimeskip - debtBalanceBeforeTimeskip;

    uint256 discountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      BORROW_AMOUNT,
      IERC20(tokenList.stkAave).balanceOf(bob)
    );

    uint256 expectedDiscount = (debtIncrease * discountPercent) / 10_000; // PERCENTAGE_FACTOR is 10000

    assertGt(expectedDiscount, 1);

    vm.prank(bob);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), 1, 2, 0, bob);

    uint256 balanceAfterBorrow = ghoContracts.ghoToken.balanceOf(bob);

    assertEq(balanceAfterBorrow, balanceBeforeBorrow + 1);
  }

  function test_Alice_IncreaseTime1MoreYearAndBorrowMoreGho() public {
    test_Bob_DepositWethAfter1YearAndBorrowGho();

    // clear logs
    vm.getRecordedLogs();

    uint256 aliceBeforeDebt = ghoVariableDebtToken.scaledBalanceOf(alice);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 bobScaledBefore = ghoVariableDebtToken.scaledBalanceOf(bob);

    // Increase time by another year
    skip(365 days);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();
    uint256 borrowedAmountScaled = BORROW_AMOUNT.rayDiv(expectedBorrowIndex);
    uint256 aliceExpectedBalance = (aliceScaledBefore + borrowedAmountScaled).rayMul(
      expectedBorrowIndex
    );
    uint256 amount = aliceExpectedBalance - BORROW_AMOUNT;
    uint256 aliceBalanceIncrease = amount - BORROW_AMOUNT;

    uint256 bobExpectedBalanceNoDiscount = bobScaledBefore.rayMul(expectedBorrowIndex);
    uint256 bobBalanceIncrease = bobExpectedBalanceNoDiscount - BORROW_AMOUNT;

    uint256 bobDiscountTokenBalance = IERC20(tokenList.stkAave).balanceOf(bob);
    uint256 bobDiscountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      BORROW_AMOUNT,
      bobDiscountTokenBalance
    );
    uint256 bobExpectedDiscount = (bobBalanceIncrease * bobDiscountPercent) / 10_000;
    uint256 bobExpectedBalance = bobExpectedBalanceNoDiscount - bobExpectedDiscount;

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, amount);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(alice, alice, amount, aliceBalanceIncrease, expectedBorrowIndex);
    vm.prank(alice);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);
    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), 0);
    assertEq(ghoVariableDebtToken.getDiscountPercent(bob), bobDiscountPercent);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT * 2);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);

    assertEq(ghoVariableDebtToken.balanceOf(alice), aliceExpectedBalance);
    assertEq(ghoVariableDebtToken.balanceOf(bob), bobExpectedBalance);

    uint256 balanceIncrease = ghoVariableDebtToken.balanceOf(alice) -
      BORROW_AMOUNT -
      aliceBeforeDebt;
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), balanceIncrease);
  }

  function test_Bob_ReceiveGhoFromAliceAndRepayDebt() public {
    test_Alice_IncreaseTime1MoreYearAndBorrowMoreGho();

    vm.prank(alice);
    ghoContracts.ghoToken.transfer(bob, BORROW_AMOUNT);
    vm.prank(bob);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 bobScaledBefore = ghoVariableDebtToken.scaledBalanceOf(bob);
    uint256 bobDiscountPercentBefore = ghoVariableDebtToken.getDiscountPercent(bob);

    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = aliceScaledBefore.rayMul(expectedBorrowIndex);

    uint256 bobExpectedBalanceNoDiscount = bobScaledBefore.rayMul(expectedBorrowIndex);
    uint256 bobBalanceIncrease = bobExpectedBalanceNoDiscount - BORROW_AMOUNT;
    uint256 bobDiscountTokenBalance = IERC20(tokenList.stkAave).balanceOf(bob);
    uint256 bobExpectedDiscount = (bobBalanceIncrease * bobDiscountPercentBefore) / 10_000;
    uint256 bobExpectedBalance = bobExpectedBalanceNoDiscount - bobExpectedDiscount;
    uint256 bobExpectedInterest = bobBalanceIncrease - bobExpectedDiscount;

    uint256 bobDiscountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      0,
      bobDiscountTokenBalance
    );

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountPercentUpdated(
      bob,
      bobDiscountPercentBefore,
      bobDiscountPercent
    );
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(bob, address(0), BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Burn(
      bob,
      address(0),
      BORROW_AMOUNT,
      bobExpectedInterest,
      expectedBorrowIndex
    );

    vm.prank(bob);
    marketContracts.poolProxy.repay(address(ghoContracts.ghoToken), type(uint256).max, 2, bob);

    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);

    assertEq(ghoVariableDebtToken.getDiscountPercent(bob), bobDiscountPercent);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT * 2 - bobExpectedBalance);

    assertEq(ghoVariableDebtToken.balanceOf(alice), aliceExpectedBalance);
    assertEq(ghoVariableDebtToken.balanceOf(bob), 0);

    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), bobExpectedInterest);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
  }

  function test_Charlie_DepositEthAndBorrowGho() public {
    test_Bob_ReceiveGhoFromAliceAndRepayDebt();

    vm.prank(charlie);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, charlie, 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), charlie, BORROW_AMOUNT * 3);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(charlie, charlie, BORROW_AMOUNT * 3, 0, expectedBorrowIndex);

    vm.prank(charlie);
    marketContracts.poolProxy.borrow(
      address(ghoContracts.ghoToken),
      BORROW_AMOUNT * 3,
      2,
      0,
      charlie
    );

    assertEq(ghoVariableDebtToken.getDiscountPercent(charlie), 0);
    assertEq(ghoContracts.ghoToken.balanceOf(charlie), BORROW_AMOUNT * 3);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(charlie), 0);
    assertEq(ghoVariableDebtToken.balanceOf(charlie), BORROW_AMOUNT * 3);
  }

  function test_Alice_RepaySmallGhoDebt() public {
    test_Charlie_DepositEthAndBorrowGho();

    // clear logs
    vm.getRecordedLogs();

    uint256 repayAmount = 100;

    vm.prank(alice);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    uint256 aliceScaledBalanceBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 aTokenGhoBalanceBefore = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 aliceAccruedInterestBefore = ghoVariableDebtToken.getBalanceFromInterest(alice);

    skip(2 seconds);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();
    uint256 aliceExpectedBalance = aliceScaledBalanceBefore.rayMul(expectedBorrowIndex);
    uint256 aliceExpectedInterest = aliceExpectedBalance - BORROW_AMOUNT * 2;
    uint256 aliceExpectedBalanceIncrease = aliceExpectedInterest - aliceAccruedInterestBefore;
    uint256 expectedATokenBalance = aTokenGhoBalanceBefore + repayAmount;

    uint256 amount = aliceExpectedBalanceIncrease - repayAmount;

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, amount);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(
      alice,
      alice,
      amount,
      aliceExpectedBalanceIncrease,
      expectedBorrowIndex
    );

    vm.prank(alice);
    marketContracts.poolProxy.repay(address(ghoContracts.ghoToken), repayAmount, 2, alice);
    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(alice), aliceExpectedBalance - repayAmount);
    assertEq(
      ghoVariableDebtToken.getBalanceFromInterest(alice),
      aliceAccruedInterestBefore + aliceExpectedBalanceIncrease - repayAmount
    );
    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), expectedATokenBalance);
  }

  function test_Alice_ReceiveGhoFromCharlieAndRepayDebt() public {
    test_Alice_RepaySmallGhoDebt();

    vm.prank(charlie);
    ghoContracts.ghoToken.transfer(alice, BORROW_AMOUNT * 3);

    vm.prank(alice);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 aTokenGhoBalanceBefore = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 aliceAccruedInterestBefore = ghoVariableDebtToken.getBalanceFromInterest(alice);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = aliceScaledBefore.rayMul(expectedBorrowIndex);
    uint256 aliceExpectedInterest = aliceExpectedBalance - BORROW_AMOUNT * 2;
    uint256 aliceExpectedBalanceIncrease = aliceExpectedInterest - aliceAccruedInterestBefore;
    uint256 expectedATokenGhoBalance = aTokenGhoBalanceBefore + aliceExpectedInterest;

    uint256 amount = aliceExpectedBalance - aliceExpectedBalanceIncrease;

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(alice, address(0), amount);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Burn(
      alice,
      address(0),
      amount,
      aliceExpectedBalanceIncrease,
      expectedBorrowIndex
    );

    vm.prank(alice);
    marketContracts.poolProxy.repay(address(ghoContracts.ghoToken), type(uint256).max, 2, alice);
    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(alice), 0);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), expectedATokenGhoBalance);
  }

  function test_DistributeFeesToTreasury() public {
    test_Alice_ReceiveGhoFromCharlieAndRepayDebt();

    uint256 aTokenBalance = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 treasuryBalance = ghoContracts.ghoToken.balanceOf(address(marketContracts.treasury));

    assertGt(aTokenBalance, 0);
    assertEq(treasuryBalance, 0);

    vm.expectEmit(address(ghoAToken));
    emit IGhoFacilitator.FeesDistributedToTreasury(
      address(marketContracts.treasury),
      address(ghoContracts.ghoToken),
      aTokenBalance
    );

    ghoAToken.distributeFeesToTreasury();

    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), 0);
    assertEq(ghoContracts.ghoToken.balanceOf(address(marketContracts.treasury)), aTokenBalance);
  }
}
