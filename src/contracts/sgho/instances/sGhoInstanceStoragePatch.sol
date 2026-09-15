// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {sGho} from 'src/contracts/sgho/sGho.sol';

/**
 * @title sGhoInstanceStoragePatch
 * @author kpk, TokenLogic & Aave Labs
 * @notice One-off implementation that migrates the live Ethereum mainnet sGHO to the repacked
 * single-slot storage layout.
 * @dev The proxy is upgraded to this patch (atomically with `initialize`) and then to `sGhoInstance`,
 * so no migration logic remains in the final implementation.
 */
contract sGhoInstanceStoragePatch is sGho {
  using SafeCast for uint256;

  /// @dev Same as `sGhoInstance.SGHO_REVISION`, so the final swap needs no initializer call
  uint64 public constant SGHO_REVISION = 2;

  /// @dev Thrown when the yield index was not checkpointed in the same block as the migration
  error YieldIndexNotCheckpointed();

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Rewrites the namespaced storage from the previous two-slot layout into the repacked slot.
   * @dev Must run atomically with the implementation swap. Reads the raw slots of the previous layout,
   * converts `supplyCap` to whole GHO units and zeroes the orphaned second slot. Reverts unless the
   * yield index was checkpointed in the same block, so no accrual under the previous model is lost.
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
    uint40 lastUpdate_ = uint256(uint64(slot0 >> 176)).toUint40();
    uint16 targetRate_ = uint16(slot0 >> 240);

    if (lastUpdate_ != block.timestamp) revert YieldIndexNotCheckpointed();
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
