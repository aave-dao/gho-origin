// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IGhoSwapFacility
/// @notice Swaps GHO against an asset token. GHO comes from a `GhoReserve`.
/// @dev Liquidity is split into pools, all stored in one mapping keyed by address. The public pool is
/// the `address(0)` key and is open to every caller the AccessManager allows to call `swap`. Any other
/// key is a private pool that only that address can swap against. Each pool keeps exactly enough
/// asset to back the GHO it drew; any surplus (yield, for a yield-bearing asset) is sent to the
/// treasury in the asset itself ("skimmed").
interface IGhoSwapFacility {
  /// @notice Liquidity and GHO accounting of one pool.
  /// @param balance Amount of the asset held for the pool.
  /// @param used GHO drawn from the reserve for the pool (gross of fees).
  /// @param cap Maximum value of `used`. Swaps that would push `used` above it revert.
  struct Pool {
    uint128 balance;
    uint128 used;
    uint128 cap;
  }

  /// @notice Fees charged to an account, in basis points of the amount sent in.
  /// @param assetInBps Fee when the account swaps the asset for GHO.
  /// @param ghoInBps Fee when the account swaps GHO for the asset.
  /// @param isSet Whether the tier is configured. Accounts without a tier pay the market tier.
  struct FeeTier {
    uint16 assetInBps;
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
  event Skimmed(address indexed pool, uint256 amount);
  event DeficitRepaid(address indexed pool, address indexed payer, uint256 amount);
  event PoolSeized(address indexed pool, address indexed to, uint256 amount, uint256 debt);
  event PoolMadePublic(address indexed pool, uint256 balance, uint256 used, uint256 cap);
  event PoolCapSet(address indexed pool, uint256 cap);
  event FeeTierSet(address indexed account, uint16 assetInBps, uint16 ghoInBps);
  event FeeTierCleared(address indexed account);
  event TreasurySet(address indexed treasury);
  event FeesClaimed(address indexed treasury, uint256 amount);

  /// @notice Initializes the proxy.
  /// @param authority The AccessManager that governs restricted functions.
  /// @param treasury Recipient of skimmed surplus and swap fees.
  function initialize(address authority, address treasury) external;

  /// @notice Swaps `amountIn` of `tokenIn` (GHO or the asset) for the other token.
  /// @dev Skims the pool first, so the pool never holds more value than the GHO it owes.
  /// @param pool `address(0)` for the public pool, or the caller's address for its private pool.
  /// @param tokenIn GHO or the asset.
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

  /// @notice Sends the pool's surplus asset (value above `used`) to the treasury.
  /// @return amount Asset sent.
  function skim(address pool) external returns (uint256 amount);

  /// @notice Pays GHO back to the reserve on behalf of a pool whose balance is worth less than `used`.
  /// @dev Capped at the current deficit.
  /// @return repaid GHO pulled from the caller.
  function repay(address pool, uint256 amount) external returns (uint256 repaid);

  /// @notice Sends accrued GHO swap fees to the treasury.
  function claimFees() external returns (uint256 amount);

  /// @notice Moves the whole balance of `pool` to `to` and sets its cap to zero. The pool keeps its debt.
  function seize(address pool, address to) external returns (uint256 amount);

  /// @notice Merges a private pool into the public pool: balance, debt and cap move over, and the
  /// private pool is deleted. Both pools are skimmed first.
  function makePublic(address pool) external;

  function setPoolCap(address pool, uint128 cap) external;

  /// @notice Sets the fee tier of `account`. `address(0)` is the market tier, paid by accounts without one.
  function setFeeTier(address account, uint16 assetInBps, uint16 ghoInBps) external;

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

  /// @notice GHO value of the pool's balance minus `used`. Negative when the pool is in deficit.
  function getSurplus(address pool) external view returns (int256);

  function GHO() external view returns (address);

  /// @notice The token swapped against GHO (for the ERC4626 variant, the vault share).
  function ASSET() external view returns (address);

  function RESERVE() external view returns (address);

  function PUBLIC_POOL() external view returns (address);

  function treasury() external view returns (address);

  function accruedFees() external view returns (uint256);
}
