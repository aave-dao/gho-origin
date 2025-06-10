// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketReport, Roles, MarketConfig, DeployFlags} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';

import {BatchTestProcedures as BaseBatchTestProcedures} from 'aave-v3-origin-tests/utils/BatchTestProcedures.sol';

import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {GhoOrchestration} from 'src/deployments/projects/aave-v3-gho-facilitator/GhoOrchestration.sol';

contract BatchTestProcedures is BaseBatchTestProcedures {
  function deployGhoTestnet(
    address deployer,
    uint256 flashMinterFee,
    MarketReport memory marketReport
  ) internal returns (GhoReportTypes.GhoReport memory ghoReport) {
    vm.startPrank(deployer);
    ghoReport = GhoOrchestration.deployGho(deployer, flashMinterFee, marketReport);
    vm.stopPrank();
  }

  function deployAaveV3AndGhoTestnet(
    address deployer,
    Roles memory roles,
    MarketConfig memory marketConfig,
    DeployFlags memory flags,
    MarketReport memory deployedContracts,
    uint256 flashMinterFee
  ) internal returns (MarketReport memory marketReport, GhoReportTypes.GhoReport memory ghoReport) {
    marketReport = deployAaveV3Testnet(deployer, roles, marketConfig, flags, deployedContracts);

    ghoReport = deployGhoTestnet(deployer, flashMinterFee, marketReport);
  }
}
