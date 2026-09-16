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
    uint256 amount = 1_000 ether;
    deal(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), amount);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 0);

    GHO_ROUTER.rescueToken(address(GHO_TOKEN), RECIPIENT, amount);

    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), 0);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), amount);
  }
}
