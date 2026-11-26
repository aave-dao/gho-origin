// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import '../../unit/GhoRouter/TestGhoRouterBase.t.sol';

import {IERC4626} from '@openzeppelin/contracts/interfaces/IERC4626.sol';
import {PausableUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol';
import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';

import {AaveV3StataEnvironment} from '../../helpers/AaveV3StataEnvironment.sol';

/**
 * @title TestGhoRouterStata
 * @notice GhoRouter against a real StataTokenV2 on a local Aave v3 market
 */
contract TestGhoRouterStata is TestGhoRouterBase {
  using SafeCast for uint256;

  uint256 internal constant GSM_SEED = 1_000_000e6;
  uint256 internal constant SWAP_AMOUNT = 10_000e6;
  uint256 internal constant GHO_SWAP_AMOUNT = 1_000 ether;
  uint256 internal constant MIN_USDX = 1e6;
  uint256 internal constant MAX_USDX = 500_000e6;
  uint256 internal constant MIN_GHO = 1 ether;
  uint256 internal constant MAX_GHO = 500_000 ether;
  /// @dev Keeps the redeemed GHO, after up to 5 years at the max sGHO rate, within the GSM's stataUSDX
  uint256 internal constant MAX_SGHO_DEPOSIT = 20_000 ether;

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

  /// @dev 10,000 USDX wrap 1:1 at rate 1 and sell for 9,000 GHO after the 10% fee. The GSM takes
  /// every share, so nothing is refunded
  function test_stata_tokenToGho() external {
    _assertTokenToGho(SWAP_AMOUNT, 9_000 ether, 0);
  }

  function test_stata_tokenToGho_fuzzAmount(uint256 amount) external {
    amount = bound(amount, MIN_USDX, MAX_USDX);
    (uint256 gho, uint256 refund) = _expectedSell(amount);
    _assertTokenToGho(amount, gho, refund);
  }

  function test_stata_tokenToGho_indexAboveOne(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    amount = bound(amount, MIN_USDX, MAX_USDX);
    (uint256 gho, uint256 refund) = _expectedSell(amount);
    _assertTokenToGho(amount, gho, refund);
  }

  /// @dev Same GHO as `test_stata_tokenToGho`, deposited into sGHO at index 1
  function test_stata_tokenToSGho() external {
    _assertSGhoIndexOne();
    _assertTokenToSGho(SWAP_AMOUNT, 9_000 ether, 0);
  }

  function test_stata_tokenToSGho_fuzzAmount(uint256 amount) external {
    amount = bound(amount, MIN_USDX, MAX_USDX);
    (uint256 gho, uint256 refund) = _expectedSell(amount);
    _assertSGhoIndexOne();
    _assertTokenToSGho(amount, gho, refund);
  }

  function test_stata_tokenToSGho_indexAboveOne(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    amount = bound(amount, MIN_USDX, MAX_USDX);
    (uint256 gho, uint256 refund) = _expectedSell(amount);
    _assertSGhoIndexOne();
    _assertTokenToSGho(amount, gho, refund);
  }

  /// @dev 1,000 GHO buy 1,000 / 1.1 USDX after the 10% buy fee, floored to 6 decimals. The GSM
  /// charges 999.9999999 GHO for it, so 1e11 wei of GHO stays with the sender
  function test_stata_ghoToToken() external {
    _assertGhoToToken(GHO_SWAP_AMOUNT, 909_090909, 1e11);
  }

  function test_stata_ghoToToken_fuzzAmount(uint256 amount) external {
    amount = bound(amount, MIN_GHO, MAX_GHO);
    (uint256 usdx, uint256 ghoSold) = _expectedBuy(amount);
    _assertGhoToToken(amount, usdx, amount - ghoSold);
  }

  function test_stata_ghoToToken_indexAboveOne(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    amount = bound(amount, MIN_GHO, MAX_GHO);
    (uint256 usdx, uint256 ghoSold) = _expectedBuy(amount);
    _assertGhoToToken(amount, usdx, amount - ghoSold);
  }

  /// @dev 1,000 sGHO redeem to 1,000 GHO at index 1, then buy as in `test_stata_ghoToToken`, and the
  /// unspent 1e11 wei of GHO is refunded to the sender
  function test_stata_sGhoToToken() external {
    _assertSGhoIndexOne();
    _mintSgho(GHO_SWAP_AMOUNT);
    _assertSGhoToToken(GHO_SWAP_AMOUNT, 909_090909, 1e11);
  }

  function test_stata_sGhoToToken_fuzzAmount(uint256 amount) external {
    amount = bound(amount, MIN_GHO, MAX_GHO);
    (uint256 usdx, uint256 ghoSold) = _expectedBuy(amount);
    _assertSGhoIndexOne();
    _mintSgho(amount);
    _assertSGhoToToken(amount, usdx, amount - ghoSold);
  }

  function test_stata_sGhoToToken_indexAboveOne(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    amount = bound(amount, MIN_GHO, MAX_GHO);
    (uint256 usdx, uint256 ghoSold) = _expectedBuy(amount);
    _assertSGhoIndexOne();
    _mintSgho(amount);
    _assertSGhoToToken(amount, usdx, amount - ghoSold);
  }

  /// @dev With the stata rate and the sGHO index both above 1, the GHO from the sale buys fewer sGHO
  /// shares than it would at index 1
  function test_stata_tokenToSGho_sGhoRateUp(
    uint256 amount,
    uint256 rate,
    uint256 elapsed
  ) external {
    _setSGhoRate(rate);
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));
    assertGt(SGHO.convertToAssets(1 ether), 1 ether, 'sGHO index did not grow');
    amount = bound(amount, MIN_USDX, MAX_USDX);
    (uint256 gho, uint256 refund) = _expectedSell(amount);
    _assertTokenToSGho(amount, SGHO.previewDeposit(gho), refund);
  }

  /// @dev With the stata rate and the sGHO index both above 1, the shares redeem for more GHO than
  /// was deposited, and that GHO is what the GSM buy is priced on
  function test_stata_sGhoToToken_sGhoRateUp(
    uint256 amount,
    uint256 rate,
    uint256 elapsed
  ) external {
    _setSGhoRate(rate);
    amount = bound(amount, MIN_GHO, MAX_SGHO_DEPOSIT);
    _mintSgho(amount);
    _growIndex(bound(elapsed, 1 days, 5 * 365 days));

    uint256 ghoRedeemed = SGHO.previewRedeem(IERC20(address(SGHO)).balanceOf(USER));
    assertGt(ghoRedeemed, amount, 'sGHO index did not grow');
    // Fund the vault so it can pay out the accrued yield on redeem
    deal(address(GHO_TOKEN), address(SGHO), ghoRedeemed * 2);
    (uint256 usdx, uint256 ghoSold) = _expectedBuy(ghoRedeemed);
    _assertSGhoToToken(amount, usdx, ghoRedeemed - ghoSold);
  }

  /// @dev Asking for one wei more than the route pays reverts, on the wrap and the unwrap paths
  function test_stata_slippage(uint256 usdxAmount, uint256 ghoAmount) external {
    usdxAmount = bound(usdxAmount, MIN_USDX, MAX_USDX);
    ghoAmount = bound(ghoAmount, MIN_GHO, MAX_GHO);
    (uint256 gho, ) = _expectedSell(usdxAmount);
    (uint256 usdx, ) = _expectedBuy(ghoAmount);

    _assertSlippageReverts(AAVE_USDX, address(GHO_TOKEN), usdxAmount, gho + 1);
    _assertSlippageReverts(AAVE_USDX, address(SGHO), usdxAmount, gho + 1);
    _assertSlippageReverts(address(GHO_TOKEN), AAVE_USDX, ghoAmount, usdx + 1);
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
    _assertGhoToToken(GHO_SWAP_AMOUNT, 909_090909, 1e11);
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
    (, uint256 ghoSold) = _expectedBuy(ghoAmount);
    uint256 amountOut = _swap({
      tokenIn: address(GHO_TOKEN),
      tokenOut: address(STATA_USDX),
      amount: ghoAmount,
      expectedAmountIn: ghoSold,
      expectedOut: preview
    });
    assertEq(amountOut, preview, 'output != preview');
    assertEq(STATA_USDX.balanceOf(RECIPIENT), amountOut, 'recipient stata balance');
    _assertGhoKeptBySender(ghoAmount - ghoSold);
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
  function _assertTokenToGho(uint256 amount, uint256 expected, uint256 expectedRefund) internal {
    uint256 preview = GHO_ROUTER.previewSwap(
      AAVE_USDX,
      address(GHO_TOKEN),
      address(STATA_GSM),
      amount
    );
    uint256 amountOut = _swap({
      tokenIn: AAVE_USDX,
      tokenOut: address(GHO_TOKEN),
      amount: amount,
      expectedAmountIn: amount,
      expectedOut: expected
    });

    assertEq(amountOut, expected, 'output');
    assertGe(amountOut, preview, 'output below preview');
    assertLe(amountOut - preview, _oneShareInGho(), 'output above preview by more than one share');
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), amountOut, 'recipient GHO balance');
    _assertStataRefundedToSender(expectedRefund);
    _assertRouterClean();
  }

  function _assertTokenToSGho(uint256 amount, uint256 expected, uint256 expectedRefund) internal {
    uint256 preview = GHO_ROUTER.previewSwap(AAVE_USDX, address(SGHO), address(STATA_GSM), amount);
    uint256 amountOut = _swap({
      tokenIn: AAVE_USDX,
      tokenOut: address(SGHO),
      amount: amount,
      expectedAmountIn: amount,
      expectedOut: expected
    });

    assertEq(amountOut, expected, 'output');
    assertGe(amountOut, preview, 'output below preview');
    assertLe(
      SGHO.convertToAssets(amountOut - preview),
      _oneShareInGho(),
      'output above preview by more than one share'
    );
    assertEq(IERC20(address(SGHO)).balanceOf(RECIPIENT), amountOut, 'recipient sGHO balance');
    _assertStataRefundedToSender(expectedRefund);
    _assertRouterClean();
  }

  /// @dev The router pulls only the GHO the GSM charges, so the rest never leaves the sender
  function _assertGhoToToken(uint256 amount, uint256 expected, uint256 expectedGhoKept) internal {
    uint256 preview = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      AAVE_USDX,
      address(STATA_GSM),
      amount
    );
    // On GHO -> token routes the event reports the GHO the GSM charged, not the GHO offered
    uint256 amountOut = _swap({
      tokenIn: address(GHO_TOKEN),
      tokenOut: AAVE_USDX,
      amount: amount,
      expectedAmountIn: amount - expectedGhoKept,
      expectedOut: expected
    });

    assertEq(amountOut, expected, 'output');
    assertEq(amountOut, preview, 'output != preview');
    assertEq(IERC20(AAVE_USDX).balanceOf(RECIPIENT), amountOut, 'recipient USDX balance');
    _assertGhoKeptBySender(expectedGhoKept);
    _assertRouterClean();
  }

  /// @dev Swaps the sender's whole sGHO balance. GHO redeemed from sGHO but not spent by the GSM is
  /// refunded to the sender, not the recipient
  function _assertSGhoToToken(
    uint256 sghoAmountIn,
    uint256 expected,
    uint256 expectedRefund
  ) internal {
    uint256 sghoAmount = IERC20(address(SGHO)).balanceOf(USER);
    assertEq(sghoAmount, sghoAmountIn, 'sender sGHO');
    uint256 preview = GHO_ROUTER.previewSwap(
      address(SGHO),
      AAVE_USDX,
      address(STATA_GSM),
      sghoAmount
    );
    vm.prank(USER);
    IERC20(address(SGHO)).approve(address(GHO_ROUTER), sghoAmount);
    vm.expectEmit(address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, address(SGHO), AAVE_USDX, sghoAmount, expected, RECIPIENT);
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
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'sender sGHO left');
    _assertGhoKeptBySender(expectedRefund);
    _assertRouterClean();
  }

  /// @dev Static aToken shares the GSM did not take go back to the sender, and all USDX was pulled
  function _assertStataRefundedToSender(uint256 expectedRefund) internal view {
    assertEq(STATA_USDX.balanceOf(USER), expectedRefund, 'stata refund to sender');
    assertEq(STATA_USDX.balanceOf(RECIPIENT), 0, 'stata refund to recipient');
    assertEq(IERC20(AAVE_USDX).balanceOf(USER), 0, 'sender USDX left');
  }

  function _assertGhoKeptBySender(uint256 expectedGho) internal view {
    assertEq(GHO_TOKEN.balanceOf(USER), expectedGho, 'sender GHO');
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 0, 'recipient GHO');
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

  function _assertSlippageReverts(
    address tokenIn,
    address tokenOut,
    uint256 amount,
    uint256 minAmountOut
  ) internal {
    _dealAndApprove(tokenIn, address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      gsm: address(STATA_GSM),
      exactAmountIn: amount,
      minAmountOut: minAmountOut,
      recipient: RECIPIENT,
      deadline: block.timestamp
    });
  }

  /// @dev Swaps from `USER` to `RECIPIENT`, expecting the router's `Swap` event
  function _swap(
    address tokenIn,
    address tokenOut,
    uint256 amount,
    uint256 expectedAmountIn,
    uint256 expectedOut
  ) internal returns (uint256) {
    _dealAndApprove(tokenIn, address(GHO_ROUTER), amount);
    vm.expectEmit(address(GHO_ROUTER));
    emit IGhoRouter.Swap(USER, tokenIn, tokenOut, expectedAmountIn, expectedOut, RECIPIENT);
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

  function _assertSGhoIndexOne() internal view {
    assertEq(SGHO.convertToAssets(1 ether), 1 ether, 'sGHO index not 1');
  }

  function _setSGhoRate(uint256 rate) internal {
    SGHO.grantRole(SGHO.YIELD_MANAGER_ROLE(), address(this));
    SGHO.setTargetRate(bound(rate, 1, SGHO.MAX_SAFE_RATE()).toUint16());
  }

  /// @dev Borrows half the reserve and lets interest accrue, so the stata rate grows above 1
  function _growIndex(uint256 elapsed) internal {
    uint256 rateBefore = STATA_USDX.convertToAssets(1e6);
    AAVE.borrow(AAVE_USDX, AAVE.availableLiquidity(AAVE_USDX) / 2);
    vm.warp(block.timestamp + elapsed);
    assertGt(STATA_USDX.convertToAssets(1e6), rateBefore, 'stata rate did not grow');
  }

  /// @dev GHO from selling `usdxAmount` through the stata GSM, and the shares the GSM leaves unsold.
  /// The USDX wraps at the pool rate (floor) and the shares are valued 1:1 (floor, 6 -> 18 decimals)
  /// minus the 10% sell fee (rounded up). The GSM then takes only the shares worth that GHO grossed
  /// back up (rounded up), and the rest are refunded
  function _expectedSell(uint256 usdxAmount) internal view returns (uint256 gho, uint256 refund) {
    uint256 rate = AAVE.normalizedIncome(AAVE_USDX);
    uint256 shares = Math.mulDiv(usdxAmount, WadRayMath.RAY, rate);
    uint256 gross = Math.mulDiv(shares, rate, WadRayMath.RAY) * 1e12;
    gho = gross - Math.mulDiv(gross, sellFee, 1e4, Math.Rounding.Ceil);

    uint256 soldGross = Math.mulDiv(gho, 1e4, 1e4 - sellFee, Math.Rounding.Ceil);
    uint256 soldUsdx = Math.mulDiv(soldGross, 1, 1e12, Math.Rounding.Ceil);
    refund = shares - Math.mulDiv(soldUsdx, WadRayMath.RAY, rate, Math.Rounding.Ceil);
  }

  /// @dev USDX from buying with `ghoAmount` through the stata GSM and unwrapping, and the GHO the GSM
  /// charges. The GSM quotes the shares `ghoAmount` buys net of the 10% buy fee, re-prices them on
  /// the buy (rounding up), then the shares are redeemed at the pool rate (floor)
  function _expectedBuy(uint256 ghoAmount) internal view returns (uint256 usdx, uint256 ghoSold) {
    uint256 rate = AAVE.normalizedIncome(AAVE_USDX);
    uint256 quotedShares = Math.mulDiv(
      (Math.mulDiv(ghoAmount, 1e4, 1e4 + buyFee)) / 1e12,
      WadRayMath.RAY,
      rate
    );

    uint256 buyGross = Math.mulDiv(quotedShares, rate, WadRayMath.RAY, Math.Rounding.Ceil) * 1e12;
    ghoSold = buyGross + Math.mulDiv(buyGross, buyFee, 1e4, Math.Rounding.Ceil);
    uint256 boughtShares = Math.mulDiv(
      Math.mulDiv(ghoSold, 1e4, 1e4 + buyFee) / 1e12,
      WadRayMath.RAY,
      rate
    );
    usdx = Math.mulDiv(boughtShares, rate, WadRayMath.RAY);
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
