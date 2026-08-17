// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import './TestGhoRouterBase.t.sol';
import {MockReentrantGsm} from '../../mocks/MockReentrantGsm.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSwap.t.sol -vvv
 */

contract SwapToGHOTest is TestGhoRouterBase {
  function testSwapToGHOZeroAmount() public {
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapToGHODeadlineExpired() public {
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1_000e6,
      0,
      address(this),
      block.timestamp - 1
    );
  }

  function testSwapToGHOSlippageExceeded() public {
    uint256 amount = 1000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    // Set unreasonably high minGHOAmount to trigger slippage
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      type(uint256).max,
      address(this),
      block.timestamp
    );
  }

  function testSwapToGHOInconsistentTokens() public {
    vm.startPrank(USER);
    deal(address(WETH), address(USER), 1);
    WETH.approve(address(GHO_ROUTER), 1);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(WETH),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      address(this),
      block.timestamp
    );
    vm.stopPrank();
  }

  function testSwapToGHOGsmNotAllowed() public {
    // GHO_GSM is not allowed in setUp; the GSM gate trips before any token check
    vm.startPrank(USER);
    deal(address(USDX_TOKEN), address(USER), 1);
    USDX_TOKEN.approve(address(GHO_ROUTER), 1);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM),
      1,
      0,
      address(this),
      block.timestamp
    );
    vm.stopPrank();
  }

  function testSwapInvalidTokenPair() public {
    // Neither token is GHO or sGHO, so no route matches
    vm.expectRevert(
      abi.encodeWithSelector(
        IGhoRouter.InvalidTokenPair.selector,
        address(WETH),
        address(USDX_TOKEN)
      )
    );
    GHO_ROUTER.swap(
      address(WETH),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapToGHOZeroAddressRecipient() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      address(0),
      block.timestamp
    );
  }

  function testSwapToGHOStata(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      amount,
      expectedOut,
      USER
    );
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
  }

  function testSwapToGHOUnderlying(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(USDX_TOKEN), address(GHO_TOKEN), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
  }

  function testSwapToGHORegularGsm(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);

    GHO_ROUTER.allowGsm(address(GHO_GSM));

    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(USDX_TOKEN), address(GHO_TOKEN), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
    assertEq(GHO_TOKEN.balanceOf(USER), expectedOut, 'User should receive GHO');
    assertEq(
      USDX_TOKEN.allowance(address(GHO_ROUTER), address(GHO_GSM)),
      0,
      'GSM asset approval should be reset'
    );
  }

  function testSwapToGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    uint256 recipientBalanceBefore = GHO_TOKEN.balanceOf(RECIPIENT);

    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);
    uint256 userBalanceBefore = GHO_TOKEN.balanceOf(USER);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      amount,
      expectedOut,
      RECIPIENT
    );
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
    assertEq(
      GHO_TOKEN.balanceOf(RECIPIENT) - recipientBalanceBefore,
      ghoReceived,
      'Recipient gets GHO'
    );
    assertEq(GHO_TOKEN.balanceOf(USER), userBalanceBefore, 'Caller should not receive GHO');
  }
}

contract SwapFromGHOTest is TestGhoRouterBase {
  function testSwapFromGHOZeroAmount() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromGHOSlippageExceeded() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    // Set unreasonably high minOutputAmount to trigger slippage
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      type(uint256).max,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromGHOInconsistentTokens() public {
    uint256 amount = 1 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(WETH),
      address(GHO_GSM_4626),
      amount,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromGHOZeroAddressRecipient() public {
    uint256 amount = 1 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      address(0),
      block.timestamp
    );
  }

  function testSwapFromGHOToUSDX_4626_TOKEN_GSMUsesLessGho() public {
    uint256 expectedAmount = 90909090;
    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.mockCall(
      address(GHO_GSM_4626),
      abi.encodeWithSelector(IGsm.buyAsset.selector),
      abi.encode(expectedAmount, amount / 2)
    );

    // Deal Token as buyAsset call is mocked
    deal(address(USDX_4626_TOKEN), address(GHO_ROUTER), expectedAmount);

    // Router only pulls and emits the GHO actually needed for the buy, not the full input
    (, uint256 ghoUsed, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      ghoUsed,
      expectedAmount,
      USER
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');
  }

  function testSwapFromGHORevertsWhenRequiredGhoExceedsInput() public {
    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    // Force the GSM to report it needs more GHO than the caller supplied
    vm.mockCall(
      address(GHO_GSM_4626),
      abi.encodeWithSelector(IGsm.getAssetAmountForBuyAsset.selector),
      abi.encode(uint256(1), amount + 1, uint256(0), uint256(0))
    );

    vm.prank(USER);
    vm.expectRevert(IGhoRouter.RequiredGhoGreaterThanExpectedAmount.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapFromGHOToUSDX_TOKEN(uint256 amount) public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    deal(address(USDX_TOKEN), address(this), MAX_FUZZ_AMOUNT_6_DECIMALS);
    USDX_TOKEN.approve(address(GHO_GSM), MAX_FUZZ_AMOUNT_6_DECIMALS);
    GHO_GSM.sellAsset(MAX_FUZZ_AMOUNT_6_DECIMALS, address(this));

    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    // USDX is 6 decimals, GHO is 18 — scale the gross GHO amount down to the asset amount
    uint256 expectedAmount = (grossAmount * 1e6) / 1e18;

    // Router only pulls and emits the GHO actually needed for the buy, not the full input
    (, uint256 ghoUsed, , ) = GHO_GSM.getAssetAmountForBuyAsset(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      ghoUsed,
      expectedAmount,
      USER
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM),
      amount,
      0,
      USER,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');
    assertEq(
      GHO_TOKEN.allowance(address(GHO_ROUTER), address(GHO_GSM)),
      0,
      'GHO approval to GSM should be reset'
    );
  }

  function testSwapFromGHOToStataUSDX_4626_TOKENWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);

    // Router only pulls and emits the GHO actually needed for the buy, not the full input
    (, uint256 ghoUsed, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      ghoUsed,
      expectedAmount,
      RECIPIENT
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      1,
      RECIPIENT,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');

    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(RECIPIENT),
      outputAmount,
      'User gets static aToken'
    );
  }
}

contract SwapToSGhoTest is TestGhoRouterBase {
  function testSwapToSGHOInconsistentTokens() public {
    vm.startPrank(USER);
    deal(address(WETH), address(USER), 1);
    WETH.approve(address(GHO_ROUTER), 1);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(WETH),
      address(SGHO),
      address(GHO_GSM_4626),
      1,
      0,
      address(this),
      block.timestamp
    );
    vm.stopPrank();
  }

  function testSwapToSGhoZeroAddressRecipient() public {
    uint256 amount = 1 ether;
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      address(0),
      block.timestamp
    );
  }

  function testSwapToSGHOUnderlying(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(USDX_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 actualShares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(actualShares, expectedOut, 'Should receive sGHO shares');
    assertEq(
      IERC20(address(SGHO)).balanceOf(USER),
      actualShares,
      'User should receive minted shares'
    );
  }

  function testSwapToSGHOStata(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(USDX_4626_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 shares = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive minted shares');
  }

  function testSwapToSGHOUnderlyingWithRecipient(uint256 amount) public {
    // Bound below 1M USDX so resulting GHO stays under SGHO's supply cap
    amount = bound(amount, 1e6, 1_000_000e6);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(USDX_TOKEN), address(SGHO), amount, expectedOut, RECIPIENT);
    uint256 actualShares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(actualShares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should receive zero shares');
    assertEq(
      IERC20(address(SGHO)).balanceOf(RECIPIENT),
      actualShares,
      'Recipient should receive minted shares'
    );
  }
}

contract SwapFromSGhoTest is TestGhoRouterBase {
  function testSwapFromSGHOZeroAmount() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromSGHOInconsistentTokens() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);
    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(WETH),
      address(GHO_GSM_4626),
      amount,
      0,
      address(this),
      block.timestamp
    );
    vm.stopPrank();
  }

  function testSwapFromSGHOZeroAddressRecipient() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      1 ether,
      1 ether,
      address(0),
      block.timestamp
    );
  }

  function testSwapFromSGHORevertsWhenRequiredGhoExceedsRedeemed() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    // GHO obtained from redeeming the caller's sGHO — the budget the buy must fit within
    uint256 ghoAmount = SGHO.previewRedeem(amount);

    // Force the GSM to report it needs more GHO than the redeemed sGHO provides
    vm.mockCall(
      address(GHO_GSM_4626),
      abi.encodeWithSelector(IGsm.getAssetAmountForBuyAsset.selector),
      abi.encode(uint256(1), ghoAmount + 1, uint256(0), uint256(0))
    );

    vm.expectRevert(IGhoRouter.RequiredGhoGreaterThanExpectedAmount.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
    vm.stopPrank();
  }

  function testSwapFromSGHOSucceedsAfterYieldAccrual() public {
    uint256 amount = 100 ether;

    // Turn on sGHO yield, then mint the caller shares while the index is still 1:1
    SGHO.grantRole(SGHO.YIELD_MANAGER_ROLE(), address(this));
    SGHO.setTargetRate(1000); // 10% APR
    _mintSgho(amount);

    // Let the index climb above 1:1 so redeemed GHO exceeds the shares burned.
    // This is the case the old `ghoUsed <= exactAmountIn` (shares) check wrongly rejected.
    vm.warp(block.timestamp + 365 days);

    // Fund the vault so it can pay out the accrued yield on redeem
    deal(address(GHO_TOKEN), address(SGHO), amount * 2);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    // Sanity: shares now redeem for strictly more GHO than were burned
    assertGt(ghoAmount, amount, 'Index should have accrued yield');

    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 stataAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(stataAmount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), address(USDX_TOKEN), amount, expectedOut, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount,
      1,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive USDX_TOKEN');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testSwapFromSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 stataAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(stataAmount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), address(USDX_TOKEN), amount, expectedOut, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount,
      1,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive USDX_TOKEN');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testSwapFromSGHOStata(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 userBalanceBefore = IERC20(address(USDX_4626_TOKEN)).balanceOf(USER);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), address(USDX_4626_TOKEN), amount, expectedOut, USER);

    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      1,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive static aToken');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(USER) - userBalanceBefore,
      outputAmount,
      'User should receive static aToken output'
    );
  }

  function testSwapFromSGHOStataWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(SGHO),
      address(USDX_4626_TOKEN),
      amount,
      expectedOut,
      RECIPIENT
    );

    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount,
      1,
      RECIPIENT,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive static aToken');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(RECIPIENT),
      outputAmount,
      'Recipient should receive static aToken output'
    );
  }
}

contract DepositForSGhoTest is TestGhoRouterBase {
  function testDepositForSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    uint256 expectedOut = SGHO.previewDeposit(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(GHO_TOKEN), address(SGHO), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'sGHO copy should mint 1:1 shares at initial index');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive all shares');
  }

  function testDepositForSGHOSlippageExceeded() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      amount + 1,
      USER,
      block.timestamp
    );
  }

  function testDepositForSGHOZeroAmount() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      0,
      amount + 1,
      USER,
      block.timestamp
    );
  }

  function testDepositForSGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = IERC20(address(SGHO)).balanceOf(RECIPIENT);
    uint256 userBalanceBefore = IERC20(address(SGHO)).balanceOf(USER);
    uint256 expectedOut = SGHO.previewDeposit(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(GHO_TOKEN), address(SGHO), amount, expectedOut, RECIPIENT);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'sGHO copy should mint 1:1 shares at initial index');
    assertEq(
      IERC20(address(SGHO)).balanceOf(RECIPIENT) - recipientBalanceBefore,
      shares,
      'Recipient should receive shares'
    );
    assertEq(
      IERC20(address(SGHO)).balanceOf(USER),
      userBalanceBefore,
      'Caller should not receive shares'
    );
  }
}

contract RedeemSGhoTest is TestGhoRouterBase {
  function testRedeemSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    uint256 expectedOut = SGHO.previewRedeem(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), address(GHO_TOKEN), amount, expectedOut, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should redeem to full GHO amount');
    assertEq(GHO_TOKEN.balanceOf(USER), outputAmount, 'User should receive redeemed GHO');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testRedeemSGHOSlippageExceeded() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      amount + 1,
      USER,
      block.timestamp
    );
    vm.stopPrank();
  }

  function testRedeemSGHOZeroAmount() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      0,
      amount + 1,
      USER,
      block.timestamp
    );
    vm.stopPrank();
  }

  function testRedeemSGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);

    SGHO.approve(address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = GHO_TOKEN.balanceOf(RECIPIENT);
    uint256 userBalanceBefore = GHO_TOKEN.balanceOf(USER);
    uint256 expectedOut = SGHO.previewRedeem(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), address(GHO_TOKEN), amount, expectedOut, RECIPIENT);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should redeem to full GHO amount');
    assertEq(
      GHO_TOKEN.balanceOf(RECIPIENT) - recipientBalanceBefore,
      outputAmount,
      'Recipient should receive GHO'
    );
    assertEq(GHO_TOKEN.balanceOf(USER), userBalanceBefore, 'Caller should not receive GHO');
  }
}

contract SwapReentrancyTest is TestGhoRouterBase {
  function _deployAndAllowReentrantGsm() internal returns (MockReentrantGsm) {
    MockReentrantGsm reentrantGsm = new MockReentrantGsm(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_ROUTER)
    );
    GHO_ROUTER.allowGsm(address(reentrantGsm));
    return reentrantGsm;
  }

  function testSwapRevertsOnReentrantGsmSellPath() public {
    MockReentrantGsm reentrantGsm = _deployAndAllowReentrantGsm();

    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    vm.prank(USER);
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(reentrantGsm),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapRevertsOnReentrantGsmBuyPath() public {
    MockReentrantGsm reentrantGsm = _deployAndAllowReentrantGsm();

    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.prank(USER);
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(reentrantGsm),
      amount,
      0,
      USER,
      block.timestamp
    );
  }
}
