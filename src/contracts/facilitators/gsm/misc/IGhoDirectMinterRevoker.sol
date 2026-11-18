// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IGhoDirectMinterRevoker
 * @notice Defines the behaviour of a GhoDirectMinterRevoker
 */
interface IGhoDirectMinterRevoker {
  /**
   * @notice Revokes MINTER_ROLE from an account on a GhoDirectFacilitator
   * @dev Only callable by owner or guardian. Requires DEFAULT_ADMIN_ROLE on the facilitator.
   * @param facilitator The address of the GhoDirectFacilitator
   * @param account The address to revoke MINTER_ROLE from
   */
  function revokeMinter(address facilitator, address account) external;
}
