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
  function testPauseUnauthorized() public {
    vm.prank(USER);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, USER)
    );
    GHO_ROUTER.pause();
  }

  function testPauseByGuardian() public {
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit Pausable.Paused(ROUTER_GUARDIAN);
    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.pause();

    assertEq(GHO_ROUTER.paused(), true);
  }

  function testPauseByGuardianWhenAlreadyPaused() public {
    GHO_ROUTER.pause();

    vm.prank(ROUTER_GUARDIAN);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.pause();
  }

  function testUnpauseByGuardian() public {
    vm.prank(ROUTER_GUARDIAN);
    GHO_ROUTER.pause();

    vm.prank(ROUTER_GUARDIAN);
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ROUTER_GUARDIAN)
    );
    GHO_ROUTER.unpause();
  }

  function testSwapWhenPausedByGuardian() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    vm.prank(ROUTER_GUARDIAN);
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
    uint256 expectedOut = grossGho - (grossGho * sellFee) / 1e4;

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
    uint256 expectedOut = grossGho - (grossGho * sellFee) / 1e4;

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

    GHO_ROUTER.removeTokenToStata(address(USDX_TOKEN));
    assertEq(GHO_ROUTER.tokenToStata(address(USDX_TOKEN)), address(0));

    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(USDX_4626_TOKEN));
    assertEq(GHO_ROUTER.tokenToStata(address(USDX_TOKEN)), address(USDX_4626_TOKEN));

    deal(address(GHO_TOKEN), address(GHO_ROUTER), 1 ether);
    GHO_ROUTER.rescueToken(address(GHO_TOKEN), RECIPIENT, 1 ether);
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 1 ether);
  }

  function testDepositForSGHOWhenPaused() public {
    GHO_ROUTER.pause();

    vm.prank(USER);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(0),
      1 ether,
      0,
      USER,
      block.timestamp
    );
  }

  function testRedeemSGHOWhenPaused() public {
    GHO_ROUTER.pause();

    vm.prank(USER);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      address(0),
      1 ether,
      0,
      USER,
      block.timestamp
    );
  }

  function testPreviewDepositForSGHOWhenPaused() public {
    GHO_ROUTER.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.previewSwap(address(GHO_TOKEN), address(SGHO), address(0), 1 ether);
  }

  function testPreviewRedeemSGHOWhenPaused() public {
    GHO_ROUTER.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    GHO_ROUTER.previewSwap(address(SGHO), address(GHO_TOKEN), address(0), 1 ether);
  }
}
