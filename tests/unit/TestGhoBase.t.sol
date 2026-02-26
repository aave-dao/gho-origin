// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import 'forge-std/console2.sol';
import {Vm} from 'forge-std/Vm.sol';

// dependencies
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';
import {AutomationCompatibleInterface} from 'src/contracts/dependencies/chainlink/AutomationCompatibleInterface.sol';

// helpers
import {Constants} from '../helpers/Constants.sol';
import {DebtUtils} from '../helpers/DebtUtils.sol';
import {Events} from '../helpers/Events.sol';
import {AccessControlErrorsLib, OwnableErrorsLib} from '../helpers/ErrorsLib.sol';
import {EIP712Types} from '../helpers/EIP712Types.sol';

// generic libs
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';
import {SafeCast} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

// mocks
import {MockAclManager} from '../mocks/MockAclManager.sol';
import {MockConfigurator} from '../mocks/MockConfigurator.sol';
import {MockFlashBorrower} from '../mocks/MockFlashBorrower.sol';
import {MockGsmV2} from '../mocks/MockGsmV2.sol';
import {MockPool} from '../mocks/MockPool.sol';
import {MockAddressesProvider} from '../mocks/MockAddressesProvider.sol';
import {MockERC4626} from '../mocks/MockERC4626.sol';
import {MockUpgradeable} from '../mocks/MockUpgradeable.sol';
import {PriceOracle} from 'aave-v3-origin/contracts/mocks/oracle/PriceOracle.sol';
import {TestnetERC20} from 'aave-v3-origin/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {WETH9Mock} from 'aave-v3-origin/contracts/mocks/WETH9Mock.sol';
import {MockPoolDataProvider} from '../mocks/MockPoolDataProvider.sol';

// interfaces
import {IERC20} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC3156FlashBorrower} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol';
import {IERC3156FlashLender} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {IDefaultInterestRateStrategyV2} from 'aave-v3-origin/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';

// non-GHO contracts
import {AdminUpgradeabilityProxy} from 'aave-v3-origin/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol';
import {ERC20} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/ERC20.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {TransparentUpgradeableProxy} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {DefaultReserveInterestRateStrategyV2} from 'aave-v3-origin/contracts/misc/DefaultReserveInterestRateStrategyV2.sol';

// GHO contracts
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';
import {GhoAaveSteward} from 'src/contracts/misc/GhoAaveSteward.sol';
import {GhoOracle} from 'src/contracts/misc/GhoOracle.sol';
import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {UpgradeableGhoToken} from 'src/contracts/gho/UpgradeableGhoToken.sol';

// GSM contracts
import {IGsm} from 'src/contracts/facilitators/gsm/interfaces/IGsm.sol';
import {Gsm} from 'src/contracts/facilitators/gsm/Gsm.sol';
import {Gsm4626} from 'src/contracts/facilitators/gsm/Gsm4626.sol';
import {FixedPriceStrategy} from 'src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol';
import {FixedPriceStrategy4626} from 'src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy4626.sol';
import {IGsmFeeStrategy} from 'src/contracts/facilitators/gsm/feeStrategy/interfaces/IGsmFeeStrategy.sol';
import {FixedFeeStrategy} from 'src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol';
import {SampleLiquidator} from 'src/contracts/facilitators/gsm/misc/SampleLiquidator.sol';
import {SampleSwapFreezer} from 'src/contracts/facilitators/gsm/misc/SampleSwapFreezer.sol';
import {GsmRegistry} from 'src/contracts/facilitators/gsm/misc/GsmRegistry.sol';
import {IGhoGsmSteward} from 'src/contracts/misc/interfaces/IGhoGsmSteward.sol';
import {GhoGsmSteward} from 'src/contracts/misc/GhoGsmSteward.sol';
import {FixedFeeStrategyFactory} from 'src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategyFactory.sol';
import {GhoReserve} from 'src/contracts/facilitators/gsm/GhoReserve.sol';
import {GhoDirectFacilitator} from 'src/contracts/facilitators/gsm/GhoDirectFacilitator.sol';
import {OracleSwapFreezerBase} from 'src/contracts/facilitators/gsm/swapFreezer/OracleSwapFreezerBase.sol';
import {ChainlinkOracleSwapFreezer} from 'src/contracts/facilitators/gsm/swapFreezer/ChainlinkOracleSwapFreezer.sol';
import {GelatoOracleSwapFreezer} from 'src/contracts/facilitators/gsm/swapFreezer/GelatoOracleSwapFreezer.sol';
import {IGelatoOracleSwapFreezer} from 'src/contracts/facilitators/gsm/swapFreezer/interfaces/IGelatoOracleSwapFreezer.sol';

// CCIP contracts
import {MockUpgradeableLockReleaseTokenPool} from '../mocks/MockUpgradeableLockReleaseTokenPool.sol';
import {RateLimiter} from 'src/contracts/dependencies/ccip/Ccip.sol';
import {GhoCcipSteward} from 'src/contracts/misc/GhoCcipSteward.sol';
import {GhoBucketSteward} from 'src/contracts/misc/GhoBucketSteward.sol';

contract TestGhoBase is Test, Constants, Events {
  using WadRayMath for uint256;
  using SafeCast for uint256;
  using PercentageMath for uint256;

  bytes32 public constant PERMIT_TYPEHASH =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  GhoToken GHO_TOKEN;
  TestnetERC20 AAVE_TOKEN;
  TestnetERC20 USDX_TOKEN;
  MockERC4626 USDX_4626_TOKEN;
  MockPool POOL;
  MockAclManager ACL_MANAGER;
  MockAddressesProvider PROVIDER;
  MockConfigurator CONFIGURATOR;
  PriceOracle PRICE_ORACLE;
  WETH9Mock WETH;
  GhoFlashMinter GHO_FLASH_MINTER;
  MockFlashBorrower FLASH_BORROWER;
  Gsm GHO_GSM;
  Gsm4626 GHO_GSM_4626;
  FixedPriceStrategy GHO_GSM_FIXED_PRICE_STRATEGY;
  FixedPriceStrategy4626 GHO_GSM_4626_FIXED_PRICE_STRATEGY;
  FixedFeeStrategy GHO_GSM_FIXED_FEE_STRATEGY;
  SampleLiquidator GHO_GSM_LAST_RESORT_LIQUIDATOR;
  SampleSwapFreezer GHO_GSM_SWAP_FREEZER;
  GsmRegistry GHO_GSM_REGISTRY;
  GhoOracle GHO_ORACLE;
  GhoAaveSteward GHO_AAVE_STEWARD;
  GhoCcipSteward GHO_CCIP_STEWARD;
  GhoGsmSteward GHO_GSM_STEWARD;
  GhoBucketSteward GHO_BUCKET_STEWARD;
  MockPoolDataProvider MOCK_POOL_DATA_PROVIDER;

  FixedFeeStrategyFactory FIXED_FEE_STRATEGY_FACTORY;
  MockUpgradeableLockReleaseTokenPool GHO_TOKEN_POOL;

  GhoReserve GHO_RESERVE;
  GhoDirectFacilitator GHO_DIRECT_FACILITATOR;

  constructor() {
    setupGho();
  }

  function test_coverage_ignore() public virtual {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }

  function setupGho() public {
    ACL_MANAGER = new MockAclManager();
    PROVIDER = new MockAddressesProvider(address(ACL_MANAGER));
    MOCK_POOL_DATA_PROVIDER = new MockPoolDataProvider(address(PROVIDER));

    POOL = new MockPool(IPoolAddressesProvider(address(PROVIDER)));
    CONFIGURATOR = new MockConfigurator(IPool(address(POOL)));
    PRICE_ORACLE = new PriceOracle();
    PROVIDER.setPool(address(POOL));
    PROVIDER.setConfigurator(address(CONFIGURATOR));
    PROVIDER.setPriceOracle(address(PRICE_ORACLE));
    GHO_ORACLE = new GhoOracle();
    GHO_TOKEN = new GhoToken(address(this));
    GHO_TOKEN.grantRole(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, address(this));
    GHO_TOKEN.grantRole(GHO_TOKEN_BUCKET_MANAGER_ROLE, address(this));
    AAVE_TOKEN = new TestnetERC20('AAVE', 'AAVE', 18, FAUCET);
    USDX_TOKEN = new TestnetERC20('USD Coin', 'USDX', 6, FAUCET);
    USDX_4626_TOKEN = new MockERC4626('USD Coin 4626', '4626', address(USDX_TOKEN));
    WETH = new WETH9Mock('Wrapped Ether', 'WETH', FAUCET);

    GHO_RESERVE = _deployReserve();

    GHO_DIRECT_FACILITATOR = new GhoDirectFacilitator(address(this), address(GHO_TOKEN));
    // Give GhoDirectFacilitator twice the default capacity to fully fund two GSMs
    GHO_TOKEN.addFacilitator(
      address(GHO_DIRECT_FACILITATOR),
      'GhoDirectFacilitator',
      DEFAULT_CAPACITY * 2
    );

    GHO_FLASH_MINTER = new GhoFlashMinter(
      address(GHO_TOKEN),
      TREASURY,
      DEFAULT_FLASH_FEE,
      address(PROVIDER)
    );
    FLASH_BORROWER = new MockFlashBorrower(IERC3156FlashLender(GHO_FLASH_MINTER));

    GHO_TOKEN.addFacilitator(address(GHO_FLASH_MINTER), 'Flash Minter', DEFAULT_CAPACITY);
    GHO_TOKEN.addFacilitator(address(FLASH_BORROWER), 'Gho Flash Borrower', DEFAULT_CAPACITY);

    GHO_GSM_FIXED_PRICE_STRATEGY = new FixedPriceStrategy(
      DEFAULT_FIXED_PRICE,
      address(USDX_TOKEN),
      6
    );
    GHO_GSM_4626_FIXED_PRICE_STRATEGY = new FixedPriceStrategy4626(
      DEFAULT_FIXED_PRICE,
      address(USDX_4626_TOKEN),
      6
    );
    GHO_GSM_LAST_RESORT_LIQUIDATOR = new SampleLiquidator();
    GHO_GSM_SWAP_FREEZER = new SampleSwapFreezer();
    GHO_GSM = _deployGsmProxy({
      underlyingToken: address(USDX_TOKEN),
      priceStrategy: address(GHO_GSM_FIXED_PRICE_STRATEGY),
      exposureCap: DEFAULT_GSM_USDX_EXPOSURE,
      admin: address(this)
    });

    GHO_GSM_4626 = _deployGsm4626Proxy({
      underlyingToken: address(USDX_4626_TOKEN),
      priceStrategy: address(GHO_GSM_4626_FIXED_PRICE_STRATEGY),
      exposureCap: DEFAULT_GSM_USDX_EXPOSURE
    });

    GHO_RESERVE.addEntity(address(GHO_GSM));
    GHO_RESERVE.addEntity(address(GHO_GSM_4626));
    GHO_RESERVE.setLimit(address(GHO_GSM), DEFAULT_CAPACITY);
    GHO_RESERVE.setLimit(address(GHO_GSM_4626), DEFAULT_CAPACITY);

    // Mint twice default capacity for both GSMs to be fully funded
    GHO_DIRECT_FACILITATOR.mint(address(GHO_RESERVE), DEFAULT_CAPACITY * 2);

    GHO_GSM_FIXED_FEE_STRATEGY = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE);
    GHO_GSM.updateFeeStrategy(address(GHO_GSM_FIXED_FEE_STRATEGY));
    GHO_GSM_4626.updateFeeStrategy(address(GHO_GSM_FIXED_FEE_STRATEGY));

    GHO_GSM.grantRole(GSM_LIQUIDATOR_ROLE, address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
    GHO_GSM.grantRole(GSM_SWAP_FREEZER_ROLE, address(GHO_GSM_SWAP_FREEZER));
    GHO_GSM_4626.grantRole(GSM_LIQUIDATOR_ROLE, address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
    GHO_GSM_4626.grantRole(GSM_SWAP_FREEZER_ROLE, address(GHO_GSM_SWAP_FREEZER));

    GHO_TOKEN.addFacilitator(FAUCET, 'Faucet Facilitator', type(uint128).max);

    GHO_GSM_REGISTRY = new GsmRegistry(address(this));

    // Deploy Gho Token Pool
    address ARM_PROXY = makeAddr('ARM_PROXY');
    address OWNER = makeAddr('OWNER');
    address ROUTER = makeAddr('ROUTER');
    address PROXY_ADMIN_OWNER = makeAddr('PROXY_ADMIN_OWNER');
    uint256 INITIAL_BRIDGE_LIMIT = 100e6 * 1e18;
    MockUpgradeableLockReleaseTokenPool tokenPoolImpl = new MockUpgradeableLockReleaseTokenPool(
      address(GHO_TOKEN),
      ARM_PROXY,
      false,
      true
    );
    // proxy deploy and init
    address[] memory emptyArray = new address[](0);
    bytes memory tokenPoolInitParams = abi.encodeCall(
      MockUpgradeableLockReleaseTokenPool.initialize,
      (OWNER, emptyArray, ROUTER, INITIAL_BRIDGE_LIMIT)
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      PROXY_ADMIN_OWNER,
      tokenPoolInitParams
    );

    // Manage ownership
    vm.prank(OWNER);
    MockUpgradeableLockReleaseTokenPool(address(tokenPoolProxy)).acceptOwnership();
    GHO_TOKEN_POOL = MockUpgradeableLockReleaseTokenPool(address(tokenPoolProxy));

    // Setup GHO Token Pool
    uint64 DEST_CHAIN_SELECTOR = 2;
    RateLimiter.Config memory initialOutboundRateLimit = RateLimiter.Config({
      isEnabled: true,
      capacity: 100e28,
      rate: 1e15
    });
    RateLimiter.Config memory initialInboundRateLimit = RateLimiter.Config({
      isEnabled: true,
      capacity: 222e30,
      rate: 1e18
    });
    MockUpgradeableLockReleaseTokenPool.ChainUpdate[]
      memory chainUpdate = new MockUpgradeableLockReleaseTokenPool.ChainUpdate[](1);
    chainUpdate[0] = MockUpgradeableLockReleaseTokenPool.ChainUpdate({
      remoteChainSelector: DEST_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: initialOutboundRateLimit,
      inboundRateLimiterConfig: initialInboundRateLimit
    });
    vm.prank(OWNER);
    GHO_TOKEN_POOL.applyChainUpdates(chainUpdate);
  }

  function ghoFaucet(address to, uint256 amount) public {
    vm.prank(FAUCET);
    GHO_TOKEN.mint(to, amount);
  }

  function _deployGsmProxy(
    address underlyingToken,
    address priceStrategy,
    uint128 exposureCap
  ) internal returns (Gsm) {
    return
      _deployGsmProxy({
        underlyingToken: underlyingToken,
        priceStrategy: priceStrategy,
        exposureCap: exposureCap,
        admin: address(this)
      });
  }

  function _deployGsmProxy(
    address underlyingToken,
    address priceStrategy,
    uint128 exposureCap,
    address admin
  ) internal returns (Gsm) {
    return
      _deployGsmProxy({
        underlyingToken: underlyingToken,
        priceStrategy: priceStrategy,
        exposureCap: exposureCap,
        admin: admin,
        reserve: address(GHO_RESERVE)
      });
  }

  function _deployGsmProxy(
    address underlyingToken,
    address priceStrategy,
    uint128 exposureCap,
    address admin,
    address reserve
  ) internal returns (Gsm) {
    Gsm gsmImpl = new Gsm(address(GHO_TOKEN), underlyingToken, priceStrategy);
    AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(
      address(gsmImpl),
      SHORT_EXECUTOR,
      abi.encodeWithSignature(
        'initialize(address,address,uint128,address)',
        admin,
        TREASURY,
        exposureCap,
        reserve
      )
    );
    return Gsm(address(gsmProxy));
  }

  function _deployGsm4626Proxy(
    address underlyingToken,
    address priceStrategy,
    uint128 exposureCap
  ) internal returns (Gsm4626) {
    Gsm4626 gsmImpl = new Gsm4626(address(GHO_TOKEN), underlyingToken, priceStrategy);
    AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(
      address(gsmImpl),
      SHORT_EXECUTOR,
      abi.encodeWithSignature(
        'initialize(address,address,uint128,address)',
        address(this),
        TREASURY,
        exposureCap,
        address(GHO_RESERVE)
      )
    );
    return Gsm4626(address(gsmProxy));
  }

  function _deployReserve() public returns (GhoReserve) {
    address proxyAdmin = makeAddr('PROXY_ADMIN');

    GhoReserve reserveImpl = new GhoReserve(address(GHO_TOKEN));

    bytes memory ghoReserveInitParams = abi.encodeWithSignature(
      'initialize(address)',
      address(this)
    );

    TransparentUpgradeableProxy reserveProxy = new TransparentUpgradeableProxy(
      address(reserveImpl),
      proxyAdmin,
      ghoReserveInitParams
    );

    return GhoReserve(address(reserveProxy));
  }

  /// Helper function to sell asset in the GSM
  function _sellAsset(
    Gsm gsm,
    TestnetERC20 token,
    address receiver,
    uint256 amount
  ) internal returns (uint256) {
    vm.startPrank(FAUCET);
    token.mint(FAUCET, amount);
    token.approve(address(gsm), amount);
    (, uint256 ghoBought) = gsm.sellAsset(amount, receiver);
    vm.stopPrank();
    return ghoBought;
  }

  /// Helper function to mint an amount of assets of an ERC4626 token
  function _mintVaultAssets(
    MockERC4626 vault,
    TestnetERC20 token,
    address receiver,
    uint256 amount
  ) internal {
    vm.startPrank(FAUCET);
    token.mint(FAUCET, amount);
    token.approve(address(vault), amount);
    vault.deposit(amount, receiver);
    vm.stopPrank();
  }

  /// Helper function to mint an amount of shares of an ERC4626 token
  function _mintVaultShares(
    MockERC4626 vault,
    TestnetERC20 token,
    address receiver,
    uint256 sharesAmount
  ) internal {
    uint256 assets = vault.previewMint(sharesAmount);
    vm.startPrank(FAUCET);
    token.mint(FAUCET, assets);
    token.approve(address(vault), assets);
    vault.deposit(assets, receiver);
    vm.stopPrank();
  }

  /// Helper function to sell shares of an ERC4626 token in the GSM
  function _sellAsset(
    Gsm4626 gsm,
    MockERC4626 vault,
    TestnetERC20 token,
    address receiver,
    uint256 amount
  ) internal returns (uint256) {
    uint256 assetsToMint = vault.previewRedeem(amount);
    _mintVaultAssets(vault, token, address(this), assetsToMint);
    vault.approve(address(gsm), amount);
    (, uint256 ghoBought) = gsm.sellAsset(amount, receiver);
    return ghoBought;
  }

  /// Helper function to alter the exchange rate between shares and assets in a ERC4626 vault
  function _changeExchangeRate(
    MockERC4626 vault,
    TestnetERC20 token,
    uint256 amount,
    bool inflate
  ) internal {
    if (inflate) {
      // Inflate
      vm.prank(FAUCET);
      token.mint(address(vault), amount);
    } else {
      // Deflate
      vm.prank(address(vault));
      token.transfer(address(1), amount);
    }
  }

  function _contains(address[] memory list, address item) internal pure returns (bool) {
    for (uint256 i = 0; i < list.length; i++) {
      if (list[i] == item) {
        return true;
      }
    }
    return false;
  }

  function getProxyAdminAddress(address proxy) internal view returns (address) {
    bytes32 adminSlot = vm.load(proxy, ERC1967_ADMIN_SLOT);
    return address(uint160(uint256(adminSlot)));
  }

  function getProxyImplementationAddress(address proxy) internal view returns (address) {
    bytes32 implSlot = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);
    return address(uint160(uint256(implSlot)));
  }

  function getPermitSignature(
    address owner,
    uint256 ownerPk,
    address spender,
    uint256 value,
    uint256 nonce,
    uint256 deadline
  ) public view returns (uint8 v, bytes32 r, bytes32 s) {
    bytes32 innerHash = keccak256(
      abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
    );
    bytes32 outerHash = keccak256(
      abi.encodePacked('\x19\x01', GHO_TOKEN.DOMAIN_SEPARATOR(), innerHash)
    );
    (v, r, s) = vm.sign(ownerPk, outerHash);
  }

  function _getBuyAssetTypedDataHash(
    EIP712Types.BuyAssetWithSig memory params
  ) internal view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          '\x19\x01',
          GHO_GSM.DOMAIN_SEPARATOR(),
          vm.eip712HashStruct('BuyAssetWithSig', abi.encode(params))
        )
      );
  }

  function _getSellAssetTypedDataHash(
    EIP712Types.SellAssetWithSig memory params
  ) internal view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          '\x19\x01',
          GHO_GSM.DOMAIN_SEPARATOR(),
          vm.eip712HashStruct('SellAssetWithSig', abi.encode(params))
        )
      );
  }
}
