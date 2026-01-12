// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';

import {GhoDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoDiscountRateStrategy.sol';
import {UiGhoDataProvider} from 'src/contracts/facilitators/aave/misc/UiGhoDataProvider.sol';
import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';

contract GhoAaveListingProcedure {
  function _deployGhoATokenImpl(address poolProxy) internal returns (address) {
    return address(new GhoAToken(IPool(poolProxy), address(0)));
  }

  function _deployGhoOracle() internal returns (address) {
    return address(new GhoOracle());
  }

  function _deployGhoVariableDebtTokenImpl(address poolProxy) internal returns (address) {
    // Note: With the new VersionedInitializable, implementation contracts can't be initialized directly.
    // The implementation will be initialized when deployed behind a proxy.
    return address(new GhoVariableDebtToken(IPool(poolProxy), address(0)));
  }

  function _deployGhoDiscountRateStrategy() internal returns (address) {
    return address(new GhoDiscountRateStrategy());
  }

  function _deployUiGhoDataProvider(
    address poolProxy,
    address ghoToken
  ) internal returns (address) {
    return address(new UiGhoDataProvider(IPool(poolProxy), IGhoToken(ghoToken)));
  }
}
