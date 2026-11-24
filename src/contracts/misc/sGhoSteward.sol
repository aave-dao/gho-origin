// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {IsGhoSteward} from 'src/contracts/misc/interfaces/IsGhoSteward.sol';

/**
 * @title sGhoSteward
 * @author BGD Labs
 * @notice Helper contract for managing rate and supply cap parameters for sGho.
 */
contract sGhoSteward is AccessControl, IsGhoSteward {
  /// @inheritdoc IsGhoSteward
  bytes32 public constant RATE_MANAGER_ROLE = keccak256('RATE_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  /// @notice sGho contract address
  IsGho internal immutable _sGho;

  constructor(address owner, address riskCouncil, address sGho) {
    if (owner == address(0) || riskCouncil == address(0) || sGho == address(0)) {
      revert ZeroAddress();
    }

    _sGho = IsGho(sGho);

    _grantRole(DEFAULT_ADMIN_ROLE, owner);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `riskCouncil`
    _grantRole(RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);
  }

  /// @inheritdoc IsGhoSteward
  function setTargetRate(
    uint16 targetRate,
    uint40 effectiveAt
  ) external onlyRole(RATE_MANAGER_ROLE) {
    (, uint40 pendingEffectiveAt) = _sGho.pendingTargetRate();
    if (pendingEffectiveAt == 0 && targetRate == _sGho.targetRate()) {
      revert RateUnchanged();
    }

    _sGho.setTargetRate(targetRate, effectiveAt);
    emit TargetRateUpdated(msg.sender, targetRate, effectiveAt);
  }

  /// @inheritdoc IsGhoSteward
  function setSupplyCap(uint256 supplyCap) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {
    uint256 currentSupplyCap = _sGho.supplyCap();

    if (currentSupplyCap == supplyCap) {
      revert SupplyCapUnchanged();
    }

    _sGho.setSupplyCap(supplyCap);
    emit SupplyCapUpdated(msg.sender, supplyCap);
  }

  /// @inheritdoc IsGhoSteward
  function sGHO() external view returns (IsGho) {
    return _sGho;
  }
}
