// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IScaledBalanceToken} from 'aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {IGhoFacilitator} from 'src/contracts/gho/interfaces/IGhoFacilitator.sol';

contract TestBasicBorrow is TestnetProcedures {
  using WadRayMath for uint256;

  uint256 public constant COLLATERAL_AMOUNT = 1000e18;
  uint256 public constant BORROW_AMOUNT = 1000e18;

  function test_Alice_DepositWethBorrowGho() public {
    vm.prank(alice);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, alice, 0);

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(alice, alice, BORROW_AMOUNT, 0, 1e27);

    vm.prank(alice);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.totalSupply(), BORROW_AMOUNT);
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
    assertEq(ghoVariableDebtToken.totalSupply(), aliceExpectedBalance);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
  }

  function test_Bob_DepositWethBorrowGhoAfter1Year() public {
    test_Alice_InterestAccruedAfter1Year();

    vm.prank(bob);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, bob, 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), bob, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(bob, bob, BORROW_AMOUNT, 0, expectedBorrowIndex);

    vm.prank(bob);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, bob);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
    assertEq(ghoVariableDebtToken.balanceOf(bob), BORROW_AMOUNT);
  }

  function test_Alice_BorrowMoreGhoAfterAnotherYear() public {
    test_Bob_DepositWethBorrowGhoAfter1Year();

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 bobScaledBefore = ghoVariableDebtToken.scaledBalanceOf(bob);

    skip(365 days);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 borrowedAmountScaled = BORROW_AMOUNT.rayDiv(expectedBorrowIndex);
    uint256 aliceExpectedBalance = (aliceScaledBefore + borrowedAmountScaled).rayMul(
      expectedBorrowIndex
    );
    uint256 bobExpectedBalance = bobScaledBefore.rayMul(expectedBorrowIndex);
    uint256 amount = aliceExpectedBalance - BORROW_AMOUNT;
    uint256 aliceExpectedBalanceIncrease = amount - BORROW_AMOUNT;

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
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    uint256 aliceDebtAfter = ghoVariableDebtToken.balanceOf(alice);
    uint256 bobDebtAfter = ghoVariableDebtToken.balanceOf(bob);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT * 2);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(aliceDebtAfter, aliceExpectedBalance);
    assertEq(bobDebtAfter, bobExpectedBalance);

    uint256 interestsSinceLastAction = aliceDebtAfter - BORROW_AMOUNT * 2;
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), interestsSinceLastAction);
  }

  function test_Bob_ReceiveGhoFromAliceAndRepay() public {
    test_Alice_BorrowMoreGhoAfterAnotherYear();

    vm.prank(alice);
    ghoContracts.ghoToken.transfer(bob, BORROW_AMOUNT);

    vm.prank(bob);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 bobScaledBefore = ghoVariableDebtToken.scaledBalanceOf(bob);

    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = aliceScaledBefore.rayMul(expectedBorrowIndex);
    uint256 bobExpectedBalance = bobScaledBefore.rayMul(expectedBorrowIndex);
    uint256 bobExpectedInterest = bobExpectedBalance - BORROW_AMOUNT;

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

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    uint256 aliceDebt = ghoVariableDebtToken.balanceOf(alice);
    uint256 bobDebt = ghoVariableDebtToken.balanceOf(bob);

    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT * 2 - bobExpectedBalance);
    assertEq(aliceDebt, aliceExpectedBalance);
    assertEq(bobDebt, 0);

    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), bobExpectedInterest);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
  }

  function test_Charlie_DepositWethBorrowGho() public {
    test_Bob_ReceiveGhoFromAliceAndRepay();

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

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(charlie), BORROW_AMOUNT * 3);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(charlie), 0);
    assertEq(ghoVariableDebtToken.balanceOf(charlie), BORROW_AMOUNT * 3);
  }

  function test_Alice_RepaySmallAmountOfGho() public {
    test_Charlie_DepositWethBorrowGho();

    uint256 repayAmount = 100;

    vm.prank(alice);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    skip(2 seconds);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 aTokenGhoBalanceBefore = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 aliceAccruedInterestBefore = ghoVariableDebtToken.getBalanceFromInterest(alice);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = aliceScaledBefore.rayMul(expectedBorrowIndex);
    uint256 aliceExpectedInterest = aliceExpectedBalance - BORROW_AMOUNT * 2;
    uint256 aliceExpectedBalanceIncrease = aliceExpectedInterest - aliceAccruedInterestBefore;
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

    assertEq(ghoVariableDebtToken.balanceOf(alice), aliceExpectedBalance - repayAmount);
    assertEq(
      ghoVariableDebtToken.getBalanceFromInterest(alice),
      aliceAccruedInterestBefore + aliceExpectedBalanceIncrease - repayAmount
    );

    uint256 expectedATokenGhoBalance = aTokenGhoBalanceBefore + repayAmount;
    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), expectedATokenGhoBalance);
  }

  function test_Alice_ReceiveGhoFromCharlieAndRepay() public {
    test_Alice_RepaySmallAmountOfGho();

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

    assertEq(ghoVariableDebtToken.balanceOf(alice), 0);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);

    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), expectedATokenGhoBalance);
  }

  function test_DistributeFeesToTreasury() public {
    test_Alice_ReceiveGhoFromCharlieAndRepay();

    uint256 aTokenGhoBalanceBefore = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 treasuryGhoBalanceBefore = ghoContracts.ghoToken.balanceOf(
      address(marketContracts.treasury)
    );

    assertGt(aTokenGhoBalanceBefore, 0);
    assertEq(treasuryGhoBalanceBefore, 0);

    vm.expectEmit(address(ghoAToken));
    emit IGhoFacilitator.FeesDistributedToTreasury(
      address(marketContracts.treasury),
      address(ghoContracts.ghoToken),
      aTokenGhoBalanceBefore
    );

    ghoAToken.distributeFeesToTreasury();

    uint256 aTokenGhoBalanceAfter = ghoContracts.ghoToken.balanceOf(address(ghoAToken));
    uint256 treasuryGhoBalanceAfter = ghoContracts.ghoToken.balanceOf(
      address(marketContracts.treasury)
    );

    assertEq(aTokenGhoBalanceAfter, 0);
    assertEq(treasuryGhoBalanceAfter, aTokenGhoBalanceBefore);
  }
}
