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
  mapping(address token => mapping(address gsm => bool allowed)) public allowedGsm;

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
    address gsm,
    uint256 exactAmountIn,
    uint256 minAmountOut,
    address recipient,
    uint256 deadline
  ) external returns (uint256) {
    _validateInputs(exactAmountIn, recipient, deadline);

    uint256 amountOut;
    if (tokenIn == GHO) {
      if (tokenOut == sGHO) {
        amountOut = _ghoToSGho(exactAmountIn, minAmountOut, recipient);
      } else {
        (amountOut, exactAmountIn) = _ghoToToken(
          tokenOut,
          gsm,
          exactAmountIn,
          minAmountOut,
          recipient
        );
      }
    } else if (tokenIn == sGHO) {
      if (tokenOut == GHO) {
        amountOut = _sGhoToGho(exactAmountIn, minAmountOut, recipient);
      } else {
        amountOut = _sGhoToToken(tokenOut, gsm, exactAmountIn, minAmountOut, recipient);
      }
    } else {
      if (tokenOut == GHO) {
        amountOut = _tokenToGho(tokenIn, gsm, exactAmountIn, minAmountOut, recipient);
      } else if (tokenOut == sGHO) {
        amountOut = _tokenToSGho(tokenIn, gsm, exactAmountIn, minAmountOut, recipient);
      } else {
        revert InvalidTokenPair(tokenIn, tokenOut);
      }
    }

    emit Swap(msg.sender, tokenIn, tokenOut, exactAmountIn, amountOut, recipient);

    return amountOut;
  }

  /// @inheritdoc IGhoRouter
  function allowTokenGsm(address token, address gsm) external onlyOwner {
    require(token != address(0) && gsm != address(0), ZeroAddress());
    require(allowedGsm[token][gsm] == false, TokenToGsmAlreadySet());

    _validateGsm(gsm, token);

    allowedGsm[token][gsm] = true;
    emit TokenToGsmAdded(token, gsm);
  }

  /// @inheritdoc IGhoRouter
  function revokeTokenGsm(address token, address gsm) external onlyOwner {
    require(allowedGsm[token][gsm], TokenToGsmNotSet());

    delete allowedGsm[token][gsm];

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
    address gsm,
    uint256 exactAmountIn
  ) external view returns (uint256) {
    require(exactAmountIn > 0, InvalidAmount());

    uint256 amountOut;
    if (tokenIn == GHO) {
      if (tokenOut == sGHO) {
        amountOut = IERC4626(sGHO).previewDeposit(exactAmountIn);
      } else {
        amountOut = _previewGhoToToken(tokenOut, gsm, exactAmountIn);
      }
    } else if (tokenIn == sGHO) {
      if (tokenOut == GHO) {
        amountOut = IERC4626(sGHO).previewRedeem(exactAmountIn);
      } else {
        amountOut = _previewGhoToToken(tokenOut, gsm, IERC4626(sGHO).previewRedeem(exactAmountIn));
      }
    } else {
      if (tokenOut == GHO) {
        amountOut = _previewTokenToGho(tokenIn, gsm, exactAmountIn);
      } else if (tokenOut == sGHO) {
        amountOut = _previewTokenToSGho(tokenIn, gsm, exactAmountIn);
      } else {
        revert InvalidTokenPair(tokenIn, tokenOut);
      }
    }

    return amountOut;
  }

  /**
   * @notice Preview the amount of GHO received for a given input amount
   * @param token Input token address (GSM underlying token or static aToken)
   * @param gsm Address of the GSM used to perform the swap
   * @param amount Amount of input token to sell
   * @return ghoAmount Expected amount of GHO to receive
   */
  function _previewTokenToGho(
    address token,
    address gsm,
    uint256 amount
  ) internal view returns (uint256) {
    require(allowedGsm[token][gsm], GsmNotConfigured());

    address underlying = IGsm(gsm).UNDERLYING_ASSET();

    _validateTokens(token, underlying);
    uint256 sharesAmount = token == underlying
      ? amount
      : IERC4626(underlying).previewDeposit(amount);
    (, uint256 ghoAmount, , ) = IGsm(gsm).getGhoAmountForSellAsset(sharesAmount);

    return ghoAmount;
  }

  /**
   * @notice Preview the amount of sGHO received for a given input amount through a GSM path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param gsm Address of the GSM used to perform the swap
   * @param amount Amount of input token to sell
   * @return sghoAmount Expected amount of sGHO shares to receive
   */
  function _previewTokenToSGho(
    address token,
    address gsm,
    uint256 amount
  ) internal view returns (uint256) {
    uint256 ghoAmount = _previewTokenToGho(token, gsm, amount);

    return IERC4626(sGHO).previewDeposit(ghoAmount);
  }

  /**
   * @dev Swaps a GSM-supported token into GHO and forwards output to the recipient.
   * @param token Input token (either GSM underlying token or its static aToken).
   * @param gsm Whitelisted GSM used for the swap.
   * @param exactAmountIn Amount of input tokens pulled from the caller.
   * @param minGhoAmount Minimum acceptable GHO output for slippage protection.
   * @param recipient Address that receives the resulting GHO.
   * @return ghoAmount Amount of GHO sent to `recipient`.
   */
  function _tokenToGho(
    address token,
    address gsm,
    uint256 exactAmountIn,
    uint256 minGhoAmount,
    address recipient
  ) internal returns (uint256) {
    uint256 ghoAmount = _performSwapToGho(token, gsm, exactAmountIn, minGhoAmount);
    IERC20(GHO).safeTransfer(recipient, ghoAmount);

    return ghoAmount;
  }

  /**
   * @dev Swaps GHO into a caller-selected GSM token (underlying or static aToken) and forwards output.
   * @dev An almost negligible amount of dust can be left unsued, would cost more in gas than amount returned.
   * @param token Output token (either GSM underlying token or its static aToken).
   * @param gsm Whitelisted GSM used for the swap.
   * @param exactAmountIn Amount of GHO pulled from the caller.
   * @param minOutputAmount Minimum acceptable output-token amount.
   * @param recipient Address that receives the resulting token.
   * @return outputAmount Amount of output tokens sent to `recipient`.
   * @return ghoUsed Amount of GHO actually consumed by the swap.
   */
  function _ghoToToken(
    address token,
    address gsm,
    uint256 exactAmountIn,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256, uint256) {
    require(allowedGsm[token][gsm], GsmNotConfigured());

    (uint256 amountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(exactAmountIn);

    IERC20(GHO).safeTransferFrom(msg.sender, address(this), ghoUsed);

    (, uint256 outputAmount) = _buyTokenWithGho({
      gsm: gsm,
      token: token,
      exactAmountIn: ghoUsed,
      amountToBuy: amountToBuy,
      outputReceiver: recipient,
      minOutputAmount: minOutputAmount
    });

    return (outputAmount, ghoUsed);
  }

  /**
   * @dev Swaps a GSM-supported token into GHO and deposits the result into sGHO.
   * @param token Input token (either GSM underlying token or its static aToken).
   * @param gsm Whitelisted GSM used for the swap.
   * @param exactAmountIn Amount of input tokens pulled from the caller.
   * @param minSGHOAmount Minimum acceptable sGHO shares minted.
   * @param recipient Address that receives the minted sGHO shares.
   * @return sghoAmount Amount of sGHO shares minted to `recipient`.
   */
  function _tokenToSGho(
    address token,
    address gsm,
    uint256 exactAmountIn,
    uint256 minSGHOAmount,
    address recipient
  ) internal returns (uint256) {
    uint256 ghoAmount = _performSwapToGho(token, gsm, exactAmountIn, 0);
    uint256 sghoAmount = _depositGho(ghoAmount, recipient, minSGHOAmount);

    return sghoAmount;
  }

  /**
   * @dev Deposits GHO directly into sGHO.
   * @param exactAmountIn Amount of GHO pulled from the caller.
   * @param minSGHOAmount Minimum acceptable sGHO shares minted.
   * @param recipient Address that receives the minted sGHO shares.
   * @return sghoAmount Amount of sGHO shares minted to `recipient`.
   */
  function _ghoToSGho(
    uint256 exactAmountIn,
    uint256 minSGHOAmount,
    address recipient
  ) internal returns (uint256) {
    IERC20(GHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
    uint256 sghoAmount = _depositGho(exactAmountIn, recipient, minSGHOAmount);

    return sghoAmount;
  }

  /**
   * @dev Redeems sGHO into GHO, then swaps through GSM into a caller-selected token.
   * @dev An almost negligible amount of dust can be left unsued, would cost more in gas than amount returned.
   * @param token Output token (either GSM static aToken or aToken's underlying).
   * @param gsm Whitelisted GSM used for the swap.
   * @param exactAmountIn Amount of sGHO shares pulled from the caller.
   * @param minOutputAmount Minimum acceptable output-token amount.
   * @param recipient Address that receives the resulting token.
   * @return outputAmount Amount of output tokens sent to `recipient`.
   */
  function _sGhoToToken(
    address token,
    address gsm,
    uint256 exactAmountIn,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256) {
    require(allowedGsm[token][gsm], GsmNotConfigured());

    uint256 ghoAmount = _redeemGho(exactAmountIn, 0);

    (uint256 amountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(ghoAmount);
    (, uint256 outputAmount) = _buyTokenWithGho({
      gsm: gsm,
      token: token,
      exactAmountIn: ghoUsed,
      amountToBuy: amountToBuy,
      outputReceiver: recipient,
      minOutputAmount: minOutputAmount
    });

    return outputAmount;
  }

  /**
   * @dev Redeems sGHO directly into GHO and forwards output to the recipient.
   * @param exactAmountIn Amount of sGHO shares pulled from the caller.
   * @param minOutputAmount Minimum acceptable GHO output.
   * @param recipient Address that receives the resulting GHO.
   * @return ghoAmount Amount of GHO sent to `recipient`.
   */
  function _sGhoToGho(
    uint256 exactAmountIn,
    uint256 minOutputAmount,
    address recipient
  ) internal returns (uint256) {
    uint256 ghoAmount = _redeemGho(exactAmountIn, minOutputAmount);

    IERC20(GHO).safeTransfer(recipient, ghoAmount);

    return ghoAmount;
  }

  /**
   * @dev Deposits GHO held by the router into sGHO.
   * @param exactAmountIn Amount of GHO to deposit.
   * @param receiver Address receiving the minted sGHO shares.
   * @param minSghoAmount Minimum acceptable sGHO share output.
   * @return sghoAmount Amount of sGHO shares minted.
   */
  function _depositGho(
    uint256 exactAmountIn,
    address receiver,
    uint256 minSghoAmount
  ) internal returns (uint256) {
    IERC20(GHO).forceApprove(sGHO, exactAmountIn);
    uint256 sghoAmount = IERC4626(sGHO).deposit({assets: exactAmountIn, receiver: receiver});
    require(sghoAmount >= minSghoAmount, SlippageExceeded());
    return sghoAmount;
  }

  /**
   * @dev Pulls sGHO from the caller and redeems it for GHO into the router.
   * @param exactAmountIn Amount of sGHO shares to redeem.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return ghoAmount Amount of GHO redeemed.
   */
  function _redeemGho(uint256 exactAmountIn, uint256 minGhoAmount) internal returns (uint256) {
    uint256 ghoAmount = IERC4626(sGHO).redeem({
      shares: exactAmountIn,
      receiver: address(this),
      owner: msg.sender
    });
    require(ghoAmount >= minGhoAmount, SlippageExceeded());
    return ghoAmount;
  }

  /**
   * @dev Transfers token in from caller to perform swap for GHO.
   * @param token Input token address provided by the caller.
   * @param gsm Whitelisted GSM used for the swap.
   * @param exactAmountIn Amount of input tokens pulled from the caller.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return ghoAmount Amount of GHO received from GSM.
   */
  function _performSwapToGho(
    address token,
    address gsm,
    uint256 exactAmountIn,
    uint256 minGhoAmount
  ) internal returns (uint256) {
    require(allowedGsm[token][gsm], GsmNotConfigured());

    IERC20(token).safeTransferFrom(msg.sender, address(this), exactAmountIn);

    (, uint256 ghoAmount) = _sellTokenForGho({
      gsm: gsm,
      token: token,
      exactAmountIn: exactAmountIn,
      minGhoAmount: minGhoAmount
    });

    return ghoAmount;
  }

  /**
   * @dev Sells input tokens through GSM for GHO, converting underlying to static aToken when needed.
   * @param gsm Whitelisted GSM used for the sell path.
   * @param token Input token address provided by the caller.
   * @param exactAmountIn Amount of input tokens pulled from the caller.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return inputAmountUsed Amount of input tokens used in the swap.
   * @return ghoAmount Amount of GHO received from GSM.
   */
  function _sellTokenForGho(
    address gsm,
    address token,
    uint256 exactAmountIn,
    uint256 minGhoAmount
  ) internal returns (uint256, uint256) {
    address underlying = IGsm(gsm).UNDERLYING_ASSET();
    uint256 amount = exactAmountIn;
    if (token != underlying) {
      _validateTokens(token, underlying);
      IERC20(token).forceApprove(underlying, exactAmountIn);
      amount = IERC4626(underlying).deposit(exactAmountIn, address(this));
    }

    IERC20(underlying).forceApprove(gsm, amount);
    (uint256 assetSold, uint256 ghoAmount) = IGsm(gsm).sellAsset({
      maxAmount: amount,
      receiver: address(this)
    });

    require(ghoAmount >= minGhoAmount, SlippageExceeded());
    return (token == underlying ? assetSold : exactAmountIn, ghoAmount);
  }

  /**
   * @dev Buys GSM static aTokens with GHO, then returns either static or underlying output based on `token`.
   * @dev An almost negligible amount of dust can be left unsued, would cost more in gas than amount returned.
   * @param gsm Whitelisted GSM used for the buy path.
   * @param token Output token requested by the caller (underlying token or static aToken).
   * @param exactAmountIn GHO budget used to acquire static aTokens.
   * @param amountToBuy Amount of token to acquire from the GSM.
   * @param outputReceiver Address receiving output tokens.
   * @param minOutputAmount Minimum acceptable output amount.
   * @return ghoSold Amount of GHO consumed by GSM.
   * @return outputAmount Amount of output tokens sent to `outputReceiver`.
   */
  function _buyTokenWithGho(
    address gsm,
    address token,
    uint256 exactAmountIn,
    uint256 amountToBuy,
    address outputReceiver,
    uint256 minOutputAmount
  ) internal returns (uint256, uint256) {
    address underlying = IGsm(gsm).UNDERLYING_ASSET();
    _validateTokens(token, underlying);

    IERC20(GHO).forceApprove(gsm, exactAmountIn);
    (uint256 underlyingAmount, uint256 ghoSold) = IGsm(gsm).buyAsset({
      minAmount: amountToBuy,
      receiver: address(this)
    });

    uint256 outputAmount = underlyingAmount;
    if (token == underlying) {
      IERC20(underlying).safeTransfer(outputReceiver, underlyingAmount);
    } else {
      outputAmount = IERC4626(underlying).redeem({
        shares: underlyingAmount,
        receiver: outputReceiver,
        owner: address(this)
      });
    }

    require(outputAmount >= minOutputAmount, SlippageExceeded());
    return (ghoSold, outputAmount);
  }

  /**
   * @dev Previews output amount for a GHO->GSM route without state changes.
   * @param token Output token requested (underlying token or static aToken).
   * @param gsm Address of the GSM used to perform the swap.
   * @param ghoAmount GHO amount to simulate.
   * @return outputAmount Estimated output-token amount.
   */
  function _previewGhoToToken(
    address token,
    address gsm,
    uint256 ghoAmount
  ) internal view returns (uint256) {
    require(allowedGsm[token][gsm], GsmNotConfigured());

    address underlying = IGsm(gsm).UNDERLYING_ASSET();

    _validateTokens(token, underlying);
    (uint256 assetAmount, , , ) = IGsm(gsm).getAssetAmountForBuyAsset(ghoAmount);
    uint256 outputAmount = token == underlying
      ? assetAmount
      : IERC4626(underlying).previewRedeem(assetAmount);
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

  /**
   * @dev Validates GSM tokens.
   * @param token Address of input token
   * @param underlying Address of GSM underlying token
   */
  function _validateTokens(address token, address underlying) internal view {
    require(token == underlying || token == IERC4626(underlying).asset(), InvalidToken());
  }
}
