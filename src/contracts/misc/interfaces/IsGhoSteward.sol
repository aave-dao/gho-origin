// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IsGho} from '../../sgho/interfaces/IsGho.sol';

/**
 * @title IsGhoSteward Interface
 * @notice Interface for the sGHO steward contract, which manages the `targetRate` and `supplyCap` of the sGHO contract.
 */
interface IsGhoSteward {
  /**
   * @dev Event is emitted whenever the `targetRate` is updated.
   * @param caller Message sender, who initiated the update
   * @param targetRate Target rate set in `sGHO`
   * @param effectiveAt Timestamp at which the target rate takes effect on `sGHO`
   */
  event TargetRateUpdated(address indexed caller, uint16 targetRate, uint40 effectiveAt);

  /**
   * @dev Event is emitted whenever a scheduled `targetRate` update is cancelled.
   * @param caller Message sender, who initiated the cancellation
   */
  event TargetRateCancelled(address indexed caller);

  /**
   * @dev Event is emitted whenever the `supplyCap` is updated.
   * @param caller Message sender, who initiated the update
   * @param supplyCap Supply Cap set in `sGHO` after update
   */
  event SupplyCapUpdated(address indexed caller, uint256 supplyCap);

  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();

  /**
   * @dev Attempted to set the rate already in force.
   */
  error RateUnchanged();

  /**
   * @dev Attempted to set the same supplyCap, which is already set.
   */
  error SupplyCapUnchanged();

  /**
   * @notice Updates `targetRate` on `sGHO`, effective at `effectiveAt`.
   * @dev Only callable by `RATE_MANAGER_ROLE`.
   * @dev Reverts with `RateUnchanged` if `targetRate` is already in force. A scheduled update is
   * overwritten; use `cancelTargetRate` to drop it instead.
   * @dev Submitting the same `targetRate` and `effectiveAt` on the stewards of every chain keeps
   * the yield indexes in sync. Passing the current timestamp applies immediately and is only
   * suitable for single-chain deployments.
   * @param targetRate New annual rate in basis points, compounded every second
   * @param effectiveAt Timestamp at which the rate takes effect (must not be in the past)
   */
  function setTargetRate(uint16 targetRate, uint40 effectiveAt) external;

  /**
   * @notice Cancels the scheduled `targetRate` update on `sGHO`, without a checkpoint.
   * @dev Only callable by `RATE_MANAGER_ROLE`. Reverts if no update is scheduled or it is already
   * effective. Across chains, the cancel must execute before the pending `effectiveAt` on every
   * chain.
   */
  function cancelTargetRate() external;

  /**
   * @notice Updates `supplyCap` on `sGHO`.
   * @dev In whole GHO units (no decimals); reverts above `uint40`.
   * Only callable by `SUPPLY_CAP_MANAGER_ROLE`.
   * @param supplyCap_ New `supplyCap` to set.
   */
  function setSupplyCap(uint256 supplyCap_) external;

  /**
   * @notice Returns `sGHO` address, wrapped in interface.
   */
  function sGHO() external view returns (IsGho);

  /**
   * @notice Returns role that can update the `targetRate`.
   */
  function RATE_MANAGER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns role that can update the `supplyCap` parameter.
   */
  function SUPPLY_CAP_MANAGER_ROLE() external view returns (bytes32);
}
