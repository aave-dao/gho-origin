// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for the refund of the GSM asset not taken by `sellAsset`, on 18-decimal GSMs
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSellRefund.t.sol -vvv
 */
contract SellRefundTest is TestGhoRouterBase {
  uint128 internal constant EXPOSURE_CAP_18_DECIMALS = 100_000_000 ether;

  TestnetERC20 internal TOKEN_18;
  Gsm internal GSM_18;

  TestnetERC20 internal UNDERLYING_18;
  MockERC4626 internal STATA_18;
  Gsm4626 internal GSM_STATA_18;

  function setUp() public override {
    super.setUp();
    FixedFeeStrategy feeStrategy = new FixedFeeStrategy(0.1e2, 0.2e2);

    TOKEN_18 = new TestnetERC20('Token 18', 'TKN18', 18, FAUCET);
    GSM_18 = _deployGsmProxy(
      address(TOKEN_18),
      address(new FixedPriceStrategy(1e18, address(TOKEN_18), 18)),
      EXPOSURE_CAP_18_DECIMALS
    );
    GSM_18.updateFeeStrategy(address(feeStrategy));
    GHO_RESERVE.addEntity(address(GSM_18));
    GHO_RESERVE.setLimit(address(GSM_18), EXPOSURE_CAP_18_DECIMALS);
    GHO_ROUTER.allowGsm(address(GSM_18));

    UNDERLYING_18 = new TestnetERC20('Underlying 18', 'UND18', 18, FAUCET);
    STATA_18 = new MockERC4626('Stata 18', 'STATA18', address(UNDERLYING_18));
    GSM_STATA_18 = _deployGsm4626Proxy(
      address(STATA_18),
      address(new FixedPriceStrategy4626(1e18, address(STATA_18), 18)),
      EXPOSURE_CAP_18_DECIMALS
    );
    GSM_STATA_18.updateFeeStrategy(address(feeStrategy));
    GHO_RESERVE.addEntity(address(GSM_STATA_18));
    GHO_RESERVE.setLimit(address(GSM_STATA_18), EXPOSURE_CAP_18_DECIMALS);
    GHO_ROUTER.allowGsm(address(GSM_STATA_18));
    GHO_ROUTER.setTokenToStata(address(UNDERLYING_18), address(STATA_18));

    // Vault rate of 1.1 assets per share
    deal(address(UNDERLYING_18), address(this), 1_000 ether);
    UNDERLYING_18.approve(address(STATA_18), 1_000 ether);
    STATA_18.deposit(1_000 ether, address(this));
    deal(address(UNDERLYING_18), address(STATA_18), 1_100 ether);
  }

  function testSwapToGHOPlain18DecimalsRefundsUnsoldAsset() public {
    uint256 amount = 1_000 ether + 1;
    (uint256 assetSold, uint256 expectedGho, , ) = GSM_18.getGhoAmountForSellAsset(amount);
    assertGt(amount - assetSold, 0, 'GSM should take less than offered');
    _dealAndApprove(address(TOKEN_18), address(GHO_ROUTER), amount);

    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(TOKEN_18),
      address(GHO_TOKEN),
      address(GSM_18),
      amount,
      expectedGho,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedGho, 'Received GHO does not match');
    assertEq(TOKEN_18.balanceOf(USER), amount - assetSold, 'Unsold asset should be refunded');
    _assertRouterHoldsNo18DecimalsAssets();
    _assertRouterEmpty();
  }

  function testSwapToSGhoPlain18DecimalsRefundsUnsoldAsset() public {
    uint256 amount = 1_000 ether + 1;
    (uint256 assetSold, , , ) = GSM_18.getGhoAmountForSellAsset(amount);
    assertGt(amount - assetSold, 0, 'GSM should take less than offered');
    _dealAndApprove(address(TOKEN_18), address(GHO_ROUTER), amount);

    vm.prank(USER);
    uint256 sghoReceived = GHO_ROUTER.swap(
      address(TOKEN_18),
      address(SGHO),
      address(GSM_18),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(SGHO.balanceOf(RECIPIENT), sghoReceived, 'Recipient should receive sGHO');
    assertEq(TOKEN_18.balanceOf(USER), amount - assetSold, 'Unsold asset should be refunded');
    _assertRouterHoldsNo18DecimalsAssets();
    _assertRouterEmpty();
  }

  function testSwapToGHOStata18DecimalsUnderlyingRefundsUnsoldShares() public {
    uint256 amount = 1_100 ether + 502;
    uint256 shares = STATA_18.previewDeposit(amount);
    uint256 gsmSharesBefore = STATA_18.balanceOf(address(GSM_STATA_18));
    _dealAndApprove(address(UNDERLYING_18), address(GHO_ROUTER), amount);

    vm.prank(USER);
    GHO_ROUTER.swap(
      address(UNDERLYING_18),
      address(GHO_TOKEN),
      address(GSM_STATA_18),
      amount,
      0,
      USER,
      block.timestamp
    );

    uint256 sharesSold = STATA_18.balanceOf(address(GSM_STATA_18)) - gsmSharesBefore;
    assertEq(UNDERLYING_18.balanceOf(USER), 0, 'Caller should spend all underlying');
    assertGt(STATA_18.balanceOf(USER), 0, 'GSM should take less than offered');
    assertEq(STATA_18.balanceOf(USER), shares - sharesSold, 'Unsold shares should be refunded');
    _assertRouterHoldsNo18DecimalsAssets();
    _assertRouterEmpty();
  }

  function testFuzzSwapToGHOPlain18DecimalsRouterEmpty(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    (uint256 assetSold, , , ) = GSM_18.getGhoAmountForSellAsset(amount);
    _dealAndApprove(address(TOKEN_18), address(GHO_ROUTER), amount);

    vm.prank(USER);
    GHO_ROUTER.swap(
      address(TOKEN_18),
      address(GHO_TOKEN),
      address(GSM_18),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(TOKEN_18.balanceOf(USER), amount - assetSold, 'Unsold asset should be refunded');
    _assertRouterHoldsNo18DecimalsAssets();
    _assertRouterEmpty();
  }

  function testFuzzSwapToGHOStata18DecimalsUnderlyingRouterEmpty(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    uint256 shares = STATA_18.previewDeposit(amount);
    uint256 gsmSharesBefore = STATA_18.balanceOf(address(GSM_STATA_18));
    _dealAndApprove(address(UNDERLYING_18), address(GHO_ROUTER), amount);

    vm.prank(USER);
    GHO_ROUTER.swap(
      address(UNDERLYING_18),
      address(GHO_TOKEN),
      address(GSM_STATA_18),
      amount,
      0,
      USER,
      block.timestamp
    );

    uint256 sharesSold = STATA_18.balanceOf(address(GSM_STATA_18)) - gsmSharesBefore;
    assertEq(STATA_18.balanceOf(USER), shares - sharesSold, 'Unsold shares should be refunded');
    _assertRouterHoldsNo18DecimalsAssets();
    _assertRouterEmpty();
  }

  function _assertRouterHoldsNo18DecimalsAssets() internal view {
    assertEq(TOKEN_18.balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no TOKEN_18');
    assertEq(
      UNDERLYING_18.balanceOf(address(GHO_ROUTER)),
      0,
      'Router should hold no UNDERLYING_18'
    );
    assertEq(STATA_18.balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no STATA_18');
  }
}
