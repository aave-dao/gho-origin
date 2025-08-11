// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {AccessControl} from 'openzeppelin-contracts/access/AccessControl.sol';

import {IsGHO} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {sGhoSteward, IsGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';

import {MockSGho} from '../mocks/MockSGho.sol';

contract sGhoStewardTest is Test {
  MockSGho public sGho;
  sGhoSteward public steward;

  address public executor = vm.addr(0x0001);
  address public ghoCommittee = vm.addr(0x0002);

  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER';

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  bytes32 public constant AMPLIFICATION_MANAGER_ROLE = keccak256('AMPLIFICATION_MANAGER_ROLE');
  bytes32 public constant FLOAT_RATE_MANAGER_ROLE = keccak256('FLOAT_RATE_MANAGER_ROLE');
  bytes32 public constant FIXED_RATE_MANAGER_ROLE = keccak256('FIXED_RATE_MANAGER_ROLE');
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  function setUp() public {
    sGho = new MockSGho();
    sGho.initialize(executor);

    steward = new sGhoSteward(address(sGho), executor, ghoCommittee);

    vm.startPrank(executor);

    AccessControl(address(sGho)).grantRole(YIELD_MANAGER_ROLE, address(steward));
  }

  function test_wrongSetUp() public {
    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(address(0), executor, ghoCommittee);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(address(sGho), address(0), ghoCommittee);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(address(sGho), executor, address(0));
  }

  function test_initialRoles() public view {
    assertTrue(steward.hasRole(DEFAULT_ADMIN_ROLE, executor));

    assertTrue(steward.hasRole(AMPLIFICATION_MANAGER_ROLE, ghoCommittee));
    assertTrue(steward.hasRole(FLOAT_RATE_MANAGER_ROLE, ghoCommittee));
    assertTrue(steward.hasRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee));
    assertTrue(steward.hasRole(SUPPLY_CAP_MANAGER_ROLE, ghoCommittee));
  }

  function test_setRateConfig() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    vm.startPrank(ghoCommittee);

    // 100_00
    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 200 // 2%
    });

    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 200);

    assertEq(sGho.targetRate(), 400);
  }

  function test_setRateConfigNotAllRoles() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    vm.startPrank(executor);

    steward.revokeRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee);

    vm.stopPrank();
    vm.startPrank(ghoCommittee);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 0
    });

    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 0);

    assertEq(sGho.targetRate(), 200);

    vm.stopPrank();
    vm.startPrank(executor);

    steward.revokeRole(FLOAT_RATE_MANAGER_ROLE, ghoCommittee);

    vm.stopPrank();
    vm.startPrank(ghoCommittee);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 200_00, // 2 * AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 0
    });

    steward.setRateConfig(newConfig);

    configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 200_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 0);

    assertEq(sGho.targetRate(), 400);

    vm.stopPrank();
    vm.startPrank(executor);

    steward.grantRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee);
    steward.revokeRole(AMPLIFICATION_MANAGER_ROLE, ghoCommittee);

    vm.stopPrank();
    vm.startPrank(ghoCommittee);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 200_00, // 2 * AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 200 // 2%
    });

    steward.setRateConfig(newConfig);

    configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 200_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 200);

    assertEq(sGho.targetRate(), 600);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 200_00, // 2 * AMPLIFICATION_DENOMINATOR
      floatRate: 300, // 3%
      fixedRate: 200 // 2%
    });

    vm.expectRevert();
    steward.setRateConfig(newConfig);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 300_00, // 3 * AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 200 // 2%
    });

    vm.expectRevert();
    steward.setRateConfig(newConfig);

    vm.stopPrank();
    vm.startPrank(executor);

    steward.revokeRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee);

    vm.stopPrank();
    vm.startPrank(ghoCommittee);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 200_00, // 3 * AMPLIFICATION_DENOMINATOR
      floatRate: 200, // 2%
      fixedRate: 300 // 3%
    });

    vm.expectRevert();
    steward.setRateConfig(newConfig);
  }

  function test_setRateSameValue() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    vm.startPrank(ghoCommittee);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 0,
      floatRate: 0,
      fixedRate: 0
    });

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.SameValue.selector));
    steward.setRateConfig(newConfig);
  }

  function test_supplyCap() public {
    uint256 initialSupplyCap = sGho.supplyCap();
    assertEq(initialSupplyCap, 0);

    vm.startPrank(ghoCommittee);

    steward.setSupplyCap(type(uint160).max);

    uint256 supplyCapAfterUpdate = sGho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint160).max);

    vm.stopPrank();
    vm.startPrank(executor);

    steward.revokeRole(SUPPLY_CAP_MANAGER_ROLE, ghoCommittee);

    vm.stopPrank();
    vm.startPrank(ghoCommittee);

    vm.expectRevert();
    steward.setSupplyCap(1e18);
  }

  function test_supplyCapSameValue() public {
    uint256 initialSupplyCap = sGho.supplyCap();
    assertEq(initialSupplyCap, 0);

    vm.startPrank(ghoCommittee);

    steward.setSupplyCap(type(uint160).max);

    uint256 supplyCapAfterUpdate = sGho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint160).max);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.SameValue.selector));
    steward.setSupplyCap(type(uint160).max);
  }

  function test_previewTargetRate(uint16 ampl, uint16 float, uint16 fix) public {
    vm.assume((uint256(ampl) * float) / 1e4 + fix < 5e3);
    vm.assume(ampl != 0 || float != 0 || fix != 0);

    vm.startPrank(ghoCommittee);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: ampl,
      floatRate: float,
      fixedRate: fix
    });

    uint16 target = steward.previewTargetRate(newConfig);
    uint16 resultTarget = steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, ampl);
    assertEq(configAfterUpdate.floatRate, float);
    assertEq(configAfterUpdate.fixedRate, fix);

    assertEq(sGho.targetRate(), target);
    assertEq(resultTarget, target);
  }
}
