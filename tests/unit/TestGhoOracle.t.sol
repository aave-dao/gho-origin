// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {GhoOracle} from 'src/contracts/misc/GhoOracle.sol';

contract TestGhoOracle is Test {
  GhoOracle internal ghoOracle;

  function setUp() public {
    ghoOracle = new GhoOracle();
  }

  function test_GetGhoPriceViaGhoOracle() public view {
    int256 price = ghoOracle.latestAnswer();
    assertEq(price, 1e8, 'Wrong price from gho oracle');
  }

  function test_GetGhoDecimalsViaGhoOracle() public view {
    uint8 decimals = ghoOracle.decimals();
    assertEq(decimals, 8, 'Wrong decimals from gho oracle');
  }
}
