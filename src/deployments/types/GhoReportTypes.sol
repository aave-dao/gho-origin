// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {UpgradeableGhoToken} from 'src/contracts/gho/UpgradeableGhoToken.sol';
import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {GhoDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoDiscountRateStrategy.sol';
import {UiGhoDataProvider} from 'src/contracts/facilitators/aave/misc/UiGhoDataProvider.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

library GhoReportTypes {
  struct GhoTokenReport {
    address ghoToken;
    address upgradeableGhoToken;
  }

  struct GhoAaveListingReport {
    address ghoOracle;
    address ghoATokenImpl;
    address ghoVariableDebtTokenImpl;
    address ghoDiscountRateStrategy;
    address uiGhoDataProvider;
  }

  struct GhoFlashMinterReport {
    address ghoFlashMinter;
  }

  struct GhoStewardReport {
    address ghoAaveSteward;
    address ghoBucketSteward;
    address ghoCcipSteward;
    address ghoGsmSteward;
  }

  struct GhoReport {
    GhoTokenReport ghoTokenReport;
    GhoAaveListingReport ghoAaveListingReport;
    GhoFlashMinterReport ghoFlashMinterReport;
  }

  struct GhoContracts {
    GhoToken ghoToken;
    UpgradeableGhoToken upgradeableGhoToken;
    GhoOracle ghoOracle;
    GhoDiscountRateStrategy ghoDiscountRateStrategy;
    UiGhoDataProvider uiGhoDataProvider;
    GhoFlashMinter ghoFlashMinter;
  }
}
