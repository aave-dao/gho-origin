// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IRoleManager} from './interfaces/IRoleManager.sol';

contract StkGhoMigratorForkTest is Test {
  StkGhoMigrator public migrator;
  address public user = makeAddr('USER');
  address public user2 = makeAddr('USER2');
  address public ownerMigrator = makeAddr('OWNER_MIGRATOR');
  address public pauseGuardian = makeAddr('PAUSE_GUARDIAN');
  IStakeToken public constant STKGHO = IStakeToken(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);
  IERC4626 public constant SGHO = IERC4626(0xE1753F2e00940cC31213dd92013cF019DFE4ca1d);
  IERC20 public constant GHO = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
  IRoleManager public role = IRoleManager(address(STKGHO));
  uint256 constant CLAIM_HELPER_ROLE = 2;
  uint256 constant COOLDOWN_ADMIN_ROLE = 1;

  modifier depositStkGhoReadyToRedeem() {
    vm.deal(user2, 1 ether);
    deal(address(GHO), user2, 1_000e18);
    vm.startPrank(user2);
    IERC20(GHO).approve(address(STKGHO), 90e18);
    STKGHO.stake(user2, 90e18);
    vm.warp(block.timestamp + 30 days);
    vm.stopPrank();
    _;
  }
  modifier changeCooldownToNotZero() {
    address adminCooldown = role.getAdmin(COOLDOWN_ADMIN_ROLE);
    vm.prank(adminCooldown);
    role.setPendingAdmin(COOLDOWN_ADMIN_ROLE, address(this));
    role.claimRoleAdmin(COOLDOWN_ADMIN_ROLE);
    STKGHO.setCooldownSeconds(86400); // Set cooldown to 1 day
    _;
  }

  function setUp() public {
    // Skip if RPC_MAINNET env variable is not set.
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc);
    migrator = new StkGhoMigrator(ownerMigrator, pauseGuardian);

    address admin = role.getAdmin(CLAIM_HELPER_ROLE);
    vm.prank(admin);
    role.setPendingAdmin(CLAIM_HELPER_ROLE, address(migrator));
    migrator.claimHelperRole();
  }

  // --- Test Constructor ---

  function test_Constructor() public {
    StkGhoMigrator freshMigrator = new StkGhoMigrator(ownerMigrator, pauseGuardian);

    assertEq(freshMigrator.owner(), ownerMigrator);
    assertEq(freshMigrator.pauseGuardian(), pauseGuardian);
    assertEq(GHO.allowance(address(freshMigrator), address(SGHO)), type(uint256).max);
    assertEq(address(freshMigrator.STKGHO()), address(STKGHO));
    assertEq(address(freshMigrator.SGHO()), address(SGHO));
    assertEq(address(freshMigrator.GHO()), address(GHO));
    assertEq(freshMigrator.CLAIM_HELPER_ROLE(), CLAIM_HELPER_ROLE);
  }

  function test_Revert_Constructor_InvalidPauseGuardian() public {
    vm.expectRevert(IStkGhoMigrator.InvalidAddressZero.selector);
    new StkGhoMigrator(ownerMigrator, address(0));
  }

  // --- Test Deployment and Role Claiming ---
  function test_ClaimHelperRole_FreshDeploy() public {
    StkGhoMigrator freshMigrator = new StkGhoMigrator(ownerMigrator, pauseGuardian);

    assertNotEq(role.getAdmin(CLAIM_HELPER_ROLE), address(freshMigrator));

    vm.expectRevert(bytes('CALLER_NOT_PENDING_ROLE_ADMIN'));
    freshMigrator.claimHelperRole();

    address admin = role.getAdmin(CLAIM_HELPER_ROLE);

    vm.prank(admin);
    role.setPendingAdmin(CLAIM_HELPER_ROLE, address(freshMigrator));

    freshMigrator.claimHelperRole();

    assertEq(role.getAdmin(CLAIM_HELPER_ROLE), address(freshMigrator));
  }

  // --- Test Pause Guardian ---
  function test_PauseGuardian_FreshDeploy() public view {
    assertEq(migrator.pauseGuardian(), pauseGuardian);
  }

  function test_SetPauseGuardian() public {
    address newPauseGuardian = makeAddr('NEW_PAUSE_GUARDIAN');

    vm.expectEmit(true, true, false, true);
    emit IStkGhoMigrator.PauseGuardianUpdated(pauseGuardian, newPauseGuardian);

    vm.prank(ownerMigrator);
    migrator.setPauseGuardian(newPauseGuardian);

    assertEq(migrator.pauseGuardian(), newPauseGuardian);
  }

  function test_SetPauseGuardian_UpdatesPausePermissions() public {
    address newPauseGuardian = makeAddr('NEW_PAUSE_GUARDIAN');

    vm.prank(ownerMigrator);
    migrator.setPauseGuardian(newPauseGuardian);

    vm.prank(pauseGuardian);
    vm.expectRevert(IStkGhoMigrator.CallerNotOwnerOrPauseGuardian.selector);
    migrator.pause();

    vm.prank(newPauseGuardian);
    migrator.pause();

    assertTrue(migrator.paused());
  }

  function test_Revert_SetPauseGuardian_InvalidAddressZero() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddressZero.selector);
    migrator.setPauseGuardian(address(0));
  }

  function test_Revert_SetPauseGuardian_SamePauseGuardian() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidSamePauseGuardian.selector);
    migrator.setPauseGuardian(pauseGuardian);
  }

  function test_Revert_SetPauseGuardian_NotOwner() public {
    vm.prank(user2);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
    migrator.setPauseGuardian(user);
  }

  function test_PauseUnpause_ByPauseGuardian() public depositStkGhoReadyToRedeem {
    uint256 sGhoSharesBefore = SGHO.balanceOf(user2);

    vm.prank(pauseGuardian);
    migrator.pause();

    assertTrue(migrator.paused());

    vm.prank(user2);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    migrator.migrate();

    vm.prank(pauseGuardian);
    migrator.unpause();

    assertFalse(migrator.paused());

    vm.prank(user2);
    migrator.migrate();

    assertEq(STKGHO.balanceOf(user2), 0);
    assertEq(GHO.balanceOf(address(migrator)), 0);
    assertGt(SGHO.balanceOf(user2), sGhoSharesBefore);
  }

  function test_PauseUnpause_ByOwner() public {
    vm.prank(ownerMigrator);
    migrator.pause();

    assertTrue(migrator.paused());

    vm.prank(ownerMigrator);
    migrator.unpause();

    assertFalse(migrator.paused());
  }

  function test_Revert_Pause_NotOwnerOrPauseGuardian() public {
    vm.prank(user2);
    vm.expectRevert(IStkGhoMigrator.CallerNotOwnerOrPauseGuardian.selector);
    migrator.pause();
  }

  function test_Revert_Unpause_NotOwnerOrPauseGuardian() public {
    vm.prank(user2);
    vm.expectRevert(IStkGhoMigrator.CallerNotOwnerOrPauseGuardian.selector);
    migrator.unpause();
  }

  // --- Test Setup ---
  function test_SetUp() public view {
    assertEq(migrator.owner(), ownerMigrator);
    assertEq(role.getAdmin(CLAIM_HELPER_ROLE), address(migrator));
  }

  // --- Tests migrate ---
  function test_Migrate() public depositStkGhoReadyToRedeem {
    uint256 stkGhoShares = STKGHO.balanceOf(user2);
    uint256 sGhoSharesBefore = SGHO.balanceOf(user2);

    vm.prank(user2);
    migrator.migrate();

    assertEq(STKGHO.balanceOf(user2), 0);
    assertGt(SGHO.balanceOf(user2), sGhoSharesBefore);
    assertEq(GHO.balanceOf(address(migrator)), 0);
    assertGt(stkGhoShares, 0);
  }

  function test_Revert_Migrate_NoSGhoSharesReceived() public {
    uint256 amount = 1;

    vm.deal(user2, 1 ether);
    deal(address(GHO), user2, amount);
    vm.startPrank(user2);
    IERC20(GHO).approve(address(STKGHO), amount);
    STKGHO.stake(user2, amount);
    vm.stopPrank();

    vm.expectRevert(IStkGhoMigrator.NoSGhoSharesReceived.selector);
    vm.prank(user2);
    migrator.migrate();
  }

  function test_Revert_NoStkGhoSharesToRedeem() public {
    vm.prank(user);
    vm.expectRevert(IStkGhoMigrator.NoStkGhoSharesToRedeem.selector);
    migrator.migrate();
  }

  function test_Revert_Not_Zero_Cooldown_Migrate()
    public
    depositStkGhoReadyToRedeem
    changeCooldownToNotZero
  {
    vm.prank(user2);
    vm.expectRevert(IStkGhoMigrator.CooldownPeriodNotZero.selector);
    migrator.migrate();
  }

  // Mock the calls to simulate redeeming stkGHO but receiving an unexpected amount of GHO.
  function test_Revert_UnexpectedGhoRedeemed() public {
    uint256 stkGhoShares = 90e18;

    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.getCooldownSeconds.selector),
      abi.encode(0)
    );

    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, user2),
      abi.encode(stkGhoShares)
    );

    vm.mockCall(
      address(GHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(migrator)),
      abi.encode(0)
    );

    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(IStakeToken.cooldownOnBehalfOf.selector, user2),
      ''
    );

    vm.mockCall(
      address(STKGHO),
      abi.encodeWithSelector(
        IStakeToken.redeemOnBehalf.selector,
        user2,
        address(migrator),
        stkGhoShares
      ),
      ''
    );

    vm.prank(user2);
    vm.expectRevert(IStkGhoMigrator.UnexpectedGhoRedeemed.selector);
    migrator.migrate();
  }

  // --- Tests rescue ---
  function test_Rescue_erc20() public {
    vm.deal(user2, 1 ether);
    deal(address(GHO), user2, 1_000e18);
    deal(address(STKGHO), user2, 90e18);
    deal(address(SGHO), user2, 50e18);
    vm.startPrank(user2);
    assertTrue(IERC20(GHO).transfer(address(migrator), 1_000e18));
    assertTrue(IERC20(STKGHO).transfer(address(migrator), 90e18));
    assertTrue(IERC20(SGHO).transfer(address(migrator), 50e18));
    vm.stopPrank();

    vm.startPrank(ownerMigrator);
    migrator.rescue(address(GHO), user2, 1_000e18);
    migrator.rescue(address(STKGHO), user2, 90e18);
    migrator.rescue(address(SGHO), user2, 50e18);
    vm.stopPrank();

    assertEq(GHO.balanceOf(address(migrator)), 0);
    assertEq(STKGHO.balanceOf(address(migrator)), 0);
    assertEq(SGHO.balanceOf(address(migrator)), 0);
    assertEq(GHO.balanceOf(user2), 1_000e18);
    assertEq(STKGHO.balanceOf(user2), 90e18);
    assertEq(SGHO.balanceOf(user2), 50e18);
  }

  function test_Revert_Rescue_Not_Owner() public {
    vm.deal(user2, 1 ether);
    deal(address(GHO), user2, 1_000e18);
    vm.prank(user2);
    vm.expectRevert();
    migrator.rescue(address(GHO), user2, 1_000e18);
  }

  function test_Revert_Rescue_Invalid_Address() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddressZero.selector);
    migrator.rescue(address(0), user2, 1_000e18);

    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddressZero.selector);
    migrator.rescue(address(GHO), address(0), 1_000e18);
  }

  function test_Revert_Rescue_Invalid_Amount() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAmount.selector);
    migrator.rescue(address(GHO), user2, 0);
  }

  // --- Tests setClaimHelperPendingAdmin ---
  function test_SetClaimHelperPendingAdmin() public {
    address newPendingAdmin = makeAddr('NEW_PENDING_ADMIN');

    vm.prank(ownerMigrator);
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);

    assertEq(role.getPendingAdmin(CLAIM_HELPER_ROLE), newPendingAdmin);
  }

  function test_Revert_SetClaimHelperPendingAdmin_InvalidAddressZero() public {
    vm.prank(ownerMigrator);
    vm.expectRevert(IStkGhoMigrator.InvalidAddressZero.selector);
    migrator.setClaimHelperPendingAdmin(address(0));
  }

  function test_Revert_SetClaimHelperPendingAdmin_NotOwner() public {
    address newPendingAdmin = makeAddr('NEW_PENDING_ADMIN');

    vm.prank(user);
    vm.expectRevert();
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);
  }
}
