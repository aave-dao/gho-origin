// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {GPv2SafeERC20} from 'aave-v3-origin/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {VersionedInitializable} from 'aave-v3-origin/contracts/misc/aave-upgradeability/VersionedInitializable.sol';
import {Errors} from 'aave-v3-origin/contracts/protocol/libraries/helpers/Errors.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IAToken} from 'aave-v3-origin/contracts/interfaces/IAToken.sol';
import {IAaveIncentivesController} from 'aave-v3-origin/contracts/interfaces/IAaveIncentivesController.sol';
import {IInitializableAToken} from 'aave-v3-origin/contracts/interfaces/IInitializableAToken.sol';
import {ScaledBalanceTokenBase} from 'aave-v3-origin/contracts/protocol/tokenization/base/ScaledBalanceTokenBase.sol';
import {IncentivizedERC20} from 'aave-v3-origin/contracts/protocol/tokenization/base/IncentivizedERC20.sol';
import {EIP712Base} from 'aave-v3-origin/contracts/protocol/tokenization/base/EIP712Base.sol';

// Gho Imports
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {IGhoFacilitator} from 'src/contracts/gho/interfaces/IGhoFacilitator.sol';
import {IGhoAToken} from 'src/contracts/facilitators/aave/tokens/interfaces/IGhoAToken.sol';
import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';

/**
 * @title GhoAToken
 * @author Aave
 * @notice Implementation of the interest bearing token for the Aave protocol
 */
contract GhoAToken is VersionedInitializable, ScaledBalanceTokenBase, EIP712Base, IGhoAToken {
  using WadRayMath for uint256;
  using GPv2SafeERC20 for IERC20;

  bytes32 public constant PERMIT_TYPEHASH =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  uint256 public constant ATOKEN_REVISION = 0x1;

  address internal _treasury;
  address internal _underlyingAsset;

  // Gho Storage
  GhoVariableDebtToken internal _ghoVariableDebtToken;
  address internal _ghoTreasury;

  // Accumulated interest to be distributed to treasury
  // In aave-v3-origin, handleRepayment is called before GHO is transferred,
  // so we track the interest portion and burn principal in distributeFeesToTreasury
  uint256 internal _accumulatedInterest;

  /// @inheritdoc VersionedInitializable
  function getRevision() internal pure virtual override returns (uint256) {
    return ATOKEN_REVISION;
  }

  /**
   * @dev Constructor.
   * @param pool The address of the Pool contract
   */
  constructor(
    IPool pool,
    address rewardsController
  )
    ScaledBalanceTokenBase(pool, 'GHO_ATOKEN_IMPL', 'GHO_ATOKEN_IMPL', 0, rewardsController)
    EIP712Base()
  {
    // Intentionally left blank
  }

  /// @inheritdoc IInitializableAToken
  function initialize(
    IPool initializingPool,
    address underlyingAsset,
    uint8 aTokenDecimals,
    string calldata aTokenName,
    string calldata aTokenSymbol,
    bytes calldata params
  ) external override initializer {
    require(initializingPool == POOL, Errors.PoolAddressesDoNotMatch());
    _setName(aTokenName);
    _setSymbol(aTokenSymbol);
    _setDecimals(aTokenDecimals);

    _underlyingAsset = underlyingAsset;

    _domainSeparator = _calculateDomainSeparator();

    emit Initialized(
      underlyingAsset,
      address(POOL),
      _treasury,
      address(REWARDS_CONTROLLER),
      aTokenDecimals,
      aTokenName,
      aTokenSymbol,
      params
    );
  }

  /// @inheritdoc IAToken
  function mint(
    address,
    address,
    uint256,
    uint256
  ) external virtual override onlyPool returns (bool) {
    revert Errors.OperationNotSupported();
  }

  /// @inheritdoc IAToken
  function burn(
    address,
    address,
    uint256,
    uint256,
    uint256
  ) external virtual override onlyPool returns (bool) {
    revert Errors.OperationNotSupported();
  }

  /// @inheritdoc IAToken
  function mintToTreasury(uint256, uint256) external virtual override onlyPool {
    revert Errors.OperationNotSupported();
  }

  /// @inheritdoc IAToken
  function transferOnLiquidation(
    address,
    address,
    uint256,
    uint256,
    uint256
  ) external virtual override onlyPool {
    revert Errors.OperationNotSupported();
  }

  /// @inheritdoc IERC20
  function balanceOf(
    address
  ) public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
    return 0;
  }

  /// @inheritdoc IERC20
  /// @dev Returns the available capacity for the GHO facilitator (bucket capacity - bucket level)
  /// @dev This is needed for aave-v3-origin's ValidationLogic which checks aToken.totalSupply() >= borrowAmount
  function totalSupply() public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
    (uint256 bucketCapacity, uint256 bucketLevel) = IGhoToken(_underlyingAsset)
      .getFacilitatorBucket(address(this));
    return bucketCapacity - bucketLevel;
  }

  /// @inheritdoc IAToken
  function RESERVE_TREASURY_ADDRESS() external view override returns (address) {
    return _treasury;
  }

  /// @inheritdoc IAToken
  function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
    return _underlyingAsset;
  }

  /**
   * @notice Transfers the underlying asset to `target`.
   * @dev It performs a mint of GHO on behalf of the `target`
   * @dev Used by the Pool to transfer assets in borrow(), withdraw() and flashLoan()
   * @param target The recipient of the underlying
   * @param amount The amount getting transferred
   */
  function transferUnderlyingTo(address target, uint256 amount) external virtual override onlyPool {
    IGhoToken(_underlyingAsset).mint(target, amount);
  }

  /**
   * @notice Handles repayment of GHO debt
   * @dev Called by the GhoVariableDebtToken during burn (repay) to properly handle the interest vs principal.
   *      In aave-v3-origin, this is called before GHO is transferred to the aToken, so we cannot burn
   *      the principal immediately. Instead, we track the interest portion and burn principal in
   *      distributeFeesToTreasury.
   * @param onBehalfOf The address of the user who's debt is being repaid
   * @param amount The amount being repaid
   */
  function handleRepayment(address, address onBehalfOf, uint256 amount) external virtual {
    require(
      msg.sender == address(POOL) || msg.sender == address(_ghoVariableDebtToken),
      'CALLER_NOT_POOL_OR_DEBT_TOKEN'
    );
    uint256 balanceFromInterest = _ghoVariableDebtToken.getBalanceFromInterest(onBehalfOf);
    if (amount <= balanceFromInterest) {
      // All of the repayment is interest - accumulate it for treasury distribution
      _ghoVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, amount);
      _accumulatedInterest += amount;
    } else {
      // Part is interest, part is principal
      // Accumulate interest for treasury, principal will be burned in distributeFeesToTreasury
      _ghoVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, balanceFromInterest);
      _accumulatedInterest += balanceFromInterest;
      // Principal (amount - balanceFromInterest) will be burned when distributeFeesToTreasury is called
    }
  }

  /// @inheritdoc IGhoFacilitator
  /// @dev Burns the principal portion of accumulated repayments and transfers only interest to treasury
  function distributeFeesToTreasury() external virtual override {
    uint256 balance = IERC20(_underlyingAsset).balanceOf(address(this));
    uint256 interestToDistribute = _accumulatedInterest;

    // Reset accumulated interest before external calls
    _accumulatedInterest = 0;

    if (balance > interestToDistribute) {
      // Burn the principal portion
      uint256 principalToBurn = balance - interestToDistribute;
      IGhoToken(_underlyingAsset).burn(principalToBurn);
    }

    // Transfer interest to treasury (may be less than interestToDistribute if some was already transferred)
    uint256 remainingBalance = IERC20(_underlyingAsset).balanceOf(address(this));
    if (remainingBalance > 0) {
      IERC20(_underlyingAsset).transfer(_ghoTreasury, remainingBalance);
    }

    emit FeesDistributedToTreasury(_ghoTreasury, _underlyingAsset, remainingBalance);
  }

  /// @inheritdoc IAToken
  function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external override {
    revert Errors.OperationNotSupported();
  }

  /**
   * @notice Overrides the parent _transfer to force validated transfer() and transferFrom()
   * @param from The source address
   * @param to The destination address
   * @param amount The amount getting transferred
   */
  function _transfer(address from, address to, uint120 amount) internal override {
    revert Errors.OperationNotSupported();
  }

  /**
   * @dev Overrides the base function to fully implement IAToken
   * @dev see `EIP712Base.DOMAIN_SEPARATOR()` for more detailed documentation
   */
  function DOMAIN_SEPARATOR() public view override(IAToken, EIP712Base) returns (bytes32) {
    return super.DOMAIN_SEPARATOR();
  }

  /**
   * @dev Overrides the base function to fully implement IAToken
   * @dev see `EIP712Base.nonces()` for more detailed documentation
   */
  function nonces(address owner) public view override(IAToken, EIP712Base) returns (uint256) {
    return super.nonces(owner);
  }

  /// @inheritdoc EIP712Base
  function _EIP712BaseId() internal view override returns (string memory) {
    return name();
  }

  /// @inheritdoc IAToken
  function rescueTokens(address token, address to, uint256 amount) external override onlyPoolAdmin {
    require(token != _underlyingAsset, Errors.UnderlyingCannotBeRescued());
    IERC20(token).safeTransfer(to, amount);
  }

  /// @inheritdoc IGhoAToken
  function setVariableDebtToken(address ghoVariableDebtToken) external override onlyPoolAdmin {
    require(address(_ghoVariableDebtToken) == address(0), 'VARIABLE_DEBT_TOKEN_ALREADY_SET');
    require(ghoVariableDebtToken != address(0), 'ZERO_ADDRESS_NOT_VALID');
    _ghoVariableDebtToken = GhoVariableDebtToken(ghoVariableDebtToken);
    emit VariableDebtTokenSet(ghoVariableDebtToken);
  }

  /// @inheritdoc IGhoAToken
  function getVariableDebtToken() external view override returns (address) {
    return address(_ghoVariableDebtToken);
  }

  /// @inheritdoc IGhoFacilitator
  function updateGhoTreasury(address newGhoTreasury) external override onlyPoolAdmin {
    require(newGhoTreasury != address(0), 'ZERO_ADDRESS_NOT_VALID');
    address oldGhoTreasury = _ghoTreasury;
    _ghoTreasury = newGhoTreasury;
    _treasury = newGhoTreasury;
    emit GhoTreasuryUpdated(oldGhoTreasury, newGhoTreasury);
  }

  /// @inheritdoc IGhoFacilitator
  function getGhoTreasury() external view override returns (address) {
    return _ghoTreasury;
  }
}
