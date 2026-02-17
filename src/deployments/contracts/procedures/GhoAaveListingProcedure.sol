// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';

contract GhoAaveListingProcedure {
  function _deployGhoOracle() internal returns (address) {
    return address(new GhoOracle());
  }
}
