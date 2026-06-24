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
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(WETH), address(GHO_TOKEN), address(GHO_GSM_4626), 1);
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

    uint256 fee = amount / 10; // 10% fee
    uint256 expectedOut = ((amount - fee) * 1e18) / 1e6;

    assertApproxEqAbs(ghoAmount, expectedOut, 0.000001 ether, 'Should preview GHO amount');
  }

  function testPreviewSwapFromGHO(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    assertEq(outputAmount, expectedOut, 'Should preview output amount');
  }

  function testPreviewSwapFromGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
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

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
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

    uint256 fee = amount / 10; // 10% fee
    uint256 expectedOut = ((amount - fee) * 1e18) / 1e6;

    assertApproxEqAbs(sghoAmount, expectedOut, 0.000001 ether, 'Should preview sGHO amount');
  }

  function testPreviewSwapToSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
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

  function testPreviewSwapFromSGHOUSDX_4626_TOKEN(uint256 amount) public view {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    assertEq(outputAmount, expectedOut, 'Should preview USDX_4626_TOKEN output');
  }

  function testPreviewSwapFromSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
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
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
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
