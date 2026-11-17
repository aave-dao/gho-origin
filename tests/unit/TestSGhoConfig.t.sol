// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';
import {AccessControlErrorsLib} from '../helpers/ErrorsLib.sol';

contract TestSGhoConfig is TestSGhoBase {
  // ========================================
  // ADMINISTRATIVE FUNCTIONS TESTS
  // ========================================
  function test_setTargetRate_event() external {
    vm.startPrank(yManager);
    uint16 newRate = 2000; // 20% APR
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.TargetRateUpdated(newRate);
    sgho.setTargetRate(newRate);
    vm.stopPrank();
    assertEq(sgho.targetRate(), newRate, 'Target rate should be updated');
  }

  function test_revert_setTargetRate_exceedsMaxRate() external {
    vm.startPrank(yManager);
    uint16 newRate = MAX_SAFE_RATE + 1;
    vm.expectRevert(IsGho.MaxRateExceeded.selector);
    sgho.setTargetRate(newRate);
    vm.stopPrank();
  }

  function test_setTargetRate_atMaxRate() external {
    vm.startPrank(yManager);
    sgho.setTargetRate(MAX_SAFE_RATE);
    vm.stopPrank();
    assertEq(sgho.targetRate(), MAX_SAFE_RATE, 'Target rate should be updated to max rate');
  }

  function test_setSupplyCap_event() external {
    vm.startPrank(yManager);
    uint160 newSupplyCap = 1000 ether;
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.SupplyCapUpdated(newSupplyCap);
    sgho.setSupplyCap(newSupplyCap);
    vm.stopPrank();
    assertEq(sgho.supplyCap(), newSupplyCap, 'Supply cap should be updated');
  }

  function test_setTargetRate() external {
    uint16 newRate = 2000; // 20% APR

    vm.startPrank(yManager);
    sgho.setTargetRate(newRate);
    vm.stopPrank();

    assertEq(sgho.targetRate(), newRate, 'Target rate not set correctly');
  }

  function test_revert_setTargetRate_notYieldManager() external {
    uint16 newRate = 2000; // 20% APR

    vm.startPrank(user1);
    vm.expectRevert(AccessControlErrorsLib.UNAUTHORIZED_ACCOUNT(sgho.YIELD_MANAGER_ROLE(), user1));
    sgho.setTargetRate(newRate);
    vm.stopPrank();
  }

  function test_revert_setTargetRate_rateGreaterThanMaxRate() external {
    uint16 newRate = 5001; // 50.01% APR
    vm.startPrank(yManager);
    vm.expectRevert(IsGho.MaxRateExceeded.selector);
    sgho.setTargetRate(newRate);
    vm.stopPrank();
  }
}
