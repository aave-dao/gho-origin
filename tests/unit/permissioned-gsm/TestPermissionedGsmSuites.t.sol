// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestGsm} from '../TestGsm.t.sol';
import {TestGsm4626} from '../TestGsm4626.t.sol';
import {TestGsm4626Edge} from '../TestGsm4626Edge.t.sol';
import {TestGsmFullFlow} from '../TestGsmFullFlow.t.sol';
import {TestGsmSampleLiquidator} from '../TestGsmSampleLiquidator.t.sol';
import {TestGsmSwapEdge} from '../TestGsmSwapEdge.t.sol';
import {TestGsmSwapFuzz} from '../TestGsmSwapFuzz.t.sol';

/**
 * @dev Reruns the regular GSM test suites against `PermissionedGsm`/`PermissionedGsm4626`. The
 * deployment helpers in `TestGhoBase` deploy the permissioned flavours and grant the Swapper Role
 * to the swap originators, so every assertion holding for the regular GSMs must hold here too.
 */
contract TestPermissionedGsm is TestGsm {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsm4626 is TestGsm4626 {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsm4626Edge is TestGsm4626Edge {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsmFullFlow is TestGsmFullFlow {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsmSampleLiquidator is TestGsmSampleLiquidator {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsmSwapEdge is TestGsmSwapEdge {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}

contract TestPermissionedGsmSwapFuzz is TestGsmSwapFuzz {
  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }
}
