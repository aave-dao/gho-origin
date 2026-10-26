// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterConstructor.t.sol -vvv
 */
contract ConstructorTest is TestGhoRouterBase {
  function testConstructorZeroAddressOwner() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new GhoRouter(address(0), ROUTER_GUARDIAN, address(GHO_TOKEN), address(SGHO));
  }

  function testConstructorZeroAddressGHO() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    new GhoRouter(address(this), ROUTER_GUARDIAN, address(0), address(SGHO));
  }

  function testConstructorZeroAddressSGHO() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    new GhoRouter(address(this), ROUTER_GUARDIAN, address(GHO_TOKEN), address(0));
  }

  function testConstructorInvalidSGho() public {
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    new GhoRouter(address(this), ROUTER_GUARDIAN, address(GHO_TOKEN), address(USDX_4626_TOKEN));
  }

  function testConstructorZeroGuardian() public {
    GhoRouter router = new GhoRouter(address(this), address(0), address(GHO_TOKEN), address(SGHO));
    assertEq(router.guardian(), address(0));

    router.pause();
    assertEq(router.paused(), true);
  }

  function testConstructor() public {
    address routerOwner = makeAddr('router-owner');

    vm.expectEmit(true, true, true, true);
    emit Ownable.OwnershipTransferred(address(0), routerOwner);
    vm.expectEmit(true, true, true, true);
    emit IWithGuardian.GuardianUpdated(address(0), ROUTER_GUARDIAN);
    GhoRouter router = new GhoRouter(
      routerOwner,
      ROUTER_GUARDIAN,
      address(GHO_TOKEN),
      address(SGHO)
    );

    assertEq(router.GHO(), address(GHO_TOKEN));
    assertEq(router.sGHO(), address(SGHO));
    assertEq(router.owner(), routerOwner);
    assertEq(router.pendingOwner(), address(0));
    assertEq(router.guardian(), ROUTER_GUARDIAN);
  }
}
