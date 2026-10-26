// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterRescueToken.t.sol -vvv
 */
contract RescueTokenTest is TestGhoRouterBase {
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
    uint256 balance = 1_000 ether;
    uint256 amount = 400 ether;
    deal(address(GHO_TOKEN), address(GHO_ROUTER), balance);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), balance);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 0);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenRescued(address(GHO_TOKEN), RECIPIENT, amount);
    GHO_ROUTER.rescueToken(address(GHO_TOKEN), RECIPIENT, amount);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), balance - amount);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), amount);
  }

  function testRescueTokenNonGho() public {
    uint256 balance = 1_000e6;
    uint256 amount = 400e6;
    deal(address(USDX_TOKEN), address(GHO_ROUTER), balance);

    assertEq(USDX_TOKEN.balanceOf(address(GHO_ROUTER)), balance);
    assertEq(USDX_TOKEN.balanceOf(RECIPIENT), 0);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.TokenRescued(address(USDX_TOKEN), RECIPIENT, amount);
    GHO_ROUTER.rescueToken(address(USDX_TOKEN), RECIPIENT, amount);

    assertEq(USDX_TOKEN.balanceOf(address(GHO_ROUTER)), balance - amount);
    assertEq(USDX_TOKEN.balanceOf(RECIPIENT), amount);
  }
}
