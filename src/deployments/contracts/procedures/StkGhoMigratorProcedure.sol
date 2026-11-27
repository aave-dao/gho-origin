// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';

contract StkGhoMigratorProcedure {
  function _deployStkGhoMigrator(
    address initialOwner,
    address initialPauseGuardian
  ) internal returns (address) {
    return
      address(
        new StkGhoMigrator({
          initialOwner_: initialOwner,
          initialPauseGuardian_: initialPauseGuardian
        })
      );
  }
}
