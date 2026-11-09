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
    IPermissionedGsm(address(GHO_GSM)).setBuyAccessOpen(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setBuyAccessOpen(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setSellAccessOpen(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setSellAccessOpen(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).getIsBuyAccessOpen();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).getIsSellAccessOpen();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).SELL_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).SWAP_ACCESS_MANAGER_ROLE();
  }

  function testRevertPermissionedFunctionsOnGsm4626() public {
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setBuyAccessOpen(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setBuyAccessOpen(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setSellAccessOpen(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setSellAccessOpen(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).getIsBuyAccessOpen();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).getIsSellAccessOpen();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).SELL_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).SWAP_ACCESS_MANAGER_ROLE();
  }
}
