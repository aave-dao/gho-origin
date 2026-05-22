// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetERC20} from 'lib/aave-v3-origin/src/contracts/mocks/testnet-helpers/TestnetERC20.sol';

contract MockAToken is TestnetERC20 {
  constructor(
    string memory name,
    string memory symbol,
    uint8 decimals,
    address owner,
    address pool
  ) TestnetERC20(name, symbol, decimals, owner) {
    POOL = pool;
  }

  address public immutable POOL;

  function burn(address from, uint256 amount) external {
    require(msg.sender == POOL, 'Only pool');
    _burn(from, amount);
  }
}
