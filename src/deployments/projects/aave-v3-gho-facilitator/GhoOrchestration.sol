// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoFlashMinterBatch} from 'src/deployments/projects/aave-v3-gho-facilitator/batches/GhoFlashMinterBatch.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {GhoTokenBatch} from 'src/deployments/projects/aave-v3-gho-facilitator/batches/GhoTokenBatch.sol';

library GhoOrchestration {
  function deployGho(
    address deployer,
    uint256 flashMinterFee,
    address treasury,
    address poolAddressesProvider
  ) internal returns (GhoReportTypes.GhoReport memory ghoReport) {
    GhoTokenBatch ghoTokenBatch = new GhoTokenBatch(deployer);
    GhoReportTypes.GhoTokenReport memory ghoTokenReport = ghoTokenBatch.getGhoTokenReport();

    GhoFlashMinterBatch ghoFlashMinterBatch = new GhoFlashMinterBatch(
      flashMinterFee,
      ghoTokenReport,
      treasury,
      poolAddressesProvider
    );
    GhoReportTypes.GhoFlashMinterReport memory ghoFlashMinterReport = ghoFlashMinterBatch
      .getGhoFlashMinterReport();

    ghoReport = GhoReportTypes.GhoReport({
      ghoTokenReport: ghoTokenReport,
      ghoFlashMinterReport: ghoFlashMinterReport
    });

    return ghoReport;
  }
}
