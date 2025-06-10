// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {GhoDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoDiscountRateStrategy.sol';
import {IGhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/interfaces/IGhoVariableDebtToken.sol';
import {IUiGhoDataProvider} from 'src/contracts/facilitators/aave/misc/interfaces/IUiGhoDataProvider.sol';

/**
 * @title UiGhoDataProvider
 * @author Aave
 * @notice Data provider of GHO token as a reserve within the Aave Protocol
 */
contract UiGhoDataProvider is IUiGhoDataProvider {
  IPool public immutable POOL;
  IGhoToken public immutable GHO;

  /**
   * @dev Constructor
   * @param pool The address of the Pool contract
   * @param ghoToken The address of the GhoToken contract
   */
  constructor(IPool pool, IGhoToken ghoToken) {
    POOL = pool;
    GHO = ghoToken;
  }

  /// @inheritdoc IUiGhoDataProvider
  function getGhoReserveData() public view override returns (GhoReserveData memory) {
    DataTypes.ReserveDataLegacy memory baseData = POOL.getReserveData(address(GHO));
    IGhoVariableDebtToken debtToken = IGhoVariableDebtToken(baseData.variableDebtTokenAddress);
    GhoDiscountRateStrategy discountRateStrategy = GhoDiscountRateStrategy(
      debtToken.getDiscountRateStrategy()
    );

    (uint256 bucketCapacity, uint256 bucketLevel) = GHO.getFacilitatorBucket(
      baseData.aTokenAddress
    );

    return
      GhoReserveData({
        ghoBaseVariableBorrowRate: baseData.currentVariableBorrowRate,
        ghoDiscountedPerToken: discountRateStrategy.GHO_DISCOUNTED_PER_DISCOUNT_TOKEN(),
        ghoDiscountRate: discountRateStrategy.DISCOUNT_RATE(),
        ghoMinDebtTokenBalanceForDiscount: discountRateStrategy.MIN_DEBT_TOKEN_BALANCE(),
        ghoMinDiscountTokenBalanceForDiscount: discountRateStrategy.MIN_DISCOUNT_TOKEN_BALANCE(),
        ghoReserveLastUpdateTimestamp: baseData.lastUpdateTimestamp,
        ghoCurrentBorrowIndex: baseData.variableBorrowIndex,
        aaveFacilitatorBucketLevel: bucketLevel,
        aaveFacilitatorBucketMaxCapacity: bucketCapacity
      });
  }

  /// @inheritdoc IUiGhoDataProvider
  function getGhoUserData(address user) public view override returns (GhoUserData memory) {
    DataTypes.ReserveDataLegacy memory baseData = POOL.getReserveData(address(GHO));
    IGhoVariableDebtToken debtToken = IGhoVariableDebtToken(baseData.variableDebtTokenAddress);
    address discountToken = debtToken.getDiscountToken();

    return
      GhoUserData({
        userGhoDiscountPercent: debtToken.getDiscountPercent(user),
        userDiscountTokenBalance: IERC20(discountToken).balanceOf(user),
        userPreviousGhoBorrowIndex: debtToken.getPreviousIndex(user),
        userGhoScaledBorrowBalance: debtToken.scaledBalanceOf(user)
      });
  }
}
