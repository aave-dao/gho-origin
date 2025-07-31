// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IsGHO} from '../../sgho/interfaces/IsGho.sol';

interface IsGhoSteward {
  /// @notice Formula for rate is:
  /// `rate = amplification * floatRate + fixedRate`
  struct RateConfig {
    /// @notice Amplification factor
    uint16 amplification;
    /// @notice Representative of market conditions
    uint16 floatRate;
    /// @notice Nominal Amount
    uint16 fixedRate;
  }

  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();
}
