// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {IStakeToken} from 'aave-address-book/common/IStakeToken.sol';

/**
 * @title StkGhoMigrator
 * @author Aave Labs
 * @notice Migrates stkGHO positions into the sGHO ERC4626 vault in a single transaction.
 * @dev The contract must hold the stkGHO claim helper role to call cooldownOnBehalfOf and redeemOnBehalf.
 */
contract StkGhoMigrator is IStkGhoMigrator, Pausable, Ownable {
  using SafeERC20 for IERC20;

  /// @notice The stkGHO token contract
  IStakeToken public constant STKGHO = IStakeToken(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);
  /// @notice The sGHO ERC4626 vault contract
  IERC4626 public constant SGHO = IERC4626(0xE1753F2e00940cC31213dd92013cF019DFE4ca1d);
  /// @notice The GHO token contract
  IERC20 public constant GHO = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
  /// @notice The stkGHO claim helper role ID
  uint256 public constant CLAIM_HELPER_ROLE = 2;
  /// @notice The address authorized to pause migrations in case of emergency
  address public pauseGuardian;

  modifier onlyOwnerOrPauseGuardian() {
    require(msg.sender == owner() || msg.sender == pauseGuardian, CallerNotOwnerOrPauseGuardian());
    _;
  }

  /**
   * @notice Initializes the contract owner and grants the sGHO vault maximum GHO allowance.
   * @param owner The address of the contract owner.
   * @param initialPauseGuardian The address of the new pause guardian.
   */
  constructor(address owner, address initialPauseGuardian) Ownable(owner) {
    require(initialPauseGuardian != address(0), InvalidAddressZero());
    pauseGuardian = initialPauseGuardian;
    GHO.forceApprove(address(SGHO), type(uint256).max);
  }

  /// @inheritdoc IStkGhoMigrator
  function claimHelperRole() external {
    STKGHO.claimRoleAdmin(CLAIM_HELPER_ROLE);
  }

  /// @inheritdoc IStkGhoMigrator
  function setClaimHelperPendingAdmin(address newPendingAdmin) external onlyOwner {
    require(newPendingAdmin != address(0), InvalidAddressZero());
    STKGHO.setPendingAdmin(CLAIM_HELPER_ROLE, newPendingAdmin);
  }

  /// @inheritdoc IStkGhoMigrator
  function setPauseGuardian(address newPauseGuardian) external onlyOwner {
    require(newPauseGuardian != address(0), InvalidAddressZero());
    require(newPauseGuardian != pauseGuardian, InvalidSamePauseGuardian());
    address oldPauseGuardian = pauseGuardian;
    pauseGuardian = newPauseGuardian;
    emit PauseGuardianUpdated(oldPauseGuardian, newPauseGuardian);
  }

  /// @inheritdoc IStkGhoMigrator
  function rescue(address token, address to, uint256 amount) external onlyOwner {
    require(token != address(0) && to != address(0), InvalidAddressZero());
    require(amount > 0, InvalidAmount());
    IERC20(token).safeTransfer(to, amount);
  }

  /// @inheritdoc IStkGhoMigrator
  function pause() external onlyOwnerOrPauseGuardian {
    _pause();
  }

  /// @inheritdoc IStkGhoMigrator
  function unpause() external onlyOwnerOrPauseGuardian {
    _unpause();
  }

  /// @inheritdoc IStkGhoMigrator
  function migrate() external whenNotPaused {
    require(STKGHO.getCooldownSeconds() == 0, CooldownPeriodNotZero());

    uint256 stkGhoShares = STKGHO.balanceOf(msg.sender);
    require(stkGhoShares != 0, NoStkGhoSharesToRedeem());

    uint256 ghoBalanceBefore = GHO.balanceOf(address(this));

    STKGHO.cooldownOnBehalfOf(msg.sender);
    STKGHO.redeemOnBehalf(msg.sender, address(this), stkGhoShares);
    uint256 ghoRedeemed = GHO.balanceOf(address(this)) - ghoBalanceBefore;
    require(ghoRedeemed == stkGhoShares, UnexpectedGhoRedeemed());

    uint256 sghoSharesReceived = SGHO.deposit(ghoRedeemed, msg.sender);
    require(sghoSharesReceived != 0, NoSGhoSharesReceived());

    emit MigrationBatchExecuted(msg.sender, stkGhoShares, ghoRedeemed, sghoSharesReceived);
  }
}
