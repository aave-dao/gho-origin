//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {StkGhoMigratorBaseTest} from './StkGhoMigratorBase.t.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';

contract StkGhoMigratorUnitTest is StkGhoMigratorBaseTest {
  function setUp() public {
    _deployMigratorWithMockedTargets();
  }

  // --- Test Constructor ---

  function test_Constructor_ApprovesSGhoMax() public {
    _etchIntegrationTargets();
    _mockGhoApprove(address(SGHO), type(uint256).max);

    vm.expectCall(
      address(GHO),
      abi.encodeWithSelector(IERC20.approve.selector, address(SGHO), type(uint256).max)
    );

    _deployStkGhoMigrator({initialOwner: ownerMigrator, initialPauseGuardian: pauseGuardian});
  }

  // --- Test claimHelperRole ---

  function test_ClaimHelperRole() public {
    _mockClaimRoleAdmin(CLAIM_HELPER_ROLE);

    vm.expectCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.claimRoleAdmin.selector, CLAIM_HELPER_ROLE)
    );

    migrator.claimHelperRole();
  }

  // --- Tests migrate ---

  function test_Migrate() public {
    uint256 stkGhoShares = 90e18;
    uint256 sGhoShares = 89e18;
    bytes[] memory ghoBalances = new bytes[](2);
    ghoBalances[0] = abi.encode(0);
    ghoBalances[1] = abi.encode(stkGhoShares);

    _mockCooldownSeconds(0);
    _mockStkGhoBalance(user, stkGhoShares);
    vm.mockCalls(
      address(GHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(migrator)),
      ghoBalances
    );
    _mockCooldownOnBehalfOf(user);
    _mockRedeemOnBehalf(user, address(migrator), stkGhoShares);
    _mockSGhoDeposit(stkGhoShares, user, sGhoShares);

    vm.expectCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.cooldownOnBehalfOf.selector, user)
    );
    vm.expectCall(
      address(STKGHO),
      abi.encodeWithSelector(
        IStakeToken.redeemOnBehalf.selector,
        user,
        address(migrator),
        stkGhoShares
      )
    );
    vm.expectCall(
      address(SGHO),
      abi.encodeWithSelector(IERC4626.deposit.selector, stkGhoShares, user)
    );
    vm.expectEmit(address(migrator));
    emit IStkGhoMigrator.StkGhoMigrated(user, stkGhoShares);

    vm.prank(user);
    migrator.migrate();
  }

  function test_Revert_Migrate_CooldownPeriodNotZero() public {
    _mockCooldownSeconds(1 days);

    vm.prank(user);
    vm.expectRevert(IStkGhoMigrator.CooldownPeriodNotZero.selector);
    migrator.migrate();
  }

  function test_Revert_Migrate_NoStkGhoSharesToRedeem() public {
    _mockCooldownSeconds(0);
    _mockStkGhoBalance(user, 0);

    vm.prank(user);
    vm.expectRevert(IStkGhoMigrator.NoStkGhoSharesToRedeem.selector);
    migrator.migrate();
  }

  function test_Revert_UnexpectedGhoRedeemed() public {
    uint256 stkGhoShares = 90e18;
    bytes[] memory ghoBalances = new bytes[](2);
    ghoBalances[0] = abi.encode(0);
    ghoBalances[1] = abi.encode(stkGhoShares - 1);

    _mockCooldownSeconds(0);
    _mockStkGhoBalance(user, stkGhoShares);
    vm.mockCalls(
      address(GHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(migrator)),
      ghoBalances
    );
    _mockCooldownOnBehalfOf(user);
    _mockRedeemOnBehalf(user, address(migrator), stkGhoShares);

    vm.prank(user);
    vm.expectRevert(IStkGhoMigrator.UnexpectedGhoRedeemed.selector);
    migrator.migrate();
  }

  function test_Revert_Migrate_NoSGhoSharesReceived() public {
    uint256 stkGhoShares = 90e18;
    bytes[] memory ghoBalances = new bytes[](2);
    ghoBalances[0] = abi.encode(0);
    ghoBalances[1] = abi.encode(stkGhoShares);

    _mockCooldownSeconds(0);
    _mockStkGhoBalance(user, stkGhoShares);
    vm.mockCalls(
      address(GHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(migrator)),
      ghoBalances
    );
    _mockCooldownOnBehalfOf(user);
    _mockRedeemOnBehalf(user, address(migrator), stkGhoShares);
    _mockSGhoDeposit(stkGhoShares, user, 0);

    vm.prank(user);
    vm.expectRevert(IStkGhoMigrator.NoSGhoSharesReceived.selector);
    migrator.migrate();
  }

  // --- Tests rescue ---

  function test_Rescue() public {
    _mockTokenTransfer(address(GHO), user, 100e18);
    vm.prank(ownerMigrator);
    migrator.rescue(address(GHO), user, 100e18);
  }

  function test_Revert_Rescue_NotOwner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    migrator.rescue(address(GHO), user, 100e18);
  }

  function test_Revert_Rescue_InvalidTokenAddress() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddress.selector);
    migrator.rescue(address(0), user, 100e18);
  }

  function test_Revert_Rescue_InvalidAmount() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAmount.selector);
    migrator.rescue(address(GHO), user, 0);
  }

  // --- Tests setClaimHelperPendingAdmin ---
  function test_SetClaimHelperPendingAdmin() public {
    address newPendingAdmin = makeAddr('NEW_PENDING_ADMIN');

    _mockSetPendingAdmin(CLAIM_HELPER_ROLE, newPendingAdmin);

    vm.expectCall(
      address(STKGHO),
      abi.encodeWithSelector(
        IStakeToken.setPendingAdmin.selector,
        CLAIM_HELPER_ROLE,
        newPendingAdmin
      )
    );

    vm.prank(ownerMigrator);
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);
  }
}
