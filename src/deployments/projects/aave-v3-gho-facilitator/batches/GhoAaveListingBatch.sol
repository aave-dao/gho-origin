// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MarketReport} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';
import {GhoAaveListingProcedure} from 'src/deployments/contracts/procedures/GhoAaveListingProcedure.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';

contract GhoAaveListingBatch is GhoAaveListingProcedure {
  GhoReportTypes.GhoAaveListingReport _ghoAaveListingReport;

  constructor(
    GhoReportTypes.GhoTokenReport memory ghoTokenReport,
    MarketReport memory aaveV3MarketReport
  ) {
    address ghoOracle = _deployGhoOracle();
    address ghoATokenImpl = _deployGhoATokenImpl({poolProxy: aaveV3MarketReport.poolProxy});
    address ghoVariableDebtTokenImpl = _deployGhoVariableDebtTokenImpl({
      poolProxy: aaveV3MarketReport.poolProxy
    });
    address ghoDiscountRateStrategy = _deployGhoDiscountRateStrategy();
    address uiGhoDataProvider = _deployUiGhoDataProvider({
      poolProxy: aaveV3MarketReport.poolProxy,
      ghoToken: ghoTokenReport.ghoToken
    });

    _ghoAaveListingReport = GhoReportTypes.GhoAaveListingReport({
      ghoOracle: ghoOracle,
      ghoATokenImpl: ghoATokenImpl,
      ghoVariableDebtTokenImpl: ghoVariableDebtTokenImpl,
      ghoDiscountRateStrategy: ghoDiscountRateStrategy,
      uiGhoDataProvider: uiGhoDataProvider
    });
  }

  function getGhoAaveListingReport()
    public
    view
    returns (GhoReportTypes.GhoAaveListingReport memory)
  {
    return _ghoAaveListingReport;
  }
}
