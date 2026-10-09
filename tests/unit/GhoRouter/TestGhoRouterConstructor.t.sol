// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterConstructor.t.sol -vvv
 */
contract ConstructorTest is TestGhoRouterBase {
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
