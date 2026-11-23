// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Reference model of the sGHO yield index: the checkpointed index times
/// `1 + x + x^2 / 2 + x^3 / 6` with `x = rate * elapsed / year`, every operation rounded down.
library SGhoYieldMath {
  uint256 internal constant RAY = 1e27;

  function accrue(uint256 index, uint256 rateBps, uint256 elapsed) internal pure returns (uint256) {
    if (rateBps == 0) return index;
    uint256 x = (((rateBps * RAY) / 10_000) * elapsed) / 365 days;
    uint256 growth = RAY + x + (x * (x / 2 + (x * (x / 6)) / RAY)) / RAY;
    return (index * growth) / RAY;
  }
}
