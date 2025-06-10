// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IPoolDataProvider} from 'aave-v3-origin/contracts/interfaces/IPoolDataProvider.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';

contract MockPoolDataProvider is IPoolDataProvider {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
    return POOL_ADDRESSES_PROVIDER;
  }

  constructor(address addressesProvider) {
    POOL_ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
  }

  function getInterestRateStrategyAddress(address asset) external view returns (address) {
    DataTypes.ReserveDataLegacy memory reserveData = IPool(
      IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPool()
    ).getReserveData(asset);
    return reserveData.interestRateStrategyAddress;
  }

  function getATokenTotalSupply(address) external pure returns (uint256) {
    return 0;
  }

  function getAllATokens() external pure returns (TokenData[] memory) {
    return new TokenData[](0);
  }

  function getAllReservesTokens() external pure returns (TokenData[] memory) {
    return new TokenData[](0);
  }

  function getDebtCeiling(address) external pure returns (uint256) {
    return 0;
  }

  function getDebtCeilingDecimals() external pure returns (uint256) {
    return 0;
  }

  function getFlashLoanEnabled(address) external pure returns (bool) {
    return false;
  }

  function getLiquidationProtocolFee(address) external pure returns (uint256) {
    return 0;
  }

  function getPaused(address) external pure returns (bool isPaused) {
    return false;
  }

  function getReserveCaps(address) external pure returns (uint256 borrowCap, uint256 supplyCap) {
    return (0, 0);
  }

  function getReserveConfigurationData(
    address
  )
    external
    pure
    returns (
      uint256 decimals,
      uint256 ltv,
      uint256 liquidationThreshold,
      uint256 liquidationBonus,
      uint256 reserveFactor,
      bool usageAsCollateralEnabled,
      bool borrowingEnabled,
      bool stableBorrowRateEnabled,
      bool isActive,
      bool isFrozen
    )
  {
    return (0, 0, 0, 0, 0, false, false, false, false, false);
  }

  function getReserveData(
    address
  )
    external
    pure
    returns (
      uint256 unbacked,
      uint256 accruedToTreasuryScaled,
      uint256 totalAToken,
      uint256 totalStableDebt,
      uint256 totalVariableDebt,
      uint256 liquidityRate,
      uint256 variableBorrowRate,
      uint256 stableBorrowRate,
      uint256 averageStableBorrowRate,
      uint256 liquidityIndex,
      uint256 variableBorrowIndex,
      uint40 lastUpdateTimestamp
    )
  {
    return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  }

  function getReserveEModeCategory(address) external pure returns (uint256) {
    return 0;
  }

  function getReserveTokensAddresses(
    address
  )
    external
    pure
    returns (
      address aTokenAddress,
      address stableDebtTokenAddress,
      address variableDebtTokenAddress
    )
  {
    return (address(0), address(0), address(0));
  }

  function getSiloedBorrowing(address) external pure returns (bool) {
    return false;
  }

  function getTotalDebt(address) external pure returns (uint256) {
    return 0;
  }

  function getUnbackedMintCap(address) external pure returns (uint256) {
    return 0;
  }

  function getUserReserveData(
    address,
    address
  )
    external
    pure
    returns (
      uint256 currentATokenBalance,
      uint256 currentStableDebt,
      uint256 currentVariableDebt,
      uint256 principalStableDebt,
      uint256 scaledVariableDebt,
      uint256 stableBorrowRate,
      uint256 liquidityRate,
      uint40 stableRateLastUpdated,
      bool usageAsCollateralEnabled
    )
  {
    return (0, 0, 0, 0, 0, 0, 0, 0, false);
  }

  function getIsVirtualAccActive(address) external pure returns (bool) {
    return false;
  }

  function getVirtualUnderlyingBalance(address) external pure returns (uint256) {
    return 0;
  }

  function getReserveDeficit(address) external pure returns (uint256) {
    return 0;
  }
}
