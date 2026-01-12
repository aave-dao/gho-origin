// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IReserveInterestRateStrategy} from 'aave-v3-origin/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IDefaultInterestRateStrategyV2} from 'aave-v3-origin/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

/**
 * @title GhoInterestRateStrategy
 * @author Aave
 * @notice A wrapper interest rate strategy that handles GHO specially.
 * @dev GHO is minted on demand and doesn't have actual liquidity backing, so standard
 *      interest rate calculations based on utilization don't apply. This wrapper:
 *      - For GHO: returns a fixed borrow rate
 *      - For other assets: delegates to the underlying DefaultReserveInterestRateStrategyV2
 */
contract GhoInterestRateStrategy is IDefaultInterestRateStrategyV2 {
  using WadRayMath for uint256;

  /// @notice The underlying interest rate strategy for non-GHO assets
  IDefaultInterestRateStrategyV2 public immutable UNDERLYING_STRATEGY;

  /// @notice The GHO token address
  address public immutable GHO;

  /// @notice The fixed borrow rate for GHO in ray (1e27)
  uint256 public immutable GHO_BORROW_RATE;

  /// @notice The pool addresses provider
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  /**
   * @notice Constructor
   * @param underlyingStrategy The underlying interest rate strategy for non-GHO assets
   * @param gho The GHO token address
   * @param ghoBorrowRate The fixed borrow rate for GHO in ray
   */
  constructor(
    IDefaultInterestRateStrategyV2 underlyingStrategy,
    address gho,
    uint256 ghoBorrowRate
  ) {
    UNDERLYING_STRATEGY = underlyingStrategy;
    GHO = gho;
    GHO_BORROW_RATE = ghoBorrowRate;
    ADDRESSES_PROVIDER = underlyingStrategy.ADDRESSES_PROVIDER();
  }

  /// @inheritdoc IReserveInterestRateStrategy
  function setInterestRateParams(address reserve, bytes calldata rateData) external override {
    if (reserve == GHO) {
      // GHO uses a fixed rate, no dynamic params to set
      return;
    }
    UNDERLYING_STRATEGY.setInterestRateParams(reserve, rateData);
  }

  /// @inheritdoc IReserveInterestRateStrategy
  function calculateInterestRates(
    DataTypes.CalculateInterestRatesParams memory params
  ) external view override returns (uint256, uint256) {
    if (params.reserve == GHO) {
      // GHO has no liquidity rate (it's not supplied), only a fixed borrow rate
      return (0, GHO_BORROW_RATE);
    }
    return UNDERLYING_STRATEGY.calculateInterestRates(params);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getInterestRateData(
    address reserve
  ) external view override returns (InterestRateDataRay memory) {
    if (reserve == GHO) {
      // Return GHO-specific rate data
      return
        InterestRateDataRay({
          optimalUsageRatio: WadRayMath.RAY, // 100% - GHO is always "at capacity"
          baseVariableBorrowRate: GHO_BORROW_RATE,
          variableRateSlope1: 0,
          variableRateSlope2: 0
        });
    }
    return UNDERLYING_STRATEGY.getInterestRateData(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getInterestRateDataBps(
    address reserve
  ) external view override returns (InterestRateData memory) {
    InterestRateDataRay memory rayData = this.getInterestRateData(reserve);
    // Convert from ray to bps (1 ray = 1e27, 1 bps = 0.01% = 1e23 ray)
    uint256 rayToBps = 1e23;
    return
      InterestRateData({
        optimalUsageRatio: uint16(rayData.optimalUsageRatio / rayToBps),
        baseVariableBorrowRate: uint32(rayData.baseVariableBorrowRate / rayToBps),
        variableRateSlope1: uint32(rayData.variableRateSlope1 / rayToBps),
        variableRateSlope2: uint32(rayData.variableRateSlope2 / rayToBps)
      });
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getOptimalUsageRatio(address reserve) external view override returns (uint256) {
    if (reserve == GHO) {
      return WadRayMath.RAY; // 100%
    }
    return UNDERLYING_STRATEGY.getOptimalUsageRatio(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getVariableRateSlope1(address reserve) external view override returns (uint256) {
    if (reserve == GHO) {
      return 0;
    }
    return UNDERLYING_STRATEGY.getVariableRateSlope1(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getVariableRateSlope2(address reserve) external view override returns (uint256) {
    if (reserve == GHO) {
      return 0;
    }
    return UNDERLYING_STRATEGY.getVariableRateSlope2(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getBaseVariableBorrowRate(address reserve) external view override returns (uint256) {
    if (reserve == GHO) {
      return GHO_BORROW_RATE;
    }
    return UNDERLYING_STRATEGY.getBaseVariableBorrowRate(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function getMaxVariableBorrowRate(address reserve) external view override returns (uint256) {
    if (reserve == GHO) {
      return GHO_BORROW_RATE;
    }
    return UNDERLYING_STRATEGY.getMaxVariableBorrowRate(reserve);
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function MAX_BORROW_RATE() external view override returns (uint256) {
    return UNDERLYING_STRATEGY.MAX_BORROW_RATE();
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function MIN_OPTIMAL_POINT() external view override returns (uint256) {
    return UNDERLYING_STRATEGY.MIN_OPTIMAL_POINT();
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function MAX_OPTIMAL_POINT() external view override returns (uint256) {
    return UNDERLYING_STRATEGY.MAX_OPTIMAL_POINT();
  }

  /// @inheritdoc IDefaultInterestRateStrategyV2
  function setInterestRateParams(
    address reserve,
    InterestRateData calldata rateData
  ) external override {
    if (reserve == GHO) {
      // GHO uses a fixed rate, no dynamic params to set
      return;
    }
    UNDERLYING_STRATEGY.setInterestRateParams(reserve, rateData);
  }
}
