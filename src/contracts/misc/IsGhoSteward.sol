// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/access/AccessControl.sol';

import {IsGhoSteward} from './interfaces/IsGhoSteward.sol';
import {IsGHO} from '../sgho/interfaces/IsGho.sol';

/**
 * @title sGhoSteward
 * @author BGD Labs
 * @notice Helper contract for managing rate and supply cap parameters for sGho.
 */
contract sGhoSteward is AccessControl, IsGhoSteward {
  /// @notice Current rate parameters
  RateConfig public rateConfig;
  /// @notice Supply cap limit
  uint208 public supplyCap;

  uint16 public immutable MAX_RATE;
  IsGHO public immutable sGHO;

  bytes32 public constant AMPLIFICATION_MANAGER_ROLE = keccak256('AMPLIFICATION_MANAGER_ROLE');
  bytes32 public constant FLOAT_RATE_MANAGER_ROLE = keccak256('FLOAT_RATE_MANAGER_ROLE');
  bytes32 public constant FIXED_RATE_MANAGER_ROLE = keccak256('FIXED_RATE_MANAGER_ROLE');
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  modifier rateRolesCheck(RateConfig calldata rateConfig_) {
    if (rateConfig.amplification != 0) {
      _checkRole(AMPLIFICATION_MANAGER_ROLE);
    }

    if (rateConfig.floatRate != 0) {
      _checkRole(FLOAT_RATE_MANAGER_ROLE);
    }

    if (rateConfig.fixedRate != 0) {
      _checkRole(FIXED_RATE_MANAGER_ROLE);
    }

    _;
  }

  constructor(address sGho, address governance, address ghoCommittee) {
    if (sGho == address(0) || governance == address(0) || ghoCommittee == address(0)) {
      revert ZeroAddress();
    }

    sGHO = IsGHO(sGho);
    MAX_RATE = sGHO.MAX_SAFE_RATE();

    _grantRole(DEFAULT_ADMIN_ROLE, governance);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `ghoCommittee`
    _grantRole(AMPLIFICATION_MANAGER_ROLE, ghoCommittee);
    _grantRole(FLOAT_RATE_MANAGER_ROLE, ghoCommittee);
    _grantRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, ghoCommittee);
  }

  function setRateConfig(RateConfig calldata rateConfig_) external rateRolesCheck(rateConfig_) {}

  function setAmplification(uint256 amplification_) external onlyRole(AMPLIFICATION_MANAGER_ROLE) {}

  function setFloatRate(uint256 floatRate_) external onlyRole(FLOAT_RATE_MANAGER_ROLE) {}

  function setFixedRate(uint256 fixedRate_) external onlyRole(FIXED_RATE_MANAGER_ROLE) {}

  function setSupplyCap(uint256 supplyCap_) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {}
}
