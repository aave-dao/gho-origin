// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {StkGhoMigratorProcedure} from 'src/deployments/contracts/procedures/StkGhoMigratorProcedure.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

interface IStakeTokenGetters {
  function EXCHANGE_RATE_UNIT() external view returns (uint256);

  function stakersCooldowns(
    address staker
  ) external view returns (uint40 timestamp, uint216 amount);

  function UNSTAKE_WINDOW() external view returns (uint256);
}

abstract contract StkGhoMigratorHelpers is Test, StkGhoMigratorProcedure {
  struct MigrationState {
    uint256 accountStkGho;
    uint256 accountSGho;
    uint256 accountGho;
    uint256 accountCooldownTimestamp;
    uint256 accountCooldownAmount;
    uint256 migratorGho;
    uint256 migratorStkGho;
    uint256 migratorSGho;
    uint256 stkGhoTotalSupply;
    uint256 stkGhoGhoBalance;
    uint256 stkGhoExchangeRate;
    uint256 sGhoTotalSupply;
    uint256 sGhoGhoBalance;
  }

  StkGhoMigrator public migrator;
  address public user = makeAddr('USER');
  address public ownerMigrator = makeAddr('OWNER_MIGRATOR');
  address public pauseGuardian = makeAddr('PAUSE_GUARDIAN');

  uint256 public constant SLASH_ADMIN_ROLE = 0;
  uint256 public constant COOLDOWN_ADMIN_ROLE = 1;
  uint256 public constant CLAIM_HELPER_ROLE = 2;

  IStakeToken public constant STKGHO = IStakeToken(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);
  IERC4626 public constant SGHO = IERC4626(0xE1753F2e00940cC31213dd92013cF019DFE4ca1d);
  IERC20 public constant GHO = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
  address public constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;

  /// @dev Migrates `account` and asserts every balance and supply affected by the migration.
  function _migrateAndValidate(address account) internal {
    MigrationState memory stateBefore = _migrationState(account);
    uint256 expectedGho = _expectedGhoRedeemed(stateBefore.accountStkGho);
    uint256 expectedSGhoShares = _expectedSGhoShares(expectedGho);
    assertEq(STKGHO.previewRedeem(stateBefore.accountStkGho), expectedGho, 'stkGHO previewRedeem');
    assertEq(SGHO.previewDeposit(expectedGho), expectedSGhoShares, 'sGHO previewDeposit');

    vm.expectEmit(address(migrator));
    emit IStkGhoMigrator.StkGhoMigrated(account, expectedGho);
    vm.prank(account);
    (uint256 ghoRedeemed, uint256 sGhoShares) = migrator.migrate();

    assertEq(ghoRedeemed, expectedGho, 'returned GHO redeemed');
    assertEq(sGhoShares, expectedSGhoShares, 'returned sGHO shares');
    assertLe(SGHO.previewRedeem(sGhoShares), ghoRedeemed, 'sGHO value above GHO redeemed');
    MigrationState memory stateAfter = _migrationState(account);
    assertEq(stateAfter.accountStkGho, 0, 'account stkGHO');
    assertEq(stateAfter.accountSGho, stateBefore.accountSGho + expectedSGhoShares, 'account sGHO');
    assertEq(stateAfter.accountGho, stateBefore.accountGho, 'account GHO');
    assertEq(stateAfter.accountCooldownTimestamp, 0, 'account cooldown timestamp');
    assertEq(stateAfter.accountCooldownAmount, 0, 'account cooldown amount');
    assertEq(stateAfter.migratorGho, stateBefore.migratorGho, 'migrator GHO');
    assertEq(stateAfter.migratorStkGho, stateBefore.migratorStkGho, 'migrator stkGHO');
    assertEq(stateAfter.migratorSGho, stateBefore.migratorSGho, 'migrator sGHO');
    assertEq(
      stateAfter.stkGhoTotalSupply,
      stateBefore.stkGhoTotalSupply - stateBefore.accountStkGho,
      'stkGHO total supply'
    );
    assertEq(
      stateAfter.stkGhoGhoBalance,
      stateBefore.stkGhoGhoBalance - expectedGho,
      'stkGHO GHO balance'
    );
    assertEq(stateAfter.stkGhoExchangeRate, stateBefore.stkGhoExchangeRate, 'stkGHO rate');
    assertEq(
      stateAfter.sGhoTotalSupply,
      stateBefore.sGhoTotalSupply + expectedSGhoShares,
      'sGHO total supply'
    );
    assertEq(stateAfter.sGhoGhoBalance, stateBefore.sGhoGhoBalance + expectedGho, 'sGHO GHO');
  }

  /// @dev Expects `migrate` to revert with `revertData` and asserts no balance or supply moved.
  function _expectMigrateRevert(address account, bytes memory revertData) internal {
    MigrationState memory stateBefore = _migrationState(account);

    vm.prank(account);
    vm.expectRevert(revertData);
    migrator.migrate();

    assertEq(keccak256(abi.encode(_migrationState(account))), keccak256(abi.encode(stateBefore)));
  }

  /// @dev stkGHO redeems `shares * EXCHANGE_RATE_UNIT / exchangeRate` GHO, rounded down.
  function _expectedGhoRedeemed(uint256 stkGhoShares) internal view returns (uint256) {
    return (stkGhoShares * _exchangeRateUnit()) / STKGHO.getExchangeRate();
  }

  function _exchangeRateUnit() internal view returns (uint256) {
    return IStakeTokenGetters(address(STKGHO)).EXCHANGE_RATE_UNIT();
  }

  /// @dev sGHO mints `assets * RAY / yieldIndex` shares, rounded down, where the yield index grows
  /// linearly at `ratePerSecond` since `lastUpdate`.
  function _expectedSGhoShares(uint256 assets) internal view returns (uint256) {
    IsGho sGho = IsGho(address(SGHO));
    uint256 yieldIndex = sGho.yieldIndex();
    uint256 elapsed = block.timestamp - sGho.lastUpdate();
    if (sGho.ratePerSecond() != 0 && elapsed != 0) {
      yieldIndex =
        (yieldIndex * (WadRayMath.RAY + uint256(sGho.ratePerSecond()) * elapsed)) /
        WadRayMath.RAY;
    }
    return (assets * WadRayMath.RAY) / yieldIndex;
  }

  function _migrationState(address account) internal view returns (MigrationState memory) {
    (uint40 cooldownTimestamp, uint216 cooldownAmount) = IStakeTokenGetters(address(STKGHO))
      .stakersCooldowns(account);
    return
      MigrationState({
        accountStkGho: STKGHO.balanceOf(account),
        accountSGho: SGHO.balanceOf(account),
        accountGho: GHO.balanceOf(account),
        accountCooldownTimestamp: cooldownTimestamp,
        accountCooldownAmount: cooldownAmount,
        migratorGho: GHO.balanceOf(address(migrator)),
        migratorStkGho: STKGHO.balanceOf(address(migrator)),
        migratorSGho: SGHO.balanceOf(address(migrator)),
        stkGhoTotalSupply: STKGHO.totalSupply(),
        stkGhoGhoBalance: GHO.balanceOf(address(STKGHO)),
        stkGhoExchangeRate: STKGHO.getExchangeRate(),
        sGhoTotalSupply: SGHO.totalSupply(),
        sGhoGhoBalance: GHO.balanceOf(address(SGHO))
      });
  }

  function _stake(address staker, uint256 amount) internal {
    deal(address(GHO), staker, amount);
    vm.startPrank(staker);
    GHO.approve(address(STKGHO), amount);
    STKGHO.stake(staker, amount);
    vm.stopPrank();
  }

  function _returnFunds(uint256 amount) internal {
    address donor = makeAddr('DONOR');
    deal(address(GHO), donor, amount);
    vm.startPrank(donor);
    GHO.approve(address(STKGHO), amount);
    STKGHO.returnFunds(amount);
    vm.stopPrank();
  }

  function _slash(uint256 amount) internal {
    vm.startPrank(STKGHO.getAdmin(SLASH_ADMIN_ROLE));
    STKGHO.setMaxSlashablePercentage(10_00);
    STKGHO.slash(makeAddr('SLASH_RECEIVER'), amount);
    vm.stopPrank();
  }

  function _setCooldownSeconds(uint256 cooldownSeconds) internal {
    vm.prank(STKGHO.getAdmin(COOLDOWN_ADMIN_ROLE));
    STKGHO.setPendingAdmin(COOLDOWN_ADMIN_ROLE, address(this));
    STKGHO.claimRoleAdmin(COOLDOWN_ADMIN_ROLE);
    STKGHO.setCooldownSeconds(cooldownSeconds);
  }
}
