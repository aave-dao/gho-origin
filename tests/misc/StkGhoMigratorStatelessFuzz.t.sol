// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {StkGhoMigratorHelpers} from './StkGhoMigratorHelpers.t.sol';

contract StkGhoMigratorStatelessFuzz is StkGhoMigratorHelpers {
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

  // --- Stateless fuzz tests: migrate ---
  // Fuzzes the migration amount while keeping it within the sGHO deposit capacity.
  // The lower bound skips the 1 wei case, which is covered separately as a zero-share revert.
  function testFuzz_Migrate(uint256 amount) public {
    uint256 maxDeposit = SGHO.maxDeposit(address(migrator));
    vm.assume(maxDeposit >= 2);
    amount = bound(amount, 2, maxDeposit);

    _stake(user, amount);
    assertEq(STKGHO.balanceOf(user), amount);
    assertEq(STKGHO.previewRedeem(amount), amount);

    _migrateAndValidate(user);
  }

  // Fuzzes a stake followed by a permissionless `returnFunds` donation, which moves the stkGHO
  // exchange rate below 1e18 so each share redeems for more than 1 GHO.
  function testFuzz_Migrate_StakeThenReturnFunds(uint256 amount, uint256 donation) public {
    amount = bound(amount, 1e18, 1_000_000e18);
    donation = bound(donation, 1e18, 10_000_000e18);

    _stake(user, amount);
    _returnFunds(donation);

    assertLt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertEq(STKGHO.balanceOf(user), amount);
    uint256 expectedGho = STKGHO.previewRedeem(amount);
    assertGt(expectedGho, amount);

    _migrateAndValidate(user);
  }

  // Fuzzes a permissionless `returnFunds` donation followed by a stake at the moved exchange rate.
  function testFuzz_Migrate_ReturnFundsThenStake(uint256 amount, uint256 donation) public {
    amount = bound(amount, 1e18, 1_000_000e18);
    donation = bound(donation, 1e18, 10_000_000e18);

    _returnFunds(donation);
    assertLt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    _stake(user, amount);

    uint256 stkGhoShares = STKGHO.balanceOf(user);
    uint256 expectedGho = STKGHO.previewRedeem(stkGhoShares);
    assertLt(stkGhoShares, amount);
    assertGt(expectedGho, stkGhoShares);
    assertLe(expectedGho, amount);

    _migrateAndValidate(user);
  }

  // Fuzzes a governance slash after the stake, which moves the stkGHO exchange rate above 1e18 so
  // each share redeems for less than 1 GHO.
  function testFuzz_Migrate_StakeThenSlash(uint256 amount, uint256 slashAmount) public {
    amount = bound(amount, 1e18, 1_000_000e18);
    _stake(user, amount);

    uint256 totalAssets = STKGHO.previewRedeem(STKGHO.totalSupply());
    slashAmount = bound(slashAmount, totalAssets / 1e6, totalAssets / 10);
    _slash(slashAmount);

    assertGt(STKGHO.getExchangeRate(), _exchangeRateUnit());
    assertEq(STKGHO.balanceOf(user), amount);
    assertLt(STKGHO.previewRedeem(amount), amount);

    _migrateAndValidate(user);
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

  // --- Helper functions ---
  function _boundToken(uint256 tokenIndex) internal pure returns (IERC20) {
    uint256 boundedIndex = bound(tokenIndex, 0, 2);

    if (boundedIndex == 0) return GHO;
    if (boundedIndex == 1) return IERC20(address(STKGHO));
    return IERC20(address(SGHO));
  }
}
