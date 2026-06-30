// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {sGho} from 'src/contracts/sgho/sGho.sol';

/**
 * @title sGhoInstanceStoragePatch
 * @author kpk, TokenLogic & Aave Labs
 * @notice One-off implementation that migrates the live Ethereum mainnet sGHO to the repacked,
 * single-slot storage layout (which dropped `ratePerSecond` and made `supplyCap` decimal-less).
 * @dev Deployed only for that upgrade. Once mainnet is migrated, `sGhoInstance` is the implementation
 * to use for any future deployment.
 */
contract sGhoInstanceStoragePatch is sGho {
  using SafeCast for uint256;

  uint64 public constant SGHO_REVISION = 2;

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Re-lays out the namespaced storage from the previous two-slot layout into the repacked slot.
   * @dev Must be called atomically with the implementation swap (via `upgradeToAndCall`). The previous
   * values are read straight from the raw slots (the live layout, still untouched at this point), with
   * `supplyCap` converted from asset terms to whole GHO units. The orphaned second slot is wiped.
   *
   * Previous layout:
   *   slot 0: yieldIndex(uint176) | lastUpdate(uint64) << 176 | targetRate(uint16) << 240
   *   slot 1: supplyCap(uint160, asset terms) | ratePerSecond(uint96) << 160
   */
  function initialize() external reinitializer(SGHO_REVISION) {
    uint256 slot0;
    uint256 slot1;
    assembly {
      slot0 := sload(sGhoStorageLocation)
      slot1 := sload(add(sGhoStorageLocation, 1))
    }

    uint120 yieldIndex_ = uint256(uint176(slot0)).toUint120();
    uint40 lastUpdate_ = uint40(slot0 >> 176);
    uint16 targetRate_ = uint16(slot0 >> 240);
    uint40 supplyCap_ = (uint256(uint160(slot1)) / 10 ** decimals()).toUint40();

    assembly {
      sstore(sGhoStorageLocation, 0)
      sstore(add(sGhoStorageLocation, 1), 0)
    }

    sGhoStorage storage $ = _getSGhoStorage();
    $.yieldIndex = yieldIndex_;
    $.lastUpdate = lastUpdate_;
    $.targetRate = targetRate_;
    $.supplyCap = supplyCap_;
  }
}
