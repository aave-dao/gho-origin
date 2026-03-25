// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IGhoRouter
 * @notice Interface for GhoRouter contract
 */
interface IGhoRouter {
  /// @dev GSM is not whitelisted for swaps
  error GsmNotAllowed();

  /// @dev Amount must be greater than zero
  error InvalidAmount();

  /// @dev GSM not configured for the given token
  error InvalidGsm();

  /// @dev Unsupported token provided
  error InvalidToken();

  /// @dev Swap amount is lower than minimum expected amount
  error SlippageExceeded();

  /// @dev Zero address is not allowed
  error ZeroAddress();

  /**
   * @notice Emitted when a swap to GHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired GHO
   * @param ghoAmount The amount of GHO tokens deposited
   * @param sghoAmount The amount of sGHO received
   */
  event DepositForSGho(
    address indexed user,
    address indexed recipient,
    uint256 ghoAmount,
    uint256 sghoAmount
  );

  /**
   * @notice Emitted when a swap from sGHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired token
   * @param sghoAmount The amount of sGHO shares burned
   * @param ghoAmount The amount of GHO tokens received
   */
  event RedeemFromSGho(
    address indexed user,
    address indexed recipient,
    uint256 sghoAmount,
    uint256 ghoAmount
  );

  /**
   * @notice Emitted when a swap to GHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired GHO
   * @param token The address of the input token
   * @param inputAmount The amount of input tokens sold
   * @param ghoAmount The amount of GHO received
   */
  event SwapToGho(
    address indexed user,
    address indexed recipient,
    address indexed token,
    uint256 inputAmount,
    uint256 ghoAmount
  );

  /**
   * @notice Emitted when a swap from GHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired token
   * @param token The address of the output token
   * @param ghoAmount The amount of GHO sold
   * @param outputAmount The amount of output tokens received
   */
  event SwapFromGho(
    address indexed user,
    address indexed recipient,
    address indexed token,
    uint256 ghoAmount,
    uint256 outputAmount
  );

  /**
   * @notice Emitted when a swap to sGHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired token
   * @param token The address of the input token
   * @param inputAmount The amount of input tokens sold
   * @param sghoAmount The amount of sGHO shares minted
   */
  event SwapToSGho(
    address indexed user,
    address indexed recipient,
    address indexed token,
    uint256 inputAmount,
    uint256 sghoAmount
  );

  /**
   * @notice Emitted when a swap from sGHO is completed
   * @param user The address of the user who initiated the swap
   * @param recipient The address of the recipient of the acquired token
   * @param token The address of the output token
   * @param sghoAmount The amount of sGHO shares burned
   * @param outputAmount The amount of output tokens received
   */
  event SwapFromSGho(
    address indexed user,
    address indexed recipient,
    address indexed token,
    uint256 sghoAmount,
    uint256 outputAmount
  );

  /**
   * @notice Emitted when a GSM whitelist status is updated
   * @param gsm GSM address whose allowlist status changed
   * @param allowed Whether the GSM is allowed for swap paths
   */
  event GsmAllowedUpdated(address indexed gsm, bool allowed);

  /**
   * @notice Swap token to GHO through a GSM path
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to swap
   * @param minGHOAmount Minimum amount of GHO to receive (slippage protection)
   * @return Amount of GHO received
   */
  function swapToGho(
    address gsm,
    address token,
    uint256 amount,
    uint256 minGHOAmount
  ) external returns (uint256);

  /**
   * @notice Swap token to GHO through a GSM path and send output to recipient
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to swap
   * @param minGHOAmount Minimum amount of GHO to receive (slippage protection)
   * @param recipient Address that receives GHO
   * @return Amount of GHO received
   */
  function swapToGho(
    address gsm,
    address token,
    uint256 amount,
    uint256 minGHOAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Swap GHO through a GSM path and choose output token (underlying token or static aToken)
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param ghoAmount Amount of GHO to swap
   * @param minOutputAmount Minimum amount of output token to receive (slippage protection)
   * @return Amount of output token received
   */
  function swapFromGho(
    address gsm,
    address token,
    uint256 ghoAmount,
    uint256 minOutputAmount
  ) external returns (uint256);

  /**
   * @notice Swap GHO through a GSM path, choose output token, and send output to recipient
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param ghoAmount Amount of GHO to swap
   * @param minOutputAmount Minimum amount of output token to receive (slippage protection)
   * @param recipient Address that receives output token
   * @return Amount of output token received
   */
  function swapFromGho(
    address gsm,
    address token,
    uint256 ghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Swap token to sGHO through a GSM path
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to swap
   * @param minSGHOAmount Minimum amount of sGHO shares to receive (slippage protection)
   * @return Amount of sGHO shares received
   */
  function swapToSGho(
    address gsm,
    address token,
    uint256 amount,
    uint256 minSGHOAmount
  ) external returns (uint256);

  /**
   * @notice Swap token to sGHO through a GSM path and send output to recipient
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to swap
   * @param minSGHOAmount Minimum amount of sGHO shares to receive (slippage protection)
   * @param recipient Address that receives sGHO shares
   * @return Amount of sGHO shares received
   */
  function swapToSGho(
    address gsm,
    address token,
    uint256 amount,
    uint256 minSGHOAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Swap GHO directly to sGHO
   * @param ghoAmount Amount of GHO to deposit into sGHO
   * @param minSGHOAmount Minimum amount of sGHO shares to receive (slippage protection)
   * @return Amount of sGHO shares received
   */
  function depositForSGho(uint256 ghoAmount, uint256 minSGHOAmount) external returns (uint256);

  /**
   * @notice Swap GHO directly to sGHO and send output to recipient
   * @param ghoAmount Amount of GHO to deposit into sGHO
   * @param minSGHOAmount Minimum amount of sGHO shares to receive (slippage protection)
   * @param recipient Address that receives sGHO shares
   * @return Amount of sGHO shares received
   */
  function depositForSGho(
    uint256 ghoAmount,
    uint256 minSGHOAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Swap sGHO back through a GSM path and choose output token (underlying token or static aToken)
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param sghoAmount Amount of sGHO shares to redeem
   * @param minOutputAmount Minimum amount of output token to receive (slippage protection)
   * @return Amount of output token received
   */
  function swapFromSGho(
    address gsm,
    address token,
    uint256 sghoAmount,
    uint256 minOutputAmount
  ) external returns (uint256);

  /**
   * @notice Swap sGHO back through a GSM path, choose output token, and send output to recipient
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param sghoAmount Amount of sGHO shares to redeem
   * @param minOutputAmount Minimum amount of output token to receive (slippage protection)
   * @param recipient Address that receives output token
   * @return Amount of output token received
   */
  function swapFromSGho(
    address gsm,
    address token,
    uint256 sghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Redeem sGHO directly to GHO
   * @param sghoAmount Amount of sGHO shares to redeem
   * @param minOutputAmount Minimum amount of GHO to receive (slippage protection)
   * @return Amount of GHO received
   */
  function redeemSGho(uint256 sghoAmount, uint256 minOutputAmount) external returns (uint256);

  /**
   * @notice Redeem sGHO directly to GHO and send output to recipient
   * @param sghoAmount Amount of sGHO shares to redeem
   * @param minOutputAmount Minimum amount of GHO to receive (slippage protection)
   * @param recipient Address that receives GHO
   * @return Amount of GHO received
   */
  function redeemSGho(
    uint256 sghoAmount,
    uint256 minOutputAmount,
    address recipient
  ) external returns (uint256);

  /**
   * @notice Updates GSM whitelist status
   * @param gsm GSM address to update
   * @param allowed Whether this GSM should be allowed for swap paths
   */
  function setGsmAllowed(address gsm, bool allowed) external;

  /**
   * @notice Rescue ERC20 token from the contract
   * @param token Address of the token to rescue
   * @param to Address to send the tokens to
   * @param amount Amount of tokens to rescue
   */
  function rescueToken(address token, address to, uint256 amount) external;

  /**
   * @notice Returns address of the GHO token on the deployed network
   * @return Address of the token
   */
  function GHO() external view returns (address);

  /**
   * @notice Returns address of the sGHO vault on the deployed network
   * @return Address of the vault token
   */
  function sGHO() external view returns (address);

  /**
   * @notice Returns whether a GSM address is whitelisted for swap paths
   * @param gsm GSM address to check
   * @return True if the GSM is allowed for swap paths
   */
  function isGsmAllowed(address gsm) external view returns (bool);

  /**
   * @notice Preview the amount of GHO received for a given input amount
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to sell
   * @return ghoAmount Expected amount of GHO to receive
   * @return fee Fee amount charged by the GSM
   */
  function previewSwapToGho(
    address gsm,
    address token,
    uint256 amount
  ) external view returns (uint256 ghoAmount, uint256 fee);

  /**
   * @notice Preview the amount of chosen output token received for a given GHO amount
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param ghoAmount Amount of GHO to sell
   * @return assetAmount Expected amount of output token to receive
   * @return fee Fee amount charged by the GSM
   */
  function previewSwapFromGho(
    address gsm,
    address token,
    uint256 ghoAmount
  ) external view returns (uint256 assetAmount, uint256 fee);

  /**
   * @notice Preview the amount of sGHO received for a given input amount through a GSM path
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param gsm GSM address used for the swap path
   * @param token Input token address (GSM underlying token or static aToken)
   * @param amount Amount of input token to sell
   * @return sghoAmount Expected amount of sGHO shares to receive
   * @return fee Fee amount charged by the GSM path
   */
  function previewSwapToSGho(
    address gsm,
    address token,
    uint256 amount
  ) external view returns (uint256 sghoAmount, uint256 fee);

  /**
   * @notice Preview the amount of sGHO received for a direct GHO deposit
   * @param ghoAmount Amount of GHO to deposit
   * @return sghoAmount Expected amount of sGHO shares to receive
   */
  function previewDepositForSGho(uint256 ghoAmount) external view returns (uint256 sghoAmount);

  /**
   * @notice Preview the amount of chosen output token received for a given sGHO amount through a GSM path
   * @dev This is an estimation and actual results may vary slightly due to interest accrual
   * @param gsm GSM address used for the swap path
   * @param token Output token address (GSM underlying token or static aToken)
   * @param sghoAmount Amount of sGHO shares to redeem
   * @return outputAmount Expected amount of output token to receive
   * @return fee Fee amount charged by the GSM path
   */
  function previewSwapFromSGho(
    address gsm,
    address token,
    uint256 sghoAmount
  ) external view returns (uint256 outputAmount, uint256 fee);

  /**
   * @notice Preview the amount of GHO received for direct sGHO redemption
   * @param sghoAmount Amount of sGHO shares to redeem
   * @return ghoAmount Expected amount of GHO to receive
   */
  function previewRedeemSGho(uint256 sghoAmount) external view returns (uint256 ghoAmount);
}
