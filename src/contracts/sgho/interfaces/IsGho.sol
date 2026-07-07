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
   * @notice Thrown if the yield index is synced with a checkpoint timestamp in the future.
   */
  error SyncTimestampInFuture();

  /**
   * @notice Thrown if the yield index is synced with a value below its RAY genesis value.
   */
  error YieldIndexTooLow();

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
   * @dev Emitted when the yield index checkpoint is overwritten via `syncYieldIndex`.
   * @param newYieldIndex The new yield index.
   * @param newLastUpdate The new checkpoint timestamp.
   * @param newTargetRate The new target rate.
   */
  event YieldIndexSynced(uint256 newYieldIndex, uint256 newLastUpdate, uint256 newTargetRate);

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
   * The yield index is updated before the deposit to ensure correct share calculation.
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
   * @notice Sets the target rate for yield generation, effective immediately.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * The new rate must be less than 50% (5000 basis points).
   * @dev Checkpoints the yield index at the current timestamp and discards any scheduled rate
   * change, so it is only suitable for single-chain deployments; on multi-chain deployments use
   * the scheduled variant to keep yield indexes in sync.
   * @param newRate The new target rate in basis points (e.g., 1000 for 10%).
   */
  function setTargetRate(uint16 newRate) external;

  /**
   * @notice Schedules a target rate update that takes effect at `effectiveAt`.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * The new rate must be less than 50% (5000 basis points).
   * @dev Scheduling the same rate with the same `effectiveAt` on every chain keeps yield indexes
   * identical across chains at all times: the index is checkpointed exactly at `effectiveAt`
   * regardless of when the update is executed or first touched afterwards. A previously scheduled
   * update that is not yet effective is overwritten.
   * @param newRate The new target rate in basis points (e.g., 1000 for 10%).
   * @param effectiveAt The timestamp at which the new rate takes effect (must not be in the past).
   */
  function setTargetRate(uint16 newRate, uint40 effectiveAt) external;

  /**
   * @notice Overwrites the yield index checkpoint and target rate, discarding any scheduled rate change.
   * @dev This function can only be called by an address with the DEFAULT_ADMIN role.
   * @dev Used to bring a deployment in sync with the other chains: on a cold start (right after
   * initialization on a new chain) or to reconcile after a multi-chain rate update failed on this
   * chain. Passing the `yieldIndex`/`lastUpdate`/`targetRate` values read from an in-sync
   * deployment makes both accrue identically from `newLastUpdate` onwards. If the in-sync
   * deployment also has a scheduled rate change, it must be re-scheduled after syncing.
   * @dev Can decrease the yield index and thereby the asset value of existing shares.
   * @param newYieldIndex The new yield index (RAY scale, at least RAY).
   * @param newLastUpdate The new checkpoint timestamp (must not be in the future).
   * @param newTargetRate The new target rate in basis points (e.g., 1000 for 10%).
   */
  function syncYieldIndex(
    uint120 newYieldIndex,
    uint40 newLastUpdate,
    uint16 newTargetRate
  ) external;

  /**
   * @notice Sets the supply cap for the vault.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * @dev Supply cap is in whole GHO units (no decimals).
   * @param newSupplyCap The new supply cap.
   */
  function setSupplyCap(uint256 newSupplyCap) external;

  /**
   * @notice Returns the maximum safe rate for the vault.
   * @dev Maximum safe annual yield rate in basis points (50%)
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
   * @notice Returns the current target annual percentage rate (APR) for yield generation.
   * @dev The rate is expressed in basis points (1% = 100).
   * @dev Reflects a scheduled rate change once it is effective, even before it is persisted.
   * @return The target rate in basis points.
   */
  function targetRate() external view returns (uint16);

  /**
   * @notice Returns the last checkpointed yield index.
   * @dev This index is used to calculate the value of sGHO in terms of GHO. Index scale is in RAY.
   * @dev Reflects a scheduled rate change once it is effective, even before it is persisted.
   * @return The last checkpointed yield index.
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
