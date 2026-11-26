// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

import {IERC4626} from '@openzeppelin/contracts/interfaces/IERC4626.sol';
import {PausableUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol';
import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';

import {AaveV3StataEnvironment} from '../../helpers/AaveV3StataEnvironment.sol';

/**
 * @title TestGhoRouterStata
 * @notice GhoRouter against a real StataTokenV2 on a local Aave v3 market
 */
contract TestGhoRouterStata is TestGhoRouterBase {
  uint256 internal constant GSM_SEED = 1_000_000e6;
  uint256 internal constant SWAP_AMOUNT = 10_000e6;
  uint256 internal constant GHO_SWAP_AMOUNT = 1_000 ether;
  uint256 internal constant RAY = 1e27;

  AaveV3StataEnvironment internal AAVE;
  address internal AAVE_USDX;
  IERC4626 internal STATA_USDX;
  Gsm4626 internal STATA_GSM;

  function setUp() public override {
    super.setUp();

    AAVE = new AaveV3StataEnvironment();
    AAVE.deploy();
    AAVE_USDX = AAVE.usdxToken();
    STATA_USDX = IERC4626(AAVE.stataToken(AAVE_USDX));

    STATA_GSM = _deployGsm4626Proxy({
      underlyingToken: address(STATA_USDX),
      priceStrategy: address(
        new FixedPriceStrategy4626(DEFAULT_FIXED_PRICE, address(STATA_USDX), 6)
      ),
      exposureCap: DEFAULT_GSM_USDX_EXPOSURE
    });
    STATA_GSM.updateFeeStrategy(address(GHO_GSM_FIXED_FEE_STRATEGY));
    GHO_RESERVE.addEntity(address(STATA_GSM));
    GHO_RESERVE.setLimit(address(STATA_GSM), DEFAULT_CAPACITY);
    vm.prank(FAUCET);
    GHO_TOKEN.mint(address(GHO_RESERVE), DEFAULT_CAPACITY);

    GHO_ROUTER.allowGsm(address(STATA_GSM));
    GHO_ROUTER.setTokenToStata(AAVE_USDX, address(STATA_USDX));

    // Seed the GSM with stataUSDX so the GHO -> USDX routes have liquidity to buy
    deal(AAVE_USDX, address(this), GSM_SEED);
    IERC20(AAVE_USDX).approve(address(STATA_USDX), GSM_SEED);
    uint256 seedShares = STATA_USDX.deposit(GSM_SEED, address(this));
    IERC20(address(STATA_USDX)).approve(address(STATA_GSM), seedShares);
    STATA_GSM.sellAsset(seedShares, address(this));
  }

  /// @dev 10,000 USDX wrap 1:1 at rate 1, minus the 10% sell fee
  function test_stata_tokenToGho() external {
    _assertTokenToGho(9_000 ether);
  }

  function test_stata_tokenToGho_indexAboveOne(uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    _assertTokenToGho(_expectedGhoForSell(SWAP_AMOUNT));
  }

  /// @dev Same GHO as `test_stata_tokenToGho`, deposited into sGHO at index 1
  function test_stata_tokenToSGho() external {
    _assertTokenToSGho(9_000 ether);
  }

  function test_stata_tokenToSGho_indexAboveOne(uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    _assertTokenToSGho(_expectedGhoForSell(SWAP_AMOUNT));
  }

  /// @dev 1,000 GHO buy 1,000 / 1.1 USDX after the 10% buy fee, floored to 6 decimals
  function test_stata_ghoToToken() external {
    _assertGhoToToken(909_090909);
  }

  function test_stata_ghoToToken_indexAboveOne(uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    _assertGhoToToken(_expectedUsdxForBuy(GHO_SWAP_AMOUNT));
  }

  /// @dev 1,000 sGHO redeem to 1,000 GHO at index 1, then buy as in `test_stata_ghoToToken`
  function test_stata_sGhoToToken() external {
    _assertSGhoToToken(909_090909);
  }

  function test_stata_sGhoToToken_indexAboveOne(uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    _assertSGhoToToken(_expectedUsdxForBuy(GHO_SWAP_AMOUNT));
  }

  /// @dev A paused reserve blocks both the wrap and the unwrap, while previews still quote an amount
  function test_stata_reservePaused() external {
    AAVE.setReservePaused(AAVE_USDX, true);
    _assertWrapReverts(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector);
    _assertUnwrapReverts(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector);
  }

  /// @dev A frozen reserve blocks new deposits only, so the unwrap still goes through
  function test_stata_reserveFrozen() external {
    AAVE.setReserveFrozen(AAVE_USDX, true);
    _assertWrapReverts(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector);
    _assertGhoToToken(909_090909);
  }

  function test_stata_supplyCapReached() external {
    // Supply cap in whole USDX, below what the GSM seed already supplied
    AAVE.setSupplyCap(AAVE_USDX, 1);
    _assertWrapReverts(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector);
  }

  /// @dev With the reserve borrowed out the unwrap reverts, but buying the static aToken itself works
  function test_stata_liquidityBorrowedOut() external {
    AAVE.borrow(AAVE_USDX, AAVE.availableLiquidity(AAVE_USDX));
    assertEq(AAVE.availableLiquidity(AAVE_USDX), 0, 'reserve not borrowed out');
    _assertUnwrapReverts(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector);

    uint256 ghoAmount = 1_000 ether;
    uint256 preview = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(STATA_USDX),
      address(STATA_GSM),
      ghoAmount
    );
    uint256 amountOut = _swap(address(GHO_TOKEN), address(STATA_USDX), ghoAmount);
    assertEq(amountOut, preview, 'output != preview');
    assertEq(STATA_USDX.balanceOf(RECIPIENT), amountOut, 'recipient stata balance');
    _assertRouterClean();
  }

  /// @dev A paused static aToken cannot be minted, burned or transferred
  function test_stata_stataPaused() external {
    AAVE.setStataPaused(address(STATA_USDX), true);
    assertFalse(GHO_ROUTER.paused(), 'router paused');
    _assertWrapReverts(PausableUpgradeable.EnforcedPause.selector);
    _assertUnwrapReverts(PausableUpgradeable.EnforcedPause.selector);
  }

  /// @dev The wrap path may pay up to one static aToken share more than previewed, never less
  function _assertTokenToGho(uint256 expected) internal {
    uint256 preview = GHO_ROUTER.previewSwap(
      AAVE_USDX,
      address(GHO_TOKEN),
      address(STATA_GSM),
      SWAP_AMOUNT
    );
    uint256 amountOut = _swap(AAVE_USDX, address(GHO_TOKEN), SWAP_AMOUNT);

    assertEq(amountOut, expected, 'output');
    assertGe(amountOut, preview, 'output below preview');
    assertLe(amountOut - preview, _oneShareInGho(), 'output above preview by more than one share');
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), amountOut, 'recipient GHO balance');
    _assertRouterClean();
  }

  function _assertTokenToSGho(uint256 expected) internal {
    assertEq(SGHO.convertToAssets(1 ether), 1 ether, 'sGHO index not 1');
    uint256 preview = GHO_ROUTER.previewSwap(
      AAVE_USDX,
      address(SGHO),
      address(STATA_GSM),
      SWAP_AMOUNT
    );
    uint256 amountOut = _swap(AAVE_USDX, address(SGHO), SWAP_AMOUNT);

    assertEq(amountOut, expected, 'output');
    assertGe(amountOut, preview, 'output below preview');
    assertLe(
      SGHO.convertToAssets(amountOut - preview),
      _oneShareInGho(),
      'output above preview by more than one share'
    );
    assertEq(IERC20(address(SGHO)).balanceOf(RECIPIENT), amountOut, 'recipient sGHO balance');
    _assertRouterClean();
  }

  function _assertGhoToToken(uint256 expected) internal {
    uint256 ghoAmount = GHO_SWAP_AMOUNT;
    uint256 preview = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      AAVE_USDX,
      address(STATA_GSM),
      ghoAmount
    );
    uint256 amountOut = _swap(address(GHO_TOKEN), AAVE_USDX, ghoAmount);

    assertEq(amountOut, expected, 'output');
    assertEq(amountOut, preview, 'output != preview');
    assertEq(IERC20(AAVE_USDX).balanceOf(RECIPIENT), amountOut, 'recipient USDX balance');
    _assertRouterClean();
  }

  function _assertSGhoToToken(uint256 expected) internal {
    assertEq(SGHO.convertToAssets(1 ether), 1 ether, 'sGHO index not 1');
    _mintSgho(GHO_SWAP_AMOUNT);
    uint256 sghoAmount = IERC20(address(SGHO)).balanceOf(USER);
    uint256 preview = GHO_ROUTER.previewSwap(
      address(SGHO),
      AAVE_USDX,
      address(STATA_GSM),
      sghoAmount
    );
    vm.prank(USER);
    IERC20(address(SGHO)).approve(address(GHO_ROUTER), sghoAmount);
    vm.prank(USER);
    uint256 amountOut = GHO_ROUTER.swap({
      tokenIn: address(SGHO),
      tokenOut: AAVE_USDX,
      gsm: address(STATA_GSM),
      exactAmountIn: sghoAmount,
      minAmountOut: preview,
      recipient: RECIPIENT,
      deadline: block.timestamp
    });

    assertEq(amountOut, expected, 'output');
    assertEq(amountOut, preview, 'output != preview');
    assertEq(IERC20(AAVE_USDX).balanceOf(RECIPIENT), amountOut, 'recipient USDX balance');
    _assertRouterClean();
  }

  /// @dev USDX -> GHO reverts with `selector` on the stata deposit, while the preview still quotes
  function _assertWrapReverts(bytes4 selector) internal {
    assertGt(
      GHO_ROUTER.previewSwap(AAVE_USDX, address(GHO_TOKEN), address(STATA_GSM), SWAP_AMOUNT),
      0,
      'wrap preview'
    );
    _dealAndApprove(AAVE_USDX, address(GHO_ROUTER), SWAP_AMOUNT);
    vm.expectPartialRevert(selector);
    vm.prank(USER);
    GHO_ROUTER.swap({
      tokenIn: AAVE_USDX,
      tokenOut: address(GHO_TOKEN),
      gsm: address(STATA_GSM),
      exactAmountIn: SWAP_AMOUNT,
      minAmountOut: 0,
      recipient: RECIPIENT,
      deadline: block.timestamp
    });
  }

  /// @dev GHO -> USDX reverts with `selector` on the stata redeem, while the preview still quotes
  function _assertUnwrapReverts(bytes4 selector) internal {
    uint256 ghoAmount = 1_000 ether;
    assertGt(
      GHO_ROUTER.previewSwap(address(GHO_TOKEN), AAVE_USDX, address(STATA_GSM), ghoAmount),
      0,
      'unwrap preview'
    );
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), ghoAmount);
    vm.expectPartialRevert(selector);
    vm.prank(USER);
    GHO_ROUTER.swap({
      tokenIn: address(GHO_TOKEN),
      tokenOut: AAVE_USDX,
      gsm: address(STATA_GSM),
      exactAmountIn: ghoAmount,
      minAmountOut: 0,
      recipient: RECIPIENT,
      deadline: block.timestamp
    });
  }

  function _swap(address tokenIn, address tokenOut, uint256 amount) internal returns (uint256) {
    _dealAndApprove(tokenIn, address(GHO_ROUTER), amount);
    vm.prank(USER);
    return
      GHO_ROUTER.swap({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        gsm: address(STATA_GSM),
        exactAmountIn: amount,
        minAmountOut: 0,
        recipient: RECIPIENT,
        deadline: block.timestamp
      });
  }

  /// @dev Borrows half the reserve and lets interest accrue, so the stata rate grows above 1
  function _growIndex(uint256 elapsed) internal {
    uint256 rateBefore = STATA_USDX.convertToAssets(1e6);
    AAVE.borrow(AAVE_USDX, AAVE.availableLiquidity(AAVE_USDX) / 2);
    vm.warp(block.timestamp + elapsed);
    assertGt(STATA_USDX.convertToAssets(1e6), rateBefore, 'stata rate did not grow');
  }

  /// @dev GHO for selling `usdxAmount` through the stata GSM: wrap at the pool rate (floor), value
  /// the shares at 1:1 (floor, 6 -> 18 decimals), minus the 10% sell fee (rounded up)
  function _expectedGhoForSell(uint256 usdxAmount) internal view returns (uint256) {
    uint256 rate = AAVE.normalizedIncome(AAVE_USDX);
    uint256 shares = Math.mulDiv(usdxAmount, RAY, rate);
    uint256 gross = Math.mulDiv(shares, rate, RAY) * 1e12;
    return gross - Math.mulDiv(gross, sellFee, 1e4, Math.Rounding.Ceil);
  }

  /// @dev USDX for buying with `ghoAmount` through the stata GSM and unwrapping. The GSM quotes the
  /// shares `ghoAmount` buys net of the 10% buy fee, re-prices them on the buy (rounding up), then
  /// the shares are redeemed at the pool rate (floor)
  function _expectedUsdxForBuy(uint256 ghoAmount) internal view returns (uint256) {
    uint256 rate = AAVE.normalizedIncome(AAVE_USDX);
    uint256 quotedShares = Math.mulDiv(
      (Math.mulDiv(ghoAmount, 1e4, 1e4 + buyFee)) / 1e12,
      RAY,
      rate
    );

    uint256 buyGross = Math.mulDiv(quotedShares, rate, RAY, Math.Rounding.Ceil) * 1e12;
    uint256 ghoSold = buyGross + Math.mulDiv(buyGross, buyFee, 1e4, Math.Rounding.Ceil);
    uint256 boughtShares = Math.mulDiv(Math.mulDiv(ghoSold, 1e4, 1e4 + buyFee) / 1e12, RAY, rate);
    return Math.mulDiv(boughtShares, rate, RAY);
  }

  /// @dev GHO value of one static aToken share, at the GSM's 1:1 price and 6 -> 18 decimals
  function _oneShareInGho() internal view returns (uint256) {
    return STATA_USDX.previewMint(1) * 1e12;
  }

  function _assertRouterClean() internal view {
    address router = address(GHO_ROUTER);
    assertEq(GHO_TOKEN.balanceOf(router), 0, 'router GHO');
    assertEq(IERC20(address(SGHO)).balanceOf(router), 0, 'router sGHO');
    assertEq(IERC20(AAVE_USDX).balanceOf(router), 0, 'router USDX');
    assertEq(STATA_USDX.balanceOf(router), 0, 'router stata');
    assertEq(
      IERC20(AAVE_USDX).allowance(router, address(STATA_USDX)),
      0,
      'USDX -> stata allowance'
    );
    assertEq(
      IERC20(address(STATA_USDX)).allowance(router, address(STATA_GSM)),
      0,
      'stata -> GSM allowance'
    );
    assertEq(GHO_TOKEN.allowance(router, address(STATA_GSM)), 0, 'GHO -> GSM allowance');
    assertEq(GHO_TOKEN.allowance(router, address(SGHO)), 0, 'GHO -> sGHO allowance');
  }
}
