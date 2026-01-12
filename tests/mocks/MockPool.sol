// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from 'aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';
import {IERC20} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/ERC20.sol';

/**
 * @dev Simplified MockPool that doesn't inherit from Pool/VersionedInitializable
 * to avoid initialization issues in tests.
 */
contract MockPool {
  using WadRayMath for uint256;

  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  GhoVariableDebtToken public DEBT_TOKEN;
  GhoAToken public ATOKEN;
  address public GHO;

  // Simple reserve data storage
  mapping(address => DataTypes.ReserveDataLegacy) internal _reserves;
  uint128 internal _currentIndex = uint128(WadRayMath.RAY);

  constructor(IPoolAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
  }

  function test_coverage_ignore() public virtual {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }

  function setGhoTokens(GhoVariableDebtToken ghoDebtToken, GhoAToken ghoAToken) external {
    DEBT_TOKEN = ghoDebtToken;
    ATOKEN = ghoAToken;
    GHO = ghoAToken.UNDERLYING_ASSET_ADDRESS();

    // Initialize reserve data
    _reserves[GHO].liquidityIndex = _currentIndex;
    _reserves[GHO].variableBorrowIndex = _currentIndex;
    _reserves[GHO].aTokenAddress = address(ATOKEN);
    _reserves[GHO].variableDebtTokenAddress = address(DEBT_TOKEN);
  }

  function supply(address, uint256, address, uint16) public virtual {}

  function borrow(
    address, // asset
    uint256 amount,
    uint256, // interestRateMode
    uint16, // referralCode
    address onBehalfOf
  ) public virtual {
    uint256 index = _reserves[GHO].variableBorrowIndex;
    uint256 scaledAmount = amount.rayDiv(index);

    // New mint signature: mint(user, onBehalfOf, amount, scaledAmount, index)
    DEBT_TOKEN.mint(msg.sender, onBehalfOf, amount, scaledAmount, index);

    ATOKEN.transferUnderlyingTo(onBehalfOf, amount);
  }

  function repay(
    address, // asset
    uint256 amount,
    uint256, // interestRateMode
    address onBehalfOf
  ) public virtual returns (uint256) {
    uint256 index = _reserves[GHO].variableBorrowIndex;

    uint256 paybackAmount = DEBT_TOKEN.balanceOf(onBehalfOf);

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    // New burn signature: burn(from, scaledAmount, index)
    uint256 scaledAmount = paybackAmount.rayDiv(index);
    DEBT_TOKEN.burn(onBehalfOf, scaledAmount, index);

    IERC20(GHO).transferFrom(msg.sender, address(ATOKEN), paybackAmount);

    ATOKEN.handleRepayment(msg.sender, onBehalfOf, paybackAmount);

    return paybackAmount;
  }

  function getReserveNormalizedIncome(address) external view returns (uint256) {
    return _currentIndex;
  }

  function getReserveNormalizedVariableDebt(address) external view returns (uint256) {
    return _currentIndex;
  }

  function getReserveData(
    address asset
  ) external view returns (DataTypes.ReserveDataLegacy memory) {
    return _reserves[asset];
  }

  function setConfiguration(
    address asset,
    DataTypes.ReserveConfigurationMap calldata configuration
  ) external {
    _reserves[asset].configuration = configuration;
  }

  function getConfiguration(
    address asset
  ) external view returns (DataTypes.ReserveConfigurationMap memory) {
    return _reserves[asset].configuration;
  }

  function setReserveInterestRateStrategyAddress(
    address asset,
    address rateStrategyAddress
  ) external {
    _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
  }

  function getReserveInterestRateStrategyAddress(address asset) public view returns (address) {
    return _reserves[asset].interestRateStrategyAddress;
  }

  // Update index for time simulation
  function setVariableBorrowIndex(address asset, uint128 index) external {
    _reserves[asset].variableBorrowIndex = index;
  }

  function setLiquidityIndex(address asset, uint128 index) external {
    _reserves[asset].liquidityIndex = index;
  }
}
