// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IGhoSwapFacility
/// @notice Swaps GHO against an asset token. GHO comes from a `GhoReserve`.
/// @dev Liquidity is split into pools, all stored in one mapping keyed by address. The public pool is
/// the `address(0)` key; every other key is the private pool of that address. `swap` routes by caller:
/// an account whose pool has a non-zero cap trades against it, every other account against the public
/// pool. Fees are set per pool, so the public pool's fees are the market fees and a private pool's
/// fees are its owner's. Each pool keeps exactly enough
/// asset to back the GHO it drew; any surplus (yield, for a yield-bearing asset) is sent to the
/// treasury in the asset itself ("skimmed").
interface IGhoSwapFacility {
  /// @notice Liquidity and GHO accounting of one pool.
  /// @param balance Amount of the asset held for the pool.
  /// @param used GHO drawn from the reserve for the pool (gross of fees).
  /// @param cap Maximum value of `used`. Swaps that would push `used` above it revert.
  /// For a private pool, a non-zero cap is also what routes its owner to it.
  /// @param assetInBps Fee on swaps of the asset for GHO, in basis points of the amount in.
  /// @param ghoInBps Fee on swaps of GHO for the asset, in basis points of the amount in.
  struct Pool {
    uint128 balance;
    uint128 used;
    uint128 cap;
    uint16 assetInBps;
    uint16 ghoInBps;
  }

  error ZeroAddress();
  error ZeroAmount();
  error InvalidFee(uint256 feeBps);
  error InvalidToken(address token);
  error UnsupportedDecimals(uint8 decimals);
  error ReserveTokenMismatch(address reserveToken);
  error PoolCapExceeded(address pool, uint256 used, uint256 cap);
  error InsufficientLiquidity(address pool);
  error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
  error NoDeficit(address pool);
  error NotPrivatePool();
  error SwapsPaused();

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
  event PoolFeesSet(address indexed pool, uint16 assetInBps, uint16 ghoInBps);
  event TreasurySet(address indexed treasury);
  event FeesClaimed(address indexed treasury, uint256 amount);
  event PausedSet(bool paused);

  /// @notice Initializes the proxy.
  /// @param authority The AccessManager that governs restricted functions.
  /// @param treasury Recipient of skimmed surplus and swap fees.
  function initialize(address authority, address treasury) external;

  /// @notice Swaps `amountIn` of `tokenIn` (GHO or the asset) for the other token.
  /// @dev Skims the pool first, so the pool never holds more value than the GHO it owes.
  /// @dev Trades against the caller's private pool if it has one, otherwise the public pool.
  /// @param tokenIn GHO or the asset.
  /// @param amountIn Exact amount of `tokenIn` pulled from the caller, fee included.
  /// @param minAmountOut Minimum amount of the other token to receive.
  /// @param receiver Recipient of the output token.
  /// @return amountOut Amount of the other token sent to `receiver`.
  function swap(
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

  /// @notice Merges a private pool into the public pool: balance, debt and cap move over, the private
  /// pool's fees are dropped, and the private pool is deleted. Both pools are skimmed first.
  function makePublic(address pool) external;

  /// @notice Sets the cap of `pool`. A non-zero cap on a private pool routes its owner to it; a zero
  /// cap routes the owner back to the public pool and leaves the private balance until `makePublic`
  /// or `seize`.
  function setPoolCap(address pool, uint128 cap) external;

  function setPoolFees(address pool, uint16 assetInBps, uint16 ghoInBps) external;

  /// @notice Pool `account` trades against: its own if its cap is non-zero, otherwise `PUBLIC_POOL`.
  function poolOf(address account) external view returns (address);

  function setTreasury(address treasury) external;

  /// @notice Pauses or resumes `swap`. Skimming, repaying and claiming fees keep working.
  function setPaused(bool paused) external;

  function paused() external view returns (bool);

  /// @notice Amount out and fee for `account` swapping `amountIn` of `tokenIn` in the pool it is
  /// routed to, ignoring liquidity and caps.
  function quote(
    address account,
    address tokenIn,
    uint256 amountIn
  ) external view returns (uint256 amountOut, uint256 fee);

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
