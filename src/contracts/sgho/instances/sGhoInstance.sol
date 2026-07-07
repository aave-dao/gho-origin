// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {sGho} from 'src/contracts/sgho/sGho.sol';

/**
 * @title sGhoInstance
 * @author kpk, TokenLogic & Aave Labs
 * @notice Deployable implementation of the sGHO vault.
 */
contract sGhoInstance is sGho {
  /// @dev One above the mainnet storage-patch revision: the patch is followed by a swap to this
  /// implementation, re-initialized with the migrated values, so all chains end locked at the
  /// same revision through the same initializer
  uint64 public constant SGHO_REVISION = 3;

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the sGHO vault.
   * @dev On a new chain, passing the checkpoint of a live deployment cold starts the vault with
   * its yield index in sync; a genesis deployment starts at (RAY, current timestamp, 0).
   * @param gho Address of the underlying GHO token.
   * @param initialSupplyCap The supply cap for the vault, in whole GHO units.
   * @param owner The address that will be granted the DEFAULT_ADMIN_ROLE.
   * @param initialYieldIndex The initial yield index (RAY scale, at least RAY).
   * @param initialLastUpdate The initial checkpoint timestamp (must not be in the future).
   * @param initialTargetRate The initial target rate in basis points.
   */
  function initialize(
    address gho,
    uint40 initialSupplyCap,
    address owner,
    uint120 initialYieldIndex,
    uint40 initialLastUpdate,
    uint16 initialTargetRate
  ) external reinitializer(SGHO_REVISION) {
    __sGho_init({
      gho: gho,
      initialSupplyCap: initialSupplyCap,
      owner: owner,
      initialYieldIndex: initialYieldIndex,
      initialLastUpdate: initialLastUpdate,
      initialTargetRate: initialTargetRate
    });
  }
}
