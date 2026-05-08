// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import '../TestGhoBase.t.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';

contract BadGsm {
  address public immutable GHO_TOKEN;
  address public immutable UNDERLYING_ASSET;

  constructor(address gho, address ua) {
    GHO_TOKEN = gho;
    UNDERLYING_ASSET = ua;
  }
}

contract BadStata {
  function asset() external pure returns (address) {
    return address(0);
  }
}

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/GhoRouterTest.t.sol -vvv
 */
contract GhoRouterTest is TestGhoBase {
  // Test user address
  address constant USER = address(0xF00DBA11);
  address constant RECIPIENT = address(0xCAFEF00D);
  uint256 public constant EXPECTED_OUT_GHO_TO_TOKEN = 909090909;

  function setUp() public {
    uint256 amount = 10_000e6;
    GHO_ROUTER.setTokenToGsm(address(USDX_4626_TOKEN), address(GHO_GSM_4626));
    deal(address(USDX_4626_TOKEN), address(this), amount);
    USDX_4626_TOKEN.approve(address(GHO_GSM_4626), amount);
    GHO_GSM_4626.sellAsset(amount, address(this));

    deal(address(USDX_TOKEN), address(USDX_4626_TOKEN), amount);
  }
}

contract ConstructorTest is TestGhoBase {
  function testConstructorZeroAddressGHO() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    new GhoRouter(address(this), address(0), address(SGHO));
  }

  function testConstructorZeroAddressSGHO() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    new GhoRouter(address(this), address(GHO_TOKEN), address(0));
  }

  function testConstructorInvalidSGho() public {
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    new GhoRouter(address(this), address(GHO_TOKEN), address(USDX_4626_TOKEN));
  }

  function testConstructor() public {
    GhoRouter router = new GhoRouter(address(this), address(GHO_TOKEN), address(SGHO));
    assertEq(router.GHO(), address(GHO_TOKEN));
    assertEq(router.sGHO(), address(SGHO));
  }
}

contract SetTokenToGsmTest is GhoRouterTest {
  function testSetTokenToGsmNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.setTokenToGsm(address(USDX_4626_TOKEN), address(GHO_GSM_4626));
  }

  function testSetTokenToGsmTokenZeroAddress() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.setTokenToGsm(address(0), address(GHO_GSM_4626));
  }

  function testSetTokenToGsmGSMZeroAddress() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_4626_TOKEN), address(0));
  }

  function testSetTokenToGsmNoCode() public {
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), makeAddr('eoa'));
  }

  function testSetTokenToGsmNotGhoToken() public {
    BadGsm gsm = new BadGsm(makeAddr('bad-gho'), address(USDX_TOKEN));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(gsm));
  }

  function testSetTokenToGsmNotStata() public {
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(0));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(gsm));
  }

  function testSetTokenToGsmNotUnderlying() public {
    BadStata stata = new BadStata();
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(stata));
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(gsm));
  }

  function testSetTokenToGsmAlreadySet() public {
    vm.expectRevert(IGhoRouter.TokenToGsmAlreadySet.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_4626_TOKEN), address(GHO_GSM_4626));
  }

  function testSetTokenToGsm() public {
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(0));

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmAdded(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(GHO_GSM_4626));
  }

  function testRemoveTokenToGsm() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmAdded(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(GHO_GSM_4626));

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmRemoved(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.removeTokenToGsm(address(USDX_TOKEN));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(0));
  }
}

contract RescueTokenTest is GhoRouterTest {
  function testRescueTokenInvalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    vm.prank(USER);
    GHO_ROUTER.rescueToken(address(GHO_TOKEN), RECIPIENT, 1);
  }

  function testRescueTokenZeroAddressToken() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.rescueToken(address(0), RECIPIENT, 1);
  }

  function testRescueTokenZeroAddressRecipient() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.rescueToken(address(GHO_TOKEN), address(0), 1);
  }

  function testRescueToken() public {
    uint256 amount = 1_000 ether;
    deal(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), amount);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 0);

    GHO_ROUTER.rescueToken(address(GHO_TOKEN), RECIPIENT, amount);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), 0);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), amount);
  }
}

contract PreviewSwapsTest is GhoRouterTest {
  function testPreviewSwapToGHOZeroAmount() public {
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.previewSwap(address(USDX_4626_TOKEN), address(GHO_TOKEN), 0);
  }

  function testPreviewSwapToGHO() public view {
    uint256 amount = 1_000e6;
    uint256 ghoAmount = GHO_ROUTER.previewSwap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      amount
    );

    uint256 fee = amount / 10; // 10% fee
    uint256 expectedOut = ((amount - fee) * 1e18) / 1e6;

    assertEq(ghoAmount, expectedOut, 'Should preview GHO amount');
  }

  function testPreviewSwapToGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(WETH), address(GHO_TOKEN), 1);
  }

  function testPreviewSwapFromGHO() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount
    );

    assertEq(outputAmount, EXPECTED_OUT_GHO_TO_TOKEN, 'Should preview output amount');
  }

  function testPreviewSwapFromGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(GHO_TOKEN), address(WETH), 1);
  }

  function testPreviewSwapFromGHOToStataUSDX_4626_TOKEN() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount
    );

    assertEq(outputAmount, EXPECTED_OUT_GHO_TO_TOKEN, 'Should preview static aToken output amount');
  }

  function testPreviewSwapToSGHO() public view {
    uint256 amount = 1_000e6;
    uint256 sghoAmount = GHO_ROUTER.previewSwap(address(USDX_4626_TOKEN), address(SGHO), amount);

    uint256 fee = amount / 10; // 10% fee
    uint256 expectedOut = ((amount - fee) * 1e18) / 1e6;

    assertEq(sghoAmount, expectedOut, 'Should preview sGHO amount');
  }

  function testPreviewSwapToSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(WETH), address(SGHO), 1);
  }

  function testPreviewDepositForSGHO() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(address(GHO_TOKEN), address(SGHO), amount);

    assertEq(outputAmount, amount, 'sGHO copy preview should be 1:1 at initial index');
  }

  function testPreviewSwapFromSGHOUSDX_4626_TOKEN() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(address(SGHO), address(USDX_4626_TOKEN), amount);

    assertEq(outputAmount, EXPECTED_OUT_GHO_TO_TOKEN, 'Should preview USDX_4626_TOKEN output');
  }

  function testPreviewSwapFromSGHOInconsistentTokens() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.previewSwap(address(SGHO), address(WETH), 1);
  }

  function testPreviewSwapFromSGHOStataUSDX_4626_TOKEN() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(address(SGHO), address(USDX_4626_TOKEN), amount);

    assertEq(outputAmount, EXPECTED_OUT_GHO_TO_TOKEN, 'Should preview static aToken output');
  }

  function testPreviewRedeemSGho() public view {
    uint256 amount = 1_000 ether;
    uint256 outputAmount = GHO_ROUTER.previewSwap(address(SGHO), address(GHO_TOKEN), amount);

    assertEq(outputAmount, amount, 'Should preview static aToken output');
  }
}
