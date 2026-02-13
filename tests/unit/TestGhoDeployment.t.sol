// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AugustusRegistryMock} from 'aave-v3-origin-tests/mocks/AugustusRegistryMock.sol';
import {WETH9} from 'aave-v3-origin/contracts/dependencies/weth/WETH9.sol';
import {MarketReport, Roles, MarketConfig, DeployFlags} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {BatchTestProcedures} from '../helpers/BatchTestProcedures.sol';

contract TestGhoDeployment is BatchTestProcedures {
  MarketReport internal marketReport;
  GhoReportTypes.GhoReport internal ghoReport;

  Roles internal roles;
  MarketConfig internal config;
  DeployFlags internal flags;

  uint256 public constant FLASH_MINTER_FEE = 100;

  function setUp() public {
    poolAdmin = makeAddr('poolAdmin');

    MarketReport memory deployedContracts;
    (roles, config, flags, deployedContracts) = _getMarketInput(poolAdmin);

    config.networkBaseTokenPriceInUsdProxyAggregator = makeAddr('ethUsdOracle');
    config.marketReferenceCurrencyPriceInUsdProxyAggregator = makeAddr('ethUsdOracle');
    config.paraswapAugustusRegistry = address(new AugustusRegistryMock());
    config.wrappedNativeToken = address(new WETH9());

    (marketReport, ghoReport) = deployAaveV3AndGhoTestnet(
      roles.marketOwner,
      roles,
      config,
      flags,
      deployedContracts,
      FLASH_MINTER_FEE
    );
  }

  function test_AaveV3Deployment() public view {
    checkFullReport(config, flags, marketReport);
  }

  function test_GhoDeployment() public view {
    assertNotEq(ghoReport.ghoTokenReport.ghoToken, address(0), 'ghoToken');
    assertNotEq(ghoReport.ghoTokenReport.upgradeableGhoToken, address(0), 'upgradeableGhoToken');

    assertNotEq(ghoReport.ghoOracle, address(0), 'ghoOracle');

    assertNotEq(ghoReport.ghoFlashMinterReport.ghoFlashMinter, address(0), 'ghoFlashMinter');

    GhoFlashMinter ghoFlashMinter = GhoFlashMinter(ghoReport.ghoFlashMinterReport.ghoFlashMinter);
    assertEq(
      address(ghoFlashMinter.GHO_TOKEN()),
      ghoReport.ghoTokenReport.ghoToken,
      'GHO_TOKEN in FlashMinter does not match ghoToken address'
    );
    assertEq(
      address(ghoFlashMinter.getGhoTreasury()),
      marketReport.treasury,
      'Treasury in FlashMinter does not match marketReport.treasury'
    );
    assertEq(ghoFlashMinter.getFee(), FLASH_MINTER_FEE, 'Unexpected Fee in FlashMinter');
    assertEq(
      address(ghoFlashMinter.ADDRESSES_PROVIDER()),
      marketReport.poolAddressesProvider,
      'PoolAddressesProvider in FlashMinter does not match marketReport.poolAddressesProvider'
    );
  }
}
