// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {AToken} from 'aave-v3-origin/contracts/protocol/tokenization/AToken.sol';
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
  uint256 public constant FUNDING_BUFFER_DURATION = 90 days;

  /// @inheritdoc IsGhoSteward
  uint256 public constant INITIAL_MAX_FUNDING_AMOUNT = 100_000e18;

  /// @inheritdoc IsGhoSteward
  IsGho public immutable SGHO;

  /// @inheritdoc IsGhoSteward
  IERC20 public immutable GHO;

  /// @inheritdoc IsGhoSteward
  ICollector public immutable COLLECTOR;

  /// @notice Maximum amount of GHO a single funding can send
  uint256 internal _maxFundingAmount;

  /// @notice Timestamp of the last funding
  uint256 internal _lastFundingTimestamp;

  /**
   * @param owner Address granted `DEFAULT_ADMIN_ROLE`
   * @param riskCouncil Address granted every other role
   * @param sGho Address of the sGho contract
   * @param collector Address of the collector funding sGho
   */
  constructor(address owner, address riskCouncil, address sGho, address collector) {
    if (
      owner == address(0) ||
      riskCouncil == address(0) ||
      sGho == address(0) ||
      collector == address(0)
    ) {
      revert ZeroAddress();
    }

    SGHO = IsGho(sGho);
    GHO = IERC20(IsGho(sGho).GHO());
    COLLECTOR = ICollector(collector);
    _maxFundingAmount = INITIAL_MAX_FUNDING_AMOUNT;

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
    if (targetRate == SGHO.targetRate()) {
      revert RateUnchanged();
    }

    SGHO.setTargetRate(targetRate, effectiveAt);
    emit TargetRateUpdated(msg.sender, targetRate, effectiveAt);
  }

  /// @inheritdoc IsGhoSteward
  function cancelTargetRate() external onlyRole(RATE_MANAGER_ROLE) {
    SGHO.cancelPendingTargetRate();
    emit TargetRateCancelled(msg.sender);
  }

  /// @inheritdoc IsGhoSteward
  function setSupplyCap(uint256 supplyCap) external onlyRole(SUPPLY_CAP_MANAGER_ROLE) {
    uint256 currentSupplyCap = SGHO.supplyCap();

    if (currentSupplyCap == supplyCap) {
      revert SupplyCapUnchanged();
    }

    SGHO.setSupplyCap(supplyCap);
    emit SupplyCapUpdated(msg.sender, supplyCap);
  }

  /// @inheritdoc IsGhoSteward
  function fundSGho(uint256 amount) external onlyRole(FUNDING_MANAGER_ROLE) {
    uint256 balanceBefore = _validateFunding(amount);

    COLLECTOR.transfer(GHO, address(SGHO), amount);

    _finalizeFunding({source: address(GHO), amount: amount, balanceBefore: balanceBefore});
  }

  /// @inheritdoc IsGhoSteward
  function fundSGhoFromAToken(
    address aToken,
    uint256 amount
  ) external onlyRole(FUNDING_MANAGER_ROLE) {
    uint256 balanceBefore = _validateFunding(amount);

    IPool pool = AToken(aToken).POOL();
    if (pool.getReserveAToken(address(GHO)) != aToken) {
      revert InvalidFundingSource();
    }

    COLLECTOR.transfer(IERC20(aToken), address(this), amount);
    pool.withdraw({asset: address(GHO), amount: amount, to: address(SGHO)});

    _finalizeFunding({source: aToken, amount: amount, balanceBefore: balanceBefore});
  }

  /// @inheritdoc IsGhoSteward
  function fundSGhoFromVault(
    address vault,
    uint256 amount
  ) external onlyRole(FUNDING_MANAGER_ROLE) {
    uint256 balanceBefore = _validateFunding(amount);

    if (vault == address(SGHO) || IERC4626(vault).asset() != address(GHO)) {
      revert InvalidFundingSource();
    }

    COLLECTOR.transfer(IERC20(vault), address(this), IERC4626(vault).previewWithdraw(amount));
    IERC4626(vault).withdraw({assets: amount, receiver: address(SGHO), owner: address(this)});

    _finalizeFunding({source: vault, amount: amount, balanceBefore: balanceBefore});
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
  function getMaxFundingAmount() external view returns (uint256) {
    return _maxFundingAmount;
  }

  /// @inheritdoc IsGhoSteward
  function getLastFundingTimestamp() external view returns (uint256) {
    return _lastFundingTimestamp;
  }

  /// @inheritdoc IsGhoSteward
  function getFundingHeadroom() public view returns (uint256) {
    uint256 totalAssets = IERC4626(address(SGHO)).totalAssets();
    uint256 buffer = Math.mulDiv(
      totalAssets,
      uint256(SGHO.targetRate()) * FUNDING_BUFFER_DURATION,
      PercentageMath.PERCENTAGE_FACTOR * MathUtils.SECONDS_PER_YEAR
    );
    uint256 balance = GHO.balanceOf(address(SGHO));
    return totalAssets + buffer > balance ? totalAssets + buffer - balance : 0;
  }

  /**
   * @dev Checks the debounce, the per-funding cap and that sGho ends up holding at most its
   * liabilities plus `FUNDING_BUFFER_DURATION` of yield, then records the funding time.
   * @param amount Amount of GHO to fund
   * @return The GHO held by sGho before the funding
   */
  function _validateFunding(uint256 amount) internal returns (uint256) {
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

    return GHO.balanceOf(address(SGHO));
  }

  /**
   * @dev Checks sGho received `amount`, sends any `source` left on this contract back to the
   * collector and emits `SGhoFunded`.
   * @param source Token taken from the collector
   * @param amount Amount of GHO funded
   * @param balanceBefore The GHO held by sGho before the funding
   */
  function _finalizeFunding(address source, uint256 amount, uint256 balanceBefore) internal {
    if (GHO.balanceOf(address(SGHO)) < balanceBefore + amount) {
      revert FundingNotReceived();
    }

    uint256 leftover = IERC20(source).balanceOf(address(this));
    if (leftover != 0) {
      IERC20(source).safeTransfer(address(COLLECTOR), leftover);
    }

    emit SGhoFunded(msg.sender, source, amount);
  }
}
