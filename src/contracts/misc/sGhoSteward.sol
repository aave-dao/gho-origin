// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {AccessControl} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/access/AccessControl.sol';
import {SafeCast} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
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
  uint256 public constant MINIMUM_DELAY = 1 days;

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
  bytes32 public constant SGHO_FUNDING_ROLE = keccak256('SGHO_FUNDING_ROLE');

  /// @inheritdoc IsGhoSteward
  uint16 public immutable MAX_RATE;

  /// @notice sGho contract address
  IsGho internal immutable SGHO;

  /// @notice sGho contract address
  ICollector internal immutable COLLECTOR;

  /// @notice Gho contract address
  IERC20 internal immutable GHO;

  /// @notice aEthLidoGho contract address
  IERC20 internal immutable PRIME_GHO;

  /// @notice Aave V3 Prime pool contract address
  IPool internal immutable POOL;

  /// @notice Current rate parameters
  RateConfig internal _rateConfig;

  /// @notice Last transfer made by the steward
  uint256 internal _lastTransferTimestamp;

  /// @notice The maximum amount that can be transfered at a time between timelocks.
  uint256 internal _maxTransferAmount = 100_000 ether;

  constructor(
    address owner,
    address riskCouncil,
    address sGho,
    address primeGho,
    address collector,
    address pool
  ) {
    if (
      owner == address(0) ||
      riskCouncil == address(0) ||
      sGho == address(0) ||
      primeGho == address(0) ||
      collector == address(0) ||
      pool == address(0)
    ) {
      revert ZeroAddress();
    }

    SGHO = IsGho(sGho);
    MAX_RATE = SGHO.MAX_SAFE_RATE();
    COLLECTOR = ICollector(collector);
    GHO = IERC20(SGHO.GHO());
    PRIME_GHO = IERC20(primeGho);
    POOL = IPool(pool);

    _grantRole(DEFAULT_ADMIN_ROLE, owner);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `riskCouncil`
    _grantRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil);
    _grantRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(FIXED_RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);
    _grantRole(SGHO_FUNDING_ROLE, riskCouncil);
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
      revert RateUnchanged();
    }

    return _setRateConfig(rateConfigCopy);
  }

  /// @inheritdoc IsGhoSteward
  function setSupplyCap(uint256 supplyCap) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {
    uint256 currentSupplyCap = SGHO.supplyCap();

    if (currentSupplyCap == supplyCap) {
      revert SupplyCapUnchanged();
    }

    SGHO.setSupplyCap(supplyCap.toUint160());
    emit SupplyCapUpdated(msg.sender, supplyCap);
  }

  /// @inheritdoc IsGhoSteward
  function fundSGho(uint256 amount, bool withdrawFromAave) external onlyRole(SGHO_FUNDING_ROLE) {
    if (block.timestamp - _lastTransferTimestamp < MINIMUM_DELAY) revert DebounceNotRespected();
    if (amount == 0) revert ZeroAmount();
    if (amount > _maxTransferAmount) revert MaxTransferExceeded(_maxTransferAmount);

    _lastTransferTimestamp = block.timestamp;

    if (withdrawFromAave) {
      COLLECTOR.transfer(PRIME_GHO, address(this), amount);
      POOL.withdraw(address(GHO), amount, address(COLLECTOR));
    }

    COLLECTOR.transfer(GHO, address(SGHO), amount);
    emit SGhoFunded(amount);
  }

  /// @inheritdoc IsGhoSteward
  function setMaxTransferAmount(uint256 maxAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_maxTransferAmount == maxAmount) revert MaxTransferAmountUnchanged();

    _maxTransferAmount = maxAmount;
    emit MaxTransferAmountUpdated(msg.sender, maxAmount);
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
    return SGHO;
  }

  /// @inheritdoc IsGhoSteward
  function getMaxTransferAmount() external view returns (uint256) {
    return _maxTransferAmount;
  }

  function _setRateConfig(RateConfig memory rateConfig) internal returns (uint16) {
    uint16 targetRate = _computeRateConfig(rateConfig);

    SGHO.setTargetRate(targetRate);
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
