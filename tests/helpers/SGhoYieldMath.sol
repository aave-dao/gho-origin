// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Reference model of the sGHO yield index: the checkpointed index times
/// `(RAY + rate / year) ^ elapsed`, by binary exponentiation with every product rounded down, in
/// checked arithmetic.
library SGhoYieldMath {
  uint256 internal constant RAY = 1e27;

  function growth(uint256 rateBps, uint256 elapsed) internal pure returns (uint256 result) {
    uint256 base = RAY + ((rateBps * RAY) / 10_000) / 365 days;
    result = RAY;
    while (elapsed != 0) {
      if (elapsed % 2 == 1) result = (result * base) / RAY;
      elapsed /= 2;
      if (elapsed != 0) base = (base * base) / RAY;
    }
  }

  function accrue(uint256 index, uint256 rateBps, uint256 elapsed) internal pure returns (uint256) {
    if (rateBps == 0) return index;
    return (index * growth(rateBps, elapsed)) / RAY;
  }
}
