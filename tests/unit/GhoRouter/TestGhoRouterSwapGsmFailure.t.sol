// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter swaps when the underlying GSM reverts
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSwapGsmFailure.t.sol -vvv
 */
contract SwapGsmFailureTest is TestGhoRouterBase {
  function testSwapFromGHOAmountTooSmallToBuyAsset(uint256 amount) public {
    uint256 ghoForOneShare = _ghoForBuy(USDX_4626_TOKEN.previewMint(1) * 1e12);
    amount = bound(amount, 1, ghoForOneShare - 1);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.prank(USER);
    vm.expectRevert(bytes('INVALID_AMOUNT'));
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

  function testSwapFromSGHOAmountTooSmallToBuyAsset(uint256 amount) public {
    uint256 ghoForOneShare = _ghoForBuy(USDX_4626_TOKEN.previewMint(1) * 1e12);
    amount = bound(amount, 1, ghoForOneShare - 1);
    _mintSgho(amount);
    vm.prank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    vm.prank(USER);
    vm.expectRevert(bytes('INVALID_AMOUNT'));
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapToGHOAmountTooSmallToWrap() public {
    _setUsdxVaultRate(2, 1);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), 1);
    assertEq(USDX_4626_TOKEN.previewDeposit(1), 0);

    vm.prank(USER);
    vm.expectRevert(bytes('INVALID_AMOUNT'));
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapToGHOWhenGsmFrozen() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(address(GHO_GSM_SWAP_FREEZER));
    GHO_GSM_4626.setSwapFreeze(true);

    vm.prank(USER);
    vm.expectRevert(bytes('GSM_FROZEN'));
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapFromGHOWhenGsmFrozen() public {
    uint256 amount = 1_000 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(address(GHO_GSM_SWAP_FREEZER));
    GHO_GSM_4626.setSwapFreeze(true);

    vm.prank(USER);
    vm.expectRevert(bytes('GSM_FROZEN'));
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

  function testSwapToGHOWhenGsmSeized() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
    GHO_GSM_4626.seize();

    vm.prank(USER);
    vm.expectRevert(bytes('GSM_SEIZED'));
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapFromGHOWhenGsmSeized() public {
    uint256 amount = 1_000 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
    GHO_GSM_4626.seize();

    vm.prank(USER);
    vm.expectRevert(bytes('GSM_SEIZED'));
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

  function testSwapToGHOExposureCapReached() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);
    GHO_GSM_4626.updateExposureCap(uint128(GHO_GSM_4626.getAvailableLiquidity()));

    vm.prank(USER);
    vm.expectRevert(bytes('EXOGENOUS_ASSET_EXPOSURE_TOO_HIGH'));
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapFromGHOInsufficientGsmLiquidity() public {
    uint256 amount = 2 * MAX_FUZZ_AMOUNT_18_DECIMALS;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.prank(USER);
    vm.expectRevert(bytes('INSUFFICIENT_AVAILABLE_EXOGENOUS_ASSET_LIQUIDITY'));
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
}
