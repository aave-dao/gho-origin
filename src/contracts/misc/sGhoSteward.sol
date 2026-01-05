// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/access/AccessControl.sol';
import {SafeCast} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

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
  RateConfig internal _rateConfig;

  /// @notice sGho contract address
  IsGHO internal immutable _sGHO;

  /// @inheritdoc IsGhoSteward
  uint16 public immutable MAX_RATE;

  /// @inheritdoc IsGhoSteward
  uint16 public constant AMPLIFICATION_DENOMINATOR = 100_00;

  /// @inheritdoc IsGhoSteward
  bytes32 public constant AMPLIFICATION_MANAGER_ROLE = keccak256('AMPLIFICATION_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant FLOAT_RATE_MANAGER_ROLE = keccak256('FLOAT_RATE_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant FIXED_RATE_MANAGER_ROLE = keccak256('FIXED_RATE_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  constructor(address sGho, address governance, address ghoCommittee) {
    if (sGho == address(0) || governance == address(0) || ghoCommittee == address(0)) {
      revert ZeroAddress();
    }

    _sGHO = IsGHO(sGho);
    MAX_RATE = _sGHO.MAX_SAFE_RATE();

    _grantRole(DEFAULT_ADMIN_ROLE, governance);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `ghoCommittee`
    _grantRole(AMPLIFICATION_MANAGER_ROLE, ghoCommittee);
    _grantRole(FLOAT_RATE_MANAGER_ROLE, ghoCommittee);
    _grantRole(FIXED_RATE_MANAGER_ROLE, ghoCommittee);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, ghoCommittee);
  }

  /// @inheritdoc IsGhoSteward
  function setRateConfig(RateConfig calldata rateConfig) external returns (uint16) {
    RateConfig memory rateConfigCopy = _rateConfig;
    bool isRateChanged;

    if (rateConfigCopy.amplification != rateConfig.amplification) {
      _checkRole(AMPLIFICATION_MANAGER_ROLE);

      isRateChanged = true;
      rateConfigCopy.amplification = rateConfig.amplification;
    }

    if (rateConfigCopy.floatRate != rateConfig.floatRate) {
      _checkRole(FLOAT_RATE_MANAGER_ROLE);

      isRateChanged = true;
      rateConfigCopy.floatRate = rateConfig.floatRate;
    }

    if (rateConfigCopy.fixedRate != rateConfig.fixedRate) {
      _checkRole(FIXED_RATE_MANAGER_ROLE);

      isRateChanged = true;
      rateConfigCopy.fixedRate = rateConfig.fixedRate;
    }

    if (!isRateChanged) {
      revert SameValue();
    }

    return _setRateConfig(rateConfigCopy);
  }

  /// @inheritdoc IsGhoSteward
  function setSupplyCap(uint256 supplyCap) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {
    uint256 currentSupplyCap = _sGHO.supplyCap();

    if (currentSupplyCap == supplyCap) {
      revert SameValue();
    }

    _sGHO.setSupplyCap(supplyCap.toUint160());
    emit SupplyCapUpdated(msg.sender, supplyCap);
  }

  /// @inheritdoc IsGhoSteward
  function previewTargetRate(RateConfig calldata rateConfig) external view returns (uint16) {
    return _checkRateConfig(rateConfig);
  }

  /// @inheritdoc IsGhoSteward
  function getRateConfig() external view returns (RateConfig memory) {
    return _rateConfig;
  }

  /// @inheritdoc IsGhoSteward
  function sGHO() external view returns (IsGHO) {
    return _sGHO;
  }

  function _setRateConfig(RateConfig memory rateConfig) internal returns (uint16) {
    uint16 targetRate = _checkRateConfig(rateConfig);

    _sGHO.setTargetRate(targetRate);
    _rateConfig = rateConfig;

    emit RateConfigUpdated(
      msg.sender,
      targetRate,
      rateConfig.amplification,
      rateConfig.floatRate,
      rateConfig.fixedRate
    );

    return targetRate;
  }

  function _checkRateConfig(RateConfig memory rateConfig_) internal view returns (uint16) {
    // In order to avoid overflow we cast to uint256, and check result later
    uint256 targetRate = (uint256(rateConfig_.amplification) * rateConfig_.floatRate) /
      AMPLIFICATION_DENOMINATOR +
      rateConfig_.fixedRate;

    if (targetRate > MAX_RATE) {
      revert RateTooBig();
    }

    return targetRate.toUint16();
  }
}
