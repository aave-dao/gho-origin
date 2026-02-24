// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {UpgradeableGhoToken} from 'src/contracts/gho/UpgradeableGhoToken.sol';
import {GhoOracle} from 'src/contracts/misc/GhoOracle.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

library GhoReportTypes {
  struct GhoTokenReport {
    address ghoToken;
    address upgradeableGhoToken;
    address ghoOracle;
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
    GhoFlashMinterReport ghoFlashMinterReport;
  }

  struct GhoContracts {
    GhoToken ghoToken;
    UpgradeableGhoToken upgradeableGhoToken;
    GhoOracle ghoOracle;
    GhoFlashMinter ghoFlashMinter;
  }
}
