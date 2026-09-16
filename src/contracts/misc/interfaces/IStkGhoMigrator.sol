// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';

/**
 * @title IStkGhoMigrator
 * @notice Interface for migrating stkGHO positions into the sGHO ERC4626 vault in a single transaction.
 */
interface IStkGhoMigrator {
  /// @notice Emitted when a migration is executed.
  /// @param user The address of the user executing the migration.
  /// @param amount The amount of stkGHO migrated.
  event StkGhoMigrated(address indexed user, uint256 amount);

  /// @notice Thrown when the stkGHO cooldown period is not zero.
  error CooldownPeriodNotZero();
  /// @notice Thrown when the user has no stkGHO shares to redeem.
  error NoStkGhoSharesToRedeem();
  /// @notice Thrown when the redeemed shares did not return the expected amount of GHO.
  error UnexpectedGhoRedeemed();
  /// @notice Thrown when an input address is invalid.
  error InvalidAddress();
  /// @notice Thrown when the rescue amount is zero.
  error InvalidAmount();
  /// @notice Thrown when no sGHO shares were received from the deposit.
  error NoSGhoSharesReceived();

  /**
   * @notice Claims the stkGHO claim helper role.
   * @dev Reverts when the contract is paused.
   * @dev This contract must have been set as the pending admin for the claim helper role.
   */
  function claimHelperRole() external;

  /**
   * @notice Sets the pending admin for the stkGHO claim helper role.
   * @dev Only callable by the owner.
   * @param newPendingAdmin The address of the new pending admin.
   */
  function setClaimHelperPendingAdmin(address newPendingAdmin) external;

  /**
   * @notice Rescues ERC20 tokens accidentally sent to this contract.
   * @dev Only callable by the owner.
   * @param token The ERC20 token to rescue.
   * @param to The address that will receive the rescued tokens.
   * @param amount The amount of tokens to rescue.
   */
  function rescue(address token, address to, uint256 amount) external;

  /**
   * @notice Pauses migrations.
   * @dev Only callable by the owner or the pause guardian.
   */
  function pause() external;

  /**
   * @notice Unpauses migrations.
   * @dev Only callable by the owner.
   */
  function unpause() external;

  /**
   * @notice Migrates the caller's full stkGHO position into the sGHO ERC4626 vault.
   * @dev The migrator cools down and redeems the caller's full stkGHO balance on their behalf,
   *      then deposits the redeemed GHO into sGHO with the caller as receiver.
   * @dev Reverts when the contract is paused, when the stkGHO cooldown period is not zero,
   *      when the caller has no stkGHO shares, when this contract does not hold the stkGHO
   *      claim helper role, when the redeemed GHO amount does not match the stkGHO shares
   *      redeemed, or when the sGHO deposit returns zero shares.
   */
  function migrate() external;

  /**
   * @notice Returns the stkGHO token contract.
   */
  function STKGHO() external view returns (IStakeToken);

  /**
   * @notice Returns the sGHO ERC4626 vault contract.
   */
  function SGHO() external view returns (IERC4626);

  /**
   * @notice Returns the GHO token contract.
   */
  function GHO() external view returns (IERC20);

  /**
   * @notice Returns the stkGHO claim helper role ID.
   */
  function CLAIM_HELPER_ROLE() external view returns (uint256);
}
