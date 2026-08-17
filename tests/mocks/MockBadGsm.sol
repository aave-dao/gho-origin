// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

contract MockBadGsm {
  address public immutable GHO_TOKEN;
  address public immutable UNDERLYING_ASSET;

  constructor(address gho, address ua) {
    GHO_TOKEN = gho;
    UNDERLYING_ASSET = ua;
  }
}
