// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

/**
 * @title IsGho
 * @notice Interface for sGHO
 */
interface IsGho {
  /**
   * @notice Thrown if the target rate is set to a value greater than the max rate.
   */
  error MaxRateExceeded();

  /**
   * @notice Thrown when a zero address is provided for a critical parameter during initialization.
   */
  error ZeroAddressNotAllowed();

  /**
   * @notice Thrown if a target rate update is scheduled with an effective timestamp in the past.
   */
  error EffectiveTimestampInPast();

  /**
   * @notice Thrown if the yield index checkpoint is set with a timestamp in the future.
   */
  error SyncTimestampInFuture();

  /**
   * @notice Thrown if the yield index checkpoint is set with a value below its RAY genesis value.
   */
  error YieldIndexTooLow();

  /**
   * @notice Thrown if there is no scheduled rate change to cancel, or it is already effective.
   */
  error NoPendingTargetRate();

  /**
   * @dev Emitted when a target rate update is set or scheduled.
   * @param newRate The new target rate.
   * @param effectiveAt The timestamp at which the new rate takes effect.
   */
  event TargetRateUpdated(uint256 newRate, uint256 effectiveAt);

  /**
   * @dev Emitted when the timestamp and yield index are updated.
   * @param timestamp The timestamp of the checkpoint, which can precede the block timestamp when
   * a scheduled rate change is applied lazily.
   * @param currentRate The current yield index.
   */
  event ExchangeRateUpdated(uint256 timestamp, uint256 currentRate);

  /**
   * @dev Emitted when the yield index checkpoint is set at initialization.
   * @param newYieldIndex The new yield index.
   * @param newLastUpdate The new checkpoint timestamp.
   * @param newTargetRate The new target rate.
   */
  event YieldIndexSynced(uint256 newYieldIndex, uint256 newLastUpdate, uint256 newTargetRate);

  /**
   * @dev Emitted when a scheduled rate change is cancelled.
   * @param rate The cancelled target rate.
   * @param effectiveAt The timestamp at which the cancelled rate would have taken effect.
   */
  event PendingTargetRateCancelled(uint256 rate, uint256 effectiveAt);

  /**
   * @dev Emitted when the supply cap is updated.
   * @param newSupplyCap The new supply cap.
   */
  event SupplyCapUpdated(uint256 newSupplyCap);

  /**
   * @notice Struct for signature parameters.
   * @param v The recovery ID of the signature.
   * @param r The R component of the signature.
   * @param s The S component of the signature.
   */
  struct SignatureParams {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * @notice Deposits GHO into the vault using permit and mints sGHO shares to the receiver.
   * @dev This function allows users to deposit GHO without requiring a separate approve transaction.
   * The permit is used to approve the vault to spend the user's GHO tokens.
   * @param assets The amount of GHO to deposit.
   * @param receiver The address that will receive the sGHO shares.
   * @param deadline Maximum timestamp at which intent can be executed/signature is valid (must be in the future)
   * @param sig A `secp256k1` signature params from `msgSender()`.
   * @return The amount of sGHO shares minted.
   */
  function depositWithPermit(
    uint256 assets,
    address receiver,
    uint256 deadline,
    SignatureParams memory sig
  ) external returns (uint256);

  /**
   * @notice Pauses the contract, can be called by `PAUSE_GUARDIAN_ROLE`.
   * Emits a {Paused} event.
   */
  function pause() external;

  /**
   * @notice Unpauses the contract, can be called by `PAUSE_GUARDIAN_ROLE`.
   * Emits a {Unpaused} event.
   */
  function unpause() external;

  /**
   * @notice Schedules a target rate update that takes effect at `effectiveAt`.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * The new rate must not exceed `MAX_SAFE_RATE` (5000 basis points).
   * @dev The index is checkpointed at `effectiveAt`, not at execution time, so scheduling the same
   * rate with the same `effectiveAt` on every chain keeps the yield indexes identical. Views
   * resolve a due update immediately; the next rate update, deposit or withdrawal persists it.
   * @dev A pending update that is not yet effective is overwritten. Across chains, the overwrite
   * must execute either before the pending `effectiveAt` on every chain or after it on every
   * chain. A straddle desyncs the indexes.
   * @dev `effectiveAt == block.timestamp` applies the update now, at the chain-local time. Only
   * suitable for single-chain deployments.
   * @param newRate The new annual rate in basis points, compounded continuously
   * (e.g., 1000 for 10%).
   * @param effectiveAt The timestamp at which the new rate takes effect (must not be in the past).
   */
  function setTargetRate(uint16 newRate, uint40 effectiveAt) external;

  /**
   * @notice Cancels the scheduled rate change, without checkpointing the yield index.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * @dev Reverts if no change is scheduled or it is already effective. Across chains, the cancel
   * must execute before the pending `effectiveAt` on every chain.
   */
  function cancelPendingTargetRate() external;

  /**
   * @notice Sets the supply cap for the vault.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * @dev Supply cap is in whole GHO units (no decimals).
   * @param newSupplyCap The new supply cap.
   */
  function setSupplyCap(uint256 newSupplyCap) external;

  /**
   * @notice Returns the maximum safe rate for the vault.
   * @dev Maximum annual rate in basis points, compounded continuously (50%)
   * @return The maximum safe rate.
   */
  function MAX_SAFE_RATE() external view returns (uint16);

  /**
   * @notice Returns the role identifier for the Pause Guardian.
   * @dev This role has permissions to pause/unpause sGho.
   * @return The keccak256 hash of "PAUSE_GUARDIAN_ROLE".
   */
  function PAUSE_GUARDIAN_ROLE() external view returns (bytes32);

  /**
   * @notice Returns the role identifier for the Token Rescuer.
   * @dev This role has permissions to rescue tokens held on the contract.
   * @return The keccak256 hash of "TOKEN_RESCUER_ROLE".
   */
  function TOKEN_RESCUER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns the role identifier for the Yield Manager.
   * @dev This role has permissions to update the target rate.
   * @return The keccak256 hash of "YIELD_MANAGER_ROLE".
   */
  function YIELD_MANAGER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns the address of the GHO token used as the underlying asset in the vault.
   * @return The address of the GHO token.
   */
  function GHO() external view returns (address);

  /**
   * @notice Returns the timestamp of the last time the yield index was updated.
   * @dev Reflects a scheduled rate change once it is effective, even before it is persisted.
   * @return The Unix timestamp of the last update.
   */
  function lastUpdate() external view returns (uint256);

  /**
   * @notice Returns the total supply cap of the vault.
   * @dev Supply cap is in whole GHO units (no decimals).
   * @return The total supply cap.
   */
  function supplyCap() external view returns (uint256);

  /**
   * @notice Returns the current target rate for yield generation.
   * @dev Annual rate in basis points (1% = 100), compounded continuously.
   * @dev Reflects a scheduled rate change once it is effective, even before it is persisted.
   * @return The target rate in basis points.
   */
  function targetRate() external view returns (uint16);

  /**
   * @notice Returns the yield index at the last checkpoint.
   * @dev Excludes yield accrued since the checkpoint; `convertToAssets(RAY)` gives the live index.
   * Index scale is in RAY.
   * @dev Reflects a scheduled rate change once it is effective, even before it is persisted.
   * @return The yield index at the last checkpoint.
   */
  function yieldIndex() external view returns (uint256);

  /**
   * @notice Returns the scheduled target rate update, if any.
   * @dev Returns zeros if there is no scheduled update or if it is already effective.
   * @return newRate The scheduled target rate in basis points.
   * @return effectiveAt The timestamp at which the scheduled rate takes effect.
   */
  function pendingTargetRate() external view returns (uint16 newRate, uint40 effectiveAt);
}
