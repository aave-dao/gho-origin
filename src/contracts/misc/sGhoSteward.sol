// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {IsGhoSteward} from 'src/contracts/misc/interfaces/IsGhoSteward.sol';

/**
 * @title sGhoSteward
 * @author BGD Labs
 * @notice Helper contract for managing rate and supply cap parameters for sGho.
 */
contract sGhoSteward is AccessControl, IsGhoSteward {
  using SafeCast for uint256;

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

  /// @inheritdoc IsGhoSteward
  uint16 public immutable MAX_RATE;

  /// @notice sGho contract address
  IsGho internal immutable _sGho;

  /// @notice Current rate parameters
  RateConfig internal _rateConfig;

  constructor(address owner, address riskCouncil, address sGho) {
    if (owner == address(0) || riskCouncil == address(0) || sGho == address(0)) {
      revert ZeroAddress();
    }

    _sGho = IsGho(sGho);
    MAX_RATE = _sGho.MAX_SAFE_RATE();

    _grantRole(DEFAULT_ADMIN_ROLE, owner);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `riskCouncil`
    _grantRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil);
    _grantRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(FIXED_RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);
  }

  /// @inheritdoc IsGhoSteward
  function setRateConfig(
    RateConfig calldata rateConfig,
    uint40 effectiveAt
  ) external returns (uint16) {
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
      revert RateUnchanged();
    }

    return _setRateConfig(rateConfigCopy, effectiveAt);
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
  function previewTargetRate(RateConfig calldata rateConfig) external view returns (uint16) {
    return _computeRateConfig(rateConfig);
  }

  /// @inheritdoc IsGhoSteward
  function getRateConfig() external view returns (RateConfig memory) {
    return _rateConfig;
  }

  /// @inheritdoc IsGhoSteward
  function sGHO() external view returns (IsGho) {
    return _sGho;
  }

  function _setRateConfig(
    RateConfig memory rateConfig,
    uint40 effectiveAt
  ) internal returns (uint16) {
    uint16 targetRate = _computeRateConfig(rateConfig);

    _sGho.setTargetRate(targetRate, effectiveAt);
    _rateConfig = rateConfig;

    emit RateConfigUpdated({
      caller: msg.sender,
      targetRate: targetRate,
      effectiveAt: effectiveAt,
      amplification: rateConfig.amplification,
      floatRate: rateConfig.floatRate,
      fixedRate: rateConfig.fixedRate
    });

    return targetRate;
  }

  function _computeRateConfig(RateConfig memory rateConfig) internal view returns (uint16) {
    // In order to avoid overflow we cast to uint256, and check result later
    uint256 targetRate = (uint256(rateConfig.amplification) * rateConfig.floatRate) /
      AMPLIFICATION_DENOMINATOR +
      rateConfig.fixedRate;

    if (targetRate > MAX_RATE) {
      revert MaxRateExceeded();
    }

    return targetRate.toUint16();
  }
}
