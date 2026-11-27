// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {AToken} from 'aave-v3-origin/contracts/protocol/tokenization/AToken.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {MathUtils} from 'aave-v3-origin/contracts/protocol/libraries/math/MathUtils.sol';
import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';
import {IsGhoSteward} from 'src/contracts/misc/interfaces/IsGhoSteward.sol';

/**
 * @title sGhoSteward
 * @author BGD Labs
 * @notice Helper contract for managing rate and supply cap parameters for sGho, and for funding
 * sGho with GHO from the collector.
 */
contract sGhoSteward is AccessControl, IsGhoSteward {
  using SafeERC20 for IERC20;

  /// @inheritdoc IsGhoSteward
  bytes32 public constant RATE_MANAGER_ROLE = keccak256('RATE_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  bytes32 public constant FUNDING_MANAGER_ROLE = keccak256('FUNDING_MANAGER_ROLE');

  /// @inheritdoc IsGhoSteward
  uint256 public constant MINIMUM_DELAY = 1 days;

  /// @inheritdoc IsGhoSteward
  uint256 public immutable FUNDING_BUFFER_DURATION;

  /// @notice sGho contract address
  IsGho internal immutable _sGho;

  /// @notice GHO token, the asset of `_sGho`
  IERC20 internal immutable _gho;

  /// @notice Collector holding the GHO used to fund `_sGho`
  ICollector internal immutable _collector;

  /// @notice Maximum amount of GHO a single funding can send
  uint256 internal _maxFundingAmount;

  /// @notice Timestamp of the last funding
  uint256 internal _lastFundingTimestamp;

  /**
   * @param owner Address granted `DEFAULT_ADMIN_ROLE`
   * @param riskCouncil Address granted every other role
   * @param sGho Address of the sGho contract
   * @param collector Address of the collector funding sGho
   * @param maxFundingAmount Initial maximum amount of GHO per funding
   * @param fundingBufferDuration Seconds of yield at the current rate that funding may prepay
   */
  constructor(
    address owner,
    address riskCouncil,
    address sGho,
    address collector,
    uint256 maxFundingAmount,
    uint256 fundingBufferDuration
  ) {
    if (
      owner == address(0) ||
      riskCouncil == address(0) ||
      sGho == address(0) ||
      collector == address(0)
    ) {
      revert ZeroAddress();
    }

    _sGho = IsGho(sGho);
    _gho = IERC20(IsGho(sGho).GHO());
    _collector = ICollector(collector);
    _maxFundingAmount = maxFundingAmount;
    FUNDING_BUFFER_DURATION = fundingBufferDuration;

    _grantRole(DEFAULT_ADMIN_ROLE, owner);

    // Initially all roles except `DEFAULT_ADMIN_ROLE` will be granted to the `riskCouncil`
    _grantRole(RATE_MANAGER_ROLE, riskCouncil);
    _grantRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);
    _grantRole(FUNDING_MANAGER_ROLE, riskCouncil);
  }

  /// @inheritdoc IsGhoSteward
  function setTargetRate(
    uint16 targetRate,
    uint40 effectiveAt
  ) external onlyRole(RATE_MANAGER_ROLE) {
    if (targetRate == _sGho.targetRate()) {
      revert RateUnchanged();
    }

    _sGho.setTargetRate(targetRate, effectiveAt);
    emit TargetRateUpdated(msg.sender, targetRate, effectiveAt);
  }

  /// @inheritdoc IsGhoSteward
  function cancelTargetRate() external onlyRole(RATE_MANAGER_ROLE) {
    _sGho.cancelPendingTargetRate();
    emit TargetRateCancelled(msg.sender);
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
  function fundSGho(uint256 amount) external onlyRole(FUNDING_MANAGER_ROLE) {
    _validateFunding(amount);

    _collector.transfer(_gho, address(_sGho), amount);
    emit SGhoFunded(msg.sender, address(_gho), amount);
  }

  /// @inheritdoc IsGhoSteward
  function fundSGhoFromAToken(
    address aToken,
    uint256 amount
  ) external onlyRole(FUNDING_MANAGER_ROLE) {
    IPool pool = AToken(aToken).POOL();
    if (pool.getReserveAToken(address(_gho)) != aToken) {
      revert InvalidFundingSource();
    }
    _validateFunding(amount);

    _collector.transfer(IERC20(aToken), address(this), amount);
    pool.withdraw({asset: address(_gho), amount: amount, to: address(_sGho)});
    _returnToCollector(aToken);
    emit SGhoFunded(msg.sender, aToken, amount);
  }

  /// @inheritdoc IsGhoSteward
  function fundSGhoFromVault(
    address vault,
    uint256 amount
  ) external onlyRole(FUNDING_MANAGER_ROLE) {
    if (IERC4626(vault).asset() != address(_gho)) {
      revert InvalidFundingSource();
    }
    _validateFunding(amount);

    _collector.transfer(IERC20(vault), address(this), IERC4626(vault).previewWithdraw(amount));
    IERC4626(vault).withdraw({assets: amount, receiver: address(_sGho), owner: address(this)});
    _returnToCollector(vault);
    emit SGhoFunded(msg.sender, vault, amount);
  }

  /// @inheritdoc IsGhoSteward
  function setMaxFundingAmount(uint256 maxFundingAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (maxFundingAmount == _maxFundingAmount) {
      revert MaxFundingAmountUnchanged();
    }

    _maxFundingAmount = maxFundingAmount;
    emit MaxFundingAmountUpdated(msg.sender, maxFundingAmount);
  }

  /// @inheritdoc IsGhoSteward
  function sGHO() external view returns (IsGho) {
    return _sGho;
  }

  /// @inheritdoc IsGhoSteward
  function COLLECTOR() external view returns (ICollector) {
    return _collector;
  }

  /// @inheritdoc IsGhoSteward
  function getMaxFundingAmount() external view returns (uint256) {
    return _maxFundingAmount;
  }

  /// @inheritdoc IsGhoSteward
  function getLastFundingTimestamp() external view returns (uint256) {
    return _lastFundingTimestamp;
  }

  /// @inheritdoc IsGhoSteward
  function getFundingHeadroom() public view returns (uint256) {
    uint256 totalAssets = IERC4626(address(_sGho)).totalAssets();
    uint256 buffer = Math.mulDiv(
      totalAssets,
      uint256(_sGho.targetRate()) * FUNDING_BUFFER_DURATION,
      PercentageMath.PERCENTAGE_FACTOR * MathUtils.SECONDS_PER_YEAR
    );
    uint256 balance = _gho.balanceOf(address(_sGho));
    return totalAssets + buffer > balance ? totalAssets + buffer - balance : 0;
  }

  /**
   * @dev Checks the debounce, the per-funding cap and that sGho ends up holding at most its
   * liabilities plus `FUNDING_BUFFER_DURATION` of yield, then records the funding time.
   * @param amount Amount of GHO to fund
   */
  function _validateFunding(uint256 amount) internal {
    if (block.timestamp - _lastFundingTimestamp < MINIMUM_DELAY) {
      revert DebounceNotRespected();
    }
    if (amount == 0) {
      revert InvalidAmount();
    }
    if (amount > _maxFundingAmount) {
      revert FundingAmountExceeded(_maxFundingAmount);
    }
    uint256 headroom = getFundingHeadroom();
    if (amount > headroom) {
      revert FundingHeadroomExceeded(headroom);
    }

    _lastFundingTimestamp = block.timestamp;
  }

  /**
   * @dev Sends any `token` left on this contract after a withdrawal back to the collector.
   * @param token The aToken or vault share token used for the funding
   */
  function _returnToCollector(address token) internal {
    uint256 leftover = IERC20(token).balanceOf(address(this));
    if (leftover != 0) {
      IERC20(token).safeTransfer(address(_collector), leftover);
    }
  }
}
