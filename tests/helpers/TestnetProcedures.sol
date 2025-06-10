// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AugustusRegistryMock} from 'aave-v3-origin-tests/mocks/AugustusRegistryMock.sol';
import {MarketReport, Roles, MarketConfig, DeployFlags, ContractsReport as MarketContracts} from 'aave-v3-origin/deployments/interfaces/IMarketReportTypes.sol';
import {MarketReportUtils} from 'aave-v3-origin/deployments/contracts/utilities/MarketReportUtils.sol';
import {WETH9} from 'aave-v3-origin/contracts/dependencies/weth/WETH9.sol';
import {ACLManager} from 'aave-v3-origin/contracts/protocol/configuration/ACLManager.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';
import {MathUtils} from 'aave-v3-origin/contracts/protocol/libraries/math/MathUtils.sol';
import {IAaveV3ConfigEngine} from 'aave-v3-origin/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {TestnetERC20} from 'aave-v3-origin/contracts/mocks/testnet-helpers/TestnetERC20.sol';

import {IERC20} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';
import {AaveV3GhoTestListing} from 'src/deployments/projects/aave-v3-gho-facilitator/AaveV3GhoTestListing.sol';
import {GhoReportUtils} from 'src/deployments/helpers/GhoReportUtils.sol';

import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {BatchTestProcedures} from './BatchTestProcedures.sol';

import {Vm} from 'forge-std/Vm.sol';

contract TestnetProcedures is BatchTestProcedures {
  using MarketReportUtils for MarketReport;
  using GhoReportUtils for GhoReportTypes.GhoReport;

  using WadRayMath for uint256;

  bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  string internal constant AAVE_FACILITATOR_LABEL = 'Aave V3 Mainnet Market';
  uint128 internal constant AAVE_FACILITATOR_CAPACITY = 1e27;
  string internal constant FLASH_MINTER_LABEL = 'GHO FlashMinter';
  uint128 internal constant FLASH_MINTER_CAPACITY = 1e26;

  uint256 public constant FLASH_MINTER_FEE = 1_00;

  MarketReport internal marketReport;
  MarketContracts internal marketContracts;

  GhoReportTypes.GhoReport internal ghoReport;
  GhoReportTypes.GhoContracts internal ghoContracts;

  Roles internal roles;
  MarketConfig internal marketConfig;
  DeployFlags internal flags;
  MarketReport internal deployedContracts;

  TokenList internal tokenList;

  address internal alice;
  uint256 internal alicePrivateKey;

  address internal bob;
  uint256 internal bobPrivateKey;

  address internal charlie;
  uint256 internal charliePrivateKey;

  GhoAToken internal ghoAToken;
  GhoVariableDebtToken internal ghoVariableDebtToken;

  struct TokenList {
    address wbtc;
    address weth;
    address usdx;
    address aave;
    address stkAave;
    address gho;
  }

  function setUp() public virtual {
    _initTestEnvironment(true);
  }

  function _initTestEnvironment(bool mintUserTokens) internal {
    poolAdmin = makeAddr('poolAdmin');
    (alice, alicePrivateKey) = makeAddrAndKey('alice');
    (bob, bobPrivateKey) = makeAddrAndKey('bob');
    (charlie, charliePrivateKey) = makeAddrAndKey('charlie');

    tokenList.weth = address(new WETH9());

    (roles, marketConfig, flags, deployedContracts) = _getMarketInput(poolAdmin);
    marketConfig.networkBaseTokenPriceInUsdProxyAggregator = makeAddr('ethUsdOracle');
    marketConfig.marketReferenceCurrencyPriceInUsdProxyAggregator = makeAddr('ethUsdOracle');
    marketConfig.paraswapAugustusRegistry = address(new AugustusRegistryMock());
    marketConfig.wrappedNativeToken = tokenList.weth;

    (marketReport, ghoReport) = deployAaveV3AndGhoTestnet(
      roles.marketOwner,
      roles,
      marketConfig,
      flags,
      deployedContracts,
      FLASH_MINTER_FEE
    );

    marketContracts = marketReport.toContractsReport();
    ghoContracts = ghoReport.toGhoContracts();

    vm.startPrank(roles.marketOwner);
    ghoContracts.ghoToken.grantRole(ghoContracts.ghoToken.FACILITATOR_MANAGER_ROLE(), poolAdmin);
    ghoContracts.ghoToken.grantRole(ghoContracts.ghoToken.BUCKET_MANAGER_ROLE(), poolAdmin);
    vm.stopPrank();

    AaveV3GhoTestListing aaveV3GhoTestListing = new AaveV3GhoTestListing(
      IAaveV3ConfigEngine(marketReport.configEngine),
      roles.poolAdmin,
      tokenList.weth,
      marketReport,
      ghoReport
    );

    ACLManager manager = ACLManager(marketReport.aclManager);

    vm.prank(roles.poolAdmin);
    manager.addPoolAdmin(address(aaveV3GhoTestListing));

    aaveV3GhoTestListing.execute();

    tokenList = TokenList({
      wbtc: aaveV3GhoTestListing.WBTC_ADDRESS(),
      weth: aaveV3GhoTestListing.WETH_ADDRESS(),
      usdx: aaveV3GhoTestListing.USDX_ADDRESS(),
      aave: aaveV3GhoTestListing.AAVE_ADDRESS(),
      stkAave: aaveV3GhoTestListing.getStkAaveAddress(),
      gho: aaveV3GhoTestListing.GHO_ADDRESS()
    });

    vm.label(tokenList.wbtc, 'WBTC');
    vm.label(tokenList.weth, 'WETH');
    vm.label(tokenList.usdx, 'USDX');
    vm.label(tokenList.aave, 'AAVE');
    vm.label(tokenList.stkAave, 'STKAAVE');
    vm.label(tokenList.gho, 'GHO');

    _configureGho(roles.poolAdmin);

    if (mintUserTokens) {
      address[3] memory users = [alice, bob, charlie];
      for (uint256 i = 0; i < users.length; i += 1) {
        _mintUserTokens(users[i]);
        _approvePool(users[i]);
      }
    }

    vm.recordLogs();
  }

  function _mintUserTokens(address user) internal {
    // mint usdx
    vm.prank(roles.poolAdmin);
    TestnetERC20(tokenList.usdx).mint(user, 1000e6);

    // mint wbtc
    vm.prank(roles.poolAdmin);
    TestnetERC20(tokenList.wbtc).mint(user, 1000e8);

    // mint aave
    vm.prank(roles.poolAdmin);
    TestnetERC20(tokenList.aave).mint(user, 2000e18);

    // mint weth
    vm.deal(user, 1000 ether);
    vm.prank(user);
    WETH9(payable(tokenList.weth)).deposit{value: 1000 ether}();
  }

  function _approvePool(address user) internal {
    vm.startPrank(user);

    IERC20(tokenList.usdx).approve(address(marketContracts.poolProxy), type(uint256).max);
    IERC20(tokenList.wbtc).approve(address(marketContracts.poolProxy), type(uint256).max);
    IERC20(tokenList.aave).approve(address(marketContracts.poolProxy), type(uint256).max);
    IERC20(tokenList.weth).approve(address(marketContracts.poolProxy), type(uint256).max);

    vm.stopPrank();
  }

  function _configureGho(address poolAdmin) internal {
    vm.startPrank(poolAdmin);

    // Enable variable borrowing on GHO
    marketContracts.poolConfiguratorProxy.setReserveBorrowing(address(ghoContracts.ghoToken), true);

    // Set oracle for GHO in Aave Oracle
    address[] memory assets = new address[](1);
    assets[0] = address(ghoContracts.ghoToken);
    address[] memory sources = new address[](1);
    sources[0] = address(ghoContracts.ghoOracle);
    marketContracts.aaveOracle.setAssetSources(assets, sources);

    // Add Aave as a GHO entity
    (address reserveATokenAddress, , address reserveVariableDebtTokenAddress) = marketContracts
      .protocolDataProvider
      .getReserveTokensAddresses(address(ghoContracts.ghoToken));
    ghoContracts.ghoToken.addFacilitator(
      reserveATokenAddress,
      AAVE_FACILITATOR_LABEL,
      AAVE_FACILITATOR_CAPACITY
    );

    // Add FlashMinter as a GHO entity
    ghoContracts.ghoToken.addFacilitator(
      address(ghoContracts.ghoFlashMinter),
      FLASH_MINTER_LABEL,
      FLASH_MINTER_CAPACITY
    );

    // Set required addresses in GhoAToken and GhoVariableDebtToken
    ghoAToken = GhoAToken(reserveATokenAddress);
    ghoVariableDebtToken = GhoVariableDebtToken(reserveVariableDebtTokenAddress);
    ghoAToken.updateGhoTreasury(address(marketContracts.treasury));
    ghoAToken.setVariableDebtToken(reserveVariableDebtTokenAddress);
    ghoVariableDebtToken.setAToken(reserveATokenAddress);
    ghoVariableDebtToken.updateDiscountRateStrategy(address(ghoContracts.ghoDiscountRateStrategy));
    ghoVariableDebtToken.updateDiscountToken(tokenList.stkAave);

    vm.stopPrank();
  }

  function assertEventNotEmitted(bytes32 eventSignature) internal {
    Vm.Log[] memory entries = vm.getRecordedLogs();
    for (uint256 i; i < entries.length; i++) {
      assertNotEq(entries[i].topics[0], eventSignature);
    }

    vm.recordLogs();
  }

  function getExpectedBorrowIndex() internal view returns (uint256) {
    DataTypes.ReserveDataLegacy memory poolData = marketContracts.poolProxy.getReserveData(
      address(ghoContracts.ghoToken)
    );

    uint256 multiplier = MathUtils.calculateCompoundedInterest(
      poolData.currentVariableBorrowRate,
      poolData.lastUpdateTimestamp,
      block.timestamp
    );

    return uint256(poolData.variableBorrowIndex).rayMul(multiplier);
  }

  function calculateDiscountRate(
    uint256 discountRate,
    uint256 ghoDiscountedPerDiscountToken,
    uint256 minDiscountTokenBalance,
    uint256 debtBalance,
    uint256 discountTokenBalance
  ) internal pure returns (uint256) {
    if (discountTokenBalance < minDiscountTokenBalance || debtBalance == 0) {
      return 0;
    }

    uint256 discountedAmount = discountTokenBalance.wadMul(ghoDiscountedPerDiscountToken);
    if (discountedAmount >= debtBalance) {
      return discountRate;
    }

    return (discountedAmount * discountRate) / debtBalance;
  }

  function getProxyImplementationAddress(address proxy) internal view returns (address) {
    bytes32 implSlot = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);
    return address(uint160(uint256(implSlot)));
  }
}
