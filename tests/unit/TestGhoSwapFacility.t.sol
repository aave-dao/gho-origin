// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {AccessManager} from 'openzeppelin-contracts/contracts/access/manager/AccessManager.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {TestnetERC20} from 'aave-v3-origin/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {GhoReserve} from 'src/contracts/facilitators/gsm/GhoReserve.sol';
import {GhoSwapFacility} from 'src/contracts/facilitators/swap/GhoSwapFacility.sol';
import {IGhoSwapFacility} from 'src/contracts/facilitators/swap/interfaces/IGhoSwapFacility.sol';

/// @dev Base facility with a plain (non-ERC4626) 6-decimal asset.
contract TestGhoSwapFacility is Test {
  uint128 constant RESERVE_LIMIT = 1_000_000e18;
  address constant TREASURY = address(0x7EA5);
  address constant ALICE = address(0xA11CE);
  address constant BOB = address(0xB0B);
  address constant ACTOR = address(0xAC70);

  AccessManager manager;
  TestnetERC20 gho;
  TestnetERC20 usdx;
  GhoReserve reserve;
  GhoSwapFacility facility;
  address PUBLIC;

  function setUp() public {
    manager = new AccessManager(address(this));
    gho = new TestnetERC20('GHO', 'GHO', 18, address(this));
    usdx = new TestnetERC20('USDX', 'USDX', 6, address(this));
    reserve = _deployReserve();
    facility = _deployFacility(address(usdx));

    reserve.addEntity(address(facility));
    reserve.setLimit(address(facility), RESERVE_LIMIT);

    PUBLIC = facility.PUBLIC_POOL();
    facility.setPoolCap(PUBLIC, 1_000e18);
  }

  function test_assetForGho_scalesDecimals() public {
    facility.setPoolFees(PUBLIC, 100, 0);
    uint256 out = _swapAsset(ALICE, 100e6);

    assertEq(out, 99e18);
    assertEq(facility.accruedFees(), 1e18);
    assertEq(facility.getPool(PUBLIC).balance, 100e6);
    assertEq(facility.getPool(PUBLIC).used, 100e18);
    assertEq(reserve.getUsed(address(facility)), 100e18);
  }

  function test_ghoForAsset() public {
    facility.setPoolFees(PUBLIC, 0, 50);
    _swapAsset(ALICE, 100e6);

    uint256 out = _swapGho(BOB, 50e18);

    assertEq(out, 49.75e6);
    assertEq(usdx.balanceOf(BOB), 49.75e6);
    assertEq(facility.getPool(PUBLIC).used, 50.25e18);
    assertEq(facility.getPool(PUBLIC).balance, 50.25e6);
  }

  function test_ghoForAsset_dustStaysAsSurplus() public {
    _swapAsset(ALICE, 10e6);
    uint256 out = _swapGho(BOB, 1e18 + 5e11); // 1.0000005 GHO

    assertEq(out, 1e6);
    assertEq(facility.getSurplus(PUBLIC), 5e11);
    assertEq(facility.skim(PUBLIC), 0); // less than one asset unit, kept as backing
  }

  function test_skim_noYield_isNoop() public {
    _swapAsset(ALICE, 100e6);
    usdx.mint(address(facility), 5e6); // a donation is not part of any pool
    assertEq(facility.skim(PUBLIC), 0);
    assertEq(facility.getSurplus(PUBLIC), 0);
  }

  function test_fullDrain() public {
    facility.setPoolCap(PUBLIC, 100e18);
    reserve.setLimit(address(facility), 100e18);
    _swapAsset(ALICE, 100e6);

    uint256 out = _swapGho(BOB, 100e18);

    assertEq(out, 100e6);
    assertEq(facility.getPool(PUBLIC).balance, 0);
    assertEq(facility.getPool(PUBLIC).used, 0);
    assertEq(reserve.getUsed(address(facility)), 0);
  }

  function test_privatePool_andMakePublic() public {
    facility.setPoolCap(ACTOR, 100e18);
    _swapAsset(ACTOR, 40e6);
    assertEq(facility.getPool(ACTOR).balance, 40e6);
    assertEq(facility.getPool(PUBLIC).balance, 0);

    facility.makePublic(ACTOR);
    assertEq(facility.poolOf(ACTOR), PUBLIC);
    assertEq(facility.getPool(PUBLIC).balance, 40e6);
    assertEq(facility.getPool(PUBLIC).used, 40e18);

    assertEq(_swapGho(BOB, 40e18), 40e6);
  }

  function test_eighteenDecimalAsset() public {
    TestnetERC20 dai = new TestnetERC20('DAI', 'DAI', 18, address(this));
    GhoSwapFacility daiFacility = _deployFacility(address(dai));
    assertEq(daiFacility.ASSET(), address(dai));

    (uint256 out, ) = daiFacility.quote(ALICE, address(dai), 3e18);
    assertEq(out, 3e18);
    (out, ) = daiFacility.quote(ALICE, address(gho), 3e18);
    assertEq(out, 3e18);
  }

  function test_constructor_revertsAbove18Decimals() public {
    TestnetERC20 weird = new TestnetERC20('W', 'W', 24, address(this));
    vm.expectRevert(abi.encodeWithSelector(IGhoSwapFacility.UnsupportedDecimals.selector, 24));
    new GhoSwapFacility(address(gho), address(weird), address(reserve));
  }

  function test_constructor_revertsOnReserveMismatch() public {
    TestnetERC20 other = new TestnetERC20('X', 'X', 18, address(this));
    vm.expectRevert(
      abi.encodeWithSelector(IGhoSwapFacility.ReserveTokenMismatch.selector, address(gho))
    );
    new GhoSwapFacility(address(other), address(usdx), address(reserve));
  }

  function testFuzz_roundTrip(uint256 amount) public {
    amount = bound(amount, 1, 1_000e6);
    _swapAsset(ALICE, amount);
    uint256 used = facility.getPool(PUBLIC).used;
    assertEq(_swapGho(BOB, used), amount);
    assertEq(facility.getPool(PUBLIC).used, 0);
    assertEq(facility.getPool(PUBLIC).balance, 0);
  }

  function _deployReserve() internal returns (GhoReserve r) {
    r = GhoReserve(
      address(
        new TransparentUpgradeableProxy(
          address(new GhoReserve(address(gho))),
          makeAddr('PROXY_ADMIN'),
          abi.encodeCall(GhoReserve.initialize, (address(this)))
        )
      )
    );
    gho.mint(address(r), RESERVE_LIMIT);
  }

  function _deployFacility(address asset) internal returns (GhoSwapFacility) {
    return
      GhoSwapFacility(
        address(
          new TransparentUpgradeableProxy(
            address(new GhoSwapFacility(address(gho), asset, address(reserve))),
            makeAddr('PROXY_ADMIN'),
            abi.encodeCall(GhoSwapFacility.initialize, (address(manager), TREASURY))
          )
        )
      );
  }

  function _swapAsset(address user, uint256 amount) internal returns (uint256 out) {
    usdx.mint(user, amount);
    vm.startPrank(user);
    usdx.approve(address(facility), amount);
    out = facility.swap(address(usdx), amount, 0, user);
    vm.stopPrank();
  }

  function _swapGho(address user, uint256 amount) internal returns (uint256 out) {
    gho.mint(user, amount);
    vm.startPrank(user);
    gho.approve(address(facility), amount);
    out = facility.swap(address(gho), amount, 0, user);
    vm.stopPrank();
  }
}
