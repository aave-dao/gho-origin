// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter pausing
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterPausable.t.sol -vvv
 */
contract PausableTest is TestGhoRouterBase {
  function testPauseNonOwner() public {
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.pause();
  }

  function testUnpauseNonOwner() public {
    GHO_ROUTER.pause();

    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
    GHO_ROUTER.unpause();
  }

  function testStartsUnpaused() public view {
    assertEq(GHO_ROUTER.paused(), false);
  }

  function testPause() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit Pausable.Paused(address(this));
    GHO_ROUTER.pause();

    assertEq(GHO_ROUTER.paused(), true);
  }

  function testPauseWhenAlreadyPaused() public {
    GHO_ROUTER.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.pause();
  }

  function testUnpause() public {
    GHO_ROUTER.pause();

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit Pausable.Unpaused(address(this));
    GHO_ROUTER.unpause();

    assertEq(GHO_ROUTER.paused(), false);
  }

  function testUnpauseWhenNotPaused() public {
    vm.expectRevert(Pausable.ExpectedPause.selector);
    GHO_ROUTER.unpause();
  }

  function testSwapWhenPaused() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    GHO_ROUTER.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );
  }

  function testPreviewSwapWhenPaused() public {
    GHO_ROUTER.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.previewSwap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1_000e6
    );
  }

  function testSwapAfterUnpause() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    GHO_ROUTER.pause();
    GHO_ROUTER.unpause();

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 expectedOut = grossGho - (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;

    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
  }

  function testPreviewSwapAfterUnpause() public {
    uint256 amount = 1_000e6;

    GHO_ROUTER.pause();
    GHO_ROUTER.unpause();

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 expectedOut = grossGho - (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;

    uint256 ghoAmount = GHO_ROUTER.previewSwap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      amount
    );

    assertEq(ghoAmount, expectedOut, 'Previewed GHO does not match');
  }

  function testOwnerFunctionsWhilePaused() public {
    GHO_ROUTER.pause();

    GHO_ROUTER.allowGsm(address(GHO_GSM));
    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM)), true);

    GHO_ROUTER.revokeGsm(address(GHO_GSM));
    assertEq(GHO_ROUTER.allowedGsm(address(GHO_GSM)), false);
  }
}
