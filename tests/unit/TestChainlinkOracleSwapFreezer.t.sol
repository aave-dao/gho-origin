// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestOracleSwapFreezerBase.t.sol';

contract TestChainlinkOracleSwapFreezer is TestOracleSwapFreezerBase {
  function _deployOracleSwapFreezer(
    IGsm gsm,
    address underlyingAsset,
    IPoolAddressesProvider addressesProvider,
    uint128 freezeLowerBound,
    uint128 freezeUpperBound,
    uint128 unfreezeLowerBound,
    uint128 unfreezeUpperBound,
    bool allowUnfreeze
  ) internal override returns (address) {
    return
      address(
        new ChainlinkOracleSwapFreezer(
          gsm,
          underlyingAsset,
          addressesProvider,
          freezeLowerBound,
          freezeUpperBound,
          unfreezeLowerBound,
          unfreezeUpperBound,
          allowUnfreeze
        )
      );
  }

  function _checkAutomation(address swapFreezer) internal view override returns (bool) {
    bytes memory returnData = Address.functionStaticCall(
      swapFreezer,
      abi.encodeWithSelector(AutomationCompatibleInterface.checkUpkeep.selector, '')
    );
    (bool shouldRunKeeper, ) = abi.decode(returnData, (bool, bytes));
    return shouldRunKeeper;
  }

  function _checkAndPerformAutomation(address swapFreezer) internal override returns (bool) {
    bytes memory returnData = Address.functionStaticCall(
      swapFreezer,
      abi.encodeWithSelector(AutomationCompatibleInterface.checkUpkeep.selector, '')
    );
    (bool shouldRunKeeper, bytes memory performData) = abi.decode(returnData, (bool, bytes));

    if (shouldRunKeeper) {
      AutomationCompatibleInterface(swapFreezer).performUpkeep(performData);
    }
    return shouldRunKeeper;
  }
}
