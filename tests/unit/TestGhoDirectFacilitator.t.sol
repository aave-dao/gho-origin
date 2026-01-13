// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

contract TestGhoDirectFacilitator is TestGhoBase {
  function testConstructor() public {
    GhoDirectFacilitator facilitator = new GhoDirectFacilitator(address(this), address(GHO_TOKEN));
    assertEq(facilitator.GHO_TOKEN(), address(GHO_TOKEN));
    assertTrue(facilitator.hasRole(DEFAULT_ADMIN_ROLE, address(this)));
    assertTrue(facilitator.hasRole(MINTER_ROLE, address(this)));
    assertTrue(facilitator.hasRole(BURNER_ROLE, address(this)));
  }

  function testRevertConstructorInvalidAdmin() public {
    vm.expectRevert('ZERO_ADDRESS_NOT_VALID');
    new GhoDirectFacilitator(address(0), address(GHO_TOKEN));
  }

  function testRevertConstructorInvalidGhoToken() public {
    vm.expectRevert('ZERO_ADDRESS_NOT_VALID');
    new GhoDirectFacilitator(address(this), address(0));
  }

  function testMint() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 amount = 50_000_000 ether;
    uint256 ghoBalanceBefore = GHO_TOKEN.balanceOf(address(this));
    (uint256 capacity, uint256 level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, 0);
    assertEq(ghoBalanceBefore, 0);

    facilitator.mint(address(this), amount);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    uint256 ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, amount);
    assertEq(amount, ghoBalanceAfter);
  }

  function testRevertMintNoRole() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 amount = 50_000_000 ether;

    vm.expectRevert(AccessControlErrorsLib.MISSING_ROLE(MINTER_ROLE, ALICE));
    vm.prank(ALICE);
    facilitator.mint(address(this), amount);
  }

  function testMintFuzz(uint256 amount) public {
    vm.assume(amount > 0 && amount <= DEFAULT_CAPACITY);

    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 ghoBalanceBefore = GHO_TOKEN.balanceOf(address(this));
    (uint256 capacity, uint256 level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, 0);
    assertEq(ghoBalanceBefore, 0);

    facilitator.mint(address(this), amount);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    uint256 ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, amount);
    assertEq(amount, ghoBalanceAfter);
  }

  function testRevertMintIfMintIsTooHigh() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    vm.expectRevert('FACILITATOR_BUCKET_CAPACITY_EXCEEDED');
    facilitator.mint(address(this), DEFAULT_CAPACITY + 1);
  }

  function testBurn() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 amount = 50_000_000 ether;
    uint256 ghoBalanceBefore = GHO_TOKEN.balanceOf(address(this));
    (uint256 capacity, uint256 level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, 0);
    assertEq(ghoBalanceBefore, 0);

    facilitator.mint(address(this), amount);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    uint256 ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, amount);
    assertEq(amount, ghoBalanceAfter);

    GHO_TOKEN.transfer(address(facilitator), amount / 2);
    facilitator.burn(amount / 2);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, amount / 2);
    assertEq(amount / 2, ghoBalanceAfter);
  }

  function testBurnFuzz(uint256 amount) public {
    vm.assume(amount > 1 && amount <= DEFAULT_CAPACITY);

    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 ghoBalanceBefore = GHO_TOKEN.balanceOf(address(this));
    (uint256 capacity, uint256 level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, 0);
    assertEq(ghoBalanceBefore, 0);

    facilitator.mint(address(this), amount);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    uint256 ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, amount);
    assertEq(amount, ghoBalanceAfter);

    GHO_TOKEN.transfer(address(facilitator), amount / 2);
    facilitator.burn(amount / 2);

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));
    ghoBalanceAfter = GHO_TOKEN.balanceOf(address(this));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertApproxEqAbs(level, amount / 2, 1);
    assertApproxEqAbs(amount / 2, ghoBalanceAfter, 1);
  }

  function testRevertBurnNoRole() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    uint256 amount = 50_000_000 ether;

    vm.expectRevert(AccessControlErrorsLib.MISSING_ROLE(BURNER_ROLE, ALICE));
    vm.prank(ALICE);
    facilitator.burn(amount);
  }

  function testRevertBurnIfNoBalance() public {
    vm.expectRevert();
    GHO_DIRECT_FACILITATOR.burn(1);
  }

  function testOffboardFacilitator() public {
    GhoDirectFacilitator facilitator = _deployFacilitator();
    (uint256 capacity, uint256 level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, DEFAULT_CAPACITY);
    assertEq(level, 0);

    vm.expectEmit(true, false, false, true, address(GHO_TOKEN));
    emit FacilitatorRemoved(address(facilitator));
    GHO_TOKEN.removeFacilitator(address(facilitator));

    (capacity, level) = GHO_TOKEN.getFacilitatorBucket(address(facilitator));

    assertEq(capacity, 0);
    assertEq(level, 0);
  }

  function _deployFacilitator() internal returns (GhoDirectFacilitator) {
    GhoDirectFacilitator facilitator = new GhoDirectFacilitator(address(this), address(GHO_TOKEN));
    GHO_TOKEN.addFacilitator(address(facilitator), 'GhoDirectFacilitatorTest', DEFAULT_CAPACITY);

    return facilitator;
  }
}
