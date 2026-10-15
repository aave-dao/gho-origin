// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterPreviewSwap.t.sol -vvv
 */
contract PreviewSwapsTest is TestGhoRouterBase {
  function testPreviewSwapToGHOZeroAmount() public {
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.previewSwap(address(USDX_4626_TOKEN), address(GHO_TOKEN), address(GHO_GSM_4626), 0);
  }

  function testPreviewSwapToGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.previewSwap(address(WETH), address(GHO_TOKEN), address(GHO_GSM_4626), 1);
  }

  function testPreviewSwapGsmNotAllowed() public {
    // GHO_GSM is not allowed in setUp
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(USDX_TOKEN), address(GHO_TOKEN), address(GHO_GSM), 1);
  }

  function testPreviewSwapInvalidTokenPair() public {
    // Neither token is GHO or sGHO, so no route matches
    vm.expectRevert(
      abi.encodeWithSelector(
        IGhoRouter.InvalidTokenPair.selector,
        address(WETH),
        address(USDX_TOKEN)
      )
    );
    GHO_ROUTER.previewSwap(address(WETH), address(USDX_TOKEN), address(GHO_GSM_4626), 1);
  }

  function testPreviewSwapToGHO(uint256 amount) public view {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);

    uint256 ghoAmount = GHO_ROUTER.previewSwap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    // Stata shares -> vault assets -> GHO (6 -> 18 decimals), minus sell fee
    uint256 expectedOut = _ghoFromSell(USDX_4626_TOKEN.convertToAssets(amount) * 1e12);

    assertEq(ghoAmount, expectedOut, 'Should preview GHO amount');
  }

  function testPreviewSwapFromGHO(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 vaultAssets = _usdxForBuy(amount);
    uint256 expectedShares = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(expectedShares);

    assertEq(outputAmount, expectedOut, 'Should preview output amount');
  }

  function testPreviewSwapFromGHONonUnitVaultRate(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _setUsdxVaultRate(5, 4);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 vaultAssets = _usdxForBuy(amount);
    uint256 expectedShares = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(expectedShares);

    assertEq(outputAmount, expectedOut, 'Should preview output amount');
    assertApproxEqAbs(outputAmount, vaultAssets, 1, 'Output should match GHO value in USDX');
  }

  function testPreviewSwapFromGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.previewSwap(address(GHO_TOKEN), address(WETH), address(GHO_GSM_4626), 1);
  }

  function testPreviewSwapFromGHOToStataUSDX_4626_TOKEN(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 vaultAssets = _usdxForBuy(amount);
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    assertEq(outputAmount, expectedOut, 'Should preview static aToken output amount');
  }

  function testPreviewSwapToSGHO(uint256 amount) public view {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);

    uint256 sghoAmount = GHO_ROUTER.previewSwap(
      address(USDX_4626_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount
    );

    uint256 ghoOut = _ghoFromSell(USDX_4626_TOKEN.convertToAssets(amount) * 1e12);
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    assertEq(sghoAmount, expectedOut, 'Should preview sGHO amount');
  }

  function testPreviewSwapToSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.previewSwap(address(WETH), address(SGHO), address(GHO_GSM_4626), 1);
  }

  function testPreviewDepositForSGHO(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount
    );

    assertEq(outputAmount, amount, 'sGHO copy preview should be 1:1 at initial index');
  }

  function testPreviewSwapFromSGHOUSDX_TOKEN(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 vaultAssets = _usdxForBuy(ghoAmount);
    uint256 expectedShares = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(expectedShares);

    assertEq(outputAmount, expectedOut, 'Should preview USDX_TOKEN output');
  }

  function testPreviewSwapFromSGHOUSDX_TOKENNonUnitVaultRate(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _setUsdxVaultRate(5, 4);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 vaultAssets = _usdxForBuy(ghoAmount);
    uint256 expectedShares = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(expectedShares);

    assertEq(outputAmount, expectedOut, 'Should preview USDX_TOKEN output');
    assertApproxEqAbs(outputAmount, vaultAssets, 1, 'Output should match GHO value in USDX');
  }

  function testPreviewSwapFromSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.previewSwap(address(SGHO), address(WETH), address(GHO_GSM_4626), 1);
  }

  function testPreviewSwapFromSGHOStataUSDX_4626_TOKEN(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 vaultAssets = _usdxForBuy(ghoAmount);
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    assertEq(outputAmount, expectedOut, 'Should preview static aToken output');
  }

  function testPreviewRedeemSGho(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(SGHO),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    assertEq(outputAmount, amount, 'Should preview static aToken output');
  }
}

contract PreviewMatchesSwapTest is TestGhoRouterBase {
  function testPreviewMatchesSwapToGHOStata(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount
    );
  }

  function testPreviewMatchesSwapToGHOUnderlying(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    // Preview prices the wrapped shares before the deposit, so it can miss up to one share's worth
    uint256 maxShortfall = USDX_4626_TOKEN.previewMint(1) * 1e12;
    _assertPreviewMatchesSwap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      maxShortfall
    );
  }

  function testPreviewMatchesSwapToGHORegularGsm(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(address(USDX_TOKEN), address(GHO_TOKEN), address(GHO_GSM), amount);
  }

  function testPreviewMatchesSwapFromGHOStata(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );
  }

  function testPreviewMatchesSwapFromGHOUnderlying(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount
    );
  }

  function testPreviewMatchesSwapFromGHORegularGsm(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _allowAndFundPlainGsm();
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(address(GHO_TOKEN), address(USDX_TOKEN), address(GHO_GSM), amount);
  }

  function testPreviewMatchesSwapToSGHOStata(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    // Bound below 1M so resulting GHO stays under SGHO's supply cap
    amount = bound(amount, 1e6, 1_000_000e6);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(
      address(USDX_4626_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount
    );
  }

  function testPreviewMatchesSwapToSGHOUnderlying(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    // Bound below 1M so resulting GHO stays under SGHO's supply cap
    amount = bound(amount, 1e6, 1_000_000e6);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    // Preview prices the wrapped shares before the deposit, so it can miss up to one share's worth
    uint256 maxShortfall = USDX_4626_TOKEN.previewMint(1) * 1e12;
    _assertPreviewMatchesSwap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      amount,
      maxShortfall
    );
  }

  function testPreviewMatchesSwapFromSGHOStata(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    // GSM holds 10M shares; with sGHO yield and a lower buy fee, larger redeems exceed its liquidity
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS / 2);
    vaultRateBps = bound(vaultRateBps, 1e4, 2e4);
    yieldDays = bound(yieldDays, 0, 365);

    _setUsdxVaultRate(vaultRateBps, 1e4);
    _enableSghoYield();
    _mintSgho(amount);
    vm.prank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    _accrueSghoYield(yieldDays);

    _assertPreviewMatchesSwap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );
  }

  function testPreviewMatchesSwapFromSGHOUnderlying(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    // GSM holds 10M shares; with sGHO yield and a lower buy fee, larger redeems exceed its liquidity
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS / 2);
    vaultRateBps = bound(vaultRateBps, 1e4, 2e4);
    yieldDays = bound(yieldDays, 0, 365);

    _setUsdxVaultRate(vaultRateBps, 1e4);
    _enableSghoYield();
    _mintSgho(amount);
    vm.prank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    _accrueSghoYield(yieldDays);

    _assertPreviewMatchesSwap(address(SGHO), address(USDX_TOKEN), address(GHO_GSM_4626), amount);
  }

  function testPreviewMatchesSwapDepositForSGHO(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _setUpMarket(vaultRateBps, yieldDays);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    _assertPreviewMatchesSwap(address(GHO_TOKEN), address(SGHO), address(0), amount);
  }

  function testPreviewMatchesSwapRedeemSGHO(
    uint256 amount,
    uint256 vaultRateBps,
    uint256 yieldDays
  ) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    vaultRateBps = bound(vaultRateBps, 1e4, 2e4);
    yieldDays = bound(yieldDays, 0, 365);

    _setUsdxVaultRate(vaultRateBps, 1e4);
    _enableSghoYield();
    _mintSgho(amount);
    vm.prank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    _accrueSghoYield(yieldDays);

    _assertPreviewMatchesSwap(address(SGHO), address(GHO_TOKEN), address(0), amount);
  }

  function _setUpMarket(uint256 vaultRateBps, uint256 yieldDays) internal {
    _setUsdxVaultRate(bound(vaultRateBps, 1e4, 2e4), 1e4);
    _enableSghoYield();
    _accrueSghoYield(bound(yieldDays, 0, 365));
  }

  function _enableSghoYield() internal {
    SGHO.grantRole(SGHO.YIELD_MANAGER_ROLE(), address(this));
    SGHO.setTargetRate(1000);
  }

  function _accrueSghoYield(uint256 yieldDays) internal {
    vm.warp(block.timestamp + yieldDays * 1 days);
    deal(address(GHO_TOKEN), address(SGHO), GHO_TOKEN.balanceOf(address(SGHO)) * 2);
  }

  function _assertPreviewMatchesSwap(
    address tokenIn,
    address tokenOut,
    address gsm,
    uint256 amount
  ) internal {
    _assertPreviewMatchesSwap(tokenIn, tokenOut, gsm, amount, 0);
  }

  function _assertPreviewMatchesSwap(
    address tokenIn,
    address tokenOut,
    address gsm,
    uint256 amount,
    uint256 maxShortfall
  ) internal {
    uint256 previewOut = GHO_ROUTER.previewSwap(tokenIn, tokenOut, gsm, amount);
    uint256 balanceBefore = IERC20(tokenOut).balanceOf(USER);

    vm.prank(USER);
    uint256 amountOut = GHO_ROUTER.swap(tokenIn, tokenOut, gsm, amount, 0, USER, block.timestamp);

    assertGe(amountOut, previewOut, 'swap should not return less than previewed');
    assertLe(amountOut - previewOut, maxShortfall, 'preview shortfall too large');
    assertEq(
      IERC20(tokenOut).balanceOf(USER) - balanceBefore,
      amountOut,
      'User should receive swap output'
    );
    _assertRouterEmpty();
  }
}
