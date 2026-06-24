// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSetTokenToGsm.t.sol -vvv
 */
contract AllowTokenGsmTest is TestGhoRouterBase {
  function testAllowTokenGsmNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.allowTokenGsm(address(USDX_4626_TOKEN), address(GHO_GSM_4626));
  }

  function testAllowTokenGsmTokenZeroAddress() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.allowTokenGsm(address(0), address(GHO_GSM_4626));
  }

  function testAllowTokenGsmGSMZeroAddress() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.allowTokenGsm(address(USDX_4626_TOKEN), address(0));
  }

  function testAllowTokenGsmNoCode() public {
    address token = makeAddr('token');
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowTokenGsm(token, makeAddr('eoa'));
  }

  function testAllowTokenGsmNotGhoToken() public {
    address token = makeAddr('token');
    BadGsm gsm = new BadGsm(makeAddr('bad-gho'), address(USDX_TOKEN));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowTokenGsm(token, address(gsm));
  }

  function testAllowTokenGsmNotStata() public {
    address token = makeAddr('token');
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(0));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.allowTokenGsm(token, address(gsm));
  }

  function testAllowTokenGsmNotUnderlying() public {
    address token = makeAddr('token');
    BadStata stata = new BadStata();
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(stata));
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.allowTokenGsm(token, address(gsm));
  }

  function testAllowTokenGsmAlreadySet() public {
    vm.expectRevert(IGhoRouter.TokenToGsmAlreadySet.selector);
    GHO_ROUTER.allowTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
  }

  function testAllowTokenGsm() public {
    // Revoke previously allowed GSM on setUp
    GHO_ROUTER.revokeTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.allowedGsm(address(USDX_TOKEN), address(GHO_GSM_4626)), false);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmAdded(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.allowTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.allowedGsm(address(USDX_TOKEN), address(GHO_GSM_4626)), true);
  }

  function testRevokeTokenGsmNotSet() public {
    GHO_ROUTER.revokeTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    vm.expectRevert(IGhoRouter.TokenToGsmNotSet.selector);
    GHO_ROUTER.revokeTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
  }

  function testRevokeTokenGsm() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmRemoved(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.revokeTokenGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.allowedGsm(address(USDX_TOKEN), address(GHO_GSM_4626)), false);
  }
}
