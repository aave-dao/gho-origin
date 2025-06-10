// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

contract GhoFlashMinterProcedure {
  function _deployGhoFlashMinter(
    address ghoToken,
    address treasury,
    uint256 flashMinterFee,
    address poolAddressesProvider
  ) internal returns (address) {
    return address(new GhoFlashMinter(ghoToken, treasury, flashMinterFee, poolAddressesProvider));
  }
}
