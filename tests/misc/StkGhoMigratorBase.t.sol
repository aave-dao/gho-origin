// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {StkGhoMigrator} from 'src/contracts/misc/StkGhoMigrator.sol';
import {IStakeToken} from 'src/contracts/misc/interfaces/IStakeToken.sol';
import {IStkGhoMigrator} from 'src/contracts/misc/interfaces/IStkGhoMigrator.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';

contract StkGhoMigratorMockTarget {}

abstract contract StkGhoMigratorBaseTest is Test {
  StkGhoMigrator public migrator;
  address public invalidUser = makeAddr('INVALID_USER');
  address public user = makeAddr('USER');
  address public ownerMigrator = makeAddr('OWNER_MIGRATOR');
  address public pauseGuardian = makeAddr('PAUSE_GUARDIAN');

  uint256 public constant CLAIM_HELPER_ROLE = 2;
  uint256 public constant COOLDOWN_ADMIN_ROLE = 1;

  IStakeToken public constant STKGHO = IStakeToken(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);
  IERC4626 public constant SGHO = IERC4626(0xE1753F2e00940cC31213dd92013cF019DFE4ca1d);
  IERC20 public constant GHO = IERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);

  function _deployMigratorWithMockedTargets() internal {
    _etchIntegrationTargets();
    _mockGhoApprove(address(SGHO), type(uint256).max);

    migrator = new StkGhoMigrator(ownerMigrator, pauseGuardian);
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

  function _mockGhoBalance(address account, uint256 balance) internal {
    vm.mockCall(
      address(GHO),
      abi.encodeWithSelector(IERC20.balanceOf.selector, account),
      abi.encode(balance)
    );
  }

  function _mockSGhoBalance(address account, uint256 balance) internal {
    vm.mockCall(
      address(SGHO),
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

  function _mockSGhoPreviewDeposit(uint256 assets, uint256 shares) internal {
    vm.mockCall(
      address(SGHO),
      abi.encodeWithSelector(IERC4626.previewDeposit.selector, assets),
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
  // function _mockSuccessfulMigration(
  //   address account,
  //   uint256 stkGhoShares,
  //   uint256 ghoBalanceBefore,
  //   uint256 sGhoShares
  // ) internal {
  //   _mockCooldownSeconds(0);
  //   _mockStkGhoBalance(account, stkGhoShares);
  //   _mockGhoBalance(address(migrator), ghoBalanceBefore);
  //   _mockCooldownOnBehalfOf(account);
  //   _mockRedeemOnBehalf(account, address(migrator), stkGhoShares);
  //   _mockGhoBalance(address(migrator), ghoBalanceBefore + stkGhoShares);
  //   _mockSGhoDeposit(stkGhoShares, account, sGhoShares);
  // }
}
