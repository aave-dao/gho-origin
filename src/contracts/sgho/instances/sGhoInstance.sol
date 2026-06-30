// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {sGho} from 'src/contracts/sgho/sGho.sol';

/**
 * @title sGhoInstance
 * @author kpk, TokenLogic & Aave Labs
 * @notice Deployable implementation of the sGHO vault.
 */
contract sGhoInstance is sGho {
  /// @dev Aligned with the mainnet storage-patch revision so all chains share the same revision
  uint64 public constant SGHO_REVISION = 2;

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the sGHO vault.
   * @param gho Address of the underlying GHO token.
   * @param initialSupplyCap The supply cap for the vault, in whole GHO units.
   * @param owner The address that will be granted the DEFAULT_ADMIN_ROLE.
   */
  function initialize(
    address gho,
    uint40 initialSupplyCap,
    address owner
  ) external reinitializer(SGHO_REVISION) {
    __sGho_init(gho, initialSupplyCap, owner);
  }
}
