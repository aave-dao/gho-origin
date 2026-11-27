// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';
import {GhoDirectMinterRevoker} from 'src/contracts/facilitators/gsm/misc/GhoDirectMinterRevoker.sol';

contract TestGhoDirectMinterRevoker is TestGhoBase {
  address internal governance = makeAddr('governance');
  address internal guardian = makeAddr('guardian');

  GhoDirectMinterRevoker internal revoker;
  GhoDirectFacilitator internal facilitator;

  function setUp() public {
    revoker = new GhoDirectMinterRevoker(governance, guardian);
    facilitator = new GhoDirectFacilitator(governance, address(GHO_TOKEN));
    GHO_TOKEN.addFacilitator(address(facilitator), 'RevokerTest', DEFAULT_CAPACITY);

    vm.prank(governance);
    facilitator.grantRole(DEFAULT_ADMIN_ROLE, address(revoker));
  }

  function testConstructor() public view {
    assertEq(revoker.owner(), governance);
    assertEq(revoker.guardian(), guardian);
  }

  function testRevertConstructorZeroOwner() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new GhoDirectMinterRevoker(address(0), guardian);
  }

  function testConstructorZeroGuardian() public {
    GhoDirectMinterRevoker noGuardian = new GhoDirectMinterRevoker(governance, address(0));
    vm.prank(governance);
    facilitator.grantRole(DEFAULT_ADMIN_ROLE, address(noGuardian));

    assertEq(noGuardian.owner(), governance);
    assertEq(noGuardian.guardian(), address(0));
    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));

    vm.prank(governance);
    noGuardian.revokeMinter(address(facilitator), governance);

    assertFalse(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
  }

  function testRevokeMinterByGovernance() public {
    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.prank(governance);
    revoker.revokeMinter(address(facilitator), governance);

    assertFalse(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
  }

  function testRevokeMinterByGuardian() public {
    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.prank(guardian);
    revoker.revokeMinter(address(facilitator), governance);

    assertFalse(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
  }

  function testRevokeMinterBlocksMint() public {
    vm.prank(governance);
    facilitator.mint(governance, 1 ether);
    assertEq(GHO_TOKEN.balanceOf(governance), 1 ether);

    vm.prank(guardian);
    revoker.revokeMinter(address(facilitator), governance);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        governance,
        MINTER_ROLE
      )
    );
    vm.prank(governance);
    facilitator.mint(governance, 1 ether);
    assertEq(GHO_TOKEN.balanceOf(governance), 1 ether);
  }

  function testRevokeMinterMultipleFacilitators() public {
    GhoDirectFacilitator other = new GhoDirectFacilitator(governance, address(GHO_TOKEN));
    vm.prank(governance);
    other.grantRole(DEFAULT_ADMIN_ROLE, address(revoker));

    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));
    assertTrue(other.hasRole(MINTER_ROLE, governance));

    vm.startPrank(guardian);
    revoker.revokeMinter(address(facilitator), governance);
    revoker.revokeMinter(address(other), governance);
    vm.stopPrank();

    assertFalse(facilitator.hasRole(MINTER_ROLE, governance));
    assertFalse(other.hasRole(MINTER_ROLE, governance));
    assertTrue(facilitator.hasRole(BURNER_ROLE, governance));
    assertTrue(other.hasRole(BURNER_ROLE, governance));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertTrue(other.hasRole(DEFAULT_ADMIN_ROLE, governance));
  }

  function testRevertRevokeMinterInvalidCaller() public {
    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));

    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, ALICE)
    );
    vm.prank(ALICE);
    revoker.revokeMinter(address(facilitator), governance);

    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));
  }

  function testRevertRevokeMinterNotAdmin() public {
    GhoDirectFacilitator other = new GhoDirectFacilitator(governance, address(GHO_TOKEN));

    assertTrue(other.hasRole(MINTER_ROLE, governance));
    assertFalse(other.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(revoker),
        DEFAULT_ADMIN_ROLE
      )
    );
    vm.prank(guardian);
    revoker.revokeMinter(address(other), governance);

    assertTrue(other.hasRole(MINTER_ROLE, governance));
  }

  function testRevertRevokeMinterAfterAdminRevoked() public {
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));

    vm.prank(governance);
    facilitator.revokeRole(DEFAULT_ADMIN_ROLE, address(revoker));

    assertFalse(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(revoker),
        DEFAULT_ADMIN_ROLE
      )
    );
    vm.prank(guardian);
    revoker.revokeMinter(address(facilitator), governance);

    assertTrue(facilitator.hasRole(MINTER_ROLE, governance));
    assertFalse(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
  }
}
