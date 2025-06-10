// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';
import {IScaledBalanceToken} from 'aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IGhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/interfaces/IGhoVariableDebtToken.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/ZeroDiscountRateStrategy.sol';
import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';
import {MockStakedToken} from '../mocks/MockStakedToken.sol';

contract TestDiscountRebalance is TestnetProcedures {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

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

    // Charlie stakes 10 AAVE on behalf of Alice
    vm.prank(charlie);
    IERC20(tokenList.aave).approve(tokenList.stkAave, 10e18);
    vm.prank(charlie);
    MockStakedToken(tokenList.stkAave).stake(alice, 10e18);
  }

  function test_Alice_DepositWethBorrowGho() public {
    uint256 discountPercentBefore = ghoVariableDebtToken.getDiscountPercent(alice);

    vm.prank(alice);
    marketContracts.poolProxy.deposit(tokenList.weth, COLLATERAL_AMOUNT, alice, 0);

    uint256 discountTokenBalance = IERC20(tokenList.stkAave).balanceOf(alice);
    uint256 discountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      BORROW_AMOUNT,
      discountTokenBalance
    );

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountPercentUpdated(
      alice,
      discountPercentBefore,
      discountPercent
    );
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(alice, alice, BORROW_AMOUNT, 0, 1e27);

    vm.prank(alice);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, alice);

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), discountPercent);
    assertEq(ghoContracts.ghoToken.balanceOf(alice), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(alice), 0);
    assertEq(ghoVariableDebtToken.balanceOf(alice), BORROW_AMOUNT);
  }

  function test_Bob_DepositWethAndBorrowGho() public {
    test_Alice_DepositWethBorrowGho();

    // clear logs
    vm.getRecordedLogs();

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
    emit IERC20.Transfer(address(0), bob, BORROW_AMOUNT);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(bob, bob, BORROW_AMOUNT, 0, expectedBorrowIndex);

    vm.prank(bob);
    marketContracts.poolProxy.borrow(address(ghoContracts.ghoToken), BORROW_AMOUNT, 2, 0, bob);
    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoVariableDebtToken.getDiscountPercent(bob), discountPercent);
    assertEq(ghoContracts.ghoToken.balanceOf(bob), BORROW_AMOUNT);
    assertEq(ghoVariableDebtToken.getBalanceFromInterest(bob), 0);
    assertEq(ghoVariableDebtToken.balanceOf(bob), BORROW_AMOUNT);
  }

  // Discount percent is adjusted to current debt
  function test_Charlie_RebalanceAliceDiscountPercent() public {
    test_Bob_DepositWethAndBorrowGho();

    skip(365 days);

    uint256 aliceScaledBefore = ghoVariableDebtToken.scaledBalanceOf(alice);
    uint256 discountPercentBefore = ghoVariableDebtToken.getDiscountPercent(alice);

    uint256 expectedBorrowIndex = getExpectedBorrowIndex();

    uint256 aliceExpectedBalanceNoDiscount = aliceScaledBefore.rayMul(expectedBorrowIndex);
    uint256 aliceBalanceIncrease = aliceExpectedBalanceNoDiscount - BORROW_AMOUNT;
    uint256 aliceExpectedDiscount = aliceBalanceIncrease.percentMul(discountPercentBefore);
    uint256 aliceBalanceIncreaseWithDiscount = aliceBalanceIncrease - aliceExpectedDiscount;
    uint256 aliceExpectedDiscountScaled = aliceExpectedDiscount.rayDiv(expectedBorrowIndex);
    uint256 aliceExpectedScaledBalanceWithDiscount = aliceScaledBefore -
      aliceExpectedDiscountScaled;
    uint256 aliceExpectedBalance = aliceExpectedScaledBalanceWithDiscount.rayMul(
      expectedBorrowIndex
    );

    uint256 aliceDiscountTokenBalance = IERC20(tokenList.stkAave).balanceOf(alice);
    uint256 aliceExpectedDiscountPercent = calculateDiscountRate(
      discountRate,
      ghoDiscountedPerDiscountToken,
      minDiscountTokenBalance,
      aliceExpectedBalance,
      aliceDiscountTokenBalance
    );

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountPercentUpdated(
      alice,
      discountPercentBefore,
      aliceExpectedDiscountPercent
    );
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IERC20.Transfer(address(0), alice, aliceBalanceIncreaseWithDiscount);
    vm.expectEmit(address(ghoVariableDebtToken));
    emit IScaledBalanceToken.Mint(
      address(0),
      alice,
      aliceBalanceIncreaseWithDiscount,
      aliceBalanceIncreaseWithDiscount,
      expectedBorrowIndex
    );

    vm.prank(charlie);
    ghoVariableDebtToken.rebalanceUserDiscountPercent(alice);

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), aliceExpectedDiscountPercent);
  }

  function test_Governance_ChangeDiscountRateStrategy() public {
    test_Charlie_RebalanceAliceDiscountPercent();

    skip(365 days);

    address oldDiscountRateStrategyAddress = ghoVariableDebtToken.getDiscountRateStrategy();

    vm.prank(roles.marketOwner);
    address emptyStrategyAddress = address(new ZeroDiscountRateStrategy());

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountRateStrategyUpdated(
      oldDiscountRateStrategyAddress,
      emptyStrategyAddress
    );

    vm.prank(roles.marketOwner);
    ghoVariableDebtToken.updateDiscountRateStrategy(emptyStrategyAddress);
  }

  function test_Charlie_RebalancesAliceDiscountPercent_DiscountPercentChanges() public {
    test_Governance_ChangeDiscountRateStrategy();

    uint256 discountPercentBefore = ghoVariableDebtToken.getDiscountPercent(alice);

    vm.expectEmit(address(ghoVariableDebtToken));
    emit IGhoVariableDebtToken.DiscountPercentUpdated(alice, discountPercentBefore, 0);

    vm.prank(charlie);
    ghoVariableDebtToken.rebalanceUserDiscountPercent(alice);

    assertNotEq(ghoVariableDebtToken.getDiscountPercent(alice), discountPercentBefore);
    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), 0);
  }

  function test_Charlie_RebalancesALiceDiscountPercent_DiscountPercentIsSame() public {
    test_Charlie_RebalancesAliceDiscountPercent_DiscountPercentChanges();

    // clean logs
    vm.getRecordedLogs();

    uint256 discountPercentBefore = ghoVariableDebtToken.getDiscountPercent(alice);

    vm.prank(alice);
    ghoVariableDebtToken.rebalanceUserDiscountPercent(alice);
    assertEventNotEmitted(keccak256('DiscountPercentUpdated(address,uint256,uint256)'));

    assertEq(ghoVariableDebtToken.getDiscountPercent(alice), discountPercentBefore);
  }
}
