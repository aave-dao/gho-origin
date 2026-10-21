// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPermissionedGsm
 * @author Aave
 * @notice Defines the behaviour of a GHO Stability Module restricting buys to addresses holding the
 * `BUY_ASSET_ROLE` and sells to addresses holding the `SELL_ASSET_ROLE`
 */
interface IPermissionedGsm {
  /**
   * @dev Emitted when the Configurator lifts or restores the swap restrictions
   * @param configurator The address of the Configurator
   * @param enabled True if swap functions are permissionless, False otherwise
   */
  event PermissionlessUpdated(address indexed configurator, bool enabled);

  /**
   * @notice Lift or restore the role restrictions on swap functions
   * @dev Swap functions are role restricted by default
   * @param enable True to make swap functions permissionless, false otherwise
   */
  function setPermissionless(bool enable) external;

  /**
   * @notice Returns the permissionless status of the GSM
   * @return True if swap functions are permissionless, false if they are role restricted
   */
  function getIsPermissionless() external view returns (bool);

  /**
   * @notice Returns the identifier of the `BUY_ASSET_ROLE`
   * @return The bytes32 id hash of the `BUY_ASSET_ROLE`
   */
  function BUY_ASSET_ROLE() external pure returns (bytes32);

  /**
   * @notice Returns the identifier of the `SELL_ASSET_ROLE`
   * @return The bytes32 id hash of the `SELL_ASSET_ROLE`
   */
  function SELL_ASSET_ROLE() external pure returns (bytes32);
}
