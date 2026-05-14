// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoRouterBase.t.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterSwap.t.sol -vvv
 */

contract SwapToGHOTest is TestGhoRouterBase {
  function testSwapToGHOZeroAmount() public {
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapToGHODeadlineExpired() public {
    vm.expectRevert(IGhoRouter.DeadlineExpired.selector);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      1_000e6,
      0,
      address(this),
      block.timestamp - 1
    );
  }

  function testSwapToGHOSlippageExceeded() public {
    uint256 amount = 1000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    // Set unreasonably high minGHOAmount to trigger slippage
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      amount,
      type(uint256).max,
      address(this),
      block.timestamp
    );
  }

  function testSwapToGHOInconsistentTokens() public {
    vm.startPrank(USER);
    deal(address(WETH), address(USER), 1);
    WETH.approve(address(GHO_ROUTER), 1);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(address(WETH), address(GHO_TOKEN), 1, 0, address(this), block.timestamp);
    vm.stopPrank();
  }

  function testSwapToGHOZeroAddressRecipient() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      1,
      0,
      address(0),
      block.timestamp
    );
  }

  function testSwapToGHOStata(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_4626_TOKEN), address(GHO_TOKEN), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(GHO_TOKEN),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
  }

  function testSwapToGHOUnderlying(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(GHO_TOKEN), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
  }

  function testSwapToGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);

    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);
    uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 expectedOut = grossGho - fee;

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(GHO_TOKEN), amount, expectedOut, RECIPIENT);
    vm.prank(USER);
    uint256 ghoReceived = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(GHO_TOKEN),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(ghoReceived, expectedOut, 'Received GHO does not match');
    assertEq(
      IERC20(GHO_TOKEN).balanceOf(RECIPIENT) - recipientBalanceBefore,
      ghoReceived,
      'Recipient gets GHO'
    );
    assertEq(IERC20(GHO_TOKEN).balanceOf(USER), userBalanceBefore, 'Caller should not receive GHO');
  }
}

contract SwapFromGHOTest is TestGhoRouterBase {
  function testSwapFromGHOZeroAmount() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromGHOSlippageExceeded() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    // Set unreasonably high minOutputAmount to trigger slippage
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      type(uint256).max,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromGHOInconsistentTokens() public {
    uint256 amount = 1 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(address(GHO_TOKEN), address(WETH), amount, 0, address(this), block.timestamp);
  }

  function testSwapFromGHOZeroAddressRecipient() public {
    uint256 amount = 1 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      0,
      address(0),
      block.timestamp
    );
  }

  function testSwapFromGHOToUSDX_4626_TOKEN_GSMUsesLessGho() public {
    uint256 expectedAmount = 90909090;
    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.mockCall(
      address(GHO_GSM_4626),
      abi.encodeWithSelector(IGsm.buyAsset.selector),
      abi.encode(expectedAmount, amount / 2)
    );

    // Deal Token as buyAsset call is mocked
    deal(address(USDX_4626_TOKEN), address(GHO_ROUTER), expectedAmount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      expectedAmount,
      USER
    ); // 1 ether diff in input
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      0,
      USER,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');
  }

  function testSwapFromGHOToUSDX_4626_TOKEN(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      expectedAmount,
      USER
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      0,
      USER,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');
  }

  function testSwapFromGHOToStataUSDX_4626_TOKENWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossAmount = (amount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      expectedAmount,
      RECIPIENT
    );
    vm.prank(USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      amount,
      1,
      RECIPIENT,
      block.timestamp
    );
    assertEq(outputAmount, expectedAmount, 'Should receive output token');

    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(RECIPIENT),
      outputAmount,
      'User gets static aToken'
    );
  }
}

contract SwapToSGhoTest is TestGhoRouterBase {
  function testSwapToSGHOInconsistentTokens() public {
    vm.startPrank(USER);
    deal(address(WETH), address(USER), 1);
    WETH.approve(address(GHO_ROUTER), 1);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(address(WETH), address(SGHO), 1, 0, address(this), block.timestamp);
    vm.stopPrank();
  }

  function testSwapToSGhoZeroAddressRecipient() public {
    uint256 amount = 1 ether;
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(address(USDX_TOKEN), address(SGHO), amount, 0, address(0), block.timestamp);
  }

  function testSwapToSGHOUnderlying(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 actualShares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(actualShares, expectedOut, 'Should receive sGHO shares');
    assertEq(
      IERC20(address(SGHO)).balanceOf(USER),
      actualShares,
      'User should receive minted shares'
    );
  }

  function testSwapToSGHOStata(uint256 amount) public {
    amount = bound(amount, 1e6, MAX_FUZZ_AMOUNT_6_DECIMALS);
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    uint256 grossGho = (amount * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_4626_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 shares = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(SGHO),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive minted shares');
  }

  function testSwapToSGHOUnderlyingWithRecipient(uint256 amount) public {
    // Bound below 1M USDX so resulting GHO stays under SGHO's supply cap
    amount = bound(amount, 1e6, 1_000_000e6);
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 shares = USDX_4626_TOKEN.previewDeposit(amount);
    uint256 grossGho = (shares * 1e18) / 1e6;
    uint256 fee = (grossGho * DEFAULT_GSM_SELL_FEE) / 1e4;
    uint256 ghoOut = grossGho - fee;
    uint256 expectedOut = SGHO.previewDeposit(ghoOut);

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(SGHO), amount, expectedOut, RECIPIENT);
    uint256 actualShares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(actualShares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should receive zero shares');
    assertEq(
      IERC20(address(SGHO)).balanceOf(RECIPIENT),
      actualShares,
      'Recipient should receive minted shares'
    );
  }
}

contract SwapFromSGhoTest is TestGhoRouterBase {
  function testSwapFromSGHOZeroAmount() public {
    vm.prank(USER);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function testSwapFromSGHOInconsistentTokens() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);
    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.GsmNotConfigured.selector);
    GHO_ROUTER.swap(address(GHO_TOKEN), address(WETH), amount, 0, address(this), block.timestamp);
    vm.stopPrank();
  }

  function testSwapFromSGHOZeroAddressRecipient() public {
    vm.expectRevert(IGhoRouter.ZeroAddress.selector);
    GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      1 ether,
      1 ether,
      address(0),
      block.timestamp
    );
  }

  function testSwapFromSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 stataAmount = USDX_4626_TOKEN.convertToShares(vaultAssets);
    uint256 expectedOut = USDX_4626_TOKEN.previewRedeem(stataAmount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(USDX_TOKEN), amount, expectedOut, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_TOKEN),
      amount,
      1,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive USDX_TOKEN');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testSwapFromSGHOStata(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 userBalanceBefore = IERC20(address(USDX_4626_TOKEN)).balanceOf(USER);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(USDX_4626_TOKEN), amount, expectedOut, USER);

    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      amount,
      1,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive static aToken');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(USER) - userBalanceBefore,
      outputAmount,
      'User should receive static aToken output'
    );
  }

  function testSwapFromSGHOStataWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 ghoAmount = SGHO.previewRedeem(amount);
    uint256 grossAmount = (ghoAmount * 1e4) / (1e4 + DEFAULT_GSM_BUY_FEE);
    uint256 vaultAssets = (grossAmount * 1e6) / 1e18;
    uint256 expectedOut = USDX_4626_TOKEN.convertToShares(vaultAssets);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(USDX_4626_TOKEN), amount, expectedOut, RECIPIENT);

    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(USDX_4626_TOKEN),
      amount,
      1,
      RECIPIENT,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should receive static aToken');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
    assertEq(
      IERC20(address(USDX_4626_TOKEN)).balanceOf(RECIPIENT),
      outputAmount,
      'Recipient should receive static aToken output'
    );
  }
}

contract DepositForSGhoTest is TestGhoRouterBase {
  function testDepositForSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    uint256 expectedOut = SGHO.previewDeposit(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(GHO_TOKEN), address(SGHO), amount, expectedOut, USER);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      amount,
      0,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'sGHO copy should mint 1:1 shares at initial index');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive all shares');
  }

  function testDepositForSGHOSlippageExceeded() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(address(GHO_TOKEN), address(SGHO), amount, amount + 1, USER, block.timestamp);
  }

  function testDepositForSGHOZeroAmount() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    vm.prank(USER);
    GHO_ROUTER.swap(address(GHO_TOKEN), address(SGHO), 0, amount + 1, USER, block.timestamp);
  }

  function testDepositForSGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = IERC20(address(SGHO)).balanceOf(RECIPIENT);
    uint256 userBalanceBefore = IERC20(address(SGHO)).balanceOf(USER);
    uint256 expectedOut = SGHO.previewDeposit(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(GHO_TOKEN), address(SGHO), amount, expectedOut, RECIPIENT);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'sGHO copy should mint 1:1 shares at initial index');
    assertEq(
      IERC20(address(SGHO)).balanceOf(RECIPIENT) - recipientBalanceBefore,
      shares,
      'Recipient should receive shares'
    );
    assertEq(
      IERC20(address(SGHO)).balanceOf(USER),
      userBalanceBefore,
      'Caller should not receive shares'
    );
  }
}

contract RedeemSGhoTest is TestGhoRouterBase {
  function testRedeemSGHO(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    uint256 expectedOut = SGHO.previewRedeem(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(GHO_TOKEN), amount, expectedOut, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      amount,
      0,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should redeem to full GHO amount');
    assertEq(IERC20(GHO_TOKEN).balanceOf(USER), outputAmount, 'User should receive redeemed GHO');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testRedeemSGHOSlippageExceeded() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
    GHO_ROUTER.swap(address(SGHO), address(GHO_TOKEN), amount, amount + 1, USER, block.timestamp);
    vm.stopPrank();
  }

  function testRedeemSGHOZeroAmount() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectRevert(IGhoRouter.InvalidAmount.selector);
    GHO_ROUTER.swap(address(SGHO), address(GHO_TOKEN), 0, amount + 1, USER, block.timestamp);
    vm.stopPrank();
  }

  function testRedeemSGHOWithRecipient(uint256 amount) public {
    amount = bound(amount, 1 ether, MAX_FUZZ_AMOUNT_18_DECIMALS);
    _mintSgho(amount);

    vm.startPrank(USER);

    SGHO.approve(address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);
    uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);
    uint256 expectedOut = SGHO.previewRedeem(amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(GHO_TOKEN), amount, expectedOut, RECIPIENT);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      amount,
      0,
      RECIPIENT,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, expectedOut, 'Should redeem to full GHO amount');
    assertEq(
      IERC20(GHO_TOKEN).balanceOf(RECIPIENT) - recipientBalanceBefore,
      outputAmount,
      'Recipient should receive GHO'
    );
    assertEq(IERC20(GHO_TOKEN).balanceOf(USER), userBalanceBefore, 'Caller should not receive GHO');
  }
}
