// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from 'aave-v3-origin-tests/utils/TestnetProcedures.sol';
import {IStataTokenFactory} from 'aave-v3-origin/contracts/extensions/stata-token/interfaces/IStataTokenFactory.sol';
import {IStataTokenV2} from 'aave-v3-origin/contracts/extensions/stata-token/interfaces/IStataTokenV2.sol';

/**
 * @title AaveV3StataEnvironment
 * @notice Deploys a local Aave v3 market with a StataTokenV2 for each reserve, and drives its state.
 */
contract AaveV3StataEnvironment is TestnetProcedures {
  address internal immutable BORROWER = makeAddr('AAVE_BORROWER');

  function deploy() external {
    initTestEnvironment(false);
    IStataTokenFactory(report.staticATokenFactoryProxy).createStataTokens(
      contracts.poolProxy.getReservesList()
    );
  }

  function usdxToken() external view returns (address) {
    return tokenList.usdx;
  }

  function stataToken(address underlying) external view returns (address) {
    return IStataTokenFactory(report.staticATokenFactoryProxy).getStataToken(underlying);
  }

  /// @dev Underlying the pool holds for `asset`, the most a withdrawal can take.
  function availableLiquidity(address asset) external view returns (uint256) {
    return contracts.poolProxy.getVirtualUnderlyingBalance(asset);
  }

  /// @dev Liquidity index of `asset` as of now, the rate its static aToken prices shares at.
  function normalizedIncome(address asset) external view returns (uint256) {
    return contracts.poolProxy.getReserveNormalizedIncome(asset);
  }

  /// @dev Borrows `amount` of `asset` against WETH collateral, so suppliers start earning interest.
  function borrow(address asset, uint256 amount) external {
    uint256 collateral = 1_000_000e18;
    deal(address(weth), BORROWER, collateral);
    vm.startPrank(BORROWER);
    weth.approve(address(contracts.poolProxy), collateral);
    contracts.poolProxy.supply(address(weth), collateral, BORROWER, 0);
    contracts.poolProxy.borrow(asset, amount, 2, 0, BORROWER);
    vm.stopPrank();
  }

  function setReservePaused(address asset, bool paused) external {
    vm.prank(poolAdmin);
    contracts.poolConfiguratorProxy.setReservePause(asset, paused);
  }

  function setReserveFrozen(address asset, bool frozen) external {
    vm.prank(poolAdmin);
    contracts.poolConfiguratorProxy.setReserveFreeze(asset, frozen);
  }

  /// @dev `supplyCap` is in whole tokens, as the pool configurator takes it.
  function setSupplyCap(address asset, uint256 supplyCap) external {
    vm.prank(poolAdmin);
    contracts.poolConfiguratorProxy.setSupplyCap(asset, supplyCap);
  }

  function setStataPaused(address stata, bool paused) external {
    vm.prank(poolAdmin);
    IStataTokenV2(stata).setPaused(paused);
  }
}
