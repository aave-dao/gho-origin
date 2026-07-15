// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from '@openzeppelin/contracts/interfaces/IERC4626.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import {IGsm} from 'src/contracts/facilitators/gsm/interfaces/IGsm.sol';
import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';

/**
 * @title GhoRouter
 * @author TokenLogic
 * @notice Router for token swaps through whitelisted GSMs and direct GHO/sGHO conversion paths
 * @dev This contract never stores user funds and uses exact approvals only
 */
contract GhoRouter is Ownable, ReentrancyGuard, IGhoRouter {
  using SafeERC20 for IERC20;

  /// @inheritdoc IGhoRouter
  address public immutable GHO;

  /// @inheritdoc IGhoRouter
  address public immutable sGHO;

  /// @inheritdoc IGhoRouter
  mapping(address gsm => bool allowed) public allowedGsm;

  /// @inheritdoc IGhoRouter
  mapping(address token => address stataToken) public tokenToStata;

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
  ) external nonReentrant returns (uint256) {
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
  function allowGsm(address gsm) external onlyOwner {
    require(gsm != address(0), ZeroAddress());
    require(allowedGsm[gsm] == false, GsmAlreadySet());

    _validateGsm(gsm);

    allowedGsm[gsm] = true;
    emit GsmAdded(gsm);
  }

  /// @inheritdoc IGhoRouter
  function revokeGsm(address gsm) external onlyOwner {
    require(allowedGsm[gsm], GsmNotSet());

    delete allowedGsm[gsm];

    emit GsmRemoved(gsm);
  }

  /// @inheritdoc IGhoRouter
  function setTokenToStata(address token, address stata) external onlyOwner {
    require(token != address(0) && stata != address(0), ZeroAddress());
    require(tokenToStata[token] == address(0), TokenToStataAlreadySet());
    require(IERC4626(stata).asset() == token, InvalidToken());

    tokenToStata[token] = stata;
    emit TokenToStataSet(token, stata);
  }

  /// @inheritdoc IGhoRouter
  function removeTokenToStata(address token) external onlyOwner {
    address stata = tokenToStata[token];
    require(stata != address(0), TokenToStataNotSet());

    delete tokenToStata[token];

    emit TokenToStataRemoved(token, stata);
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
    (address gsmAsset, bool isStata) = _validateGsmInput(token, gsm);

    uint256 sharesAmount = isStata ? IERC4626(gsmAsset).previewDeposit(amount) : amount;
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
   * @param exactAmountIn Maximum allowed amount of GHO to be pulled from the caller.
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
    (address gsmAsset, bool isStata) = _validateGsmInput(token, gsm);

    (uint256 amountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(exactAmountIn);
    require(ghoUsed <= exactAmountIn, RequiredGhoGreaterThanExpectedAmount());

    IERC20(GHO).safeTransferFrom(msg.sender, address(this), ghoUsed);

    uint256 outputAmount = _buyTokenWithGho({
      gsm: gsm,
      gsmAsset: gsmAsset,
      isStata: isStata,
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
    (address gsmAsset, bool isStata) = _validateGsmInput(token, gsm);

    uint256 ghoAmount = _redeemGho(exactAmountIn, 0);

    (uint256 amountToBuy, uint256 ghoUsed, , ) = IGsm(gsm).getAssetAmountForBuyAsset(ghoAmount);
    require(ghoUsed <= ghoAmount, RequiredGhoGreaterThanExpectedAmount());

    uint256 outputAmount = _buyTokenWithGho({
      gsm: gsm,
      gsmAsset: gsmAsset,
      isStata: isStata,
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
    (address gsmAsset, bool isStata) = _validateGsmInput(token, gsm);

    IERC20(token).safeTransferFrom(msg.sender, address(this), exactAmountIn);

    uint256 ghoAmount = _sellTokenForGho({
      gsm: gsm,
      token: token,
      gsmAsset: gsmAsset,
      isStata: isStata,
      exactAmountIn: exactAmountIn,
      minGhoAmount: minGhoAmount
    });

    return ghoAmount;
  }

  /**
   * @dev Sells input tokens through GSM for GHO, wrapping the underlying into the static aToken when needed.
   * @param gsm Whitelisted GSM used for the sell path.
   * @param token Input token address provided by the caller.
   * @param gsmAsset GSM underlying asset the sale is settled in.
   * @param isStata Whether `token` must be wrapped into `gsmAsset` before selling.
   * @param exactAmountIn Amount of input tokens pulled from the caller.
   * @param minGhoAmount Minimum acceptable GHO output.
   * @return ghoAmount Amount of GHO received from GSM.
   */
  function _sellTokenForGho(
    address gsm,
    address token,
    address gsmAsset,
    bool isStata,
    uint256 exactAmountIn,
    uint256 minGhoAmount
  ) internal returns (uint256) {
    uint256 amount = exactAmountIn;
    if (isStata) {
      IERC20(token).forceApprove(gsmAsset, exactAmountIn);
      amount = IERC4626(gsmAsset).deposit({assets: exactAmountIn, receiver: address(this)});
    }

    IERC20(gsmAsset).forceApprove(gsm, amount);
    (, uint256 ghoAmount) = IGsm(gsm).sellAsset({maxAmount: amount, receiver: address(this)});
    IERC20(gsmAsset).forceApprove(gsm, 0);

    require(ghoAmount >= minGhoAmount, SlippageExceeded());
    return ghoAmount;
  }

  /**
   * @dev Buys GSM underlying token with GHO, then returns either the static aToken or its underlying.
   * @dev An almost negligible amount of dust can be left unsued, would cost more in gas than amount returned.
   * @param gsm Whitelisted GSM used for the buy path.
   * @param gsmAsset GSM underlying asset acquired from the GSM.
   * @param isStata Whether the acquired `gsmAsset` must be unwrapped into its underlying before delivery.
   * @param exactAmountIn GHO budget used to acquire static aTokens.
   * @param amountToBuy Amount of token to acquire from the GSM.
   * @param outputReceiver Address receiving output tokens.
   * @param minOutputAmount Minimum acceptable output amount.
   * @return outputAmount Amount of output tokens sent to `outputReceiver`.
   */
  function _buyTokenWithGho(
    address gsm,
    address gsmAsset,
    bool isStata,
    uint256 exactAmountIn,
    uint256 amountToBuy,
    address outputReceiver,
    uint256 minOutputAmount
  ) internal returns (uint256) {
    IERC20(GHO).forceApprove(gsm, exactAmountIn);
    (uint256 underlyingAmount, ) = IGsm(gsm).buyAsset({
      minAmount: amountToBuy,
      receiver: address(this)
    });

    uint256 outputAmount = underlyingAmount;
    if (isStata) {
      outputAmount = IERC4626(gsmAsset).redeem({
        shares: underlyingAmount,
        receiver: outputReceiver,
        owner: address(this)
      });
    } else {
      IERC20(gsmAsset).safeTransfer(outputReceiver, underlyingAmount);
    }

    require(outputAmount >= minOutputAmount, SlippageExceeded());
    return outputAmount;
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
    (address gsmAsset, bool isStata) = _validateGsmInput(token, gsm);

    (uint256 assetAmount, , , ) = IGsm(gsm).getAssetAmountForBuyAsset(ghoAmount);
    uint256 outputAmount = isStata ? IERC4626(gsmAsset).previewRedeem(assetAmount) : assetAmount;
    return outputAmount;
  }

  /**
   * @dev Validates that a GSM is structurally compatible with the router before it is whitelisted.
   * @param gsm GSM address to validate.
   */
  function _validateGsm(address gsm) internal view {
    require(gsm.code.length != 0, InvalidGsm());

    require(IGsm(gsm).GHO_TOKEN() == GHO, InvalidGsm());
    require(IGsm(gsm).UNDERLYING_ASSET() != address(0), InvalidGsm());
  }

  /**
   * @dev Validates a swap's `token`/`gsm` pairing and resolves how to route it.
   *      The GSM must be whitelisted, and `token` must be either the GSM asset itself
   *      or an underlying registered in `tokenToStata` whose static aToken is the GSM asset.
   *      Validation never calls `asset()` on the GSM asset, so a plain (non-stata) GSM
   *      paired with an incompatible token reverts cleanly with `InvalidToken`.
   * @param token Input or output token supplied by the caller.
   * @param gsm GSM the caller selected to route through.
   * @return gsmAsset The GSM asset (`UNDERLYING_ASSET`), i.e. the static aToken or underlying the GSM settles in.
   * @return isStata True when `token` is the underlying and must be wrapped into/unwrapped from `gsmAsset`.
   */
  function _validateGsmInput(address token, address gsm) internal view returns (address, bool) {
    require(allowedGsm[gsm], GsmNotConfigured());

    address gsmAsset = IGsm(gsm).UNDERLYING_ASSET();
    bool isStata;
    if (token != gsmAsset) {
      require(tokenToStata[token] == gsmAsset, InvalidToken());
      isStata = true;
    }

    return (gsmAsset, isStata);
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
}
