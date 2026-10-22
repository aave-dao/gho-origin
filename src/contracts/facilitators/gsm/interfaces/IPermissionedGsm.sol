// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPermissionedGsm
 * @author Aave
 * @notice Defines the access restriction behaviour of the GHO Stability Module
 */
interface IPermissionedGsm {
  /**
   * @dev Emitted when the Configurator lifts or restores the buy restriction
   * @param configurator The address of the Configurator
   * @param enabled True if `buyAsset` is permissionless, False otherwise
   */
  event BuyPermissionlessUpdated(address indexed configurator, bool enabled);

  /**
   * @dev Emitted when the Configurator lifts or restores the sell restriction
   * @param configurator The address of the Configurator
   * @param enabled True if `sellAsset` is permissionless, False otherwise
   */
  event SellPermissionlessUpdated(address indexed configurator, bool enabled);

  /**
   * @notice Lift or restore the `BUY_ASSET_ROLE` restriction on buys
   * @param enable True to make `buyAsset` permissionless, false otherwise
   */
  function setBuyPermissionless(bool enable) external;

  /**
   * @notice Lift or restore the `SELL_ASSET_ROLE` restriction on sells
   * @param enable True to make `sellAsset` permissionless, false otherwise
   */
  function setSellPermissionless(bool enable) external;

  /**
   * @notice Returns the permissionless status of buys
   * @return True if `buyAsset` is permissionless, false if it is role restricted
   */
  function getIsBuyPermissionless() external view returns (bool);

  /**
   * @notice Returns the permissionless status of sells
   * @return True if `sellAsset` is permissionless, false if it is role restricted
   */
  function getIsSellPermissionless() external view returns (bool);

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
