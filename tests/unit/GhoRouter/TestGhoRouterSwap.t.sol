// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import '../TestGhoBase.t.sol';

import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/GhoRouterSwapTest.t.sol -vvv
 */
contract GhoRouterSwapTest is TestGhoBase {
  // Test user address
  address constant USER = address(0xF00DBA11);
  address constant RECIPIENT = address(0xCAFEF00D);

  function setUp() public {
    uint256 amount = 10_000e6;
    GHO_ROUTER.setTokenToGsm(address(USDX_4626_TOKEN), address(GHO_GSM_4626));
    GHO_ROUTER.setTokenToGsm(address(USDX_TOKEN), address(GHO_GSM_4626));

    deal(address(USDX_4626_TOKEN), address(this), amount);
    USDX_4626_TOKEN.approve(address(GHO_GSM_4626), amount);
    GHO_GSM_4626.sellAsset(amount, address(this));

    deal(address(USDX_TOKEN), address(USDX_4626_TOKEN), amount);
  }

  function _dealAndApprove(address token, address spender, uint256 amount) internal {
    deal(token, USER, amount);
    vm.prank(USER);
    IERC20(token).approve(spender, amount);
  }

  function _mintSgho(uint256 amount) internal {
    _dealAndApprove(address(GHO_TOKEN), address(SGHO), amount);
    vm.prank(USER);
    SGHO.deposit(amount, USER);
  }
}

contract SwapToGHOTest is GhoRouterSwapTest {
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

  function testSwapToGHOStata() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

    uint256 expectedOut = 900000000000000000000;

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

  function testSwapToGHOUnderlying() public {
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

    uint256 expectedOut = 9900000000000000000000;

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

  function testSwapToGHOWithRecipient() public {
    uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);

    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);
    uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);
    uint256 expectedOut = 9900000000000000000000;

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

contract SwapFromGHOTest is GhoRouterSwapTest {
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
      amount / 2,
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

  function testSwapFromGHOToUSDX_4626_TOKEN() public {
    uint256 expectedAmount = 90909090;
    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      99999999000000000000,
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

  function testSwapFromGHOToStataUSDX_4626_TOKENWithRecipient() public {
    uint256 expectedAmount = 90909090;
    uint256 amount = 100 ether;
    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(
      address(GHO_TOKEN),
      address(USDX_4626_TOKEN),
      99999999000000000000,
      expectedAmount,
      RECIPIENT
    ); // 1 ether diff in input
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

contract SwapToSGhoTest is GhoRouterSwapTest {
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

  function testSwapToSGHOUnderlying() public {
    uint256 expectedOut = 9900 ether;
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), 1_000 ether); // Adjust for GHO decimals

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 shares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      amount,
      1,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive minted shares');
  }

  function testSwapToSGHOStata() public {
    uint256 expectedOut = 900 ether;
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), 1_000 ether); // Adjust for GHO decimals

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_4626_TOKEN), address(SGHO), amount, expectedOut, USER);
    uint256 shares = GHO_ROUTER.swap(
      address(USDX_4626_TOKEN),
      address(SGHO),
      amount,
      1,
      USER,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, 'User should receive minted shares');
  }

  function testSwapToSGHOUnderlyingWithRecipient() public {
    uint256 expectedOut = 9900 ether;
    uint256 amount = 1_000e6;
    _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), 1_000 ether); // Adjust for GHO decimals

    vm.prank(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(USDX_TOKEN), address(SGHO), amount, expectedOut, RECIPIENT);
    uint256 shares = GHO_ROUTER.swap(
      address(USDX_TOKEN),
      address(SGHO),
      amount,
      1,
      RECIPIENT,
      block.timestamp
    );

    assertEq(shares, expectedOut, 'Should receive sGHO shares');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should receive zero shares');
    assertEq(
      IERC20(address(SGHO)).balanceOf(RECIPIENT),
      shares,
      'Recipient should receive minted shares'
    );
  }
}

contract SwapFromSGhoTest is GhoRouterSwapTest {
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

  function testSwapFromSGHO() public {
    uint256 expectedOut = 90909090;
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

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

    assertEq(outputAmount, expectedOut, 'Should receive USDX_4626_TOKEN');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, 'User should spend all sGHO');
  }

  function testSwapFromSGHOStata() public {
    uint256 expectedOut = 90909090;
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

    uint256 userBalanceBefore = IERC20(address(USDX_4626_TOKEN)).balanceOf(USER);

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

  function testSwapFromSGHOStataWithRecipient() public {
    uint256 expectedOut = 90909090;
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);

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

contract DepositForSGhoTest is GhoRouterSwapTest {
  function testDepositForSGHO() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(GHO_TOKEN), address(SGHO), amount, amount, USER);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      amount,
      amount,
      USER,
      block.timestamp
    );

    assertEq(shares, amount, 'sGHO copy should mint 1:1 shares at initial index');
    assertEq(IERC20(address(SGHO)).balanceOf(USER), amount, 'User should receive all shares');
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

  function testDepositForSGHOWithRecipient() public {
    uint256 amount = 100 ether;

    _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = IERC20(address(SGHO)).balanceOf(RECIPIENT);
    uint256 userBalanceBefore = IERC20(address(SGHO)).balanceOf(USER);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(GHO_TOKEN), address(SGHO), amount, amount, RECIPIENT);
    vm.prank(USER);
    uint256 shares = GHO_ROUTER.swap(
      address(GHO_TOKEN),
      address(SGHO),
      amount,
      amount,
      RECIPIENT,
      block.timestamp
    );

    assertEq(shares, amount, 'sGHO copy should mint 1:1 shares at initial index');
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

contract RedeemSGhoTest is GhoRouterSwapTest {
  function testRedeemSGHO() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);
    SGHO.approve(address(GHO_ROUTER), amount);
    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(GHO_TOKEN), amount, amount, USER);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      amount,
      amount,
      USER,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, amount, 'Should redeem to full GHO amount');
    assertEq(IERC20(GHO_TOKEN).balanceOf(USER), amount, 'User should receive redeemed GHO');
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

  function testRedeemSGHOWithRecipient() public {
    uint256 amount = 100 ether;
    _mintSgho(amount);

    vm.startPrank(USER);

    SGHO.approve(address(GHO_ROUTER), amount);
    uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);
    uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);

    vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
    emit IGhoRouter.Swap(address(SGHO), address(GHO_TOKEN), amount, amount, RECIPIENT);
    uint256 outputAmount = GHO_ROUTER.swap(
      address(SGHO),
      address(GHO_TOKEN),
      amount,
      amount,
      RECIPIENT,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(outputAmount, amount, 'Should redeem to full GHO amount');
    assertEq(
      IERC20(GHO_TOKEN).balanceOf(RECIPIENT) - recipientBalanceBefore,
      outputAmount,
      'Recipient should receive GHO'
    );
    assertEq(IERC20(GHO_TOKEN).balanceOf(USER), userBalanceBefore, 'Caller should not receive GHO');
  }
}
