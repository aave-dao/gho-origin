// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestOracleSwapFreezerBase.t.sol';

contract TestGelatoOracleSwapFreezer is TestOracleSwapFreezerBase {
  using Address for address;

  function testCheckUpkeepReturnsCorrectSelector() public view {
    (, bytes memory data) = IGelatoOracleSwapFreezer(swapFreezer).checkUpkeep('');
    bytes4 selector;
    assembly {
      selector := mload(add(data, 32))
    }
    assertEq(selector, IGelatoOracleSwapFreezer.performUpkeep.selector);
  }

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
        new GelatoOracleSwapFreezer(
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
    (bool shouldRunKeeper, ) = IGelatoOracleSwapFreezer(swapFreezer).checkUpkeep('');
    return shouldRunKeeper;
  }

  function _checkAndPerformAutomation(
    address swapFreezer
  ) internal virtual override returns (bool) {
    (bool shouldRunKeeper, bytes memory encodedPerformCall) = IGelatoOracleSwapFreezer(swapFreezer)
      .checkUpkeep('');
    if (shouldRunKeeper) {
      swapFreezer.functionCall(encodedPerformCall);
    }
    return shouldRunKeeper;
  }
}
