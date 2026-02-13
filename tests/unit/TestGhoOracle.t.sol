// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';

contract TestGhoOracle is TestnetProcedures {
  function test_GetGhoPriceViaGhoOracle() public view {
    int256 price = ghoContracts.ghoOracle.latestAnswer();
    assertEq(price, 1e8, 'Wrong price from gho oracle');
  }

  function test_GetGhoDecimalsViaGhoOracle() public view {
    uint8 decimals = ghoContracts.ghoOracle.decimals();
    assertEq(decimals, 8, 'Wrong decimals from gho oracle');
  }

  function test_GetGhoPriceViaAaveOracle() public view {
    uint256 price = marketContracts.aaveOracle.getAssetPrice(address(ghoContracts.ghoToken));
    assertEq(price, 1e8, 'Wrong price from aave oracle');
  }
}
