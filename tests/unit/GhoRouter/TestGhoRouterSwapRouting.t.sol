// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter swap routing and input validation
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSwapRouting.t.sol -vvv
 */
contract SwapRoutingTest is TestGhoRouterBase {
  function testSwapStataToGHOOnPlainGsm() public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));

    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapGHOToStataOnPlainGsm() public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));

    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapGHOToGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapGHOToGHOGsmSettlingInGho() public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    vm.mockCall(
      address(GHO_GSM),
      abi.encodeWithSelector(IGsm.UNDERLYING_ASSET.selector),
      abi.encode(address(GHO_TOKEN))
    );

    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapSGHOToSGHOGsmSettlingInSGho() public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    vm.mockCall(
      address(GHO_GSM),
      abi.encodeWithSelector(IGsm.UNDERLYING_ASSET.selector),
      abi.encode(address(SGHO))
    );

    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(address(SGHO), address(SGHO), address(GHO_GSM), 1, 0, USER, block.timestamp);
  }

  function testPreviewSwapGHOToGHOGsmSettlingInGho() public {
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    vm.mockCall(
      address(GHO_GSM),
      abi.encodeWithSelector(IGsm.UNDERLYING_ASSET.selector),
      abi.encode(address(GHO_TOKEN))
    );

    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.previewSwap(address(GHO_TOKEN), address(GHO_TOKEN), address(GHO_GSM), 1 ether);
  }

  function testSwapRecipientIsRouterGHOToSGho() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidRecipient.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      address(0),
      1,
      0,
      address(GHO_ROUTER),
      block.timestamp
    );
  }

  function testSwapRecipientIsRouterTokenToGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidRecipient.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      address(GHO_ROUTER),
      block.timestamp
    );
  }

  function testSwapSGHOToSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidToken.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(SGHO),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapDeadlineExpiredToGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp - 1
    );
  }

  function testSwapDeadlineExpiredFromGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp - 1
    );
  }

  function testSwapDeadlineExpiredToSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp - 1
    );
  }

  function testSwapDeadlineExpiredFromSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      1,
      0,
      USER,
      block.timestamp - 1
    );
  }

  function testSwapDeadlineExpiredDepositForSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(address(GHO_TOKEN), address(SGHO), address(0), 1, 0, USER, block.timestamp - 1);
  }

  function testSwapDeadlineExpiredRedeemSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(address(SGHO), address(GHO_TOKEN), address(0), 1, 0, USER, block.timestamp - 1);
  }

  function testSwapGsmNotAllowedFromGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapGsmNotAllowedToSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }

  function testSwapGsmNotAllowedFromSGHO() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      address(GHO_GSM),
      1,
      0,
      USER,
      block.timestamp
    );
  }
}
