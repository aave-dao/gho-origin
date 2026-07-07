// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ProxyAdmin} from 'openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol';
import {ITransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {sGho} from 'src/contracts/sgho/sGho.sol';
import {sGhoInstance} from 'src/contracts/sgho/instances/sGhoInstance.sol';
import {sGhoInstanceStoragePatch} from 'src/contracts/sgho/instances/sGhoInstanceStoragePatch.sol';

/// @dev Rate setter of the pre-upgrade implementation, removed from the current interface
interface IsGhoLegacy {
  function setTargetRate(uint16 newRate) external;
}

/// @dev Forks Ethereum mainnet and verifies the storage-layout migration of the live sGHO instance.
contract sGhoInstanceStoragePatchForkTest is Test {
  using SafeCast for uint256;

  address internal constant PROXY = 0xE1753F2e00940cC31213dd92013cF019DFE4ca1d;
  address internal constant PROXY_ADMIN = 0xc15700631020Eba02317964550365B95a9a28aDb;
  address internal constant OWNER = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; // owns PROXY_ADMIN, is DEFAULT_ADMIN
  address internal constant HOLDER = 0x1eb3bef5C90B848ce1f848B1f31Dac068Fa54e9B; // active position

  bytes32 internal constant STORAGE_LOCATION =
    0x52190d4bcaca04cac5a7c2ae78ea3854d285be3b91819fb1b3ed9862d9a9a400;

  uint256 internal constant FORK_BLOCK = 25430761;

  sGho internal sgho = sGho(PROXY);
  bool internal forked;

  function setUp() external {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) return;
    vm.createSelectFork(rpc, FORK_BLOCK);
    forked = true;
  }

  modifier onlyForked() {
    vm.skip(!forked);
    _;
  }

  /// @dev Re-sets the same rate, only to checkpoint the yield index before the layout changes.
  function _checkpoint() internal {
    vm.startPrank(OWNER);
    // OWNER is DEFAULT_ADMIN; grant itself YIELD_MANAGER so it can checkpoint the index
    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), OWNER);
    IsGhoLegacy(PROXY).setTargetRate(sgho.targetRate());
    vm.stopPrank();
  }

  /// @dev Swaps the implementation for the storage patch (atomic with its `initialize`).
  function _patch() internal {
    address newImpl = address(new sGhoInstanceStoragePatch());
    vm.prank(OWNER);
    ProxyAdmin(PROXY_ADMIN).upgradeAndCall(
      ITransparentUpgradeableProxy(PROXY),
      newImpl,
      abi.encodeCall(sGhoInstanceStoragePatch.initialize, ())
    );
  }

  /// @dev Swaps the patch for the canonical implementation, atomically re-initializing at the
  /// final revision with the just-migrated values.
  function _finalize() internal {
    address newImpl = address(new sGhoInstance());
    bytes memory data = abi.encodeCall(
      sGhoInstance.initialize,
      (
        sgho.GHO(),
        sgho.supplyCap().toUint40(),
        OWNER,
        sgho.yieldIndex().toUint120(),
        sgho.lastUpdate().toUint40(),
        sgho.targetRate()
      )
    );
    vm.prank(OWNER);
    ProxyAdmin(PROXY_ADMIN).upgradeAndCall(ITransparentUpgradeableProxy(PROXY), newImpl, data);
  }

  /// @dev Mirrors the governance upgrade: checkpoint the index, apply the storage patch, then
  /// swap to the canonical implementation.
  function _upgrade() internal {
    _checkpoint();
    _patch();
    _finalize();
  }

  function test_fork_upgrade_preservesStorageValues() external onlyForked {
    // Checkpoint first so the stored values reflect accrual up to now and are written to storage
    _checkpoint();

    uint256 yieldIndexBefore = sgho.yieldIndex();
    uint256 lastUpdateBefore = sgho.lastUpdate();
    uint16 targetRateBefore = sgho.targetRate();
    uint256 supplyCapBefore = sgho.supplyCap(); // asset terms in the old layout

    _patch();

    // Every affected field survives the upgrade unchanged (supplyCap is converted to whole units)
    assertEq(sgho.yieldIndex(), yieldIndexBefore, 'yieldIndex changed');
    assertEq(sgho.lastUpdate(), lastUpdateBefore, 'lastUpdate changed');
    assertEq(sgho.targetRate(), targetRateBefore, 'targetRate changed');
    assertEq(sgho.supplyCap(), supplyCapBefore / 10 ** sgho.decimals(), 'supplyCap not converted');
  }

  function test_fork_upgrade_preservesPosition() external onlyForked {
    uint256 sharesBefore = sgho.balanceOf(HOLDER);
    assertGt(sharesBefore, 0, 'holder should have an active position');
    uint256 assetsBefore = sgho.convertToAssets(sharesBefore);
    uint256 totalSupplyBefore = sgho.totalSupply();
    uint16 rateBefore = sgho.targetRate();
    uint256 supplyCapBefore = sgho.supplyCap(); // asset terms in the old layout

    _upgrade();

    // The holder's position is consistent across the upgrade
    assertEq(sgho.balanceOf(HOLDER), sharesBefore, 'shares changed');
    assertApproxEqAbs(sgho.convertToAssets(sharesBefore), assetsBefore, 1, 'asset value changed');
    assertEq(sgho.totalSupply(), totalSupplyBefore, 'totalSupply changed');

    // Migrated fields are correct in the new layout
    assertEq(sgho.targetRate(), rateBefore, 'targetRate not preserved');
    assertEq(
      sgho.supplyCap(),
      supplyCapBefore / 10 ** sgho.decimals(),
      'supplyCap not converted to whole units'
    );

    // The repacked layout uses only the low 216 bits of slot 0 (uint120 + uint40 + uint16 + uint40);
    // the unused high bits must be clear of any leftover from the old layout
    assertEq(
      uint256(vm.load(PROXY, STORAGE_LOCATION)) >> 216,
      0,
      'unused bits of slot 0 not cleared'
    );

    // The orphaned second slot of the old layout is wiped
    bytes32 slot1 = bytes32(uint256(STORAGE_LOCATION) + 1);
    assertEq(vm.load(PROXY, slot1), bytes32(0), 'old slot 1 not cleared');
  }

  function test_fork_patch_revertsIfIndexNotCheckpointed() external onlyForked {
    // Move past the last checkpoint so the patch must refuse to migrate
    vm.warp(block.timestamp + 1);

    address newImpl = address(new sGhoInstanceStoragePatch());
    vm.prank(OWNER);
    vm.expectRevert(sGhoInstanceStoragePatch.YieldIndexNotCheckpointed.selector);
    ProxyAdmin(PROXY_ADMIN).upgradeAndCall(
      ITransparentUpgradeableProxy(PROXY),
      newImpl,
      abi.encodeCall(sGhoInstanceStoragePatch.initialize, ())
    );
  }

  function test_fork_upgrade_initializeLocked() external onlyForked {
    address gho = sgho.asset();

    _upgrade();

    // The final swap consumed SGHO_REVISION, so the initializer is not callable again
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    sGhoInstance(PROXY).initialize(
      gho,
      0,
      address(this),
      uint120(1e27),
      block.timestamp.toUint40(),
      0
    );
  }

  function test_fork_postUpgrade_existingUserAccruesLinearly() external onlyForked {
    _upgrade();

    uint256 ray = 1e27;
    uint16 rate = sgho.targetRate();
    uint256 shares = sgho.balanceOf(HOLDER);

    uint256 indexBefore = sgho.convertToAssets(ray);
    uint256 assetsBefore = sgho.convertToAssets(shares);

    vm.warp(block.timestamp + 365 days);

    // The index grows linearly by exactly `rate` over a year (no compounding)
    assertEq(
      sgho.convertToAssets(ray),
      indexBefore + (uint256(rate) * ray) / 10000,
      'index not linear'
    );

    // The existing holder accrues that linear yield on their shares
    assertApproxEqAbs(
      sgho.convertToAssets(shares) - assetsBefore,
      (shares * rate) / 10000,
      2,
      'existing user accrual not linear'
    );
  }

  function test_fork_postUpgrade_newUserAccruesLinearly() external onlyForked {
    _upgrade();

    address newUser = makeAddr('newUser');
    uint256 depositAmount = 10_000e18;
    deal(sgho.asset(), newUser, depositAmount);

    vm.startPrank(newUser);
    IERC20(sgho.asset()).approve(address(sgho), depositAmount);
    uint256 shares = sgho.deposit(depositAmount, newUser);
    vm.stopPrank();

    uint16 rate = sgho.targetRate();
    uint256 assetsBefore = sgho.convertToAssets(shares);

    vm.warp(block.timestamp + 365 days);

    // A position opened after the upgrade accrues the same linear yield
    assertApproxEqAbs(
      sgho.convertToAssets(shares) - assetsBefore,
      (shares * rate) / 10000,
      2,
      'new user accrual not linear'
    );
  }

  function test_fork_upgrade_holderCanRedeem() external onlyForked {
    _upgrade();

    uint256 shares = sgho.balanceOf(HOLDER) / 10;
    assertLe(shares, sgho.maxRedeem(HOLDER), 'insufficient redeemable liquidity');

    uint256 ghoBefore = IERC20(sgho.asset()).balanceOf(HOLDER);
    uint256 expected = sgho.previewRedeem(shares);

    vm.prank(HOLDER);
    uint256 assets = sgho.redeem(shares, HOLDER, HOLDER);

    assertEq(assets, expected, 'redeem returned unexpected assets');
    assertEq(IERC20(sgho.asset()).balanceOf(HOLDER), ghoBefore + assets, 'GHO not received');
  }
}
