// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IsGHO} from '../../sgho/interfaces/IsGho.sol';

interface IsGhoSteward {
  /**
   * @note Formula for rate (taking into account integer math) is:
   *       `targetRate = amplification * floatRate / AMPLIFICATION_FACTOR + fixedRate`,
   *       where `AMPLIFICATION_FACTOR` is 100_00,
   *       `amplification`, `floatRate` and `fixedRate` are `uint16`
   */
  struct RateConfig {
    /// @notice Amplification factor
    uint16 amplification;
    /// @notice Representative of market conditions
    uint16 floatRate;
    /// @notice Nominal Amount
    uint16 fixedRate;
  }

  /**
   * @notice Event is emitted whenever the `rateConfig` is updated.
   * @param caller Message sender, who initiated the update
   * @param targetRate Target rate installed in `sGHO` after update
   * @param amplification Amplification factor used to calculate `targetRate`
   * @param floatRate Float rate used to calculate `targetRate`
   * @param fixedRate Fixed rate used to calculate `targetRate`
   */
  event RateConfigUpdated(
    address indexed caller,
    uint16 targetRate,
    uint16 amplification,
    uint16 floatRate,
    uint16 fixedRate
  );

  /**
   * @notice Event is emitted whenever the `supplyCap` is updated.
   * @param caller Message sender, who initiated the update
   * @param supplyCap Supply Cap installed in `sGho` after update
   */
  event SupplyCapUpdated(address indexed caller, uint256 supplyCap);

  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();

  /**
   * @dev Attempted to set rate greater than `MAX_RATE` defined in `sGho`.
   */
  error TooBigRate();

  /**
   * @dev Attempted to set the same value, which is already installed.
   */
  error SameValue();
}
