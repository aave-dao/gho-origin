// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {GhoTokenProcedure} from 'src/deployments/contracts/procedures/GhoTokenProcedure.sol';
import {GhoOracle} from 'src/contracts/misc/GhoOracle.sol';
import {ProxyAdmin} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol';

contract GhoTokenBatch is GhoTokenProcedure {
  GhoReportTypes.GhoTokenReport _ghoTokenReport;

  constructor(address deployer) {
    address ghoToken = _deployGhoToken({tokenAdmin: deployer});
    ProxyAdmin proxyAdmin = new ProxyAdmin();
    proxyAdmin.transferOwnership(deployer);
    require(proxyAdmin.owner() == deployer, 'PROXY_ADMIN_OWNER_MISMATCH');
    address upgradeableGhoToken = _deployUpgradeableGhoTokenProxy({
      implementation: _deployUpgradeableGhoTokenImpl(),
      proxyAdmin: address(proxyAdmin),
      tokenAdmin: deployer
    });

    address ghoOracle = address(new GhoOracle());

    _ghoTokenReport = GhoReportTypes.GhoTokenReport({
      ghoToken: ghoToken,
      upgradeableGhoToken: upgradeableGhoToken,
      ghoOracle: ghoOracle
    });
  }

  function getGhoTokenReport() public view returns (GhoReportTypes.GhoTokenReport memory) {
    return _ghoTokenReport;
  }
}
