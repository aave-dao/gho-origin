// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ERC20} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

import {IGhoVariableDebtTokenTransferHook} from './MockStakedToken/interfaces/IGhoVariableDebtTokenTransferHook.sol';
import {IMockStakedToken} from './MockStakedToken/interfaces/IMockStakedToken.sol';

/**
 * @title MockStakedToken
 * @notice Minimal mock, based on StakedAaveV3 from Aave's aave-stake-v1-5
 */
contract MockStakedToken is ERC20, IMockStakedToken {
  /// @notice GHO debt token to be used in the _beforeTokenTransfer hook
  IGhoVariableDebtTokenTransferHook public ghoDebtToken;

  IERC20 public immutable STAKED_TOKEN;
  IERC20 public immutable REWARD_TOKEN;

  constructor(
    IERC20 stakedToken,
    IERC20 rewardToken,
    IGhoVariableDebtTokenTransferHook newGHODebtToken
  ) ERC20('a', 'b') {
    STAKED_TOKEN = stakedToken;
    REWARD_TOKEN = rewardToken;
    ghoDebtToken = newGHODebtToken;
  }

  /// @inheritdoc IMockStakedToken
  function stake(address to, uint256 amount) external override {
    STAKED_TOKEN.transferFrom(msg.sender, address(this), amount);
    _mint(to, amount);
  }

  /**
   * @dev updateDiscountDistribution before any operation involving transfer of value: _transfer, _mint and _burn
   * @param from the from address
   * @param to the to address
   * @param amount the amount to transfer
   */
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    ghoDebtToken.updateDiscountDistribution(from, to, balanceOf(from), balanceOf(to), amount);
  }
}
