// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {IsGho} from '../../sgho/interfaces/IsGho.sol';

/**
 * @title IsGhoSteward Interface
 * @notice Interface for the sGHO steward contract, which manages the `targetRate` and `supplyCap` of the sGHO contract
 * and funds it with GHO from the collector.
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
   * @dev Event is emitted whenever `sGHO` is funded with GHO from the collector.
   * @param caller Message sender, who initiated the funding
   * @param source Token taken from the collector: GHO, a GHO aToken or a GHO ERC4626 vault share
   * @param amount Amount of GHO sent to `sGHO`
   */
  event SGhoFunded(address indexed caller, address indexed source, uint256 amount);

  /**
   * @dev Event is emitted whenever the maximum funding amount is updated.
   * @param caller Message sender, who initiated the update
   * @param maxFundingAmount New maximum amount of GHO per funding
   */
  event MaxFundingAmountUpdated(address indexed caller, uint256 maxFundingAmount);

  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();

  /**
   * @dev Attempted to fund zero GHO.
   */
  error InvalidAmount();

  /**
   * @dev Attempted to fund before `MINIMUM_DELAY` has passed since the last funding.
   */
  error DebounceNotRespected();

  /**
   * @dev Attempted to fund more than the maximum funding amount.
   * @param maxFundingAmount The maximum amount of GHO per funding
   */
  error FundingAmountExceeded(uint256 maxFundingAmount);

  /**
   * @dev Attempted to fund more than `sGHO` liabilities plus the funding buffer allow.
   * @param headroom The maximum amount of GHO that can be funded now
   */
  error FundingHeadroomExceeded(uint256 headroom);

  /**
   * @dev The aToken or vault does not redeem for the GHO of `sGHO`.
   */
  error InvalidFundingSource();

  /**
   * @dev Attempted to set the maximum funding amount already set.
   */
  error MaxFundingAmountUnchanged();

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
   * @notice Sends GHO held by the collector to `sGHO`.
   * @dev Only callable by `FUNDING_MANAGER_ROLE`. This contract needs the collector's `FUNDS_ADMIN_ROLE`.
   * @dev Reverts if called within `MINIMUM_DELAY` of the last funding, if `amount` exceeds the
   * maximum funding amount, or if `amount` exceeds `getFundingHeadroom`.
   * @param amount Amount of GHO to send
   */
  function fundSGho(uint256 amount) external;

  /**
   * @notice Withdraws GHO from an Aave pool using an aToken held by the collector, and sends it to `sGHO`.
   * @dev Same access and limits as `fundSGho`. `aToken` must be the GHO aToken of its own `POOL`.
   * Any `aToken` left after the withdrawal is returned to the collector.
   * @param aToken GHO aToken held by the collector
   * @param amount Amount of GHO to send
   */
  function fundSGhoFromAToken(address aToken, uint256 amount) external;

  /**
   * @notice Withdraws GHO from an ERC4626 vault using shares held by the collector, and sends it to `sGHO`.
   * @dev Same access and limits as `fundSGho`. `vault` must have GHO as its `asset`. Shares left
   * after the withdrawal are returned to the collector.
   * @param vault ERC4626 vault over GHO, such as a static aToken or a tokenization spoke
   * @param amount Amount of GHO to send
   */
  function fundSGhoFromVault(address vault, uint256 amount) external;

  /**
   * @notice Updates the maximum amount of GHO per funding.
   * @dev Only callable by `DEFAULT_ADMIN_ROLE`. Reverts if the value is already set.
   * @param maxFundingAmount New maximum amount of GHO per funding
   */
  function setMaxFundingAmount(uint256 maxFundingAmount) external;

  /**
   * @notice Returns the maximum amount of GHO that can be funded now: `sGHO` liabilities plus
   * `FUNDING_BUFFER_DURATION` of yield at the current `targetRate`, minus the GHO `sGHO` holds.
   */
  function getFundingHeadroom() external view returns (uint256);

  /**
   * @notice Returns the maximum amount of GHO per funding.
   */
  function getMaxFundingAmount() external view returns (uint256);

  /**
   * @notice Returns the timestamp of the last funding.
   */
  function getLastFundingTimestamp() external view returns (uint256);

  /**
   * @notice Returns the collector funding `sGHO`.
   */
  function COLLECTOR() external view returns (ICollector);

  /**
   * @notice Returns the `sGHO` contract.
   */
  function SGHO() external view returns (IsGho);

  /**
   * @notice Returns the GHO token, the asset of `sGHO`.
   */
  function GHO() external view returns (IERC20);

  /**
   * @notice Returns role that can update the `targetRate`.
   */
  function RATE_MANAGER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns role that can update the `supplyCap` parameter.
   */
  function SUPPLY_CAP_MANAGER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns role that can fund `sGHO` from the collector.
   */
  function FUNDING_MANAGER_ROLE() external view returns (bytes32);

  /**
   * @notice Returns the minimum delay between two fundings, in seconds.
   */
  function MINIMUM_DELAY() external view returns (uint256);

  /**
   * @notice Returns how many seconds of yield at the current `targetRate` funding may prepay.
   */
  function FUNDING_BUFFER_DURATION() external view returns (uint256);

  /**
   * @notice Returns the maximum amount of GHO per funding set at deployment.
   */
  function INITIAL_MAX_FUNDING_AMOUNT() external view returns (uint256);
}
