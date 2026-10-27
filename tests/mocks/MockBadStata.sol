// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

contract MockBadStata {
  function asset() external pure returns (address) {
    return address(0);
  }
}
