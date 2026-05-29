// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IStakeToken} from 'aave-address-book/common/IStakeToken.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';

contract StkGhoMigratorStatelessFuzz is Test {
  StkGhoMigrator public migrator;
  address public user = makeAddr('USER');
  address public ownerMigrator = makeAddr('OWNER_MIGRATOR');
  address public pauseGuardian = makeAddr('PAUSE_GUARDIAN');
  IStakeToken public constant STKGHO = IStakeToken(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);
  IERC4626 public constant SGHO = IERC4626(0xE1753F2e00940cC31213dd92013cF019DFE4ca1d);
  IERC20 public constant GHO = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
  uint256 constant CLAIM_HELPER_ROLE = 2;

  function setUp() public {
    // Skip if RPC_MAINNET env variable is not set.
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc);
    migrator = new StkGhoMigrator(ownerMigrator, pauseGuardian);

    address admin = STKGHO.getAdmin(CLAIM_HELPER_ROLE);
    vm.prank(admin);
    STKGHO.setPendingAdmin(CLAIM_HELPER_ROLE, address(migrator));

    migrator.claimHelperRole();
  }

  // --- Stateless fuzz tests: migrate ---
  // Fuzzes the migration amount while keeping it within the sGHO deposit capacity.
  // The lower bound skips the 1 wei case, which is covered separately as a zero-share revert.
  function testFuzz_Migrate(uint256 amount) public {
    uint256 maxDeposit = SGHO.maxDeposit(address(migrator));
    vm.assume(maxDeposit >= 2);
    amount = bound(amount, 2, maxDeposit);

    vm.deal(user, 1 ether);
    deal(address(GHO), user, amount);
    vm.startPrank(user);
    IERC20(GHO).approve(address(STKGHO), amount);
    STKGHO.stake(user, amount);
    vm.stopPrank();

    uint256 stkGhoShares = STKGHO.balanceOf(user);
    uint256 sGhoSharesBefore = SGHO.balanceOf(user);

    vm.prank(user);
    migrator.migrate();

    assertEq(STKGHO.balanceOf(user), 0);
    assertGt(SGHO.balanceOf(user), sGhoSharesBefore);
    assertEq(GHO.balanceOf(address(migrator)), 0);
    assertEq(stkGhoShares, amount);
    assertGt(stkGhoShares, 0);
  }

  // --- Fuzzing Tests rescue ---
  function testFuzz_RescueFull(uint256 tokenIndex, address to, uint256 amount) public {
    IERC20 token = _boundToken(tokenIndex);
    vm.assume(to != address(0));
    vm.assume(to != address(migrator));

    amount = bound(amount, 1, 1_000_000e18);

    deal(address(token), address(migrator), amount);

    uint256 toBalanceBefore = token.balanceOf(to);

    vm.prank(ownerMigrator);
    migrator.rescue(address(token), to, amount);

    assertEq(token.balanceOf(address(migrator)), 0);
    assertEq(token.balanceOf(to), toBalanceBefore + amount);
  }

  function testFuzz_RescuePartial(
    uint256 tokenIndex,
    address to,
    uint256 amount,
    uint256 rescueAmount
  ) public {
    IERC20 token = _boundToken(tokenIndex);
    vm.assume(to != address(0));
    vm.assume(to != address(migrator));

    amount = bound(amount, 1, 1_000_000e18);
    rescueAmount = bound(rescueAmount, 1, amount);

    deal(address(token), address(migrator), amount);

    uint256 toBalanceBefore = token.balanceOf(to);

    vm.prank(ownerMigrator);
    migrator.rescue(address(token), to, rescueAmount);

    assertEq(token.balanceOf(address(migrator)), amount - rescueAmount);
    assertEq(token.balanceOf(to), toBalanceBefore + rescueAmount);
  }

  // --- Fuzzing Tests setClaimHelperPendingAdmin ---
  function testFuzz_SetClaimHelperPendingAdmin(address newPendingAdmin) public {
    vm.assume(newPendingAdmin != address(0));

    vm.prank(ownerMigrator);
    migrator.setClaimHelperPendingAdmin(newPendingAdmin);

    assertEq(STKGHO.getPendingAdmin(CLAIM_HELPER_ROLE), newPendingAdmin);
  }

  // --- Fuzzing Tests setPauseGuardian ---
  function testFuzz_SetPauseGuardian(address newPauseGuardian) public {
    vm.assume(newPauseGuardian != address(0));
    vm.assume(newPauseGuardian != pauseGuardian);

    vm.prank(ownerMigrator);
    migrator.setPauseGuardian(newPauseGuardian);

    assertEq(migrator.pauseGuardian(), newPauseGuardian);
  }

  // --- Helper functions ---
  function _boundToken(uint256 tokenIndex) internal pure returns (IERC20) {
    uint256 boundedIndex = bound(tokenIndex, 0, 2);

    if (boundedIndex == 0) return GHO;
    if (boundedIndex == 1) return IERC20(address(STKGHO));
    return IERC20(address(SGHO));
  }
}
