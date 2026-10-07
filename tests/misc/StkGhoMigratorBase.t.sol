// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {StkGhoMigratorHelpers} from './StkGhoMigratorHelpers.t.sol';

contract StkGhoMigratorMockTarget {}

abstract contract StkGhoMigratorBaseTest is StkGhoMigratorHelpers {
  address public invalidUser = makeAddr('INVALID_USER');

  // --- Test Constructor ---

  function test_Constructor() public view {
    assertEq(migrator.owner(), ownerMigrator);
    assertEq(migrator.guardian(), pauseGuardian);
    assertEq(address(migrator.STKGHO()), address(STKGHO));
    assertEq(address(migrator.SGHO()), address(SGHO));
    assertEq(address(migrator.GHO()), address(GHO));
    assertEq(migrator.CLAIM_HELPER_ROLE(), CLAIM_HELPER_ROLE);
  }

  function test_Revert_Constructor_InvalidOwner() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    _deployStkGhoMigrator({initialOwner: address(0), initialPauseGuardian: pauseGuardian});
  }

  function test_Revert_Constructor_InvalidPauseGuardian() public {
    vm.expectRevert(IStkGhoMigrator.InvalidAddress.selector);
    _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: address(0)});
  }

  // --- Test Guardian ---

  function test_Pause_ByGuardian() public {
    vm.prank(pauseGuardian);
    migrator.pause();

    assertTrue(migrator.paused());
  }

  function test_Revert_Pause_NotOwnerOrGuardian() public {
    vm.prank(user);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, user)
    );
    migrator.pause();
  }

  function test_Unpause_ByOwner() public {
    vm.prank(pauseGuardian);
    migrator.pause();

    vm.prank(ownerMigrator);
    migrator.unpause();

    assertFalse(migrator.paused());
  }

  function test_Revert_Unpause_NotOwner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    migrator.unpause();
  }

  function test_Revert_Unpause_ByGuardian() public {
    vm.prank(pauseGuardian);
    migrator.pause();

    vm.prank(pauseGuardian);
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pauseGuardian)
    );
    migrator.unpause();

    assertTrue(migrator.paused());
  }

  function test_Revert_Migrate_WhenPaused() public {
    vm.prank(pauseGuardian);
    migrator.pause();

    vm.prank(user);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    migrator.migrate(0);
  }

  function test_Revert_ClaimHelperRole_WhenPaused() public {
    vm.prank(pauseGuardian);
    migrator.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    migrator.claimHelperRole();
  }

  // --- Internal functions for tests ---

  function _deployMigratorWithMockedTargets() internal {
    _etchIntegrationTargets();
    _mockGhoApprove(address(SGHO), type(uint256).max);

    migrator = StkGhoMigrator(
      _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: pauseGuardian})
    );
  }

  function _etchIntegrationTargets() internal {
    StkGhoMigratorMockTarget target = new StkGhoMigratorMockTarget();

    vm.etch(address(STKGHO), address(target).code);
    vm.etch(address(SGHO), address(target).code);
    vm.etch(address(GHO), address(target).code);
  }

  function _mockGhoApprove(address spender, uint256 amount) internal {
    vm.mockCall(
      address(GHO),
      abi.encodeWithSelector(IERC20.approve.selector, spender, amount),
      abi.encode(true)
    );
  }

  function _mockCooldownSeconds(uint256 cooldownSeconds) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.getCooldownSeconds.selector),
      abi.encode(cooldownSeconds)
    );
  }

  function _mockStkGhoBalance(address account, uint256 balance) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, account),
      abi.encode(balance)
    );
  }

  function _mockCooldownOnBehalfOf(address account) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.cooldownOnBehalfOf.selector, account),
      ''
    );
  }

  function _mockRedeemOnBehalf(address from, address to, uint256 amount) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.redeemOnBehalf.selector, from, to, amount),
      ''
    );
  }

  function _mockSGhoDeposit(uint256 assets, address receiver, uint256 shares) internal {
    vm.mockCall(
      address(SGHO),
      abi.encodeWithSelector(IERC4626.deposit.selector, assets, receiver),
      abi.encode(shares)
    );
  }

  function _mockClaimRoleAdmin(uint256 role) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.claimRoleAdmin.selector, role),
      ''
    );
  }

  function _mockSetPendingAdmin(uint256 role, address pendingAdmin) internal {
    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.setPendingAdmin.selector, role, pendingAdmin),
      ''
    );
  }

  function _mockTokenTransfer(address token, address to, uint256 amount) internal {
    vm.mockCall(
      token,
      abi.encodeWithSelector(IERC20.transfer.selector, to, amount),
      abi.encode(true)
    );
  }
}
