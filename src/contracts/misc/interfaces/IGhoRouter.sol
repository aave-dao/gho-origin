// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IGhoRouter
 * @notice Interface for GhoRouter contract
 */
interface IGhoRouter {
  /// @dev Deadline for performing swap has expired
  error DeadlineExpired();

  /// @dev GSM not configured for the given token
  error GsmNotConfigured();

  /// @dev Amount must be greater than zero
  error InvalidAmount();

  /// @dev GSM is not a structurally valid GSM
  error InvalidGsm();

  /// @dev Invalid path for token swap
  /// @param tokenIn Address of the token to swap from
  /// @param tokenOut Address of the token to swap to
  error InvalidTokenPair(address tokenIn, address tokenOut);

  /// @dev Unsupported token provided
  error InvalidToken();

  /// @dev Swap amount is lower than minimum expected amount
  error SlippageExceeded();

  /// @dev The GSM is already allowed
  error GsmAlreadySet();

  /// @dev The GSM is not allowed
  error GsmNotSet();

  /// @dev The required GHO to swap for token is greater than expected amount
  error RequiredGhoGreaterThanExpectedAmount();

  /// @dev The token already has a stata mapping set
  error TokenToStataAlreadySet();

  /// @dev The token has no stata mapping set
  error TokenToStataNotSet();

  /// @dev Zero address is not allowed
  error ZeroAddress();

  /**
   * @notice Emitted when a swap is completed
   * @param caller The address of the initiator of the swap
   * @param tokenIn The address of the token to swap from
   * @param tokenOut The address of the token to swap to
   * @param exactAmountIn The amount of tokenIn swapped
   * @param amountOut The amount of tokenOut received
   * @param recipient The address of the recipient of tokenOut
   */
  event Swap(
    address indexed caller,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 exactAmountIn,
    uint256 amountOut,
    address recipient
  );

  /**
   * @notice Emitted when a GSM is allowed by the router.
   * @param gsm GSM address
   */
  event GsmAdded(address gsm);

  /**
   * @notice Emitted when a GSM is disallowed by the router.
   * @param gsm GSM address
   */
  event GsmRemoved(address gsm);

  /**
   * @notice Emitted when an underlying token is mapped to its static aToken (stata).
   * @param token Underlying token address
   * @param stata Static aToken (ERC4626) that wraps `token`
   */
  event TokenToStataSet(address indexed token, address indexed stata);

  /**
   * @notice Emitted when an underlying token's stata mapping is removed.
   * @param token Underlying token address
   * @param stata Static aToken (ERC4626) that was mapped to `token`
   */
  event TokenToStataRemoved(address indexed token, address indexed stata);

  /**
   * @notice Swap tokenIn for tokenOut and send output to recipient
   * @dev In GHO <-> sGHO paths, GSM is ignored
   * @dev Reverts while the router is paused
   * @param tokenIn Input token to swap from
   * @param tokenOut Output token address to swap to
   * @param gsm Address of the GSM used to perform swap
   * @param exactAmountIn Amount of tokens to swap
   * @param minAmountOut Minimum amount of output token to receive (slippage protection)
   * @param recipient Address that receives output token
   * @param deadline Maximum timestamp at which the swap can be executed
   * @return Amount of output token received
   */
  function swap(
    address tokenIn,
    address tokenOut,
    address gsm,
    uint256 exactAmountIn,
    uint256 minAmountOut,
    address recipient,
    uint256 deadline
  ) external returns (uint256);

  /**
   * @notice Allows a GSM to be used for swaps
   * @param gsm GSM address to allow
   */
  function allowGsm(address gsm) external;

  /**
   * @notice Revokes a GSM from being allowed for swaps
   * @param gsm GSM address to remove
   */
  function revokeGsm(address gsm) external;

  /**
   * @notice Maps an underlying token to its static aToken (stata) so the router can route
   *         swaps that wrap/unwrap through a stata GSM.
   * @dev Reverts if `token` already has a mapping (remove it first), or unless `stata` is an
   *      ERC4626 whose `asset()` is `token`.
   * @param token Underlying token address
   * @param stata Static aToken (ERC4626) that wraps `token`
   */
  function setTokenToStata(address token, address stata) external;

  /**
   * @notice Removes the stata mapping for an underlying token.
   * @param token Underlying token address whose mapping to remove
   */
  function removeTokenToStata(address token) external;

  /**
   * @notice Pauses the router, blocking `swap` and `previewSwap`
   * @dev Only callable by the owner. Reverts if the router is already paused
   */
  function pause() external;

  /**
   * @notice Unpauses the router, re-enabling `swap` and `previewSwap`
   * @dev Only callable by the owner. Reverts if the router is not paused
   */
  function unpause() external;

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
   * @notice Returns whether a GSM is allowed to be used for swaps.
   * @param gsm Address of the GSM to check
   * @return True/false on whether GSM is allowed
   */
  function allowedGsm(address gsm) external view returns (bool);

  /**
   * @notice Returns address of corresponding stataToken for an underlying token.
   * @param token Address of the token to check
   * @return Address of corresponding stataToken if set
   */
  function tokenToStata(address token) external view returns (address);

  /**
   * @notice Preview the amount of tokens received for a given input amount
   * @dev Reverts while the router is paused
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param gsm Address of the GSM used to perform swap
   * @param exactAmountIn Amount of input token to sell
   * @return Expected amount of tokenOut from swap
   */
  function previewSwap(
    address tokenIn,
    address tokenOut,
    address gsm,
    uint256 exactAmountIn
  ) external view returns (uint256);
}
