// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoAaveListingProcedure} from 'src/deployments/contracts/procedures/GhoAaveListingProcedure.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';

contract GhoAaveListingBatch is GhoAaveListingProcedure {
  GhoReportTypes.GhoAaveListingReport _ghoAaveListingReport;

  constructor() {
    address ghoOracle = _deployGhoOracle();

    _ghoAaveListingReport = GhoReportTypes.GhoAaveListingReport({ghoOracle: ghoOracle});
  }

  function getGhoAaveListingReport()
    public
    view
    returns (GhoReportTypes.GhoAaveListingReport memory)
  {
    return _ghoAaveListingReport;
  }
}
