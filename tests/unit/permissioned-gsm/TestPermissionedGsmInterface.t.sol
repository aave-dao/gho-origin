// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../TestGhoBase.t.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

/**
 * @dev Checks that the regular GSMs do not expose the `IPermissionedGsm` functions
 */
contract TestPermissionedGsmInterface is TestGhoBase {
  function testRevertPermissionedFunctionsOnGsm() public {
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).getIsPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).SELL_ASSET_ROLE();
  }

  function testRevertPermissionedFunctionsOnGsm4626() public {
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).getIsPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).SELL_ASSET_ROLE();
  }
}
