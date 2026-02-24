// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestUpgradeableGhoTokenBase, TestUpgradeableGhoTokenUpgradeBase} from './TestUpgradeableGhoTokenBase.t.sol';
import 'src/deployments/contracts/procedures/GhoTokenProcedure.sol';

contract TestUpgradeableGhoToken is TestUpgradeableGhoTokenBase, GhoTokenProcedure {
  function _deployGhoTokenProxy(
    address proxyAdmin,
    address tokenAdmin
  ) internal override returns (address ghoTokenProxy, address ghoTokenImpl) {
    ghoTokenImpl = _deployUpgradeableGhoTokenImpl();
    ghoTokenProxy = _deployUpgradeableGhoTokenProxy({
      implementation: ghoTokenImpl,
      proxyAdmin: proxyAdmin,
      tokenAdmin: tokenAdmin
    });
  }

  function _getProxyAdmin() internal view override returns (address) {
    return PROXY_ADMIN_OWNER;
  }
}

contract TestUpgradeableGhoTokenUpgrade is TestUpgradeableGhoTokenUpgradeBase, GhoTokenProcedure {
  function _deployGhoTokenProxy(
    address proxyAdmin,
    address tokenAdmin
  ) internal override returns (address ghoTokenProxy, address ghoTokenImpl) {
    ghoTokenImpl = _deployUpgradeableGhoTokenImpl();
    ghoTokenProxy = _deployUpgradeableGhoTokenProxy({
      implementation: ghoTokenImpl,
      proxyAdmin: proxyAdmin,
      tokenAdmin: tokenAdmin
    });
  }

  function _getProxyAdmin() internal view override returns (address) {
    return PROXY_ADMIN_OWNER;
  }
}
