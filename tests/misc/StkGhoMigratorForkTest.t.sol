// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {StkGhoMigratorBaseTest} from './StkGhoMigratorBase.t.sol';
import {IStakeTokenGetters} from './StkGhoMigratorHelpers.t.sol';

contract StkGhoMigratorForkTest is StkGhoMigratorBaseTest {
  function setUp() public {
    // Skip if RPC_MAINNET env variable is not set.
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc);
    migrator = StkGhoMigrator(
      _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: pauseGuardian})
    );

    address admin = STKGHO.getAdmin(CLAIM_HELPER_ROLE);
    vm.prank(admin);
    STKGHO.setPendingAdmin(CLAIM_HELPER_ROLE, address(migrator));
    migrator.claimHelperRole();
  }

  // --- Test Constructor ---
  function test_Constructor_ApprovesSGhoMaxOnFork() public {
    StkGhoMigrator freshMigrator = StkGhoMigrator(
      _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: pauseGuardian})
    );

    assertEq(GHO.allowance(address(freshMigrator), address(SGHO)), type(uint256).max);
  }

  // --- Test Deployment and Role Claiming ---
  function test_ClaimHelperRole_FreshDeploy() public {
    StkGhoMigrator freshMigrator = StkGhoMigrator(
      _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: pauseGuardian})
    );

    assertNotEq(STKGHO.getAdmin(CLAIM_HELPER_ROLE), address(freshMigrator));

    vm.expectRevert(bytes('CALLER_NOT_PENDING_ROLE_ADMIN'));
    freshMigrator.claimHelperRole();

    address admin = STKGHO.getAdmin(CLAIM_HELPER_ROLE);

    vm.prank(admin);
    STKGHO.setPendingAdmin(CLAIM_HELPER_ROLE, address(freshMigrator));

    freshMigrator.claimHelperRole();

    assertEq(STKGHO.getAdmin(CLAIM_HELPER_ROLE), address(freshMigrator));
  }

  // --- Test Guardian ---
  function test_Guardian_FreshDeploy() public view {
    assertEq(migrator.guardian(), pauseGuardian);
  }

  function test_UpdateGuardian() public {
    address newPauseGuardian = makeAddr('NEW_PAUSE_GUARDIAN');

    vm.expectEmit(address(migrator));
    emit IWithGuardian.GuardianUpdated(pauseGuardian, newPauseGuardian);

    vm.prank(ownerMigrator);
    migrator.updateGuardian(newPauseGuardian);

    assertEq(migrator.guardian(), newPauseGuardian);
  }

  function test_UpdateGuardian_UpdatesPausePermissions() public {
    address newPauseGuardian = makeAddr('NEW_PAUSE_GUARDIAN');

    vm.prank(ownerMigrator);
    migrator.updateGuardian(newPauseGuardian);

    vm.prank(pauseGuardian);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, pauseGuardian)
    );
    migrator.pause();

    vm.prank(newPauseGuardian);
    migrator.pause();

    assertTrue(migrator.paused());
  }

  function test_Revert_UpdateGuardian_NotOwnerOrGuardian() public {
    vm.prank(user);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, user)
    );
    migrator.updateGuardian(invalidUser);
  }

  function test_PauseUnpause_ByPauseGuardian() public {
    _stake(user, 90e18);

    vm.prank(pauseGuardian);
    migrator.pause();

    assertTrue(migrator.paused());
    _expectMigrateRevert(user, abi.encodeWithSelector(Pausable.EnforcedPause.selector));

    vm.prank(ownerMigrator);
    migrator.unpause();

    assertFalse(migrator.paused());
    _migrateAndValidate(user);
  }

  function test_PauseUnpause_ByOwner() public {
    vm.prank(ownerMigrator);
    migrator.pause();

    assertTrue(migrator.paused());

    vm.prank(ownerMigrator);
    migrator.unpause();

    assertFalse(migrator.paused());
  }

  // --- Test Setup ---
  function test_SetUp() public view {
    assertEq(migrator.owner(), ownerMigrator);
    assertEq(STKGHO.getAdmin(CLAIM_HELPER_ROLE), address(migrator));
  }

  // --- Tests migrate ---
  function test_Migrate() public {
    _stake(user, 90e18);

    assertEq(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertEq(STKGHO.balanceOf(user), 90e18);
    assertEq(STKGHO.previewRedeem(90e18), 90e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_WithExistingSGhoBalance() public {
    deal(address(GHO), user, 50e18);
    vm.startPrank(user);
    GHO.approve(address(SGHO), 50e18);
    SGHO.deposit(50e18, user);
    vm.stopPrank();
    _stake(user, 90e18);

    assertGt(SGHO.balanceOf(user), 0);
    _migrateAndValidate(user);
  }

  function test_Revert_Migrate_Twice() public {
    _stake(user, 90e18);
    _migrateAndValidate(user);

    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(IStkGhoMigrator.NoStkGhoSharesToRedeem.selector)
    );
  }

  function test_Migrate_PreexistingGhoBalanceStaysInMigrator() public {
    deal(address(GHO), address(migrator), 7e18);
    _stake(user, 90e18);

    _migrateAndValidate(user);

    assertEq(GHO.balanceOf(address(migrator)), 7e18);
  }

  function test_Migrate_StakeThenReturnFunds() public {
    _stake(user, 90e18);
    _returnFunds(1e18);

    uint256 expectedGho = STKGHO.previewRedeem(STKGHO.balanceOf(user));
    assertLt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertEq(STKGHO.balanceOf(user), 90e18);
    assertGt(expectedGho, 90e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_StakeThenRepeatedReturnFunds() public {
    _stake(user, 90e18);
    uint256 previousExchangeRate = STKGHO.getExchangeRate();
    for (uint256 i = 0; i < 5; i++) {
      _returnFunds(1_000e18);
      assertLt(STKGHO.getExchangeRate(), previousExchangeRate);
      previousExchangeRate = STKGHO.getExchangeRate();
    }

    uint256 expectedGho = STKGHO.previewRedeem(STKGHO.balanceOf(user));
    assertEq(STKGHO.balanceOf(user), 90e18);
    assertGt(expectedGho, 90e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_ReturnFundsThenStake() public {
    _returnFunds(1e18);
    _stake(user, 1_000e18);

    uint256 stkGhoShares = STKGHO.balanceOf(user);
    uint256 expectedGho = STKGHO.previewRedeem(stkGhoShares);
    assertLt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertLt(stkGhoShares, 1_000e18);
    assertGt(expectedGho, stkGhoShares);
    assertLe(expectedGho, 1_000e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_ReturnFundsThenStakeThenReturnFunds() public {
    _returnFunds(1e18);
    _stake(user, 1_000e18);
    uint256 stkGhoShares = STKGHO.balanceOf(user);
    uint256 ghoBeforeSecondReturn = STKGHO.previewRedeem(stkGhoShares);
    _returnFunds(1e18);

    uint256 expectedGho = STKGHO.previewRedeem(stkGhoShares);
    assertGt(expectedGho, ghoBeforeSecondReturn);

    _migrateAndValidate(user);
  }

  function test_Migrate_StakersBeforeAndAfterReturnFunds() public {
    address otherUser = makeAddr('OTHER_USER');
    _stake(user, 90e18);
    _returnFunds(1_000e18);
    _stake(otherUser, 500e18);

    assertEq(STKGHO.balanceOf(user), 90e18);
    assertLt(STKGHO.balanceOf(otherUser), 500e18);

    _migrateAndValidate(user);
    _migrateAndValidate(otherUser);
  }

  function test_Migrate_AfterSlash() public {
    _stake(user, 90e18);
    _slash(1_000e18);

    uint256 expectedGho = STKGHO.previewRedeem(STKGHO.balanceOf(user));
    assertGt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertLt(expectedGho, 90e18);

    _migrateAndValidate(user);
  }

  function test_Revert_Migrate_NoSGhoSharesReceived() public {
    _stake(user, 1);

    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(IStkGhoMigrator.NoSGhoSharesReceived.selector)
    );
  }

  function test_Revert_NoStkGhoSharesToRedeem() public {
    _expectMigrateRevert(
      invalidUser,
      abi.encodeWithSelector(IStkGhoMigrator.NoStkGhoSharesToRedeem.selector)
    );
  }

  function test_Revert_Not_Zero_Cooldown_Migrate() public {
    _stake(user, 90e18);
    _setCooldownSeconds(1 days);

    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(IStkGhoMigrator.CooldownPeriodNotZero.selector)
    );
  }

  function test_Migrate_WithActiveCooldownBelowBalance() public {
    _stake(user, 50e18);
    vm.prank(user);
    STKGHO.cooldown();
    _stake(user, 40e18);

    (, uint216 cooldownAmount) = IStakeTokenGetters(address(STKGHO)).stakersCooldowns(user);
    assertEq(cooldownAmount, 50e18);
    assertEq(STKGHO.balanceOf(user), 90e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_WithExpiredCooldown() public {
    _stake(user, 90e18);
    vm.prank(user);
    STKGHO.cooldown();
    vm.warp(block.timestamp + IStakeTokenGetters(address(STKGHO)).UNSTAKE_WINDOW() + 1);

    vm.prank(user);
    vm.expectRevert(bytes('UNSTAKE_WINDOW_FINISHED'));
    STKGHO.redeem(user, 90e18);

    _migrateAndValidate(user);
  }

  function test_Migrate_StkGhoReceivedByTransfer() public {
    address staker = makeAddr('STAKER');
    _stake(staker, 90e18);
    vm.prank(staker);
    assertTrue(IERC20(address(STKGHO)).transfer(user, 90e18));

    assertEq(STKGHO.balanceOf(user), 90e18);
    _migrateAndValidate(user);
  }

  function test_Revert_Migrate_WithoutClaimHelperRole() public {
    _stake(user, 90e18);
    _moveClaimHelperRole(makeAddr('NEW_CLAIM_HELPER'));

    _expectMigrateRevert(user, bytes('CALLER_NOT_CLAIM_HELPER'));
  }

  function test_Revert_SetClaimHelperPendingAdmin_WithoutClaimHelperRole() public {
    _moveClaimHelperRole(makeAddr('NEW_CLAIM_HELPER'));

    vm.prank(ownerMigrator);
    vm.expectRevert(bytes('CALLER_NOT_ROLE_ADMIN'));
    migrator.setClaimHelperPendingAdmin(makeAddr('NEW_PENDING_ADMIN'));
  }

  function test_Revert_Migrate_SGhoPaused() public {
    _stake(user, 90e18);
    vm.prank(EXECUTOR_LVL_1);
    IsGho(address(SGHO)).pause();

    assertFalse(migrator.paused());
    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, user, 90e18, 0)
    );
  }

  function test_Revert_Migrate_SGhoSupplyCapReached() public {
    _stake(user, 90e18);
    address depositor = makeAddr('DEPOSITOR');
    uint256 remainingCap = SGHO.maxDeposit(depositor);
    deal(address(GHO), depositor, remainingCap);
    vm.startPrank(depositor);
    GHO.approve(address(SGHO), remainingCap);
    SGHO.deposit(remainingCap, depositor);
    vm.stopPrank();

    uint256 capLeft = SGHO.maxDeposit(user);
    assertLt(capLeft, 90e18);
    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(
        ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector,
        user,
        90e18,
        capLeft
      )
    );
  }

  function test_Revert_Migrate_SGhoSupplyCapBelowAmount() public {
    _stake(user, 90e18);
    address depositor = makeAddr('DEPOSITOR');
    uint256 depositAmount = SGHO.maxDeposit(depositor) - 50e18;
    deal(address(GHO), depositor, depositAmount);
    vm.startPrank(depositor);
    GHO.approve(address(SGHO), depositAmount);
    SGHO.deposit(depositAmount, depositor);
    vm.stopPrank();

    uint256 remainingCap = SGHO.maxDeposit(user);
    assertGt(remainingCap, 0);
    assertLt(remainingCap, 90e18);
    _expectMigrateRevert(
      user,
      abi.encodeWithSelector(
        ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector,
        user,
        90e18,
        remainingCap
      )
    );
  }

  // --- Tests rescue ---
  function test_Rescue_erc20() public {
    vm.deal(user, 1 ether);
    deal(address(GHO), user, 1_000e18);
    deal(address(STKGHO), user, 90e18);
    deal(address(SGHO), user, 50e18);
    vm.startPrank(user);
    assertTrue(IERC20(GHO).transfer(address(migrator), 1_000e18));
    assertTrue(IERC20(STKGHO).transfer(address(migrator), 90e18));
    assertTrue(IERC20(SGHO).transfer(address(migrator), 50e18));
    vm.stopPrank();

    vm.startPrank(ownerMigrator);
    migrator.rescue(address(GHO), user, 1_000e18);
    migrator.rescue(address(STKGHO), user, 90e18);
    migrator.rescue(address(SGHO), user, 50e18);
    vm.stopPrank();

    assertEq(GHO.balanceOf(address(migrator)), 0);
    assertEq(STKGHO.balanceOf(address(migrator)), 0);
    assertEq(SGHO.balanceOf(address(migrator)), 0);
    assertEq(GHO.balanceOf(user), 1_000e18);
    assertEq(STKGHO.balanceOf(user), 90e18);
    assertEq(SGHO.balanceOf(user), 50e18);
  }

  function test_Revert_Rescue_Not_Owner() public {
    vm.deal(user, 1 ether);
    deal(address(GHO), user, 1_000e18);
    vm.prank(user);
    vm.expectRevert();
    migrator.rescue(address(GHO), user, 1_000e18);
  }

  function test_Revert_Rescue_Invalid_Address() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddress.selector);
    migrator.rescue(address(0), user, 1_000e18);

    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddress.selector);
    migrator.rescue(address(GHO), address(0), 1_000e18);
  }

  function test_Revert_Rescue_Invalid_Amount() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAmount.selector);
    migrator.rescue(address(GHO), user, 0);
  }

  // --- Tests setClaimHelperPendingAdmin ---
  function test_SetClaimHelperPendingAdmin() public {
    address newPendingAdmin = makeAddr('NEW_PENDING_ADMIN');

    vm.prank(ownerMigrator);
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);

    assertEq(STKGHO.getPendingAdmin(CLAIM_HELPER_ROLE), newPendingAdmin);
  }

  function test_Revert_SetClaimHelperPendingAdmin_InvalidAddress() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddress.selector);
    migrator.setClaimHelperPendingAdmin(address(0));
  }

  function test_Revert_SetClaimHelperPendingAdmin_NotOwner() public {
    address newPendingAdmin = makeAddr('NEW_PENDING_ADMIN');

    vm.prank(invalidUser);
    vm.expectRevert();
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);
  }

  // --- Tests transferOwnership ---
  function test_TransferOwnership_2Steps() public {
    address newOwner = makeAddr('NEW_OWNER');

    vm.prank(ownerMigrator);
    migrator.transferOwnership(newOwner);
    assertEq(migrator.pendingOwner(), newOwner);

    vm.prank(newOwner);
    migrator.acceptOwnership();
    assertEq(migrator.owner(), newOwner);
  }

  function test_Revert_TransferOwnership_NotOwner() public {
    address newOwner = makeAddr('NEW_OWNER');

    vm.prank(invalidUser);
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, invalidUser)
    );
    migrator.transferOwnership(newOwner);
  }

  function _moveClaimHelperRole(address newClaimHelper) internal {
    vm.prank(ownerMigrator);
    migrator.setClaimHelperPendingAdmin(newClaimHelper);
    vm.prank(newClaimHelper);
    STKGHO.claimRoleAdmin(CLAIM_HELPER_ROLE);

    assertEq(STKGHO.getAdmin(CLAIM_HELPER_ROLE), newClaimHelper);
  }
}
