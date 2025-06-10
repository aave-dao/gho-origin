// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestnetProcedures} from '../helpers/TestnetProcedures.sol';

contract TestInitialReserveConfiguration is TestnetProcedures {
  function test_Gho_ListedAsReserve() public view {
    address[] memory reserves = marketContracts.poolProxy.getReservesList();

    bool isGhoTokenListed = false;
    for (uint256 i = 0; i < reserves.length && !isGhoTokenListed; i++) {
      if (reserves[i] == address(ghoContracts.ghoToken)) {
        isGhoTokenListed = true;
      }
    }

    assertEq(isGhoTokenListed, true, 'GHO is not listed as reserve');
  }

  function test_AToken_Implementation() public view {
    assertEq(
      getProxyImplementationAddress(address(ghoAToken)),
      ghoReport.ghoAaveListingReport.ghoATokenImpl
    );
  }

  function test_VariableDebtToken_Implementation() public view {
    assertEq(
      getProxyImplementationAddress(address(ghoVariableDebtToken)),
      ghoReport.ghoAaveListingReport.ghoVariableDebtTokenImpl
    );
  }

  function test_AToken_Configuration() public view {
    assertEq(address(ghoAToken.POOL()), address(marketContracts.poolProxy));
    assertEq(ghoAToken.UNDERLYING_ASSET_ADDRESS(), address(ghoContracts.ghoToken));
    assertEq(ghoAToken.RESERVE_TREASURY_ADDRESS(), address(marketContracts.treasury));
  }

  function test_VariableDebtToken_Configuration() public view {
    assertEq(address(ghoVariableDebtToken.POOL()), address(marketContracts.poolProxy));
    assertEq(ghoVariableDebtToken.UNDERLYING_ASSET_ADDRESS(), address(ghoContracts.ghoToken));
  }

  function test_Reserve_Configuration() public view {
    (
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
    ) = marketContracts.protocolDataProvider.getReserveConfigurationData(
        address(ghoContracts.ghoToken)
      );

    assertEq(decimals, 18);
    assertEq(ltv, 0);
    assertEq(liquidationThreshold, 0);
    assertEq(liquidationBonus, 0);
    assertEq(reserveFactor, 10_00);
    assertEq(usageAsCollateralEnabled, false);
    assertEq(borrowingEnabled, true);
    assertEq(stableBorrowRateEnabled, false);
    assertEq(isActive, true);
    assertEq(isFrozen, false);
  }

  function test_AaveOracle() public view {
    assertEq(
      marketContracts.aaveOracle.getSourceOfAsset(address(ghoContracts.ghoToken)),
      address(ghoContracts.ghoOracle)
    );
  }
}
