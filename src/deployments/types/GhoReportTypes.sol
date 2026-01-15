// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {UpgradeableGhoToken} from 'src/contracts/gho/UpgradeableGhoToken.sol';
import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {
  GhoDiscountRateStrategy
} from 'src/contracts/facilitators/aave/interestStrategy/GhoDiscountRateStrategy.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

library GhoReportTypes {
  struct GhoTokenReport {
    address ghoToken;
    address upgradeableGhoToken;
  }

  // Note: GhoAaveListingReport struct retained for backwards compatibility,
  // but ghoATokenImpl, ghoVariableDebtTokenImpl, and uiGhoDataProvider fields
  // have been removed as the old Aave integration is no longer supported
  struct GhoAaveListingReport {
    address ghoOracle;
    address ghoDiscountRateStrategy;
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
    GhoFlashMinter ghoFlashMinter;
  }
}
