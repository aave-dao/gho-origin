// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {AccessManager} from 'openzeppelin-contracts/contracts/access/manager/AccessManager.sol';
import {IAccessManaged} from 'openzeppelin-contracts/contracts/access/manager/IAccessManaged.sol';
import {TestnetERC20} from 'aave-v3-origin/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {GhoReserve} from 'src/contracts/facilitators/gsm/GhoReserve.sol';
import {GhoSwapFacility} from 'src/contracts/facilitators/swap/GhoSwapFacility.sol';
import {IGhoSwapFacility} from 'src/contracts/facilitators/swap/interfaces/IGhoSwapFacility.sol';
import {MockERC4626} from '../mocks/MockERC4626.sol';

contract TestGhoSwapFacility is Test {
  uint64 constant FROZEN_ROLE = 42;
  uint128 constant RESERVE_LIMIT = 1_000_000e18;

  address constant TREASURY = address(0x7EA5);
  address constant ALICE = address(0xA11CE);
  address constant BOB = address(0xB0B);
  address constant ACTOR = address(0xAC70);

  AccessManager manager;
  TestnetERC20 gho;
  TestnetERC20 usdx;
  MockERC4626 vault;
  GhoReserve reserve;
  GhoSwapFacility facility;
  address PUBLIC;

  function setUp() public {
    manager = new AccessManager(address(this));
    gho = new TestnetERC20('GHO', 'GHO', 18, address(this));
    usdx = new TestnetERC20('USDX', 'USDX', 6, address(this));
    vault = new MockERC4626('USDX vault', 'vUSDX', address(usdx));

    reserve = GhoReserve(
      address(
        new TransparentUpgradeableProxy(
          address(new GhoReserve(address(gho))),
          makeAddr('PROXY_ADMIN'),
          abi.encodeCall(GhoReserve.initialize, (address(this)))
        )
      )
    );
    gho.mint(address(reserve), RESERVE_LIMIT);

    facility = new GhoSwapFacility(
      address(manager),
      address(gho),
      address(vault),
      address(reserve),
      TREASURY
    );
    reserve.addEntity(address(facility));
    reserve.setLimit(address(facility), RESERVE_LIMIT);

    _setSwapRole(manager.PUBLIC_ROLE());
    PUBLIC = facility.PUBLIC_POOL();
    facility.setPoolCap(PUBLIC, 1_000e18);
  }

  // ---------------------------------------------------------------- swaps

  function test_swapSharesForGho() public {
    facility.setFeeTier(PUBLIC, 100, 0); // 1% market fee
    uint256 shares = _shares(ALICE, 100e6);

    uint256 out = _swapShares(ALICE, PUBLIC, shares);

    assertEq(out, 99e18);
    assertEq(gho.balanceOf(ALICE), 99e18);
    assertEq(facility.accruedFees(), 1e18);
    assertEq(facility.getPool(PUBLIC).used, 100e18);
    assertEq(facility.getPool(PUBLIC).shares, shares);
    assertEq(reserve.getUsed(address(facility)), 100e18);
  }

  function test_swapGhoForShares() public {
    facility.setFeeTier(PUBLIC, 0, 50); // 0.5% fee on GHO in
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 100e6));

    gho.mint(BOB, 50e18);
    uint256 out = _swapGho(BOB, PUBLIC, 50e18);

    assertEq(out, vault.convertToShares(49.75e6));
    assertEq(vault.balanceOf(BOB), out);
    assertEq(facility.accruedFees(), 0.25e18);
    assertEq(facility.getPool(PUBLIC).used, 100e18 - 49.75e18);
    assertEq(reserve.getUsed(address(facility)), 100e18 - 49.75e18);
  }

  function test_swap_revertsOnInvalidToken() public {
    vm.expectRevert(abi.encodeWithSelector(IGhoSwapFacility.InvalidToken.selector, address(usdx)));
    facility.swap(PUBLIC, address(usdx), 1, 0, ALICE);
  }

  function test_swap_revertsOnSlippage() public {
    uint256 shares = _shares(ALICE, 100e6);
    vm.startPrank(ALICE);
    vault.approve(address(facility), shares);
    vm.expectRevert(
      abi.encodeWithSelector(IGhoSwapFacility.SlippageExceeded.selector, 100e18, 101e18)
    );
    facility.swap(PUBLIC, address(vault), shares, 101e18, ALICE);
    vm.stopPrank();
  }

  function test_swap_revertsAboveCap() public {
    facility.setPoolCap(PUBLIC, 50e18);
    uint256 shares = _shares(ALICE, 100e6);
    vm.startPrank(ALICE);
    vault.approve(address(facility), shares);
    vm.expectRevert(
      abi.encodeWithSelector(IGhoSwapFacility.PoolCapExceeded.selector, PUBLIC, 100e18, 50e18)
    );
    facility.swap(PUBLIC, address(vault), shares, 0, ALICE);
    vm.stopPrank();
  }

  function test_swap_revertsWhenGhoInExceedsLiquidity() public {
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 10e6));
    gho.mint(BOB, 20e18);
    vm.startPrank(BOB);
    gho.approve(address(facility), 20e18);
    vm.expectRevert(
      abi.encodeWithSelector(IGhoSwapFacility.InsufficientLiquidity.selector, PUBLIC)
    );
    facility.swap(PUBLIC, address(gho), 20e18, 0, BOB);
    vm.stopPrank();
  }

  // ---------------------------------------------------------------- access

  function test_swap_frozenThroughAccessManager() public {
    _setSwapRole(FROZEN_ROLE);
    vm.prank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, ALICE)
    );
    facility.swap(PUBLIC, address(vault), 1, 0, ALICE);
  }

  function test_swap_permissionedThroughAccessManager() public {
    uint64 swapperRole = 7;
    _setSwapRole(swapperRole);
    manager.grantRole(swapperRole, ALICE, 0);
    facility.setPoolCap(PUBLIC, 1_000e18);

    _swapShares(ALICE, PUBLIC, _shares(ALICE, 1e6));

    uint256 shares = _shares(BOB, 1e6);
    vm.startPrank(BOB);
    vault.approve(address(facility), shares);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, BOB));
    facility.swap(PUBLIC, address(vault), shares, 0, BOB);
    vm.stopPrank();
  }

  function test_adminFunctions_restricted() public {
    vm.startPrank(ALICE);
    bytes memory err = abi.encodeWithSelector(
      IAccessManaged.AccessManagedUnauthorized.selector,
      ALICE
    );
    vm.expectRevert(err);
    facility.setPoolCap(PUBLIC, 1);
    vm.expectRevert(err);
    facility.setFeeTier(ALICE, 0, 0);
    vm.expectRevert(err);
    facility.clearFeeTier(ALICE);
    vm.expectRevert(err);
    facility.setTreasury(ALICE);
    vm.expectRevert(err);
    facility.seize(PUBLIC, ALICE);
    vm.expectRevert(err);
    facility.makePublic(ACTOR);
    vm.stopPrank();
  }

  // ---------------------------------------------------------------- private pools

  function test_privatePool_onlyOwnerCanSwap() public {
    facility.setPoolCap(ACTOR, 100e18);
    uint256 shares = _shares(ALICE, 10e6);
    vm.startPrank(ALICE);
    vault.approve(address(facility), shares);
    vm.expectRevert(
      abi.encodeWithSelector(IGhoSwapFacility.PoolAccessDenied.selector, ACTOR, ALICE)
    );
    facility.swap(ACTOR, address(vault), shares, 0, ALICE);
    vm.stopPrank();

    _swapShares(ACTOR, ACTOR, _shares(ACTOR, 10e6));
    assertEq(facility.getPool(ACTOR).used, 10e18);
    assertEq(facility.getPool(PUBLIC).used, 0);
  }

  function test_privatePool_ownerCanAlsoUsePublicPool() public {
    _swapShares(ACTOR, PUBLIC, _shares(ACTOR, 10e6));
    assertEq(facility.getPool(PUBLIC).used, 10e18);
  }

  function test_makePublic_mergesPool() public {
    facility.setPoolCap(ACTOR, 100e18);
    _swapShares(ACTOR, ACTOR, _shares(ACTOR, 40e6));
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 10e6));

    facility.makePublic(ACTOR);

    IGhoSwapFacility.Pool memory pub = facility.getPool(PUBLIC);
    assertEq(pub.used, 50e18);
    assertEq(pub.cap, 1_100e18);
    assertEq(facility.getPool(ACTOR).used, 0);
    assertEq(facility.getPool(ACTOR).cap, 0);
    assertEq(facility.getPool(ACTOR).shares, 0);

    // anyone can now take the liquidity the actor provided
    gho.mint(BOB, 45e18);
    _swapGho(BOB, PUBLIC, 45e18);
    assertEq(facility.getPool(PUBLIC).used, 5e18);
  }

  function test_makePublic_revertsForPublicPool() public {
    vm.expectRevert(IGhoSwapFacility.NotPrivatePool.selector);
    facility.makePublic(PUBLIC);
  }

  // ---------------------------------------------------------------- fee tiers

  function test_feeTier_actorOverridesMarket() public {
    facility.setFeeTier(PUBLIC, 100, 100);
    facility.setFeeTier(ACTOR, 0, 10);

    (uint256 marketOut, ) = facility.quote(ALICE, address(vault), vault.convertToShares(100e6));
    (uint256 actorOut, ) = facility.quote(ACTOR, address(vault), vault.convertToShares(100e6));
    assertEq(marketOut, 99e18);
    assertEq(actorOut, 100e18);

    facility.clearFeeTier(ACTOR);
    (actorOut, ) = facility.quote(ACTOR, address(vault), vault.convertToShares(100e6));
    assertEq(actorOut, 99e18);
  }

  function test_feeTier_appliesInPrivatePool() public {
    facility.setFeeTier(PUBLIC, 100, 100);
    facility.setFeeTier(ACTOR, 20, 20);
    facility.setPoolCap(ACTOR, 100e18);

    uint256 out = _swapShares(ACTOR, ACTOR, _shares(ACTOR, 100e6));
    assertEq(out, 99.8e18);
  }

  function test_setFeeTier_revertsAbove100Percent() public {
    vm.expectRevert(abi.encodeWithSelector(IGhoSwapFacility.InvalidFee.selector, 10_001));
    facility.setFeeTier(PUBLIC, 10_001, 0);
  }

  function test_claimFees() public {
    facility.setFeeTier(PUBLIC, 100, 0);
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 100e6));
    assertEq(facility.claimFees(), 1e18);
    assertEq(gho.balanceOf(TREASURY), 1e18);
    assertEq(facility.accruedFees(), 0);
  }

  // ---------------------------------------------------------------- yield

  function test_skim_sendsYieldToTreasuryAsShares() public {
    uint256 shares = _shares(ALICE, 100e6);
    _swapShares(ALICE, PUBLIC, shares);
    _yield(20e6); // +20%

    uint256 skimmed = facility.skim(PUBLIC);

    assertApproxEqAbs(skimmed, shares / 6, 2);
    assertEq(vault.balanceOf(TREASURY), skimmed);
    assertGe(facility.getSurplus(PUBLIC), 0);
    assertGe(vault.convertToAssets(facility.getPool(PUBLIC).shares) * 1e12, 100e18 - 1e12);
    assertEq(facility.getPool(PUBLIC).used, 100e18);
  }

  /// The case that breaks Gsm4626: the credit line is exhausted, yield accrues, and buyers drain the
  /// pool in one go. Here the skim does not need reserve headroom, so the drain goes through.
  function test_exhaustedCap_yield_fullDrainSucceeds() public {
    facility.setPoolCap(PUBLIC, 100e18);
    reserve.setLimit(address(facility), 100e18);
    uint256 shares = _shares(ALICE, 100e6);
    _swapShares(ALICE, PUBLIC, shares);
    _yield(20e6);

    gho.mint(BOB, 100e18);
    uint256 out = _swapGho(BOB, PUBLIC, 100e18);

    assertEq(facility.getPool(PUBLIC).used, 0);
    assertEq(reserve.getUsed(address(facility)), 0);
    assertApproxEqAbs(vault.convertToAssets(out), 100e6, 1);
    assertApproxEqAbs(vault.balanceOf(TREASURY), shares / 6, 2);
    assertLe(facility.getPool(PUBLIC).shares, 1);
  }

  function test_sell_unaffectedBySkim_nearCap() public {
    facility.setPoolCap(PUBLIC, 100e18);
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 60e6));
    _yield(15e6); // +25%

    // selling up to the cap still works: skimming yield uses no reserve headroom
    uint256 shares = _shares(BOB, 40e6); // 32 shares at 1.25, worth 40 GHO
    _swapShares(BOB, PUBLIC, shares);
    assertApproxEqAbs(facility.getPool(PUBLIC).used, 100e18, 1e12);
  }

  // ---------------------------------------------------------------- loss handling

  function test_repay_coversDeficit() public {
    _swapShares(ALICE, PUBLIC, _shares(ALICE, 100e6));
    _loss(10e6); // -10%

    assertApproxEqAbs(facility.getSurplus(PUBLIC), -10e18, 1e12);
    gho.mint(BOB, 50e18);
    vm.startPrank(BOB);
    gho.approve(address(facility), 50e18);
    uint256 repaid = facility.repay(PUBLIC, 50e18);
    vm.stopPrank();

    assertApproxEqAbs(repaid, 10e18, 1e12);
    assertGe(facility.getSurplus(PUBLIC), 0);
    vm.expectRevert(abi.encodeWithSelector(IGhoSwapFacility.NoDeficit.selector, PUBLIC));
    facility.repay(PUBLIC, 1);
  }

  function test_seize_thenRepayClearsDebt() public {
    uint256 shares = _shares(ALICE, 100e6);
    _swapShares(ALICE, PUBLIC, shares);

    assertEq(facility.seize(PUBLIC, TREASURY), shares);
    assertEq(vault.balanceOf(TREASURY), shares);
    assertEq(facility.getPool(PUBLIC).cap, 0);
    assertEq(facility.getPool(PUBLIC).used, 100e18);

    gho.mint(address(this), 100e18);
    gho.approve(address(facility), 100e18);
    facility.repay(PUBLIC, 100e18);
    assertEq(facility.getPool(PUBLIC).used, 0);
    assertEq(reserve.getUsed(address(facility)), 0);
  }

  // ---------------------------------------------------------------- fuzz

  function testFuzz_yieldThenFullDrain(uint256 deposit, uint256 yieldAmount) public {
    deposit = bound(deposit, 1e6, 1_000e6);
    yieldAmount = bound(yieldAmount, 0, deposit);
    facility.setPoolCap(PUBLIC, uint128(deposit) * 1e12);
    reserve.setLimit(address(facility), uint128(deposit) * 1e12);

    _swapShares(ALICE, PUBLIC, _shares(ALICE, deposit));
    _yield(yieldAmount);

    uint256 used = facility.getPool(PUBLIC).used;
    gho.mint(BOB, used);
    _swapGho(BOB, PUBLIC, used);

    assertEq(facility.getPool(PUBLIC).used, 0);
    assertEq(reserve.getUsed(address(facility)), 0);
  }

  // ---------------------------------------------------------------- helpers

  function _setSwapRole(uint64 role) internal {
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = GhoSwapFacility.swap.selector;
    manager.setTargetFunctionRole(address(facility), selectors, role);
  }

  function _shares(address user, uint256 assets) internal returns (uint256 shares) {
    usdx.mint(user, assets);
    vm.startPrank(user);
    usdx.approve(address(vault), assets);
    shares = vault.deposit(assets, user);
    vm.stopPrank();
  }

  function _swapShares(address user, address pool, uint256 shares) internal returns (uint256) {
    vm.startPrank(user);
    vault.approve(address(facility), shares);
    uint256 out = facility.swap(pool, address(vault), shares, 0, user);
    vm.stopPrank();
    return out;
  }

  function _swapGho(address user, address pool, uint256 amount) internal returns (uint256) {
    vm.startPrank(user);
    gho.approve(address(facility), amount);
    uint256 out = facility.swap(pool, address(gho), amount, 0, user);
    vm.stopPrank();
    return out;
  }

  function _yield(uint256 assets) internal {
    usdx.mint(address(vault), assets);
  }

  function _loss(uint256 assets) internal {
    vm.prank(address(vault));
    usdx.transfer(address(0xdead), assets);
  }
}
