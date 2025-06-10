// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICreditDelegationToken} from 'aave-v3-origin/contracts/interfaces/ICreditDelegationToken.sol';
import {IScaledBalanceToken} from 'aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

contract TestBorrowOnBehalf is TestnetProcedures {
  using WadRayMath for uint256;

  uint256 public constant COLLATERAL_AMOUNT = 1000e18;
  uint256 public constant BORROW_AMOUNT = 1000e18;

  function test_Alice_DepositWethAndDelegateBorrowingPowerToBob() public {
    vm.prank(alice);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, alice, 0);

    vm.expectEmit(address(ghoVariableDebtToken));
    emit ICreditDelegationToken.BorrowAllowanceDelegated(
      alice,
      bob,
      address(ghoContracts.ghoToken),
      BORROW_AMOUNT
    );

    vm.prank(alice);
    ghoVariableDebtToken.approveDelegation(bob, BORROW_AMOUNT);
  }

  function test_Bob_BorrowGhoOnBehalfOfAlice() public {
    test_Alice_DepositWethAndDelegateBorrowingPowerToBob();

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(bob, alice, BORROW_AMOUNT, 0, 1e27);

    vm.prank(bob);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(alice), BORROW_AMOUNT);
  }

  function test_Alice_InterestAccruedAfter1Year() public {
    test_Bob_BorrowGhoOnBehalfOfAlice();

    skip(365 days);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = ghoVariableDebtToken.scaledBalanceOf(alice).rayMul(
      expectedBorrowIndex
    );

    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.balanceOf(alice), aliceExpectedBalance);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
  }

  function test_Charlie_DepositWethAfter1YearAndBorrowGho() public {
    test_Alice_InterestAccruedAfter1Year();

    vm.prank(charlie);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, charlie, 0);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), charlie, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(charlie, charlie, BORROW_AMOUNT, 0, expectedBorrowIndex);

    vm.prank(charlie);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, charlie);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(charlie), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(charlie), 0);
    assertEq(ghoVariableDebtToken.balanceOf(charlie), BORROW_AMOUNT);
  }

  function test_Bob_ReceiveGhoFromCharlieAndRepayDebt() public {
    test_Charlie_DepositWethAfter1YearAndBorrowGho();

    vm.prank(charlie);
    ghoContracts.ghoToken.transfer(bob, BORROW_AMOUNT);

    vm.prank(bob);
    ghoContracts.ghoToken.approve(address(marketContracts.poolProxy), type(uint256).max);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 charlieScaledBefore = ghoVariableDebtToken.scaledBalanceOf(charlie);

    skip(1 seconds);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalance = aliceScaledBefore.rayMul(expectedBorrowIndex);
    uint256 charlieExpectedBalance = charlieScaledBefore.rayMul(expectedBorrowIndex);
    uint256 aliceExpectedInterest = aliceExpectedBalance - BORROW_AMOUNT;

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(alice, address(0), BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Burn(
      alice,
      address(0),
      BORROW_AMOUNT,
      aliceExpectedInterest,
      expectedBorrowIndex
    );

    vm.prank(bob);
    marketContracts.poolProxy.repay(address(ghoContracts.ghoToken), aliceExpectedBalance, 2, alice);

    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoContracts.ghoToken.balanceOf(alice), 0);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT * 2 - aliceExpectedBalance);
    assertEq(ghoContracts.ghoToken.balanceOf(charlie), 0);

    assertEq(ghoVariableDebtToken.balanceOf(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(bob), 0);
    assertEq(ghoVariableDebtToken.balanceOf(charlie), charlieExpectedBalance);

    assertEq(ghoContracts.ghoToken.balanceOf(address(ghoAToken)), aliceExpectedInterest);

    assertEq(ghoContracts.ghoToken.balanceOf(address(marketContracts.treasury)), 0);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
  }
}
