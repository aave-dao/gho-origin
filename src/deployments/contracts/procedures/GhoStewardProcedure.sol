// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IGhoAaveSteward} from 'src/contracts/misc/interfaces/IGhoAaveSteward.sol';
import {GhoAaveSteward} from 'src/contracts/misc/GhoAaveSteward.sol';
import {GhoBucketSteward} from 'src/contracts/misc/GhoBucketSteward.sol';
import {GhoCcipSteward} from 'src/contracts/misc/GhoCcipSteward.sol';
import {GhoGsmSteward} from 'src/contracts/misc/GhoGsmSteward.sol';

contract GhoStewardProcedure {
  function _deployGhoAaveSteward(
    address owner,
    address poolAddressesProvider,
    address poolDataProvider,
    address ghoToken,
    address riskCouncil,
    IGhoAaveSteward.BorrowRateConfig memory borrowRateConfig
  ) internal returns (address) {
    return
      address(
        new GhoAaveSteward(
          owner,
          poolAddressesProvider,
          poolDataProvider,
          ghoToken,
          riskCouncil,
          borrowRateConfig
        )
      );
  }

  function _deployGhoBucketSteward(
    address owner,
    address ghoToken,
    address riskCouncil
  ) internal returns (address) {
    return address(new GhoBucketSteward(owner, ghoToken, riskCouncil));
  }

  function _deployGhoCcipSteward(
    address ghoToken,
    address ghoTokenPool,
    address riskCouncil,
    bool bridgeLimitEnabled
  ) internal returns (address) {
    return address(new GhoCcipSteward(ghoToken, ghoTokenPool, riskCouncil, bridgeLimitEnabled));
  }

  function _deployGhoGsmSteward(
    address fixedFeeStrategyFactory,
    address riskCouncil
  ) internal returns (address) {
    return address(new GhoGsmSteward(fixedFeeStrategyFactory, riskCouncil));
  }
}
