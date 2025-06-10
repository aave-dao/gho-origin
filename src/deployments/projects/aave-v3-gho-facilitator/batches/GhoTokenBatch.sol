// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {GhoTokenProcedure} from 'src/deployments/contracts/procedures/GhoTokenProcedure.sol';

contract GhoTokenBatch is GhoTokenProcedure {
  GhoReportTypes.GhoTokenReport _ghoTokenReport;

  constructor(address deployer) {
    address ghoToken = _deployGhoToken({tokenAdmin: deployer});
    address upgradeableGhoToken = _deployUpgradeableGhoTokenProxy({
      implementation: _deployUpgradeableGhoTokenImpl(),
      proxyAdmin: deployer,
      tokenAdmin: ghoToken
    });

    _ghoTokenReport = GhoReportTypes.GhoTokenReport({
      ghoToken: ghoToken,
      upgradeableGhoToken: upgradeableGhoToken
    });
  }

  function getGhoTokenReport() public view returns (GhoReportTypes.GhoTokenReport memory) {
    return _ghoTokenReport;
  }
}
