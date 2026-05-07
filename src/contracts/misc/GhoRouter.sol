// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from '@openzeppelin/contracts/interfaces/IERC4626.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {IGsm} from 'src/contracts/facilitators/gsm/interfaces/IGsm.sol';
import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';

/**
 * @title GhoRouter
 * @author TokenLogic
 * @notice Router for token swaps through whitelisted GSMs and direct GHO/sGHO conversion paths
 * @dev This contract never stores user funds and uses exact approvals only
 */
contract GhoRouter is Ownable, IGhoRouter {
  using SafeERC20 for IERC20;

  /// @inheritdoc IGhoRouter
  address public immutable GHO;

  /// @inheritdoc IGhoRouter
  address public immutable sGHO;

  /// @inheritdoc IGhoRouter
  mapping(address token => address gsm) public gsms;

  /**
   * @dev Constructor to initialize the contract
   * @param initialOwner Address of the contract owner
   * @param gho Address of the GHO token on the deployed network
   * @param sgho Address of sGHO on the deployed network
   */
  constructor(address initialOwner, address gho, address sgho) Ownable(initialOwner) {
    require(gho != address(0), ZeroAddress());
    require(sgho != address(0), ZeroAddress());
    require(IERC4626(sgho).asset() == gho, InvalidToken());

    GHO = gho;
    sGHO = sgho;
  }

  /// @inheritdoc IGhoRouter
  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address recipient,
    uint256 deadline
  ) external returns (uint256) {
    _validateInputs(amountIn, recipient, deadline);

    uint256 amountOut;
    if (tokenIn == GHO) {
      if (tokenOut == sGHO) {
        amountOut = _depositForSGho(amountIn, minAmountOut, recipient);
      } else {
        (amountIn, amountOut) = _swapFromGho(tokenOut, amountIn, minAmountOut, recipient);
      }
    } else if (tokenIn == sGHO) {
      if (tokenOut == GHO) {
        amountOut = _redeemFromSGho(amountIn, minAmountOut, recipient);
      } else {
        amountOut = _swapFromSGho(tokenOut, amountIn, minAmountOut, recipient);
      }
    } else {
      if (tokenOut == GHO) {
        (amountIn, amountOut) = _swapToGho(tokenIn, amountIn, minAmountOut, recipient);
      } else if (tokenOut == sGHO) {
        (amountIn, amountOut) = _swapToSGho(tokenIn, amountIn, minAmountOut, recipient);
      } else {
        revert InvalidPath();
      }
    }

    emit Swap(tokenIn, tokenOut, amountIn, amountOut, recipient);

    return amountOut;
  }

  /// @inheritdoc IGhoRouter
  function setTokenToGsm(address token, address gsm) external onlyOwner {
    require(token != address(0) && gsm != address(0), ZeroAddress());
    require(gsms[token] == address(0), TokenToGsmAlreadySet());

    _validateGsm(gsm, token);

    gsms[token] = gsm;
    emit TokenToGsmAdded(token, gsm);
  }

  /// @inheritdoc IGhoRouter
  function removeTokenToGsm(address token) external onlyOwner {
    address gsm = gsms[token];
    require(gsm != address(0), TokenToGsmNotSet());

    delete gsms[token];

    emit TokenToGsmRemoved(token, gsm);
  }

  /// @inheritdoc IGhoRouter
  function rescueToken(address token, address to, uint256 amount) external onlyOwner {
    require(token != address(0) && to != address(0), ZeroAddress());
    IERC20(token).safeTransfer(to, amount);
  }

  /// @inheritdoc IGhoRouter
  function previewSwap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256) {
    require(amountIn > 0, InvalidAmount());

    uint256 amountOut;
    if (tokenIn == GHO) {
      if (tokenOut == sGHO) {
        amountOut = IERC4626(sGHO).previewDeposit(amountIn);
      } else {
        amountOut = _previewTokenWithGho(tokenOut, amountIn);
      }
    } else if (tokenIn == sGHO) {
      if (tokenOut == GHO) {
        amountOut = IERC4626(sGHO).previewRedeem(amountIn);
      } else {
        amountOut = _previewTokenWithGho(tokenOut, IERC4626(sGHO).previewRedeem(amountIn));
      }
    } else {
      if (tokenOut == GHO) {
        amountOut = _previewSwapToGho(tokenIn, amountIn);
      } else if (tokenOut == sGHO) {
        amountOut = _previewSwapToSGho(tokenIn, amountIn);
      } else {
        revert InvalidPath();
      }
    }

    return amountOut;
  }

  /**
   * @notice Preview the amount of GHO received for a given input amount
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to sell
   * @return ghoAmount Expected amount of GHO to receive
   */
  function _previewSwapToGho(address token, uint256 amount) internal view returns (uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    address stata = IGsm(gsm).UNDERLYING_ASSET();

    _validateTokens(token, stata);
    uint256 sharesAmount = token == stata ? amount : IERC4626(stata).previewDeposit(amount);

    (, uint256 ghoAmount, , ) = IGsm(gsm).getGhoAmountForSellAsset(sharesAmount);
    return ghoAmount;
  }

  /**
   * @notice Preview the amount of sGHO received for a given input amount through a GSM path
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to sell
   * @return sghoAmount Expected amount of sGHO shares to receive
   */
  function _previewSwapToSGho(address token, uint256 amount) internal view returns (uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    address stata = IGsm(gsm).UNDERLYING_ASSET();

    _validateTokens(token, stata);
    uint256 sharesAmount = token == stata ? amount : IERC4626(stata).previewDeposit(amount);
    (, uint256 ghoAmount, , ) = IGsm(gsm).getGhoAmountForSellAsset(sharesAmount);

    return IERC4626(sGHO).previewDeposit(ghoAmount);
  }

  /**
   * @dev Swaps a GSM-supported token into GHO and forwards output to the recipient.
   * @param token Input token (either GSM underlying token or its static aToken).
   * @param amount Amount of input tokens pulled from the caller.
   * @param minGHOAmount Minimum acceptable GHO output for slippage protection.
   * @param recipient Address that receives the resulting GHO.
   * @return assetSold Actual amount of asset sold in swap.
   * @return ghoAmount Amount of GHO sent to `recipient`.
   */
  function _swapToGho(
    address token,
    uint256 amount,
    uint256 minGHOAmount,
    address recipient
  ) internal returns (uint256, uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    (uint256 assetSold, uint256 ghoAmount) = _sellTokenForGho(gsm, token, amount, minGHOAmount);
    IERC20(GHO).safeTransfer(recipient, ghoAmount);

    return (assetSold, ghoAmount);
  }

  /**
   * @dev Swaps GHO into a caller-selected GSM token (underlying or static aToken) and forwards output.
   * @param token Output token (either GSM underlying token or its static aToken).
   * @param ghoAmount Amount of GHO pulled from the caller.
   * @param minOutputAmount Minimum acceptable output-token amount.
   * @param recipient Address that receives the resulting token.
   * @return ghoSold Actual amount of GHO sold in swap.
   * @return outputAmount Amount of output tokens sent to `recipient`.
   */
  function _swapFromGho(
    address token,
    uint256 ghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256, uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    address stata = IGsm(gsm).UNDERLYING_ASSET();
    _validateTokens(token, stata);

    (uint256 stataAmountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(
      ghoAmount
    );

    IERC20(GHO).safeTransferFrom(msg.sender, address(this), ghoUsed);

    return
      _buyTokenWithGho(gsm, token, stata, ghoUsed, stataAmountToBuy, recipient, minOutputAmount);
  }

  /**
   * @dev Swaps a GSM-supported token into GHO and deposits the result into sGHO.
   * @param token Input token (either GSM underlying token or its static aToken).
   * @param amount Amount of input tokens pulled from the caller.
   * @param minSGHOAmount Minimum acceptable sGHO shares minted.
   * @param recipient Address that receives the minted sGHO shares.
   * @return assetSold Actual amount of asset sold in swap.
   * @return sghoAmount Amount of sGHO shares minted to `recipient`.
   */
  function _swapToSGho(
    address token,
    uint256 amount,
    uint256 minSGHOAmount,
    address recipient
  ) internal returns (uint256, uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    (uint256 assetSold, uint256 ghoAmount) = _sellTokenForGho(gsm, token, amount, 0);
    uint256 sghoAmount = _depositGho(ghoAmount, recipient, minSGHOAmount);

    return (assetSold, sghoAmount);
  }

  /**
   * @dev Deposits GHO directly into sGHO.
   * @param ghoAmount Amount of GHO pulled from the caller.
   * @param minSGHOAmount Minimum acceptable sGHO shares minted.
   * @param recipient Address that receives the minted sGHO shares.
   * @return sghoAmount Amount of sGHO shares minted to `recipient`.
   */
  function _depositForSGho(
    uint256 ghoAmount,
    uint256 minSGHOAmount,
    address recipient
  ) internal returns (uint256) {
    IERC20(GHO).safeTransferFrom(msg.sender, address(this), ghoAmount);
    uint256 sghoAmount = _depositGho(ghoAmount, recipient, minSGHOAmount);

    return sghoAmount;
  }

  /**
   * @dev Redeems sGHO into GHO, then swaps through GSM into a caller-selected token.
   * @param token Output token (either GSM static aToken or aToken's underlying).
   * @param sghoAmount Amount of sGHO shares pulled from the caller.
   * @param minOutputAmount Minimum acceptable output-token amount.
   * @param recipient Address that receives the resulting token.
   * @return outputAmount Amount of output tokens sent to `recipient`.
   */
  function _swapFromSGho(
    address token,
    uint256 sghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    uint256 ghoAmount = _redeemGho(sghoAmount, 0);
    address stata = IGsm(gsm).UNDERLYING_ASSET();
    _validateTokens(token, stata);

    (uint256 stataAmountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(
      ghoAmount
    );
    (, uint256 outputAmount) = _buyTokenWithGho(
      gsm,
      token,
      stata,
      ghoUsed,
      stataAmountToBuy,
      recipient,
      minOutputAmount
    );

    return outputAmount;
  }

  /**
   * @dev Redeems sGHO directly into GHO and forwards output to the recipient.
   * @param sghoAmount Amount of sGHO shares pulled from the caller.
   * @param minOutputAmount Minimum acceptable GHO output.
   * @param recipient Address that receives the resulting GHO.
   * @return ghoAmount Amount of GHO sent to `recipient`.
   */
  function _redeemFromSGho(
    uint256 sghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256) {
    uint256 ghoAmount = _redeemGho(sghoAmount, minOutputAmount);

    IERC20(GHO).safeTransfer(recipient, ghoAmount);

    return ghoAmount;
  }

  /**
   * @dev Deposits GHO held by the router into sGHO.
   * @param ghoAmount Amount of GHO to deposit.
   * @param receiver Address receiving the minted sGHO shares.
   * @param minSghoAmount Minimum acceptable sGHO share output.
   * @return sghoAmount Amount of sGHO shares minted.
   */
  function _depositGho(
    uint256 ghoAmount,
    address receiver,
    uint256 minSghoAmount
  ) internal returns (uint256) {
    IERC20(GHO).forceApprove(sGHO, ghoAmount);
    uint256 sghoAmount = IERC4626(sGHO).deposit(ghoAmount, receiver);
    require(sghoAmount >= minSghoAmount, SlippageExceeded());
    return sghoAmount;
  }

  /**
   * @dev Pulls sGHO from the caller and redeems it for GHO into the router.
   * @param sghoAmount Amount of sGHO shares to redeem.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return ghoAmount Amount of GHO redeemed.
   */
  function _redeemGho(uint256 sghoAmount, uint256 minGhoAmount) internal returns (uint256) {
    uint256 ghoAmount = IERC4626(sGHO).redeem(sghoAmount, address(this), msg.sender);
    require(ghoAmount >= minGhoAmount, SlippageExceeded());
    return ghoAmount;
  }

  /**
   * @dev Sells input tokens through GSM for GHO, converting underlying to static aToken when needed.
   * @param gsm Whitelisted GSM used for the sell path.
   * @param token Input token address provided by the caller.
   * @param amount Amount of input tokens pulled from the caller.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return inputAmountUsed Amount of input tokens used in the swap.
   * @return ghoAmount Amount of GHO received from GSM.
   */
  function _sellTokenForGho(
    address gsm,
    address token,
    uint256 amount,
    uint256 minGhoAmount
  ) internal returns (uint256, uint256) {
    address stata = IGsm(gsm).UNDERLYING_ASSET();
    uint256 stataAmount = amount;
    if (token != stata) {
      _validateTokens(token, stata);
      IERC20(token).forceApprove(stata, amount);
      stataAmount = IERC4626(stata).deposit(amount, address(this));
    }

    IERC20(stata).forceApprove(gsm, stataAmount);
    (uint256 assetSold, uint256 ghoAmount) = IGsm(gsm).sellAsset(stataAmount, address(this));

    require(ghoAmount >= minGhoAmount, SlippageExceeded());
    return (token == stata ? assetSold : amount, ghoAmount);
  }

  /**
   * @dev Buys GSM static aTokens with GHO, then returns either static or underlying output based on `token`.
   * @param gsm Whitelisted GSM used for the buy path.
   * @param token Output token requested by the caller (underlying token or static aToken).
   * @param stata Address of the stata token used by the GSM.
   * @param ghoUsed GHO budget used to acquire static aTokens.
   * @param stataAmountToBuy Amount of stata token to acquire from the GSM.
   * @param outputReceiver Address receiving output tokens.
   * @param minOutputAmount Minimum acceptable output amount.
   * @return outputAmount Amount of output tokens sent to `outputReceiver`.
   * @return ghoSold Amount of GHO consumed by GSM.
   */
  function _buyTokenWithGho(
    address gsm,
    address token,
    address stata,
    uint256 ghoUsed,
    uint256 stataAmountToBuy,
    address outputReceiver,
    uint256 minOutputAmount
  ) internal returns (uint256, uint256) {
    IERC20(GHO).forceApprove(gsm, ghoUsed);
    (uint256 stataAmount, uint256 ghoSold) = IGsm(gsm).buyAsset(stataAmountToBuy, address(this));

    uint256 outputAmount = stataAmount;
    if (token == stata) {
      IERC20(stata).safeTransfer(outputReceiver, stataAmount);
    } else {
      outputAmount = IERC4626(stata).redeem(stataAmount, outputReceiver, address(this));
    }

    require(outputAmount >= minOutputAmount, SlippageExceeded());
    return (ghoSold, outputAmount);
  }

  /**
   * @dev Previews output amount for a GHO->GSM route without state changes.
   * @param token Output token requested (underlying token or static aToken).
   * @param ghoAmount GHO amount to simulate.
   * @return outputAmount Estimated output-token amount.
   */
  function _previewTokenWithGho(address token, uint256 ghoAmount) internal view returns (uint256) {
    address gsm = gsms[token];
    require(gsm != address(0), GsmNotConfigured());

    address stata = IGsm(gsm).UNDERLYING_ASSET();

    _validateTokens(token, stata);
    (uint256 assetAmount, , , ) = IGsm(gsm).getAssetAmountForBuyAsset(ghoAmount);
    uint256 outputAmount = token == stata
      ? assetAmount
      : IERC4626(stata).previewRedeem(assetAmount);
    return outputAmount;
  }

  /**
   * @dev Validates GSM compatibility against router configuration and expected interfaces.
   * @param gsm GSM address to validate.
   * @param token Token address to validate.
   */
  function _validateGsm(address gsm, address token) internal view {
    require(gsm.code.length != 0, InvalidGsm());

    require(IGsm(gsm).GHO_TOKEN() == GHO, InvalidGsm());
    address stataToken = IGsm(gsm).UNDERLYING_ASSET();
    require(stataToken != address(0), InvalidGsm());

    _validateTokens(token, stataToken);
  }

  /**
   * @dev Validates non-zero inputs.
   * @param amount Input amount that must be non-zero.
   * @param recipient Recipient address that must be non-zero.
   * @param deadline Maximum timestamp swap can be executed
   */
  function _validateInputs(uint256 amount, address recipient, uint256 deadline) internal view {
    require(amount > 0, InvalidAmount());
    require(deadline >= block.timestamp, DeadlineExpired());
    require(recipient != address(0), ZeroAddress());
  }

  function _validateTokens(address token, address stata) internal view {
    require(token == stata || token == IERC4626(stata).asset(), InvalidToken());
  }
}
