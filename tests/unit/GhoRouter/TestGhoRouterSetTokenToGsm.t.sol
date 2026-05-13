// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSetTokenToGsm.t.sol -vvv
 */
contract SetTokenToGsmTest is TestGhoRouterBase {
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
    address token = makeAddr('token');
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(token, makeAddr('eoa'));
  }

  function testSetTokenToGsmNotGhoToken() public {
    address token = makeAddr('token');
    BadGsm gsm = new BadGsm(makeAddr('bad-gho'), address(USDX_TOKEN));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(token, address(gsm));
  }

  function testSetTokenToGsmNotStata() public {
    address token = makeAddr('token');
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(0));
    vm.expectRevert(IGhoRouter.InvalidGsm.selector);
    GHO_ROUTER.setTokenToGsm(token, address(gsm));
  }

  function testSetTokenToGsmNotUnderlying() public {
    address token = makeAddr('token');
    BadStata stata = new BadStata();
    BadGsm gsm = new BadGsm(address(GHO_TOKEN), address(stata));
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.setTokenToGsm(token, address(gsm));
  }

  function testSetTokenToGsmAlreadySet() public {
    vm.expectRevert(IGhoRouter.TokenToGsmAlreadySet.selector);
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
  }

  function testSetTokenToGsm() public {
    // Remove previously set GSM on setUp
    GHO_ROUTER.removeTokenToGsm(address(USDX_TOKEN));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(0));

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmAdded(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(GHO_GSM_4626));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(GHO_GSM_4626));
  }

  function testRemoveTokenToGsm() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenToGsmRemoved(address(USDX_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.removeTokenToGsm(address(USDX_TOKEN));
    assertEq(GHO_ROUTER.gsms(address(USDX_TOKEN)), address(0));
  }
}
