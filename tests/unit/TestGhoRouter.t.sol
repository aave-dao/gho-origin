// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import './TestGhoBase.t.sol';

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGhoRouter} from "src/contracts/misc/interfaces/IGhoRouter.sol";

/**
 * @title GhoRouterTest
 * @notice Integration tests for GhoRouter on mainnet fork
 * @dev Run with: forge test --match-path test/fork/onboarding/GhoRouterTest.t.sol -vvv
 */
contract GhoRouterTest is TestGhoBase {
    // Test user address
    address constant USER = address(0xF00DBA11);
    address constant RECIPIENT = address(0xCAFEF00D);

    function setUp() public {
        uint256 amount = 10_000e6;
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), true);
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

contract GsmWhitelistTest is GhoRouterTest {
    function testSetGsmAllowedNonOwner() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);
        vm.stopPrank();
    }

    function testSetGsmAllowed() public {
        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.GsmAllowedUpdated(address(GHO_GSM_4626), false);
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);
        assertFalse(GHO_ROUTER.isGsmAllowed(address(GHO_GSM_4626)));

        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), true);
        assertTrue(GHO_ROUTER.isGsmAllowed(address(GHO_GSM_4626)));
    }
}

contract SwapToGHOTest is GhoRouterTest {
    function testSwapToGHOZeroAmount() public {
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 0, 0);
    }

    function testSwapToGHOSlippageExceeded() public {
        uint256 amount = 1000e6;
        _dealAndApprove(address(USDX_4626_TOKEN), address(GHO_ROUTER), amount);

        // Set unreasonably high minGHOAmount to trigger slippage
        vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
        vm.startPrank(USER);
        GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, type(uint256).max);
        vm.stopPrank();
    }

    function testSwapToGHOGSMNotAllowed() public {
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 1, 0);
        vm.stopPrank();
    }

    function testSwapToGHOZeroAddressRecipient() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 1, 0, address(0));
        vm.stopPrank();
    }

    function testSwapToGHOUnderlying() public {
        uint256 amount = 1_000e6;
        _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);

        uint256 expectedOut = 9900000000000000000000;

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapToGho(USER, USER, amount, expectedOut);
        vm.prank(USER);
        uint256 ghoReceived = GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_TOKEN), amount, 0);

        assertEq(ghoReceived, expectedOut, "Received GHO does not match");
    }

    function testSwapToGHOWithRecipient() public {
        uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);
        
        uint256 amount = 1_000e6;
        _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), amount);
        uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);
        uint256 expectedOut = 9900000000000000000000;

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapToGho(USER, RECIPIENT, amount, expectedOut);
        vm.prank(USER);
        uint256 ghoReceived = GHO_ROUTER.swapToGho(address(GHO_GSM_4626), address(USDX_TOKEN), amount, 0, RECIPIENT);

        assertEq(ghoReceived, expectedOut, "Received GHO does not match");
        assertEq(IERC20(GHO_TOKEN).balanceOf(RECIPIENT) - recipientBalanceBefore, ghoReceived, "Recipient gets GHO");
        assertEq(IERC20(GHO_TOKEN).balanceOf(USER), userBalanceBefore, "Caller should not receive GHO");
    }

}

contract SwapFromGHOTest is GhoRouterTest {
    function testSwapFromGHOZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 0, 0);
        vm.stopPrank();
    }

    function testSwapFromGHOSlippageExceeded() public {
        uint256 amount = 100 ether;

        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

        // Set unreasonably high minOutputAmount to trigger slippage
        vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
        vm.prank(USER);
        GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, type(uint256).max);

        vm.stopPrank();
    }

    function testSwapFromGHOGSMNotAllowed() public {
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 1, 0);
        vm.stopPrank();
    }

    function testSwapFromGHOZeroAddressRecipient() public {
        uint256 amount = 1 ether;
        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, 0, address(0));
        vm.stopPrank();
    }

    function testSwapFromGHOToUSDX_4626_TOKEN() public {
        uint256 expectedAmount = 90909090;
        uint256 amount = 100 ether;
        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromGho(USER, USER, 99999999000000000000, expectedAmount); // 1 ether diff in input
        vm.prank(USER);
        uint256 outputAmount = GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, 0);
        assertEq(outputAmount, expectedAmount, "Should receive output token");
    }

    function testSwapFromGHOToStataUSDX_4626_TOKEN() public {
        uint256 expectedAmount = 90909090;
        uint256 amount = 100 ether;
        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);

        uint256 userBalanceBefore = IERC20(address(USDX_4626_TOKEN)).balanceOf(USER);

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromGho(USER, USER, 99999999000000000000, expectedAmount); // 1 ether diff in input
        vm.prank(USER);
        uint256 outputAmount = GHO_ROUTER.swapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, 1);
        assertEq(outputAmount, expectedAmount, "Should receive output token");

        assertEq(IERC20(address(USDX_4626_TOKEN)).balanceOf(USER) - userBalanceBefore, outputAmount, "User gets static aToken");
    }

}

contract SwapTosGHOTest is GhoRouterTest {
    function testSwapToSGHOGSMNotAllowed() public {
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        GHO_ROUTER.swapToSGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 1, 0);
        vm.stopPrank();
    }

    function testSwapToSGHOZeroAddressRecipient() public {
        uint256 amount = 1 ether;
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        GHO_ROUTER.depositForSGho(amount, 0, address(0));
    }

    function testSwapToSGHOUnderlying() public {
        uint256 expectedOut = 1;
        uint256 amount = 1_000e6;
        _dealAndApprove(address(USDX_TOKEN), address(GHO_ROUTER), 1_000 ether); // Adjust for GHO decimals

        vm.prank(USER);
        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapToSGho(USER, USER, amount, expectedOut);
        uint256 shares = GHO_ROUTER.swapToSGho(address(GHO_GSM_4626), address(USDX_TOKEN), amount, 1);

        assertEq(shares, expectedOut, "Should receive sGHO shares");
        assertEq(IERC20(address(SGHO)).balanceOf(USER), shares, "User should receive minted shares");
    }
}

contract SwapFromsGHOTest is GhoRouterTest {
    function testSwapFromSGHOZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        GHO_ROUTER.swapFromsGHO(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 0, 0);
        vm.stopPrank();
    }

    function testSwapFromSGHOZeroAddressRecipient() public {
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        GHO_ROUTER.swapFromsGHO(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 1 ether, 1 ether, address(0));
        vm.stopPrank();
    }

    function testSwapFromSGHOGSMNotAllowed() public {
        GHO_ROUTER.setGsmAllowed(address(GHO_GSM_4626), false);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        GHO_ROUTER.swapFromsGHO(address(GHO_GSM_4626), address(USDX_4626_TOKEN), 100 ether, 0);
        vm.stopPrank();
    }

    function testSwapFromSGHO() public {
        uint256 expectedOut = 90909090;
        uint256 amount = 100 ether;
        _mintSgho(amount);

        vm.startPrank(USER);
        SGHO.approve(address(GHO_ROUTER), amount);

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromSGho(USER, USER, amount, expectedOut);
        uint256 outputAmount = GHO_ROUTER.swapFromsGHO(address(GHO_GSM_4626), address(USDX_TOKEN), amount, 1);
        vm.stopPrank();

        assertEq(outputAmount, expectedOut, "Should receive USDX_4626_TOKEN");
        assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, "User should spend all sGHO");
    }

    function testSwapFromSGHOStata() public {
        uint256 expectedOut = 90909090;
        uint256 amount = 100 ether;
        _mintSgho(amount);

        vm.startPrank(USER);
        SGHO.approve(address(GHO_ROUTER), amount);

        uint256 userBalanceBefore = IERC20(address(USDX_4626_TOKEN)).balanceOf(USER);

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromSGho(USER, USER, amount, expectedOut);

        uint256 outputAmount = GHO_ROUTER.swapFromsGHO(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount, 1);
        vm.stopPrank();

        assertEq(outputAmount, expectedOut, "Should receive static aToken");
        assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, "User should spend all sGHO");
        assertEq(
            IERC20(address(USDX_4626_TOKEN)).balanceOf(USER) - userBalanceBefore,
            outputAmount,
            "User should receive static aToken output"
        );
    }
}

contract DepositForSGhoTest is GhoRouterTest {
    function testDepositForSGHO() public {
        uint256 amount = 100 ether;

        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapToSGho(USER, USER, amount, amount);
        vm.startPrank(USER);
        uint256 shares = GHO_ROUTER.depositForSGho(amount, amount);
        vm.stopPrank();

        assertEq(shares, amount, "sGHO copy should mint 1:1 shares at initial index");
        assertEq(IERC20(address(SGHO)).balanceOf(USER), amount, "User should receive all shares");
    }

    function testDepositForSGHOWithRecipient() public {
        uint256 amount = 100 ether;

        _dealAndApprove(address(GHO_TOKEN), address(GHO_ROUTER), amount);
        uint256 recipientBalanceBefore = IERC20(address(SGHO)).balanceOf(RECIPIENT);
        uint256 userBalanceBefore = IERC20(address(SGHO)).balanceOf(USER);
        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapToSGho(USER, RECIPIENT, amount, amount);
        vm.startPrank(USER);
        uint256 shares = GHO_ROUTER.depositForSGho(amount, amount, RECIPIENT);
        vm.stopPrank();

        assertEq(shares, amount, "sGHO copy should mint 1:1 shares at initial index");
        assertEq(
            IERC20(address(SGHO)).balanceOf(RECIPIENT) - recipientBalanceBefore,
            shares,
            "Recipient should receive shares"
        );
        assertEq(IERC20(address(SGHO)).balanceOf(USER), userBalanceBefore, "Caller should not receive shares");
    }
}

contract RedeemSGhoTest is GhoRouterTest {
    function testRedeemSGHO() public {
        uint256 amount = 100 ether;
        _mintSgho(amount);

        
        vm.startPrank(USER);
        SGHO.approve(address(GHO_ROUTER), amount);
        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromSGho(USER, USER, amount, amount);
        uint256 outputAmount = GHO_ROUTER.redeemSGho(amount, amount);
        vm.stopPrank();

        assertEq(outputAmount, amount, "Should redeem to full GHO amount");
        assertEq(IERC20(GHO_TOKEN).balanceOf(USER), amount, "User should receive redeemed GHO");
        assertEq(IERC20(address(SGHO)).balanceOf(USER), 0, "User should spend all sGHO");
    }

    function testRedeemSGHOWithRecipient() public {
        uint256 amount = 100 ether;
        _mintSgho(amount);

        vm.startPrank(USER);

        SGHO.approve(address(GHO_ROUTER), amount);
        uint256 recipientBalanceBefore = IERC20(GHO_TOKEN).balanceOf(RECIPIENT);
        uint256 userBalanceBefore = IERC20(GHO_TOKEN).balanceOf(USER);

        vm.expectEmit(true, true, true, true, address(GHO_ROUTER));
        emit IGhoRouter.SwapFromSGho(USER, RECIPIENT, amount, amount);
        uint256 outputAmount = GHO_ROUTER.redeemSGho(amount, amount, RECIPIENT);
        vm.stopPrank();

        assertEq(outputAmount, amount, "Should redeem to full GHO amount");
        assertEq(
            IERC20(GHO_TOKEN).balanceOf(RECIPIENT) - recipientBalanceBefore, outputAmount, "Recipient should receive GHO"
        );
        assertEq(IERC20(GHO_TOKEN).balanceOf(USER), userBalanceBefore, "Caller should not receive GHO");
    }
}

contract PreviewSwapsTest is GhoRouterTest {
    function testPreviewSwapToGHO() public view {
        uint256 amount = 1000e6;
        (uint256 ghoAmount, uint256 fee) = GHO_ROUTER.previewSwapToGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(ghoAmount, 0, "Should preview GHO amount");
        // Fee might be zero depending on GSM config, so we just check it doesn't revert
        assertGe(fee, 0);
    }

    function testPreviewSwapFromGHO() public view {
        uint256 amount = 1_000 ether;
        (uint256 outputAmount, uint256 fee) = GHO_ROUTER.previewSwapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(outputAmount, 0, "Should preview output amount");
        assertGe(fee, 0);
    }

    function testPreviewSwapFromGHOToStataUSDX_4626_TOKEN() public view {
        uint256 amount = 1000 * 1e18;
        (uint256 outputAmount, uint256 fee) = GHO_ROUTER.previewSwapFromGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(outputAmount, 0, "Should preview static aToken output amount");
        assertGe(fee, 0);
    }

    function testPreviewSwapToSGHO() public view {
        uint256 amount = 1000 * 1e6;
        (uint256 sghoAmount, uint256 fee) = GHO_ROUTER.previewSwapToSGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(sghoAmount, 0, "Should preview sGHO amount");
        assertGe(fee, 0, "Fee check should not revert");
    }

    function testPreviewDepositForSGHO() public view {
        uint256 amount = 100 ether;
        uint256 outputAmount = GHO_ROUTER.previewDepositForSGho(amount);

        assertEq(outputAmount, amount, "sGHO copy preview should be 1:1 at initial index");
    }

    function testPreviewSwapFromSGHOUSDX_4626_TOKEN() public view {
        uint256 amount = 100 ether;
        (uint256 outputAmount, uint256 fee) = GHO_ROUTER.previewSwapFromSGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(outputAmount, 0, "Should preview USDX_4626_TOKEN output");
        assertGe(fee, 0, "Fee check should not revert");
    }

    function testPreviewSwapFromSGHOStataUSDX_4626_TOKEN() public view {
        uint256 amount = 100 ether;
        (uint256 outputAmount, uint256 fee) = GHO_ROUTER.previewSwapFromSGho(address(GHO_GSM_4626), address(USDX_4626_TOKEN), amount);

        assertGt(outputAmount, 0, "Should preview static aToken output");
        assertGe(fee, 0, "Fee check should not revert");
    }

    function testPreviewRedeemSGho() public view {
        uint256 amount = 100 ether;
        uint256 outputAmount = GHO_ROUTER.previewRedeemSGho(amount);

        assertEq(outputAmount, amount, "Should preview static aToken output");
    }
}
