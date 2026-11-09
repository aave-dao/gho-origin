// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IGhoSwapFacility
/// @notice Swaps GHO 1:1 against the asset of an ERC4626 vault, holding the vault shares.
/// @dev Liquidity is split into pools, all stored in one mapping keyed by address. The public pool is
/// the `address(0)` key and is open to every caller the AccessManager allows to call `swap`. Any other
/// key is a private pool that only that address can swap against. Yield earned by the shares is sent to the treasury as shares ("skimmed").
interface IGhoSwapFacility {
  /// @notice Liquidity and GHO accounting of one pool.
  /// @param shares Vault shares held for the pool.
  /// @param used GHO drawn from the reserve for the pool (gross of fees).
  /// @param cap Maximum value of `used`. Swaps that would push `used` above it revert.
  struct Pool {
    uint128 shares;
    uint128 used;
    uint128 cap;
  }

  /// @notice Fees charged to an account, in basis points of the amount sent in.
  /// @param sharesInBps Fee when the account swaps vault shares for GHO.
  /// @param ghoInBps Fee when the account swaps GHO for vault shares.
  /// @param isSet Whether the tier is configured. Accounts without a tier pay the market tier.
  struct FeeTier {
    uint16 sharesInBps;
    uint16 ghoInBps;
    bool isSet;
  }

  error ZeroAddress();
  error ZeroAmount();
  error InvalidFee(uint256 feeBps);
  error InvalidToken(address token);
  error UnsupportedDecimals(uint8 decimals);
  error ReserveTokenMismatch(address reserveToken);
  error PoolAccessDenied(address pool, address caller);
  error PoolCapExceeded(address pool, uint256 used, uint256 cap);
  error InsufficientLiquidity(address pool);
  error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
  error NoDeficit(address pool);
  error NotPrivatePool();

  event Swap(
    address indexed pool,
    address indexed sender,
    address indexed receiver,
    address tokenIn,
    uint256 amountIn,
    uint256 amountOut,
    uint256 fee
  );
  event YieldSkimmed(address indexed pool, uint256 shares);
  event DeficitRepaid(address indexed pool, address indexed payer, uint256 amount);
  event PoolSeized(address indexed pool, address indexed to, uint256 shares, uint256 debt);
  event PoolMadePublic(address indexed pool, uint256 shares, uint256 used, uint256 cap);
  event PoolCapSet(address indexed pool, uint256 cap);
  event FeeTierSet(address indexed account, uint16 sharesInBps, uint16 ghoInBps);
  event FeeTierCleared(address indexed account);
  event TreasurySet(address indexed treasury);
  event FeesClaimed(address indexed treasury, uint256 amount);

  /// @notice Swaps `amountIn` of `tokenIn` (GHO or vault shares) for the other token.
  /// @dev Skims the pool's yield first, so the pool never holds more value than the GHO it owes.
  /// @param pool `address(0)` for the public pool, or the caller's address for its private pool.
  /// @param tokenIn GHO or the vault share token.
  /// @param amountIn Exact amount of `tokenIn` pulled from the caller, fee included.
  /// @param minAmountOut Minimum amount of the other token to receive.
  /// @param receiver Recipient of the output token.
  /// @return amountOut Amount of the other token sent to `receiver`.
  function swap(
    address pool,
    address tokenIn,
    uint256 amountIn,
    uint256 minAmountOut,
    address receiver
  ) external returns (uint256 amountOut);

  /// @notice Sends the pool's surplus shares (value above `used`) to the treasury.
  /// @return shares Shares sent.
  function skim(address pool) external returns (uint256 shares);

  /// @notice Pays GHO back to the reserve on behalf of a pool whose shares are worth less than `used`.
  /// @dev Capped at the current deficit.
  /// @return repaid GHO pulled from the caller.
  function repay(address pool, uint256 amount) external returns (uint256 repaid);

  /// @notice Sends accrued GHO swap fees to the treasury.
  function claimFees() external returns (uint256 amount);

  /// @notice Moves every share of `pool` to `to` and sets its cap to zero. The pool keeps its debt.
  function seize(address pool, address to) external returns (uint256 shares);

  /// @notice Merges a private pool into the public pool: shares, debt and cap move over, and the
  /// private pool is deleted. Both pools are skimmed first.
  function makePublic(address pool) external;

  function setPoolCap(address pool, uint128 cap) external;

  /// @notice Sets the fee tier of `account`. `address(0)` is the market tier, paid by accounts without one.
  function setFeeTier(address account, uint16 sharesInBps, uint16 ghoInBps) external;

  /// @notice Removes the fee tier of `account`, which then pays the market tier.
  function clearFeeTier(address account) external;

  function setTreasury(address treasury) external;

  /// @notice Amount out and fee for `account` swapping `amountIn` of `tokenIn`, ignoring pool liquidity and caps.
  function quote(
    address account,
    address tokenIn,
    uint256 amountIn
  ) external view returns (uint256 amountOut, uint256 fee);

  /// @notice Fee tier applied to `account`: its own if set, otherwise the market tier.
  function getFeeTier(address account) external view returns (FeeTier memory);

  function getPool(address pool) external view returns (Pool memory);

  /// @notice GHO value of the pool's shares minus `used`. Negative when the pool is in deficit.
  function getSurplus(address pool) external view returns (int256);

  function GHO() external view returns (address);

  function VAULT() external view returns (address);

  function RESERVE() external view returns (address);

  function PUBLIC_POOL() external view returns (address);

  function treasury() external view returns (address);

  function accruedFees() external view returns (uint256);
}
