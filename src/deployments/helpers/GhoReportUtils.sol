// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import '../types/GhoReportTypes.sol';

library GhoReportUtils {
  function toGhoContracts(
    GhoReportTypes.GhoReport memory ghoReport
  ) internal pure returns (GhoReportTypes.GhoContracts memory) {
    return
      GhoReportTypes.GhoContracts({
        ghoToken: GhoToken(ghoReport.ghoTokenReport.ghoToken),
        upgradeableGhoToken: UpgradeableGhoToken(ghoReport.ghoTokenReport.upgradeableGhoToken),
        ghoOracle: GhoOracle(ghoReport.ghoTokenReport.ghoOracle),
        ghoFlashMinter: GhoFlashMinter(ghoReport.ghoFlashMinterReport.ghoFlashMinter)
      });
  }
}
