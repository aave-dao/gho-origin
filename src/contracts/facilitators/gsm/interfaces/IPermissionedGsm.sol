// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPermissionedGsm
 * @author Aave
 * @notice Defines the access restriction behaviour of the GHO Stability Module
 */
interface IPermissionedGsm {
  /**
   * @dev Emitted when the `SWAP_ACCESS_MANAGER_ROLE` holder lifts or restores the buy restriction
   * @param manager The address of the `SWAP_ACCESS_MANAGER_ROLE` holder
   * @param open True if `buyAsset` is open to any address, False otherwise
   */
  event BuyAccessOpenUpdated(address indexed manager, bool open);

  /**
   * @dev Emitted when the `SWAP_ACCESS_MANAGER_ROLE` holder lifts or restores the sell restriction
   * @param manager The address of the `SWAP_ACCESS_MANAGER_ROLE` holder
   * @param open True if `sellAsset` is open to any address, False otherwise
   */
  event SellAccessOpenUpdated(address indexed manager, bool open);

  /**
   * @notice Lift or restore the `BUY_ASSET_ROLE` restriction on buys
   * @dev Only callable by the `SWAP_ACCESS_MANAGER_ROLE`
   * @param open True to open `buyAsset` to any address, false otherwise
   */
  function setBuyAccessOpen(bool open) external;

  /**
   * @notice Lift or restore the `SELL_ASSET_ROLE` restriction on sells
   * @dev Only callable by the `SWAP_ACCESS_MANAGER_ROLE`
   * @param open True to open `sellAsset` to any address, false otherwise
   */
  function setSellAccessOpen(bool open) external;

  /**
   * @notice Returns whether buys are open to any address
   * @return True if `buyAsset` is open to any address, false if it is role restricted
   */
  function getIsBuyAccessOpen() external view returns (bool);

  /**
   * @notice Returns whether sells are open to any address
   * @return True if `sellAsset` is open to any address, false if it is role restricted
   */
  function getIsSellAccessOpen() external view returns (bool);

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

  /**
   * @notice Returns the identifier of the `SWAP_ACCESS_MANAGER_ROLE`
   * @dev By default, `SWAP_ACCESS_MANAGER_ROLE` is the admin role of the `BUY_ASSET_ROLE`
   * and `SELL_ASSET_ROLE` roles
   * @return The bytes32 id hash of the `SWAP_ACCESS_MANAGER_ROLE`
   */
  function SWAP_ACCESS_MANAGER_ROLE() external pure returns (bytes32);
}
