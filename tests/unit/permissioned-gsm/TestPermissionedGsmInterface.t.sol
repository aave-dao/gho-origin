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
    IPermissionedGsm(address(GHO_GSM)).setBuyPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setBuyPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setSellPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).setSellPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).getIsBuyPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).getIsSellPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM)).SELL_ASSET_ROLE();
  }

  function testRevertPermissionedFunctionsOnGsm4626() public {
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setBuyPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setBuyPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setSellPermissionless(true);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).setSellPermissionless(false);
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).getIsBuyPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).getIsSellPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).BUY_ASSET_ROLE();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GHO_GSM_4626)).SELL_ASSET_ROLE();
  }
}
