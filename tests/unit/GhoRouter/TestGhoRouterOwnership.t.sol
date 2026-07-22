// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter two-step ownership transfer
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterOwnership.t.sol -vvv
 */
contract OwnershipTest is TestGhoRouterBase {
  address public immutable NEW_OWNER = makeAddr('0xNEW0WNER');

  function testTransferOwnershipNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.transferOwnership(NEW_OWNER);
  }

  function testTransferOwnershipDoesNotTransferImmediately() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit Ownable2Step.OwnershipTransferStarted(address(this), NEW_OWNER);
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    assertEq(GHO_ROUTER.owner(), address(this));
    assertEq(GHO_ROUTER.pendingOwner(), NEW_OWNER);
  }

  function testPendingOwnerCannotUseOwnerFunctions() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    vm.prank(NEW_OWNER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
    GHO_ROUTER.allowGsm(address(GHO_GSM));
  }

  function testAcceptOwnershipNonPendingOwner() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.acceptOwnership();
  }

  function testAcceptOwnershipByFormerOwner() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
    );
    GHO_ROUTER.acceptOwnership();
  }

  function testAcceptOwnership() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit Ownable.OwnershipTransferred(address(this), NEW_OWNER);
    vm.prank(NEW_OWNER);
    GHO_ROUTER.acceptOwnership();

    assertEq(GHO_ROUTER.owner(), NEW_OWNER);
    assertEq(GHO_ROUTER.pendingOwner(), address(0));
  }

  function testNewOwnerCanUseOwnerFunctionsAfterAcceptance() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);
    vm.prank(NEW_OWNER);
    GHO_ROUTER.acceptOwnership();

    vm.prank(NEW_OWNER);
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM)), true);

    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
    );
    GHO_ROUTER.revokeGsm(address(GHO_GSM));
  }

  function testTransferOwnershipOverwritesPendingOwner() public {
    address otherOwner = makeAddr('0x0THER0WNER');

    GHO_ROUTER.transferOwnership(NEW_OWNER);
    assertEq(GHO_ROUTER.pendingOwner(), NEW_OWNER);

    GHO_ROUTER.transferOwnership(otherOwner);
    assertEq(GHO_ROUTER.pendingOwner(), otherOwner);

    vm.prank(NEW_OWNER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
    GHO_ROUTER.acceptOwnership();

    vm.prank(otherOwner);
    GHO_ROUTER.acceptOwnership();
    assertEq(GHO_ROUTER.owner(), otherOwner);
  }

  function testRenounceOwnershipClearsPendingOwner() public {
    GHO_ROUTER.transferOwnership(NEW_OWNER);
    assertEq(GHO_ROUTER.pendingOwner(), NEW_OWNER);

    GHO_ROUTER.renounceOwnership();

    assertEq(GHO_ROUTER.owner(), address(0));
    assertEq(GHO_ROUTER.pendingOwner(), address(0));

    vm.prank(NEW_OWNER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
    GHO_ROUTER.acceptOwnership();
  }
}
