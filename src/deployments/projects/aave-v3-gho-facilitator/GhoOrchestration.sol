// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MarketReport} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';
import {GhoAaveListingBatch} from 'src/deployments/projects/aave-v3-gho-facilitator/batches/GhoAaveListingBatch.sol';
import {GhoFlashMinterBatch} from 'src/deployments/projects/aave-v3-gho-facilitator/batches/GhoFlashMinterBatch.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {GhoTokenBatch} from 'src/deployments/projects/aave-v3-gho-facilitator/batches/GhoTokenBatch.sol';

library GhoOrchestration {
  function deployGho(
    address deployer,
    uint256 flashMinterFee,
    MarketReport memory marketReport
  ) internal returns (GhoReportTypes.GhoReport memory ghoReport) {
    GhoTokenBatch ghoTokenBatch = new GhoTokenBatch(deployer);
    GhoReportTypes.GhoTokenReport memory ghoTokenReport = ghoTokenBatch.getGhoTokenReport();

    GhoAaveListingBatch ghoAaveListingBatch = new GhoAaveListingBatch(ghoTokenReport, marketReport);
    GhoReportTypes.GhoAaveListingReport memory ghoAaveListingReport = ghoAaveListingBatch
      .getGhoAaveListingReport();

    GhoFlashMinterBatch ghoFlashMinterBatch = new GhoFlashMinterBatch(
      flashMinterFee,
      ghoTokenReport,
      marketReport
    );
    GhoReportTypes.GhoFlashMinterReport memory ghoFlashMinterReport = ghoFlashMinterBatch
      .getGhoFlashMinterReport();

    ghoReport = GhoReportTypes.GhoReport({
      ghoTokenReport: ghoTokenReport,
      ghoAaveListingReport: ghoAaveListingReport,
      ghoFlashMinterReport: ghoFlashMinterReport
    });

    return ghoReport;
  }
}
