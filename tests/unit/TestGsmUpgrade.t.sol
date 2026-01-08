// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

contract TestGsmUpgrade is TestGhoBase {
  function testUpgrade() public {
    assertEq(GHO_GSM.GSM_REVISION(), 1, 'Unexpected pre-upgrade GSM revision');

    address beforeTreasury = GHO_GSM.getGhoTreasury();
    address beforeReserve = GHO_GSM.getGhoReserve();
    uint128 beforeExposureCap = GHO_GSM.getExposureCap();

    // Perform the mock upgrade
    address gsmV2 = address(
      new MockGsmV2(address(GHO_TOKEN), address(USDX_TOKEN), address(GHO_GSM_FIXED_PRICE_STRATEGY))
    );
    bytes memory data = abi.encodeWithSelector(MockGsmV2.initialize.selector);
    vm.expectEmit(address(GHO_GSM));
    emit Upgraded(gsmV2);
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GHO_GSM))).upgradeToAndCall(gsmV2, data);

    assertEq(GHO_GSM.GSM_REVISION(), 2, 'Unexpected post-upgrade GSM revision');

    assertEq(GHO_GSM.getGhoTreasury(), beforeTreasury, 'Unexpected treasury after upgrade');
    assertEq(GHO_GSM.getGhoReserve(), beforeReserve, 'Unexpected reserve after upgrade');
    assertEq(GHO_GSM.getExposureCap(), beforeExposureCap, 'Unexpected exposure cap after upgrade');
  }
}
