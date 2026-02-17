// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Payload} from 'aave-v3-origin/contracts/extensions/v3-config-engine/AaveV3Payload.sol';
import {ACLManager} from 'aave-v3-origin/contracts/protocol/configuration/ACLManager.sol';
import {IPoolConfigurator} from 'aave-v3-origin/contracts/interfaces/IPoolConfigurator.sol';
import {IAaveV3ConfigEngine as IEngine} from 'aave-v3-origin/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {ConfiguratorInputTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';
import {EngineFlags} from 'aave-v3-origin/contracts/extensions/v3-config-engine/EngineFlags.sol';
import {MarketReport} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';
import {TestnetERC20} from 'aave-v3-origin/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {MockAggregator} from 'aave-v3-origin/contracts/mocks/oracle/CLAggregators/MockAggregator.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';

contract AaveV3GhoTestListing is AaveV3Payload {
  bytes32 public constant POOL_ADMIN_ROLE_ID =
    0x12ad05bde78c5ab75238ce885307f96ecd482bb402ef831f99e7018a0f169b7b;

  address public immutable USDX_ADDRESS;
  address public immutable USDX_MOCK_PRICE_FEED;

  address public immutable WBTC_ADDRESS;
  address public immutable WBTC_MOCK_PRICE_FEED;

  address public immutable WETH_ADDRESS;
  address public immutable WETH_MOCK_PRICE_FEED;

  address public immutable AAVE_ADDRESS;

  address public immutable GHO_ADDRESS;
  address public immutable GHO_PRICE_FEED;

  address public immutable ATOKEN_IMPLEMENTATION;
  address public immutable VARIABLE_DEBT_TOKEN_IMPLEMENTATION;

  ACLManager immutable ACL_MANAGER;
  IPoolConfigurator immutable CONFIGURATOR;

  constructor(
    IEngine engine,
    address erc20Owner,
    address weth9,
    MarketReport memory marketReport,
    GhoReportTypes.GhoReport memory ghoReport
  ) AaveV3Payload(engine) {
    USDX_ADDRESS = address(new TestnetERC20('USDX', 'USDX', 6, erc20Owner));
    USDX_MOCK_PRICE_FEED = address(new MockAggregator(1e8));

    WBTC_ADDRESS = address(new TestnetERC20('WBTC', 'WBTC', 8, erc20Owner));
    WBTC_MOCK_PRICE_FEED = address(new MockAggregator(27000e8));

    WETH_ADDRESS = weth9;
    WETH_MOCK_PRICE_FEED = address(new MockAggregator(1800e8));

    AAVE_ADDRESS = address(new TestnetERC20('AAVE', 'AAVE', 18, erc20Owner));

    GHO_ADDRESS = ghoReport.ghoTokenReport.ghoToken;
    GHO_PRICE_FEED = ghoReport.ghoOracle;

    ATOKEN_IMPLEMENTATION = marketReport.aToken;
    VARIABLE_DEBT_TOKEN_IMPLEMENTATION = marketReport.variableDebtToken;

    ACL_MANAGER = ACLManager(marketReport.aclManager);
    CONFIGURATOR = IPoolConfigurator(marketReport.poolConfiguratorProxy);
  }

  function newListingsCustom()
    public
    view
    override
    returns (IEngine.ListingWithCustomImpl[] memory)
  {
    IEngine.ListingWithCustomImpl[] memory listingsCustom = new IEngine.ListingWithCustomImpl[](4);

    IEngine.InterestRateInputData memory rateParams = IEngine.InterestRateInputData({
      optimalUsageRatio: 45_00,
      baseVariableBorrowRate: 0,
      variableRateSlope1: 4_00,
      variableRateSlope2: 60_00
    });

    listingsCustom[0] = IEngine.ListingWithCustomImpl(
      IEngine.Listing({
        asset: USDX_ADDRESS,
        assetSymbol: 'USDX',
        priceFeed: USDX_MOCK_PRICE_FEED,
        rateStrategyParams: rateParams,
        enabledToBorrow: EngineFlags.ENABLED,
        borrowableInIsolation: EngineFlags.DISABLED,
        withSiloedBorrowing: EngineFlags.DISABLED,
        flashloanable: EngineFlags.ENABLED,
        ltv: 82_50,
        liqThreshold: 86_00,
        liqBonus: 5_00,
        reserveFactor: 10_00,
        supplyCap: 0,
        borrowCap: 0,
        debtCeiling: 0,
        liqProtocolFee: 10_00
      }),
      IEngine.TokenImplementations({
        aToken: ATOKEN_IMPLEMENTATION,
        vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION
      })
    );

    listingsCustom[1] = IEngine.ListingWithCustomImpl(
      IEngine.Listing({
        asset: WBTC_ADDRESS,
        assetSymbol: 'WBTC',
        priceFeed: WBTC_MOCK_PRICE_FEED,
        rateStrategyParams: rateParams,
        enabledToBorrow: EngineFlags.ENABLED,
        borrowableInIsolation: EngineFlags.DISABLED,
        withSiloedBorrowing: EngineFlags.DISABLED,
        flashloanable: EngineFlags.ENABLED,
        ltv: 82_50,
        liqThreshold: 86_00,
        liqBonus: 5_00,
        reserveFactor: 10_00,
        supplyCap: 0,
        borrowCap: 0,
        debtCeiling: 0,
        liqProtocolFee: 10_00
      }),
      IEngine.TokenImplementations({
        aToken: ATOKEN_IMPLEMENTATION,
        vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION
      })
    );

    listingsCustom[2] = IEngine.ListingWithCustomImpl(
      IEngine.Listing({
        asset: WETH_ADDRESS,
        assetSymbol: 'WETH',
        priceFeed: WETH_MOCK_PRICE_FEED,
        rateStrategyParams: rateParams,
        enabledToBorrow: EngineFlags.ENABLED,
        borrowableInIsolation: EngineFlags.DISABLED,
        withSiloedBorrowing: EngineFlags.DISABLED,
        flashloanable: EngineFlags.ENABLED,
        ltv: 82_50,
        liqThreshold: 86_00,
        liqBonus: 5_00,
        reserveFactor: 10_00,
        supplyCap: 0,
        borrowCap: 0,
        debtCeiling: 0,
        liqProtocolFee: 10_00
      }),
      IEngine.TokenImplementations({
        aToken: ATOKEN_IMPLEMENTATION,
        vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION
      })
    );

    listingsCustom[3] = IEngine.ListingWithCustomImpl(
      IEngine.Listing({
        asset: GHO_ADDRESS,
        assetSymbol: 'GHO',
        priceFeed: GHO_PRICE_FEED,
        rateStrategyParams: rateParams,
        enabledToBorrow: EngineFlags.ENABLED,
        borrowableInIsolation: EngineFlags.DISABLED,
        withSiloedBorrowing: EngineFlags.DISABLED,
        flashloanable: EngineFlags.DISABLED,
        ltv: 0,
        liqThreshold: 0,
        liqBonus: 0,
        reserveFactor: 10_00,
        supplyCap: 0,
        borrowCap: 0,
        debtCeiling: 0,
        liqProtocolFee: 10_00
      }),
      IEngine.TokenImplementations({
        aToken: ATOKEN_IMPLEMENTATION,
        vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION
      })
    );

    return listingsCustom;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Local', networkAbbreviation: 'Loc'});
  }

  function _postExecute() internal override {
    ACL_MANAGER.renounceRole(POOL_ADMIN_ROLE_ID, address(this));
  }
}
