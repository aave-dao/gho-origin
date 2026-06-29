// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterAllowGsm.t.sol -vvv
 */
contract AllowGsmTest is TestGhoRouterBase {
  function testAllowGsmNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.allowGsm(address(GHO_GSM));
  }

  function testAllowGsmZeroAddress() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.allowGsm(address(0));
  }

  function testAllowGsmNoCode() public {
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowGsm(makeAddr('eoa'));
  }

  function testAllowGsmNotGhoToken() public {
    BadGsm gsm = new BadGsm(makeAddr('bad-gho'), address(USDX_TOKEN));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowGsm(address(gsm));
  }

  function testAllowGsmNoUnderlying() public {
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(0));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowGsm(address(gsm));
  }

  function testAllowGsmAlreadySet() public {
    // GHO_GSM_4626 is allowed in setUp
    vm.expectRevert(IGhoRouter.GsmAlreadySet.selector);
    GHO_ROUTER.allowGsm(address(GHO_GSM_4626));
  }

  function testAllowGsm() public {
    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM)), false);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.GsmAdded(address(GHO_GSM));
    GHO_ROUTER.allowGsm(address(GHO_GSM));

    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM)), true);
  }

  function testRevokeGsmNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.revokeGsm(address(GHO_GSM_4626));
  }

  function testRevokeGsmNotSet() public {
    vm.expectRevert(IGhoRouter.GsmNotSet.selector);
    GHO_ROUTER.revokeGsm(address(GHO_GSM));
  }

  function testRevokeGsm() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.GsmRemoved(address(GHO_GSM_4626));
    GHO_ROUTER.revokeGsm(address(GHO_GSM_4626));

    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM_4626)), false);
  }
}

contract SetTokenToStataTest is TestGhoRouterBase {
  function testSetTokenToStataNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(USDX_4626_TOKEN));
  }

  function testSetTokenToStataZeroToken() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.setTokenToStata(address(0), address(USDX_4626_TOKEN));
  }

  function testSetTokenToStataZeroStata() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(0));
  }

  function testSetTokenToStataAlreadySet() public {
    // USDX_TOKEN is mapped in setUp
    vm.expectRevert(IGhoRouter.TokenToStataAlreadySet.selector);
    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(USDX_4626_TOKEN));
  }

  function testSetTokenToStataAssetMismatch() public {
    // A stata whose asset() does not return the provided token reverts cleanly
    BadStata stata = new BadStata();
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.setTokenToStata(makeAddr('token'), address(stata));
  }

  function testSetTokenToStata() public {
    TestnetERC20 token = new TestnetERC20('Token', 'TKN', 6, FAUCET);
    MockERC4626 stata = new MockERC4626('Token 4626', 'TKN4626', address(token));

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToStataSet(address(token), address(stata));
    GHO_ROUTER.setTokenToStata(address(token), address(stata));

    assertEq(GHO_ROUTER.tokenToStata(address(token)), address(stata));
  }

  function testRemoveTokenToStataNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.removeTokenToStata(address(USDX_TOKEN));
  }

  function testRemoveTokenToStataNotSet() public {
    vm.expectRevert(IGhoRouter.TokenToStataNotSet.selector);
    GHO_ROUTER.removeTokenToStata(makeAddr('token'));
  }

  function testRemoveTokenToStata() public {
    // USDX_TOKEN is mapped in setUp
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToStataRemoved(address(USDX_TOKEN), address(USDX_4626_TOKEN));
    GHO_ROUTER.removeTokenToStata(address(USDX_TOKEN));

    assertEq(GHO_ROUTER.tokenToStata(address(USDX_TOKEN)), address(0));
  }
}
