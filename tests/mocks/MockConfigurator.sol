// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {DefaultReserveInterestRateStrategyV2} from 'aave-v3-origin/contracts/misc/DefaultReserveInterestRateStrategyV2.sol';
import {IDefaultInterestRateStrategyV2} from 'aave-v3-origin/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';

contract MockConfigurator {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  IPool internal _pool;

  event ReserveInterestRateStrategyChanged(
    address indexed asset,
    address oldStrategy,
    address newStrategy
  );

  event BorrowCapChanged(address indexed asset, uint256 oldBorrowCap, uint256 newBorrowCap);

  event SupplyCapChanged(address indexed asset, uint256 oldSupplyCap, uint256 newSupplyCap);

  constructor(IPool pool) {
    _pool = pool;
  }

  function test_coverage_ignore() public virtual {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }

  function setReserveInterestRateStrategyAddress(
    address asset,
    address newRateStrategyAddress
  ) external {
    DataTypes.ReserveDataLegacy memory reserve = _pool.getReserveData(asset);
    address oldRateStrategyAddress = reserve.interestRateStrategyAddress;
    _pool.setReserveInterestRateStrategyAddress(asset, newRateStrategyAddress);
    emit ReserveInterestRateStrategyChanged(asset, oldRateStrategyAddress, newRateStrategyAddress);
  }

  function setReserveInterestRateParams(
    address asset,
    IDefaultInterestRateStrategyV2.InterestRateData calldata rateParams
  ) external {
    DataTypes.ReserveDataLegacy memory reserve = _pool.getReserveData(asset);
    address rateStrategyAddress = reserve.interestRateStrategyAddress;
    DefaultReserveInterestRateStrategyV2(rateStrategyAddress).setInterestRateParams(
      asset,
      rateParams
    );
  }

  function setReserveInterestRateData(address asset, bytes calldata rateData) external {
    this.setReserveInterestRateParams(
      asset,
      abi.decode(rateData, (IDefaultInterestRateStrategyV2.InterestRateData))
    );
  }

  function setReserveInterestRateStrategyAddress(
    address asset,
    address rateStrategyAddress,
    bytes calldata rateData
  ) external {
    this.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);
    this.setReserveInterestRateParams(
      asset,
      abi.decode(rateData, (IDefaultInterestRateStrategyV2.InterestRateData))
    );
  }

  function setBorrowCap(address asset, uint256 newBorrowCap) external {
    DataTypes.ReserveConfigurationMap memory currentConfig = _pool.getConfiguration(asset);
    uint256 oldBorrowCap = currentConfig.getBorrowCap();
    currentConfig.setBorrowCap(newBorrowCap);
    _pool.setConfiguration(asset, currentConfig);
    emit BorrowCapChanged(asset, oldBorrowCap, newBorrowCap);
  }

  function setSupplyCap(address asset, uint256 newSupplyCap) external {
    DataTypes.ReserveConfigurationMap memory currentConfig = _pool.getConfiguration(asset);
    uint256 oldSupplyCap = currentConfig.getSupplyCap();
    currentConfig.setSupplyCap(newSupplyCap);
    _pool.setConfiguration(asset, currentConfig);
    emit SupplyCapChanged(asset, oldSupplyCap, newSupplyCap);
  }
}
