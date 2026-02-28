// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

contract TestGsmUpgrade is TestGhoBase {
  function testUpgrade() public {
    assertEq(GHO_GSM.REVISION(), 1, 'Unexpected pre-upgrade GSM revision');

    bytes32[] memory beforeSnapshot = _getStorageSnapshot();

    // Sanity check on select storage variable
    assertEq(uint256(beforeSnapshot[1]), uint160(TREASURY), 'GHO Treasury address not set');

    // Perform the mock upgrade
    address gsmV2 = address(
      new MockGsmV2(address(GHO_TOKEN), address(USDX_TOKEN), address(GHO_GSM_FIXED_PRICE_STRATEGY))
    );
    bytes memory data = abi.encodeWithSelector(MockGsmV2.initialize.selector);
    vm.expectEmit(address(GHO_GSM));
    emit Upgraded(gsmV2);
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GHO_GSM))).upgradeToAndCall(gsmV2, data);

    bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    uint256 initializedVersion = uint256(vm.load(address(GHO_GSM), initializableStorageSlot)) &
      0xffffffffffffffff;
    assertEq(initializedVersion, 2, 'Unexpected post-upgrade initialized version');

    bytes32[] memory afterSnapshot = _getStorageSnapshot();
    // First storage item should be different, the rest the same post-upgrade
    assertTrue(afterSnapshot[0] != beforeSnapshot[0], 'Unexpected lastInitializedRevision');
    for (uint8 i = 1; i < afterSnapshot.length; i++) {
      assertEq(afterSnapshot[i], beforeSnapshot[i], 'Unexpected storage value updated');
    }
  }

  function _getStorageSnapshot() internal view returns (bytes32[] memory) {
    // Snapshot values for lastInitializedRevision (ERC-7201 namespaced slot) and GSM local storage (2-6)
    bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    bytes32[] memory data = new bytes32[](6);
    data[0] = vm.load(address(GHO_GSM), initializableStorageSlot);
    data[1] = vm.load(address(GHO_GSM), bytes32(uint256(2)));
    data[2] = vm.load(address(GHO_GSM), bytes32(uint256(3)));
    data[3] = vm.load(address(GHO_GSM), bytes32(uint256(4)));
    data[4] = vm.load(address(GHO_GSM), bytes32(uint256(5)));
    data[5] = vm.load(address(GHO_GSM), bytes32(uint256(6)));
    return data;
  }
}
