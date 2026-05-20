// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';

/**
 * @dev Minimal MockPool for testing purposes
 */
contract MockPool {
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  mapping(address => DataTypes.ReserveDataLegacy) internal _reserves;
  mapping(address => DataTypes.ReserveConfigurationMap) internal _configurations;

  constructor(IPoolAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
  }

  function test_coverage_ignore() public virtual {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }

  function getReserveData(
    address asset
  ) external view returns (DataTypes.ReserveDataLegacy memory) {
    return _reserves[asset];
  }

  function getConfiguration(
    address asset
  ) external view returns (DataTypes.ReserveConfigurationMap memory) {
    return _configurations[asset];
  }

  function setConfiguration(
    address asset,
    DataTypes.ReserveConfigurationMap memory configuration
  ) external {
    _configurations[asset] = configuration;
  }

  function getReserveInterestRateStrategyAddress(address asset) public view returns (address) {
    return _reserves[asset].interestRateStrategyAddress;
  }

  function setReserveInterestRateStrategyAddress(address asset, address strategy) external {
    _reserves[asset].interestRateStrategyAddress = strategy;
  }

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external {
    IERC20(asset).transferFrom(msg.sender, onBehalfOf, amount);
  }

  function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
    IERC20(asset).transfer(to, amount);

    return amount;
  }
}
