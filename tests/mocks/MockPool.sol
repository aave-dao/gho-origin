// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {GhoDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoDiscountRateStrategy.sol';
import {DefaultReserveInterestRateStrategyV2} from 'aave-v3-origin/contracts/misc/DefaultReserveInterestRateStrategyV2.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {IAaveIncentivesController} from 'aave-v3-origin/contracts/interfaces/IAaveIncentivesController.sol';
import {PoolInstance} from 'aave-v3-origin/contracts/instances/PoolInstance.sol';
import {UserConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/UserConfiguration.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {ReserveLogic} from 'aave-v3-origin/contracts/protocol/libraries/logic/ReserveLogic.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/ERC20.sol';
import {Errors} from 'aave-v3-origin/contracts/protocol/libraries/helpers/Errors.sol';

/**
 * @dev MockPool removes assets and users validations from Pool contract.
 */
contract MockPool is PoolInstance {
  using ReserveLogic for DataTypes.ReserveCache;
  using ReserveLogic for DataTypes.ReserveData;
  using UserConfiguration for DataTypes.UserConfigurationMap;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  GhoVariableDebtToken public DEBT_TOKEN;
  GhoAToken public ATOKEN;
  address public GHO;

  constructor(IPoolAddressesProvider provider) PoolInstance(provider) {}

  function test_coverage_ignore() public virtual {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }

  function setGhoTokens(GhoVariableDebtToken ghoDebtToken, GhoAToken ghoAToken) external {
    DEBT_TOKEN = ghoDebtToken;
    ATOKEN = ghoAToken;
    GHO = ghoAToken.UNDERLYING_ASSET_ADDRESS();
    _reserves[GHO].init(
      address(ATOKEN),
      address(DEBT_TOKEN),
      address(new DefaultReserveInterestRateStrategyV2(address(ADDRESSES_PROVIDER)))
    );
  }

  function supply(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) public override {}

  function borrow(
    address, // asset
    uint256 amount,
    uint256, // interestRateMode
    uint16, // referralCode
    address onBehalfOf
  ) public override {
    DataTypes.ReserveData storage reserve = _reserves[GHO];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();
    reserve.updateState(reserveCache);

    DEBT_TOKEN.mint(msg.sender, onBehalfOf, amount, reserveCache.nextVariableBorrowIndex);

    reserve.updateInterestRatesAndVirtualBalance(reserveCache, GHO, 0, amount);

    ATOKEN.transferUnderlyingTo(onBehalfOf, amount);
  }

  function repay(
    address, // asset
    uint256 amount,
    uint256, // interestRateMode
    address onBehalfOf
  ) public override returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[GHO];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();
    reserve.updateState(reserveCache);

    uint256 paybackAmount = DEBT_TOKEN.balanceOf(onBehalfOf);

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    DEBT_TOKEN.burn(onBehalfOf, paybackAmount, reserveCache.nextVariableBorrowIndex);

    reserve.updateInterestRatesAndVirtualBalance(reserveCache, GHO, 0, amount);

    IERC20(GHO).transferFrom(msg.sender, reserveCache.aTokenAddress, paybackAmount);

    ATOKEN.handleRepayment(msg.sender, onBehalfOf, paybackAmount);

    return paybackAmount;
  }

  function setReserveInterestRateStrategyAddress(
    address asset,
    address rateStrategyAddress
  ) external override {
    require(asset != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
    _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
  }

  function getReserveInterestRateStrategyAddress(address asset) public view returns (address) {
    return _reserves[asset].interestRateStrategyAddress;
  }

  function setConfiguration(
    address asset,
    DataTypes.ReserveConfigurationMap calldata configuration
  ) external override {
    require(asset != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
    _reserves[asset].configuration = configuration;
  }
}
