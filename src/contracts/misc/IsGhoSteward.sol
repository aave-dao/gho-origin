// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/access/AccessControl.sol';
import {SafeCast} from 'openzeppelin-contracts/utils/math/SafeCast.sol';

import {IsGhoSteward} from './interfaces/IsGhoSteward.sol';
import {IsGHO} from '../sgho/interfaces/IsGho.sol';

/**
 * @title sGhoSteward
 * @author BGD Labs
 * @notice Helper contract for managing rate and supply cap parameters for sGho.
 */
contract sGhoSteward is AccessControl, IsGhoSteward {
  using SafeCast for uint256;

  /// @notice Current rate parameters
  RateConfig public rateConfig;

  IsGHO public immutable sGHO;
  uint16 public immutable MAX_RATE;

  uint16 public constant AMPLIFICATION_DENOMINATOR = 100_00;

  bytes32 public constant AMPLIFICATION_MANAGER_ROLE = keccak256('AMPLIFICATION_MANAGER_ROLE');
  bytes32 public constant FLOAT_RATE_MANAGER_ROLE = keccak256('FLOAT_RATE_MANAGER_ROLE');
  bytes32 public constant FIXED_RATE_MANAGER_ROLE = keccak256('FIXED_RATE_MANAGER_ROLE');
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

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

  function setRateConfig(RateConfig calldata rateConfig_) external {
    RateConfig memory rateConfigCopy = rateConfig;

    if (rateConfigCopy.amplification != rateConfig_.amplification) {
      _checkRole(AMPLIFICATION_MANAGER_ROLE);
      rateConfigCopy.amplification = rateConfig_.amplification;
    }

    if (rateConfigCopy.floatRate != rateConfig_.floatRate) {
      _checkRole(FLOAT_RATE_MANAGER_ROLE);
      rateConfigCopy.floatRate = rateConfig_.floatRate;
    }

    if (rateConfigCopy.fixedRate != rateConfig_.fixedRate) {
      _checkRole(FIXED_RATE_MANAGER_ROLE);
      rateConfigCopy.fixedRate = rateConfig_.fixedRate;
    }

    _setRateConfig(rateConfigCopy);
  }

  function setAmplification(uint256 amplification_) external onlyRole(AMPLIFICATION_MANAGER_ROLE) {
    RateConfig memory rateConfigCopy = rateConfig;

    if (rateConfigCopy.amplification == amplification_) {
      revert SameValue();
    }

    rateConfigCopy.amplification = amplification_.toUint16();
    _setRateConfig(rateConfigCopy);
  }

  function setFloatRate(uint256 floatRate_) external onlyRole(FLOAT_RATE_MANAGER_ROLE) {
    RateConfig memory rateConfigCopy = rateConfig;

    if (rateConfigCopy.floatRate == floatRate_) {
      revert SameValue();
    }

    rateConfigCopy.floatRate = floatRate_.toUint16();
    _setRateConfig(rateConfigCopy);
  }

  function setFixedRate(uint256 fixedRate_) external onlyRole(FIXED_RATE_MANAGER_ROLE) {
    RateConfig memory rateConfigCopy = rateConfig;

    if (rateConfigCopy.fixedRate == fixedRate_) {
      revert SameValue();
    }

    rateConfigCopy.fixedRate = fixedRate_.toUint16();
    _setRateConfig(rateConfigCopy);
  }

  function setSupplyCap(uint256 supplyCap_) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {
    uint256 currentSupplyCap = sGHO.supplyCap();

    if (currentSupplyCap == supplyCap_) {
      revert SameValue();
    }

    sGHO.setSupplyCap(supplyCap_);
    emit SupplyCapUpdated(msg.sender, supplyCap_);
  }

  function _setRateConfig(RateConfig memory rateConfig_) internal {
    uint16 targetRate = _checkRateConfig(rateConfig_);

    sGHO.setTargetRate(targetRate);
    rateConfig = rateConfig_;

    emit RateConfigUpdated(
      msg.sender,
      targetRate,
      rateConfig_.amplification,
      rateConfig_.floatRate,
      rateConfig_.fixedRate
    );
  }

  function _checkRateConfig(RateConfig memory rateConfig_) internal view returns (uint16) {
    uint16 targetRate = (rateConfig_.amplification * rateConfig_.floatRate) /
      AMPLIFICATION_DENOMINATOR +
      rateConfig_.fixedRate;

    if (targetRate < MAX_RATE) {
      revert TooBigRate();
    }

    return targetRate;
  }
}
