// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoFlashMinterProcedure} from 'src/deployments/contracts/procedures/GhoFlashMinterProcedure.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';

contract GhoFlashMinterBatch is GhoFlashMinterProcedure {
  GhoReportTypes.GhoFlashMinterReport _ghoFlashMinterReport;

  constructor(
    uint256 flashMinterFee,
    GhoReportTypes.GhoTokenReport memory ghoTokenReport,
    address treasury,
    address poolAddressesProvider
  ) {
    address ghoFlashMinter = _deployGhoFlashMinter({
      ghoToken: ghoTokenReport.ghoToken,
      treasury: treasury,
      flashMinterFee: flashMinterFee,
      poolAddressesProvider: poolAddressesProvider
    });

    _ghoFlashMinterReport = GhoReportTypes.GhoFlashMinterReport({ghoFlashMinter: ghoFlashMinter});
  }

  function getGhoFlashMinterReport()
    public
    view
    returns (GhoReportTypes.GhoFlashMinterReport memory)
  {
    return _ghoFlashMinterReport;
  }
}
