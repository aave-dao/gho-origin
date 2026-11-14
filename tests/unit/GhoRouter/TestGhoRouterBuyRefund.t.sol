// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for the refund of GHO a GSM quotes but does not spend on `buyAsset`
 * @dev Run with: forge test --match-path tests/unit/GhoRouter/TestGhoRouterBuyRefund.t.sol -vvv
 */
contract BuyRefundTest is TestGhoRouterBase {
  uint256 internal constant GHO_BUDGET = 100 ether;

  function testSwapFromGHORefundsGhoNotSpentByGsm(uint256 extra) public {
    (uint256 amountToBuy, uint256 ghoSpent, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(
      GHO_BUDGET
    );
    extra = bound(extra, 1, GHO_BUDGET - ghoSpent);
    _mockBuyQuote(GHO_BUDGET, amountToBuy, ghoSpent + extra);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), GHO_BUDGET);

    // The event reports the GHO pulled from the caller; the refund is not netted
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      USER,
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      ghoSpent + extra,
      amountToBuy,
      USER
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      GHO_BUDGET,
      0,
      USER,
      block.timestamp
    );

    assertEq(outputAmount, amountToBuy, 'Should receive the quoted asset');
    assertEq(USDX_4626_TOKEN.balanceOf(USER), amountToBuy, 'User should receive the asset');
    assertEq(GHO_TOKEN.balanceOf(USER), GHO_BUDGET - ghoSpent, 'Unspent GHO should be refunded');
    _assertRouterEmpty();
    _assertNoRouterAllowances();
  }

  function testSwapFromGHORefundGoesToCallerNotRecipient() public {
    (uint256 amountToBuy, uint256 ghoSpent, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(
      GHO_BUDGET
    );
    uint256 extra = GHO_BUDGET - ghoSpent;
    assertGt(extra, 0, 'GSM should spend less than the budget');
    _mockBuyQuote(GHO_BUDGET, amountToBuy, GHO_BUDGET);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), GHO_BUDGET);

    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_TOKEN),
      address(GHO_GSM_4626),
      GHO_BUDGET,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(GHO_TOKEN.balanceOf(USER), extra, 'Caller should get the unspent GHO');
    assertEq(GHO_TOKEN.balanceOf(RECIPIENT), 0, 'Recipient should not get the refund');
    assertEq(
      USDX_TOKEN.balanceOf(RECIPIENT),
      USDX_4626_TOKEN.previewRedeem(amountToBuy),
      'Recipient should receive the unwrapped asset'
    );
    _assertRouterEmpty();
    _assertNoRouterAllowances();
  }

  function testSwapFromSGHORefundsGhoNotSpentByGsm(uint256 extra) public {
    _mintSgho(GHO_BUDGET);
    uint256 ghoAmount = SGHO.previewRedeem(GHO_BUDGET);
    (uint256 amountToBuy, uint256 ghoSpent, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(ghoAmount);
    extra = bound(extra, 1, ghoAmount - ghoSpent);
    _mockBuyQuote(ghoAmount, amountToBuy, ghoSpent + extra);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), GHO_BUDGET);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      GHO_BUDGET,
      0,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, amountToBuy, 'Should receive the quoted asset');
    assertEq(SGHO.balanceOf(USER), 0, 'User should spend all sGHO');
    assertEq(GHO_TOKEN.balanceOf(USER), ghoAmount - ghoSpent, 'Unspent GHO should be refunded');
    _assertRouterEmpty();
    _assertNoRouterAllowances();
  }

  function testSwapFromGHONoRefundWhenGsmSpendsQuote() public {
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), GHO_BUDGET);
    (, uint256 ghoSpent, , ) = GHO_GSM_4626.getAssetAmountForBuyAsset(GHO_BUDGET);

    vm.expectCall(address(GHO_TOKEN), abi.encodeWithSelector(IERC20.transfer.selector, USER), 0);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      address(GHO_GSM_4626),
      GHO_BUDGET,
      0,
      USER,
      block.timestamp
    );

    assertEq(GHO_TOKEN.balanceOf(USER), GHO_BUDGET - ghoSpent, 'Only the spent GHO is pulled');
    _assertRouterEmpty();
  }

  /// @dev Makes the GSM quote `ghoQuoted` for `budget` while `buyAsset` still spends its real amount
  function _mockBuyQuote(uint256 budget, uint256 amountToBuy, uint256 ghoQuoted) internal {
    vm.mockCall(
      address(GHO_GSM_4626),
      abi.encodeWithSelector(IGsm.getAssetAmountForBuyAsset.selector, budget),
      abi.encode(amountToBuy, ghoQuoted, uint256(0), uint256(0))
    );
  }
}
