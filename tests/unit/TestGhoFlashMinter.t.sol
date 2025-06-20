// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

contract TestGhoFlashMinter is TestGhoBase {
  using PercentageMath for uint256;

  function testConstructor() public {
    vm.expectEmit(vm.computeCreateAddress(address(this), vm.getNonce(address(this))));
    emit GhoTreasuryUpdated(address(0), TREASURY);
    vm.expectEmit(vm.computeCreateAddress(address(this), vm.getNonce(address(this))));
    emit FeeUpdated(0, DEFAULT_FLASH_FEE);
    GhoFlashMinter flashMinter = new GhoFlashMinter(
      address(GHO_TOKEN),
      TREASURY,
      DEFAULT_FLASH_FEE,
      address(PROVIDER)
    );
    assertEq(address(flashMinter.GHO_TOKEN()), address(GHO_TOKEN), 'Wrong GHO token address');
    assertEq(flashMinter.getFee(), DEFAULT_FLASH_FEE, 'Wrong fee');
    assertEq(flashMinter.getGhoTreasury(), TREASURY, 'Wrong TREASURY address');
    assertEq(
      address(flashMinter.ADDRESSES_PROVIDER()),
      address(PROVIDER),
      'Wrong addresses provider address'
    );
  }

  function testRevertConstructorFeeOutOfRange() public {
    vm.expectRevert('FlashMinter: Fee out of range');
    new GhoFlashMinter(address(GHO_TOKEN), TREASURY, 10001, address(PROVIDER));
  }

  function testRevertFlashloanNonRecipient() public {
    vm.expectRevert();
    GHO_FLASH_MINTER.flashLoan(
      IERC3156FlashBorrower(address(this)),
      address(GHO_TOKEN),
      DEFAULT_BORROW_AMOUNT,
      ''
    );
  }

  function testRevertFlashloanEOARecipient() public {
    address receiver = makeAddr('receiver');
    vm.assume(receiver.code.length == 0);
    vm.expectRevert();
    GHO_FLASH_MINTER.flashLoan(
      IERC3156FlashBorrower(receiver),
      address(GHO_TOKEN),
      DEFAULT_BORROW_AMOUNT,
      ''
    );
  }

  function testRevertFlashloanWrongToken() public {
    vm.expectRevert('FlashMinter: Unsupported currency');
    GHO_FLASH_MINTER.flashLoan(
      IERC3156FlashBorrower(address(FLASH_BORROWER)),
      address(0),
      DEFAULT_BORROW_AMOUNT,
      ''
    );
  }

  function testRevertFlashloanMoreThanCapacity() public {
    vm.expectRevert('FACILITATOR_BUCKET_CAPACITY_EXCEEDED');
    GHO_FLASH_MINTER.flashLoan(
      IERC3156FlashBorrower(address(FLASH_BORROWER)),
      address(GHO_TOKEN),
      DEFAULT_CAPACITY + 1,
      ''
    );
  }

  function testRevertFlashloanInsufficientReturned() public {
    ACL_MANAGER.setState(false);
    assertEq(
      ACL_MANAGER.isFlashBorrower(address(FLASH_BORROWER)),
      false,
      'Flash borrower should not be a whitelisted borrower'
    );
    vm.expectRevert(stdError.arithmeticError);
    FLASH_BORROWER.flashBorrow(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT);
  }

  function testRevertFlashloanWrongCallback() public {
    FLASH_BORROWER.setAllowCallback(false);
    vm.expectRevert('FlashMinter: Callback failed');
    FLASH_BORROWER.flashBorrow(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT);
  }

  function testRevertUpdateFeeNotPoolAdmin() public {
    ACL_MANAGER.setState(false);
    assertEq(
      ACL_MANAGER.isPoolAdmin(address(GHO_FLASH_MINTER)),
      false,
      'GhoFlashMinter should not be a pool admin'
    );

    vm.expectRevert('CALLER_NOT_POOL_ADMIN');
    GHO_FLASH_MINTER.updateFee(100);
  }

  function testRevertUpdateFeeOutOfRange() public {
    vm.expectRevert('FlashMinter: Fee out of range');
    GHO_FLASH_MINTER.updateFee(10001);
  }

  function testRevertUpdateTreasuryNotPoolAdmin() public {
    ACL_MANAGER.setState(false);
    assertEq(
      ACL_MANAGER.isPoolAdmin(address(GHO_FLASH_MINTER)),
      false,
      'GhoFlashMinter should not be a pool admin'
    );

    vm.expectRevert('CALLER_NOT_POOL_ADMIN');
    GHO_FLASH_MINTER.updateGhoTreasury(address(0));
  }

  function testRevertFlashfeeNotGho() public {
    vm.expectRevert('FlashMinter: Unsupported currency');
    GHO_FLASH_MINTER.flashFee(address(0), DEFAULT_BORROW_AMOUNT);
  }

  // Positives

  function testFlashloan() public {
    ACL_MANAGER.setState(false);
    assertFalse(
      ACL_MANAGER.isFlashBorrower(address(FLASH_BORROWER)),
      'Flash borrower should not be a whitelisted borrower'
    );

    uint256 feeAmount = DEFAULT_FLASH_FEE.percentMul(DEFAULT_BORROW_AMOUNT);
    ghoFaucet(address(FLASH_BORROWER), feeAmount);

    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FlashMint(
      address(FLASH_BORROWER),
      address(FLASH_BORROWER),
      address(GHO_TOKEN),
      DEFAULT_BORROW_AMOUNT,
      feeAmount
    );
    FLASH_BORROWER.flashBorrow(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT);

    assertEq(GHO_TOKEN.balanceOf(address(FLASH_BORROWER)), 0, 'Flash borrower should have no GHO');
    assertEq(GHO_TOKEN.balanceOf(address(GHO_FLASH_MINTER)), feeAmount);
  }

  function testFlashloanAsApprovedFlashBorrower() public {
    ACL_MANAGER.setState(true);
    assertTrue(ACL_MANAGER.isFlashBorrower(address(FLASH_BORROWER)));

    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FlashMint(
      address(FLASH_BORROWER),
      address(FLASH_BORROWER),
      address(GHO_TOKEN),
      DEFAULT_BORROW_AMOUNT,
      0 // feeAmount
    );
    FLASH_BORROWER.flashBorrow(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT);

    assertEq(GHO_TOKEN.balanceOf(address(FLASH_BORROWER)), 0);
    assertEq(GHO_TOKEN.balanceOf(address(GHO_FLASH_MINTER)), 0);
  }

  function testFlashloanAndChangeCapacityMidExecution() public {
    ACL_MANAGER.setState(true);
    assertTrue(ACL_MANAGER.isFlashBorrower(address(FLASH_BORROWER)));

    GHO_TOKEN.grantRole(GHO_TOKEN.BUCKET_MANAGER_ROLE(), address(FLASH_BORROWER));
    uint256 bucketCapacity = GHO_TOKEN.getFacilitator(address(GHO_FLASH_MINTER)).bucketCapacity;
    assertGt(bucketCapacity, 0);

    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FlashMint(
      address(FLASH_BORROWER),
      address(FLASH_BORROWER),
      address(GHO_TOKEN),
      bucketCapacity,
      0
    );
    FLASH_BORROWER.flashBorrowOtherActionMax(address(GHO_TOKEN));

    assertEq(GHO_TOKEN.getFacilitator(address(GHO_FLASH_MINTER)).bucketCapacity, 0);
  }

  function testFuzzFlashloanUntilBucketCapacity(uint256 amount) public {
    ACL_MANAGER.setState(false);
    assertFalse(ACL_MANAGER.isFlashBorrower(address(FLASH_BORROWER)));
    amount = bound(amount, 1, GHO_TOKEN.getFacilitator(address(GHO_FLASH_MINTER)).bucketCapacity);

    uint256 feeAmount = DEFAULT_FLASH_FEE.percentMul(amount);
    if (feeAmount > 0) ghoFaucet(address(FLASH_BORROWER), feeAmount);

    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FlashMint(
      address(FLASH_BORROWER),
      address(FLASH_BORROWER),
      address(GHO_TOKEN),
      amount,
      feeAmount
    );
    FLASH_BORROWER.flashBorrow(address(GHO_TOKEN), amount);

    assertEq(GHO_TOKEN.balanceOf(address(FLASH_BORROWER)), 0);
    assertEq(GHO_TOKEN.balanceOf(address(GHO_FLASH_MINTER)), feeAmount);
  }

  function testDistributeFeesToTreasury() public {
    uint256 treasuryBalanceBefore = GHO_TOKEN.balanceOf(TREASURY);

    ghoFaucet(address(GHO_FLASH_MINTER), 100e18);
    assertEq(
      GHO_TOKEN.balanceOf(address(GHO_FLASH_MINTER)),
      100e18,
      'GhoFlashMinter should have 100 GHO'
    );

    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FeesDistributedToTreasury(TREASURY, address(GHO_TOKEN), 100e18);
    GHO_FLASH_MINTER.distributeFeesToTreasury();

    assertEq(
      GHO_TOKEN.balanceOf(address(GHO_FLASH_MINTER)),
      0,
      'GhoFlashMinter should have no GHO left after fee distribution'
    );
    assertEq(
      GHO_TOKEN.balanceOf(TREASURY),
      treasuryBalanceBefore + 100e18,
      'Treasury should have 100 more GHO'
    );
  }

  function testUpdateFee() public {
    assertEq(GHO_FLASH_MINTER.getFee(), DEFAULT_FLASH_FEE, 'Flashminter non-default fee');
    assertTrue(DEFAULT_FLASH_FEE != 100);
    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit FeeUpdated(DEFAULT_FLASH_FEE, 100);
    GHO_FLASH_MINTER.updateFee(100);
  }

  function testUpdateGhoTreasury() public {
    assertEq(GHO_FLASH_MINTER.getGhoTreasury(), TREASURY, 'Flashminter non-default TREASURY');
    assertTrue(TREASURY != address(this));
    vm.expectEmit(address(GHO_FLASH_MINTER));
    emit GhoTreasuryUpdated(TREASURY, address(this));
    GHO_FLASH_MINTER.updateGhoTreasury(address(this));
  }

  function testMaxFlashloanNotGho() public view {
    assertEq(
      GHO_FLASH_MINTER.maxFlashLoan(address(0)),
      0,
      'Max flash loan should be 0 for non-GHO token'
    );
  }

  function testMaxFlashloanGho() public view {
    assertEq(
      GHO_FLASH_MINTER.maxFlashLoan(address(GHO_TOKEN)),
      DEFAULT_CAPACITY,
      'Max flash loan should be DEFAULT_CAPACITY for GHO token'
    );
  }

  function testWhitelistedFlashFee() public view {
    assertEq(
      GHO_FLASH_MINTER.flashFee(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT),
      0,
      'Flash fee should be 0 for whitelisted borrowers'
    );
  }

  function testNotWhitelistedFlashFee() public {
    ACL_MANAGER.setState(false);
    assertEq(
      ACL_MANAGER.isFlashBorrower(address(this)),
      false,
      'Flash borrower should not be a whitelisted borrower'
    );
    uint256 fee = GHO_FLASH_MINTER.flashFee(address(GHO_TOKEN), DEFAULT_BORROW_AMOUNT);
    uint256 expectedFee = DEFAULT_FLASH_FEE.percentMul(DEFAULT_BORROW_AMOUNT);
    assertEq(fee, expectedFee, 'Flash fee should be correct');
  }

  // Fuzzing
  function testFuzzFlashFee(uint256 feeToSet, uint256 amount) public {
    vm.assume(feeToSet <= 10000);
    vm.assume(amount <= DEFAULT_CAPACITY);
    GHO_FLASH_MINTER.updateFee(feeToSet);
    ACL_MANAGER.setState(false); // Set ACL manager to return false so there are no whitelisted borrowers.

    uint256 fee = GHO_FLASH_MINTER.flashFee(address(GHO_TOKEN), amount);
    uint256 expectedFee = feeToSet.percentMul(amount);

    // We account for +/- 1 wei of rounding error.
    assertTrue(
      fee >= (expectedFee == 0 ? 0 : expectedFee - 1),
      'Flash fee should be greater than or equal to expected fee - 1'
    );
    assertTrue(
      fee <= expectedFee + 1,
      'Flash fee should be less than or equal to expected fee + 1'
    );
  }
}
