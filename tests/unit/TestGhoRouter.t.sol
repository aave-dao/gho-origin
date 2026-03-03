// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {GhoRouter} from "src/contracts/misc/GhoRouter.sol";
import {IGhoRouter} from "src/contracts/misc/interfaces/IGhoRouter.sol";

/// Temp
contract sGho {
    function initialize(address gho, uint160 initialSupplyCap, address owner) external {}
    function deposit(uint256 amount, address recipient) external {}
}

/**
 * @title GhoRouterTest
 * @notice Integration tests for GhoRouter on mainnet fork
 * @dev Run with: forge test --match-path test/fork/onboarding/GhoRouterTest.t.sol -vvv
 */
contract GhoRouterTest is Test {
    GhoRouter public router;
    sGho public sgho;

    // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // https://etherscan.io/address/0xdAC17F958D2ee523a2206206994597C13D831ec7
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    // https://etherscan.io/address/0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

    // Static aTokens Constants
    // https://etherscan.io/address/0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E
    address public constant STATA_USDC = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    // https://etherscan.io/address/0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8
    address public constant STATA_USDT = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;

    // Addresses needed for test setup
    // https://etherscan.io/address/0xFeeb6FE430B7523fEF2a38327241eE7153779535
    address constant GSM_USDC = 0xFeeb6FE430B7523fEF2a38327241eE7153779535;
    // https://etherscan.io/address/0x535b2f7C20B9C83d70e519cf9991578eF9816B7B
    address constant GSM_USDT = 0x535b2f7C20B9C83d70e519cf9991578eF9816B7B;

    // Test user address
    address constant USER = address(0xF00DBA11);
    address constant RECIPIENT = address(0xCAFEF00D);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 24_001_794);

        sGho sghoImpl = new sGho();
        sgho = sGho(
            address(
                new ERC1967Proxy(
                    address(sghoImpl), abi.encodeCall(sGho.initialize, (GHO, type(uint160).max, address(this)))
                )
            )
        );
        router = new GhoRouter(address(this), GHO, address(sgho));
        router.setGsmAllowed(GSM_USDC, true);
        router.setGsmAllowed(GSM_USDT, true);
    }

    function _dealAndApprove(address token, address spender, uint256 amount) internal {
        deal(token, USER, amount);
        vm.prank(USER);
        SafeERC20.forceApprove(IERC20(token), spender, amount);
    }
}

contract GsmWhitelistTest is GhoRouterTest {
    function testSetGsmAllowedNonOwner() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        router.setGsmAllowed(GSM_USDC, false);
        vm.stopPrank();
    }

    function testSetGsmAllowed() public {
        router.setGsmAllowed(GSM_USDC, false);
        assertFalse(router.isGsmAllowed(GSM_USDC));

        router.setGsmAllowed(GSM_USDC, true);
        assertTrue(router.isGsmAllowed(GSM_USDC));
    }
}

contract SwapToGHOTest is GhoRouterTest {
    function _assertSwapTokenToGho(address token, address gsm, uint256 amount) internal {
        
    }

    function testSwapToGHOUSDC() public {
        uint256 amount = 1_000e6;
        _dealAndApprove(USDC, address(router), amount);

        uint256 expectedOut = 1;

        vm.expectEmit(true, true, true, true, address(router));
        emit IGhoRouter.SwapToGHO(USER, USDC, 0, 0);
        vm.prank(USER);
        uint256 ghoReceived = router.swapToGHO(GSM_USDC, USDC, amount, 0);

        assertEq(ghoReceived, expectedOut, "Received GHO does not match");
    }

    function testSwapToGHOUSDT() public {
        uint256 amount = 1_000e6;
        _dealAndApprove(USDT, address(router), amount);

        uint256 expectedOut = 1;

        vm.expectEmit(true, true, true, true, address(router));
        emit IGhoRouter.SwapToGHO(USER, USDT, 0, 0);
        vm.prank(USER);
        uint256 ghoReceived = router.swapToGHO(GSM_USDT, USDT, amount, 0);

        assertEq(ghoReceived, expectedOut, "Received GHO does not match");
    }

    function testSwapToGHOUSDCWithRecipient() public {
        uint256 recipientBalanceBefore = IERC20(GHO).balanceOf(RECIPIENT);
        
        uint256 amount = 1_000e6;
        _dealAndApprove(USDT, address(router), amount);
        uint256 userBalanceBefore = IERC20(GHO).balanceOf(USER);
        uint256 expectedOut = 1;

        vm.expectEmit(true, true, true, true, address(router));
        emit IGhoRouter.SwapToGHO(USER, USDT, 0, 0);
        vm.prank(USER);
        uint256 ghoReceived = router.swapToGHO(GSM_USDT, USDT, amount, 0);

        assertEq(ghoReceived, expectedOut, "Received GHO does not match");
        vm.stopPrank();

        assertGt(ghoReceived, 0, "Should receive GHO");
        assertEq(IERC20(GHO).balanceOf(RECIPIENT) - recipientBalanceBefore, ghoReceived, "Recipient gets GHO");
        assertEq(IERC20(GHO).balanceOf(USER), userBalanceBefore, "Caller should not receive GHO");
    }

    function test_reverts_swap_to_gho_zero_amount() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        router.swapToGHO(GSM_USDC, USDC, 0, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_to_gho_slippage_exceeded() public {
        uint256 usdcAmount = 1000 * 1e6; // 1000 USDC
        _dealAndStartUserWithRouterApproval(USDC, usdcAmount);

        // Set unreasonably high minGHOAmount to trigger slippage
        vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
        router.swapToGHO(GSM_USDC, USDC, usdcAmount, type(uint256).max);

        vm.stopPrank();
    }

    function test_reverts_swap_to_gho_gsm_not_allowed() public {
        router.setGsmAllowed(GSM_USDC, false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        router.swapToGHO(GSM_USDC, USDC, 1, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_to_gho_invalid_token() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidToken.selector);
        router.swapToGHO(GSM_USDC, GHO, 1, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_to_gho_zero_recipient() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        router.swapToGHO(GSM_USDC, USDC, 1, 0, address(0));
        vm.stopPrank();
    }
}

contract SwapFromGHOTest is GhoRouterTest {
    function _assertSwapGhoToToken(address token, address gsm, uint256 ghoAmount) internal {
        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);
        vm.expectEmit(true, true, false, false);
        emit IGhoRouter.SwapFromGHO(USER, token, 0, 0);
        uint256 outputAmount = router.swapFromGHO(gsm, ghoAmount, 0);
        assertGt(outputAmount, 0, "Should receive output token");
        vm.stopPrank();
    }

    function test_swap_gho_to_usdc() public {
        _assertSwapGhoToToken(USDC, GSM_USDC, 100 ether);
    }

    function test_swap_gho_to_usdt() public {
        _assertSwapGhoToToken(USDT, GSM_USDT, 100 ether);
    }

    function test_swap_gho_to_stata_usdc() public {
        uint256 ghoAmount = 100 ether;
        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);

        uint256 userBalanceBefore = IERC20(STATA_USDC).balanceOf(USER);
        vm.expectEmit(true, true, false, false);
        emit IGhoRouter.SwapFromGHO(USER, STATA_USDC, 0, 0);
        uint256 stataReceived = router.swapFromGHO(GSM_USDC, STATA_USDC, ghoAmount, 1);
        vm.stopPrank();

        assertGt(stataReceived, 0, "Should receive static aToken");
        assertEq(IERC20(STATA_USDC).balanceOf(USER) - userBalanceBefore, stataReceived, "User gets static aToken");
    }

    function test_swap_gho_to_usdc_with_recipient() public {
        uint256 ghoAmount = 100 ether;

        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);

        uint256 recipientBalanceBefore = IERC20(USDC).balanceOf(RECIPIENT);
        uint256 userBalanceBefore = IERC20(USDC).balanceOf(USER);
        uint256 usdcReceived = router.swapFromGHO(GSM_USDC, ghoAmount, 0, RECIPIENT);
        vm.stopPrank();

        assertGt(usdcReceived, 0, "Should receive USDC");
        assertEq(IERC20(USDC).balanceOf(RECIPIENT) - recipientBalanceBefore, usdcReceived, "Recipient gets USDC");
        assertEq(IERC20(USDC).balanceOf(USER), userBalanceBefore, "Caller should not receive USDC");
    }

    function test_reverts_swap_from_gho_zero_amount() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        router.swapFromGHO(GSM_USDC, 0, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_from_gho_slippage_exceeded() public {
        uint256 ghoAmount = 100 ether;

        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);

        // Set unreasonably high minOutputAmount to trigger slippage
        vm.expectRevert(IGhoRouter.SlippageExceeded.selector);
        router.swapFromGHO(GSM_USDC, ghoAmount, type(uint256).max);

        vm.stopPrank();
    }

    function test_reverts_swap_from_gho_gsm_not_allowed() public {
        router.setGsmAllowed(GSM_USDC, false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        router.swapFromGHO(GSM_USDC, 1, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_from_gho_invalid_token() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidToken.selector);
        router.swapFromGHO(GSM_USDC, GHO, 1 ether, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_from_gho_zero_recipient() public {
        uint256 ghoAmount = 1 ether;
        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        router.swapFromGHO(GSM_USDC, ghoAmount, 0, address(0));
        vm.stopPrank();
    }

    function test_preview_swap_to_gho() public view {
        uint256 usdcAmount = 1000 * 1e6; // 1000 USDC

        (uint256 ghoAmount, uint256 fee) = router.previewSwapToGHO(GSM_USDC, USDC, usdcAmount);

        assertGt(ghoAmount, 0, "Should preview GHO amount");
        // Fee might be zero depending on GSM config, so we just check it doesn't revert
        assertGe(fee, 0);
    }

    function test_preview_swap_from_gho() public view {
        uint256 ghoAmount = 1000 * 1e18; // 1000 GHO

        (uint256 outputAmount, uint256 fee) = router.previewSwapFromGHO(GSM_USDC, ghoAmount);

        assertGt(outputAmount, 0, "Should preview output amount");
        assertGe(fee, 0);
    }

    function test_preview_swap_from_gho_to_stata() public view {
        uint256 ghoAmount = 1000 * 1e18;

        (uint256 outputAmount, uint256 fee) = router.previewSwapFromGHO(GSM_USDC, STATA_USDC, ghoAmount);

        assertGt(outputAmount, 0, "Should preview static aToken output amount");
        assertGe(fee, 0);
    }
}

contract SwapTosGHOTest is GhoRouterTest {
    function _assertSwapTokenToSgho(address token, address gsm, uint256 amount) internal {
        _dealAndStartUserWithRouterApproval(token, amount);
        vm.expectEmit(true, true, true, false);
        emit IGhoRouter.SwapTosGHO(USER, token, 0, 0);
        uint256 shares = router.swapTosGHO(gsm, token, amount, 1);
        assertGt(shares, 0, "Should receive sGHO shares");
        assertEq(IERC20(address(sgho)).balanceOf(USER), shares, "User should receive minted shares");
        vm.stopPrank();
    }

    function test_swap_usdc_to_sgho() public {
        _assertSwapTokenToSgho(USDC, GSM_USDC, 1000 * 1e6);
    }

    function test_swap_usdt_to_sgho() public {
        _assertSwapTokenToSgho(USDT, GSM_USDT, 1000 * 1e6);
    }

    function test_swap_gho_to_sgho() public {
        uint256 ghoAmount = 100 ether;

        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);
        vm.expectEmit(true, true, true, true);
        emit IGhoRouter.SwapTosGHO(USER, GHO, ghoAmount, ghoAmount);
        uint256 shares = router.depositForSGho(ghoAmount, ghoAmount);
        vm.stopPrank();

        assertEq(shares, ghoAmount, "sGHO copy should mint 1:1 shares at initial index");
        assertEq(IERC20(address(sgho)).balanceOf(USER), ghoAmount, "User should receive all shares");
    }

    function test_swap_gho_to_sgho_with_recipient() public {
        uint256 ghoAmount = 100 ether;

        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);
        uint256 recipientBalanceBefore = IERC20(address(sgho)).balanceOf(RECIPIENT);
        uint256 userBalanceBefore = IERC20(address(sgho)).balanceOf(USER);
        uint256 shares = router.depositForSGho(ghoAmount, ghoAmount, RECIPIENT);
        vm.stopPrank();

        assertEq(shares, ghoAmount, "sGHO copy should mint 1:1 shares at initial index");
        assertEq(
            IERC20(address(sgho)).balanceOf(RECIPIENT) - recipientBalanceBefore,
            shares,
            "Recipient should receive shares"
        );
        assertEq(IERC20(address(sgho)).balanceOf(USER), userBalanceBefore, "Caller should not receive shares");
    }

    function test_preview_swap_to_sgho() public view {
        uint256 usdcAmount = 1000 * 1e6;

        (uint256 sghoAmount, uint256 fee) = router.previewSwapTosGHO(GSM_USDC, USDC, usdcAmount);

        assertGt(sghoAmount, 0, "Should preview sGHO amount");
        assertGe(fee, 0, "Fee check should not revert");
    }

    function test_reverts_swap_to_sgho_gsm_not_allowed() public {
        router.setGsmAllowed(GSM_USDC, false);

        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        router.swapTosGHO(GSM_USDC, USDC, 1, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_to_sgho_zero_recipient() public {
        uint256 ghoAmount = 1 ether;
        _dealAndStartUserWithRouterApproval(GHO, ghoAmount);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        router.depositForSGho(ghoAmount, 0, address(0));
        vm.stopPrank();
    }
}

contract SwapFromsGHOTest is GhoRouterTest {
    function _mintSgho(uint256 ghoAmount) internal {
        _dealAndStartUserWithApproval(GHO, address(sgho), ghoAmount);
        sgho.deposit(ghoAmount, USER);
        vm.stopPrank();
    }

    function test_swap_sgho_to_gho() public {
        uint256 ghoAmount = 100 ether;
        _mintSgho(ghoAmount);

        _startUserWithRouterApproval(address(sgho), ghoAmount);
        vm.expectEmit(true, true, true, true);
        emit IGhoRouter.SwapFromsGHO(USER, address(sgho), ghoAmount, ghoAmount);
        uint256 outputAmount = router.redeemSGho(ghoAmount, ghoAmount);
        vm.stopPrank();

        assertEq(outputAmount, ghoAmount, "Should redeem to full GHO amount");
        assertEq(IERC20(GHO).balanceOf(USER), ghoAmount, "User should receive redeemed GHO");
        assertEq(IERC20(address(sgho)).balanceOf(USER), 0, "User should spend all sGHO");
    }

    function test_swap_sgho_to_gho_with_recipient() public {
        uint256 ghoAmount = 100 ether;
        _mintSgho(ghoAmount);

        _startUserWithRouterApproval(address(sgho), ghoAmount);
        uint256 recipientBalanceBefore = IERC20(GHO).balanceOf(RECIPIENT);
        uint256 userBalanceBefore = IERC20(GHO).balanceOf(USER);
        uint256 outputAmount = router.redeemSGho(ghoAmount, ghoAmount, RECIPIENT);
        vm.stopPrank();

        assertEq(outputAmount, ghoAmount, "Should redeem to full GHO amount");
        assertEq(
            IERC20(GHO).balanceOf(RECIPIENT) - recipientBalanceBefore, outputAmount, "Recipient should receive GHO"
        );
        assertEq(IERC20(GHO).balanceOf(USER), userBalanceBefore, "Caller should not receive GHO");
    }

    function test_swap_sgho_to_usdc() public {
        uint256 ghoAmount = 100 ether;
        _mintSgho(ghoAmount);

        _startUserWithRouterApproval(address(sgho), ghoAmount);
        vm.expectEmit(true, true, true, false);
        emit IGhoRouter.SwapFromsGHO(USER, address(sgho), 0, 0);
        uint256 outputAmount = router.swapFromsGHO(GSM_USDC, USDC, ghoAmount, 1);
        vm.stopPrank();

        assertGt(outputAmount, 0, "Should receive USDC");
        assertEq(IERC20(address(sgho)).balanceOf(USER), 0, "User should spend all sGHO");
    }

    function test_swap_sgho_to_stata_usdc() public {
        uint256 ghoAmount = 100 ether;
        _mintSgho(ghoAmount);

        _startUserWithRouterApproval(address(sgho), ghoAmount);
        uint256 userBalanceBefore = IERC20(STATA_USDC).balanceOf(USER);
        vm.expectEmit(true, true, true, false);
        emit IGhoRouter.SwapFromsGHO(USER, address(sgho), 0, 0);
        uint256 outputAmount = router.swapFromsGHO(GSM_USDC, STATA_USDC, ghoAmount, 1);
        vm.stopPrank();

        assertGt(outputAmount, 0, "Should receive static aToken");
        assertEq(IERC20(address(sgho)).balanceOf(USER), 0, "User should spend all sGHO");
        assertEq(
            IERC20(STATA_USDC).balanceOf(USER) - userBalanceBefore,
            outputAmount,
            "User should receive static aToken output"
        );
    }

    function test_reverts_swap_from_sgho_zero_amount() public {
        vm.startPrank(USER);
        vm.expectRevert(IGhoRouter.InvalidAmount.selector);
        router.swapFromsGHO(GSM_USDC, 0, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_from_sgho_zero_recipient() public {
        _mintSgho(1 ether);

        _startUserWithRouterApproval(address(sgho), 1 ether);
        vm.expectRevert(IGhoRouter.ZeroAddress.selector);
        router.swapFromsGHO(1 ether, 0, address(0));
        vm.stopPrank();
    }

    function test_preview_swap_from_sgho_to_gho() public view {
        uint256 shareAmount = 100 ether;

        uint256 outputAmount = router.previewSwapFromsGHO(shareAmount);

        assertEq(outputAmount, shareAmount, "sGHO copy preview should be 1:1 at initial index");
    }

    function test_preview_swap_from_sgho_to_usdc() public view {
        uint256 shareAmount = 100 ether;

        (uint256 outputAmount, uint256 fee) = router.previewSwapFromsGHO(GSM_USDC, shareAmount);

        assertGt(outputAmount, 0, "Should preview USDC output");
        assertGe(fee, 0, "Fee check should not revert");
    }

    function test_reverts_swap_from_sgho_to_usdc_gsm_not_allowed() public {
        router.setGsmAllowed(GSM_USDC, false);
        _mintSgho(100 ether);

        _startUserWithRouterApproval(address(sgho), 100 ether);
        vm.expectRevert(IGhoRouter.GsmNotAllowed.selector);
        router.swapFromsGHO(GSM_USDC, 100 ether, 0);
        vm.stopPrank();
    }

    function test_reverts_swap_from_sgho_invalid_token() public {
        _mintSgho(1 ether);

        _startUserWithRouterApproval(address(sgho), 1 ether);
        vm.expectRevert(IGhoRouter.InvalidToken.selector);
        router.swapFromsGHO(GSM_USDC, GHO, 1 ether, 0);
        vm.stopPrank();
    }

    function test_preview_swap_from_sgho_to_stata() public view {
        uint256 shareAmount = 100 ether;

        (uint256 outputAmount, uint256 fee) = router.previewSwapFromsGHO(GSM_USDC, STATA_USDC, shareAmount);

        assertGt(outputAmount, 0, "Should preview static aToken output");
        assertGe(fee, 0, "Fee check should not revert");
    }
}
