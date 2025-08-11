// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';

import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol';

import {IsGHO} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {sGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';

import {MockSGho} from '../mocks/MockSGho.sol';

contract sGhoStewardTest is Test {
  MockSGho public sGho;
  sGhoSteward public steward;

  address public executor = vm.addr(0x0001);
  address public ghoCommittee = vm.addr(0x0002);

  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER';

  function setUp() public {
    sGho = new MockSGho();
    sGho.initialize(executor);

    steward = new sGhoSteward(address(sGho), executor, ghoCommittee);

    vm.start(executor);

    AccessControlUpgradeable(address(sGho)).grantRole(YIELD_MANAGER_ROLE, steward);
  }

  function test_initialRoles() public {}

  function test_setRateConfig() public {}

  function test_setRateConfigNotAllRoles() public {}

  function test_setRateSameValue() public {}

  function test_supplyCap() public {}

  function test_supplyCapSameValue() public {}

  function test_previewTargetRate() public {}
}
