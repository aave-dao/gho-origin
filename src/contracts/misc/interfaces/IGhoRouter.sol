// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IGhoRouter
 * @notice Interface for GhoRouter contract
 */
interface IGhoRouter {
  /// @dev GSM is not whitelisted for swaps
  error GsmNotConfigured();

  /// @dev Amount must be greater than zero
  error InvalidAmount();

  /// @dev GSM not configured for the given token
  error InvalidGsm();

  /// @dev Invalid path for token swap
  error InvalidPath();

  /// @dev Unsupported token provided
  error InvalidToken();

  /// @dev Swap amount is lower than minimum expected amount
  error SlippageExceeded();

  /// @dev The token to GSM mapping is not set
  error TokenToGsmNotSet();

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
   * @notice Emitted when a token to GSM mapping is added
   * @param token Address of the token that can swap via the specified GSM
   * @param gsm GSM address
   */
  event TokenToGsmAdded(address indexed token, address gsm);

  /**
   * @notice Emitted when a token to GSM mapping is removed
   * @param token Address of the token that can swap via the specified GSM
   * @param gsm GSM address
   */
  event TokenToGsmRemoved(address indexed token, address gsm);

  /**
   * @notice Swap sGHO back through a GSM path, choose output token, and send output to recipient
   * @param tokenIn Input token to swap from
   * @param tokenOut Output token address to swap to
   * @param amountIn Amount of tokens to swap
   * @param minAmountOut Minimum amount of output token to receive (slippage protection)
   * @param recipient Address that receives output token
   * @param deadline Maximum timestamp swap can be executed
   * @return Amount of output token received
   */
  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address recipient,
    uint256 deadline
  ) external returns (uint256);

  /**
   * @notice Sets a token to corresponding GSM mapping
   * @param token Address of the token that uses the GSM
   * @param gsm GSM address to update
   */
  function setTokenToGsm(address token, address gsm) external;

  /**
   * @notice Removes a token to GSM mapping
   * @param token Address of the token to remove mapping for
   */
  function removeTokenToGsm(address token) external;

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
   * @notice Returns the corresponding GSM a token should use for swapping
   * @param token Address of the token to check
   * @return Address of the corresponding GSM
   */
  function gsms(address token) external view returns (address);

  /**
   * @notice Preview the amount of tokens received for a given input amount
   * @dev This is an estimation and actual results may vary slightly
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param amountIn Amount of input token to sell
   * @return Expected amount of tokenOut from swap
   */
  function previewSwap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256);

}
