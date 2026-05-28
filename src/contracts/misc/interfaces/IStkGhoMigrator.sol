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
  /// @notice Emitted when a migration batch is executed.
  /// @param user The address of the user executing the migration.
  /// @param stkGhoSharesRedeemed The amount of stkGHO shares redeemed.
  /// @param ghoRedeemed The amount of GHO received from redeeming stkGHO.
  /// @param sghoSharesReceived The amount of sGHO shares received from the deposit.
  event MigrationBatchExecuted(
    address indexed user,
    uint256 stkGhoSharesRedeemed,
    uint256 ghoRedeemed,
    uint256 sghoSharesReceived
  );

  /// @notice Emitted when the pause guardian is updated.
  /// @param oldPauseGuardian The old pause guardian address.
  /// @param newPauseGuardian The new pause guardian address.
  event PauseGuardianUpdated(address indexed oldPauseGuardian, address indexed newPauseGuardian);

  /// @notice Thrown when the stkGHO cooldown period is not zero.
  error CooldownPeriodNotZero();
  /// @notice Thrown when the user has no stkGHO shares to redeem.
  error NoStkGhoSharesToRedeem();
  /// @notice Thrown when the redeemed shares did not return the expected amount of GHO.
  error UnexpectedGhoRedeemed();
  /// @notice Thrown when an input address is zero.
  error InvalidAddressZero();
  /// @notice Thrown when the rescue amount is zero.
  error InvalidAmount();
  /// @notice Thrown when no sGHO shares were received from the deposit.
  error NoSGhoSharesReceived();
  /// @notice Thrown when the new pause guardian is the current pause guardian.
  error InvalidSamePauseGuardian();
  /// @notice Thrown when the caller is neither the owner nor the pause guardian.
  error CallerNotOwnerOrPauseGuardian();

  /**
   * @notice Claims the stkGHO claim helper role.
   * @dev This contract must have been set as the pending admin for the claim helper role.
   */
  function claimHelperRole() external;

  /**
   * @notice Sets the pending admin for the stkGHO claim helper role.
   * @param newPendingAdmin The address of the new pending admin.
   */
  function setClaimHelperPendingAdmin(address newPendingAdmin) external;

  /**
   * @notice Updates the pause guardian.
   * @dev Only callable by the owner.
   * @param newPauseGuardian The address of the new pause guardian.
   */
  function setPauseGuardian(address newPauseGuardian) external;

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
   * @dev Callable by the owner or the pause guardian.
   */
  function pause() external;

  /**
   * @notice Unpauses migrations.
   * @dev Callable by the owner or the pause guardian.
   */
  function unpause() external;

  /**
   * @notice Migrates the caller's full stkGHO position into the sGHO ERC4626 vault.
   * @dev Reverts when the contract is paused.
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

  /**
   * @notice Returns the pause guardian address.
   */
  function pauseGuardian() external view returns (address);
}
