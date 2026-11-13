// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter guardian role
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterGuardian.t.sol -vvv
 */
contract GuardianTest is TestGhoRouterBase {
  address public immutable NEW_GUARDIAN = makeAddr('new-guardian');
  address public immutable NEW_OWNER = makeAddr('new-owner');

  function testInitialGuardian() public view {
    assertEq(GHO_ROUTER.guardian(), ROUTER_GUARDIAN);
  }

  function testUpdateGuardianByOwner() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IWithGuardian.GuardianUpdated(ROUTER_GUARDIAN, NEW_GUARDIAN);
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);

    assertEq(GHO_ROUTER.guardian(), NEW_GUARDIAN);
  }

  function testUpdateGuardianByGuardian() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IWithGuardian.GuardianUpdated(ROUTER_GUARDIAN, NEW_GUARDIAN);
    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);

    assertEq(GHO_ROUTER.guardian(), NEW_GUARDIAN);
  }

  function testUpdateGuardianUnauthorized() public {
    vm.prank(USER);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, USER)
    );
    GHO_ROUTER.updateGuardian(USER);
  }

  function testUpdateGuardianByPendingOwner() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    vm.prank(NEW_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, NEW_OWNER)
    );
    GHO_ROUTER.updateGuardian(NEW_OWNER);
  }

  function testUpdateGuardianToZeroAddress() public {
    GHO_ROUTER.updateGuardian(address(0));
    assertEq(GHO_ROUTER.guardian(), address(0));

    vm.prank(ROUTER_GUARDIAN);
    vm.expectRevert(
      abi.encodeWithSelector(
        IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
        ROUTER_GUARDIAN
      )
    );
    GHO_ROUTER.pause();

    GHO_ROUTER.pause();
    assertEq(GHO_ROUTER.paused(), true);
  }

  function testOldGuardianLosesPowersAfterUpdate() public {
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);

    vm.prank(ROUTER_GUARDIAN);
    vm.expectRevert(
      abi.encodeWithSelector(
        IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
        ROUTER_GUARDIAN
      )
    );
    GHO_ROUTER.pause();

    vm.prank(ROUTER_GUARDIAN);
    vm.expectRevert(
      abi.encodeWithSelector(
        IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
        ROUTER_GUARDIAN
      )
    );
    GHO_ROUTER.updateGuardian(ROUTER_GUARDIAN);
  }

  function testNewGuardianCanPause() public {
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);

    vm.prank(NEW_GUARDIAN);
    GHO_ROUTER.pause();

    assertEq(GHO_ROUTER.paused(), true);
  }

  function testGuardianCannotCallOwnerFunctions() public {
    bytes memory unauthorized = abi.encodeWithSelector(
      Ownable.OwnableUnauthorizedAccount.selector,
      ROUTER_GUARDIAN
    );

    vm.startPrank(ROUTER_GUARDIAN);

    vm.expectRevert(unauthorized);
    GHO_ROUTER.allowGsm(address(GHO_GSM));

    vm.expectRevert(unauthorized);
    GHO_ROUTER.revokeGsm(address(GHO_GSM_4626));

    vm.expectRevert(unauthorized);
    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(USDX_4626_TOKEN));

    vm.expectRevert(unauthorized);
    GHO_ROUTER.removeTokenToStata(address(USDX_TOKEN));

    vm.expectRevert(unauthorized);
    GHO_ROUTER.rescueToken(address(GHO_TOKEN), ROUTER_GUARDIAN, 1);

    vm.expectRevert(unauthorized);
    GHO_ROUTER.transferOwnership(ROUTER_GUARDIAN);

    vm.expectRevert(unauthorized);
    GHO_ROUTER.renounceOwnership();

    GHO_ROUTER.pause();

    vm.expectRevert(unauthorized);
    GHO_ROUTER.unpause();

    vm.stopPrank();
  }

  function testGuardianPersistsAcrossOwnershipTransfer() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);
    vm.prank(NEW_OWNER);
    GHO_ROUTER.acceptOwnership();

    assertEq(GHO_ROUTER.guardian(), ROUTER_GUARDIAN);

    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.pause();
    assertEq(GHO_ROUTER.paused(), true);

    vm.prank(NEW_OWNER);
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);
    assertEq(GHO_ROUTER.guardian(), NEW_GUARDIAN);

    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this))
    );
    GHO_ROUTER.updateGuardian(address(this));
  }

  function testGuardianRetainsPowersAfterOwnerRenounces() public {
    GHO_ROUTER.renounceOwnership();
    assertEq(GHO_ROUTER.owner(), address(0));

    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.pause();
    assertEq(GHO_ROUTER.paused(), true);

    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.updateGuardian(NEW_GUARDIAN);
    assertEq(GHO_ROUTER.guardian(), NEW_GUARDIAN);
  }
}
