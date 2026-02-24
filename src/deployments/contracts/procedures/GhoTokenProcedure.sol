// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TransparentUpgradeableProxy} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {UpgradeableGhoToken} from 'src/contracts/gho/UpgradeableGhoToken.sol';

contract GhoTokenProcedure {
  function _deployGhoToken(address tokenAdmin) internal returns (address) {
    return address(new GhoToken(tokenAdmin));
  }

  function _getUpgradeableGhoTokenInitializeCalldata(
    address tokenAdmin
  ) internal pure returns (bytes memory) {
    return abi.encodeCall(UpgradeableGhoToken.initialize, (tokenAdmin));
  }

  /// @dev This is TransparentUpgradeableProxy from OZ v4.8.1,
  /// which does not deploy a ProxyAdmin contract in the constructor.
  /// The proxy is owned by `proxyAdmin`.
  function _deployUpgradeableGhoTokenProxy(
    address implementation,
    address proxyAdmin,
    address tokenAdmin
  ) internal virtual returns (address) {
    return
      address(
        new TransparentUpgradeableProxy(
          implementation,
          proxyAdmin,
          _getUpgradeableGhoTokenInitializeCalldata(tokenAdmin)
        )
      );
  }

  function _deployUpgradeableGhoTokenImpl() internal returns (address) {
    return address(new UpgradeableGhoToken());
  }
}
