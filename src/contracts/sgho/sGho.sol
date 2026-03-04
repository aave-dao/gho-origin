// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {ERC20PermitUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol';
import {ERC20Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol';
import {PausableUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol';
import {RescuableACL} from 'solidity-utils/contracts/utils/RescuableACL.sol';
import {RescuableBase, IRescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';
import {IsGho} from 'src/contracts/sgho/interfaces/IsGho.sol';

/**
 * @title sGHO Token
 * @author kpk, TokenLogic & Aave Labs
 * @notice sGHO is an ERC4626 vault that allows users to deposit GHO and earn yield.
 * @dev This contract implements the ERC4626 standard for tokenized vaults, where the underlying asset is GHO.
 * It also includes functionalities for yield generation based on a target rate, and administrative roles for managing the contract.
 */
contract sGho is
  Initializable,
  ERC4626Upgradeable,
  ERC20PermitUpgradeable,
  AccessControlUpgradeable,
  RescuableACL,
  PausableUpgradeable,
  IsGho
{
  using Math for uint256;
  using SafeCast for uint256;

  /// @dev RAY is used for high-precision mathematical operations to avoid rounding errors
  uint176 private constant RAY = 1e27;

  /// @custom:storage-location erc7201:gho.storage.sGHO
  struct sGhoStorage {
    // Storage variables - Optimally packed for gas efficiency
    uint176 yieldIndex; // 22 bytes - current yield index for share/asset conversion
    uint64 lastUpdate; // 8 bytes - timestamp of last yield index update
    uint16 targetRate; // 2 bytes - target annual yield rate in basis points (e.g., 1000 = 10%)
    uint160 supplyCap; // 20 bytes - maximum total assets allowed in the vault
    uint96 ratePerSecond; // 12 bytes - cached rate per second for gas efficiency
  }

  // keccak256(abi.encode(uint256(keccak256("gho.storage.sGho")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant sGhoStorageLocation =
    0x52190d4bcaca04cac5a7c2ae78ea3854d285be3b91819fb1b3ed9862d9a9a400;

  function _getSGhoStorage() private pure returns (sGhoStorage storage $) {
    assembly {
      $.slot := sGhoStorageLocation
    }
  }

  /// @inheritdoc IsGho
  uint16 public constant MAX_SAFE_RATE = 50_00;

  /// @inheritdoc IsGho
  bytes32 public constant PAUSE_GUARDIAN_ROLE = keccak256('PAUSE_GUARDIAN_ROLE');

  /// @inheritdoc IsGho
  bytes32 public constant TOKEN_RESCUER_ROLE = keccak256('TOKEN_RESCUER_ROLE');

  /// @inheritdoc IsGho
  bytes32 public constant YIELD_MANAGER_ROLE = keccak256('YIELD_MANAGER_ROLE');

  /**
   * @dev Disable initializers on the implementation contract
   */
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializer for the sGHO vault.
   * @param gho Address of the underlying GHO token.
   * @param initialSupplyCap The total supply cap for the vault.
   * @param owner The address that will be granted the DEFAULT_ADMIN_ROLE.
   */
  function initialize(
    address gho,
    uint160 initialSupplyCap,
    address owner
  ) public payable initializer {
    if (gho == address(0) || owner == address(0)) revert ZeroAddressNotAllowed();

    __ERC20_init('sGho', 'sGho');
    __ERC4626_init(IERC20(gho));
    __ERC20Permit_init('sGho');
    __AccessControl_init();
    __Pausable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, owner);
    _grantRole(PAUSE_GUARDIAN_ROLE, owner);

    sGhoStorage storage $ = _getSGhoStorage();
    $.supplyCap = initialSupplyCap;
    $.yieldIndex = RAY;
    $.lastUpdate = uint64(block.timestamp);
    $.ratePerSecond = 0; // Initial rate is 0, so ratePerSecond is 0 (no yield initially)
    $.targetRate = 0;
  }

  /// @inheritdoc IsGho
  function depositWithPermit(
    uint256 assets,
    address receiver,
    uint256 deadline,
    SignatureParams memory sig
  ) external returns (uint256) {
    try
      IERC20Permit(asset()).permit(
        _msgSender(),
        address(this),
        assets,
        deadline,
        sig.v,
        sig.r,
        sig.s
      )
    {} catch {}
    return deposit(assets, receiver);
  }

  /// @inheritdoc IsGho
  function pause() external onlyRole(PAUSE_GUARDIAN_ROLE) {
    _pause();
  }

  /// @inheritdoc IsGho
  function unpause() external onlyRole(PAUSE_GUARDIAN_ROLE) {
    _unpause();
  }

  /// @inheritdoc IsGho
  function setTargetRate(uint16 newRate) public onlyRole(YIELD_MANAGER_ROLE) {
    sGhoStorage storage $ = _getSGhoStorage();
    // Update the yield index before changing the rate to ensure proper accrual
    if (newRate > MAX_SAFE_RATE) {
      revert MaxRateExceeded();
    }
    _updateYieldIndex();
    $.targetRate = newRate;

    // Convert targetRate from basis points to ray (1e27 scale)
    // targetRate is in basis points (e.g., 1000 = 10%)
    uint256 annualRateRay = (uint256(newRate) * RAY) / 10000;
    // Calculate the rate per second (annual rate / seconds in a year)
    $.ratePerSecond = (annualRateRay / 365 days).toUint96();

    emit TargetRateUpdated(newRate);
  }

  /// @inheritdoc IsGho
  function setSupplyCap(uint160 newSupplyCap) public onlyRole(YIELD_MANAGER_ROLE) {
    _getSGhoStorage().supplyCap = newSupplyCap;
    emit SupplyCapUpdated(newSupplyCap);
  }

  /// @inheritdoc IRescuableBase
  function maxRescue(
    address erc20Token
  ) public view override(IRescuableBase, RescuableBase) returns (uint256) {
    if (erc20Token == asset()) {
      return 0; // Cannot rescue GHO
    }
    return IERC20(erc20Token).balanceOf(address(this));
  }

  /// @inheritdoc IERC20Metadata
  function decimals() public pure override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
    return 18;
  }

  /// @inheritdoc IsGho
  function lastUpdate() public view returns (uint64) {
    return _getSGhoStorage().lastUpdate;
  }

  /// @inheritdoc IsGho
  function targetRate() public view returns (uint16) {
    return _getSGhoStorage().targetRate;
  }

  /// @inheritdoc IsGho
  function GHO() public view returns (address) {
    return asset();
  }

  /// @inheritdoc IERC4626
  function maxWithdraw(address owner) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxWithdrawAssets = super.maxWithdraw(owner);
    return maxWithdrawAssets < ghoBalance ? maxWithdrawAssets : ghoBalance;
  }

  /// @inheritdoc IERC4626
  function maxRedeem(address owner) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxRedeemShares = super.maxRedeem(owner);
    uint256 sharesForBalance = convertToShares(ghoBalance);
    return maxRedeemShares < sharesForBalance ? maxRedeemShares : sharesForBalance;
  }

  /// @inheritdoc IERC4626
  function maxDeposit(address) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    sGhoStorage storage $ = _getSGhoStorage();
    uint256 currentAssets = totalAssets();
    return currentAssets >= $.supplyCap ? 0 : $.supplyCap - currentAssets;
  }

  /// @inheritdoc IERC4626
  function maxMint(address receiver) public view override returns (uint256) {
    return convertToShares(maxDeposit(receiver));
  }

  /// @inheritdoc IsGho
  function supplyCap() public view returns (uint160) {
    return _getSGhoStorage().supplyCap;
  }

  /**
   * @notice Returns the total supply of vault tokens, converted to assets, rounded down
   */
  function totalAssets() public view override returns (uint256) {
    return _convertToAssets(totalSupply(), Math.Rounding.Floor);
  }

  /// @inheritdoc IsGho
  function ratePerSecond() public view returns (uint96) {
    return _getSGhoStorage().ratePerSecond;
  }

  /// @inheritdoc IsGho
  function yieldIndex() public view returns (uint176) {
    return _getSGhoStorage().yieldIndex;
  }

  /**
   * @dev Override `ERC20._update`
   * @dev Can only be called when the contract is not paused.
   * @param from Address to deduct tokens from
   * @param to Address to accrue tokens to
   * @param value Amount of tokens to move
   */
  function _update(address from, address to, uint256 value) internal override whenNotPaused {
    _updateYieldIndex();
    super._update(from, to, value);
  }

  /**
   * @dev Override to check the sender has `TOKEN_RESCUER_ROLE` role
   */
  function _checkRescueGuardian() internal view override {
    if (!hasRole(TOKEN_RESCUER_ROLE, _msgSender())) {
      revert AccessControlUnauthorizedAccount(_msgSender(), TOKEN_RESCUER_ROLE);
    }
  }

  /**
   * @notice Converts a GHO asset amount to a sGHO share amount based on the current yield index.
   * @dev Overrides the standard ERC4626 implementation to use the custom yield-based conversion.
   * @param assets The amount of GHO assets.
   * @param rounding The rounding direction to use.
   * @return The corresponding amount of sGHO shares.
   */
  function _convertToShares(
    uint256 assets,
    Math.Rounding rounding
  ) internal view virtual override returns (uint256) {
    uint256 currentYieldIndex = _getCurrentYieldIndex();
    if (currentYieldIndex == 0) return 0;
    return assets.mulDiv(RAY, currentYieldIndex, rounding);
  }

  /**
   * @notice Converts a sGHO share amount to a GHO asset amount based on the current yield index.
   * @dev Overrides the standard ERC4626 implementation to use the custom yield-based conversion.
   * @param shares The amount of sGHO shares.
   * @param rounding The rounding direction to use.
   * @return The corresponding amount of GHO assets.
   */
  function _convertToAssets(
    uint256 shares,
    Math.Rounding rounding
  ) internal view virtual override returns (uint256) {
    uint256 currentYieldIndex = _getCurrentYieldIndex();
    return shares.mulDiv(currentYieldIndex, RAY, rounding);
  }

  /**
   * @notice Calculates the current yield index, including yield accrued since the last update.
   * @dev This is a view function and does not modify state. It's used for previews.
   * The interest calculation is linear within each update period, but compounds across multiple updates.
   * Formula: newIndex = oldIndex * (1 + rate * time)
   * Uses SafeCast to prevent overflow when casting to uint176. If overflow occurs, the transaction will revert
   * instead of silently wrapping, protecting user rewards.
   * @return The current yield index.
   */
  function _getCurrentYieldIndex() internal view returns (uint176) {
    sGhoStorage storage $ = _getSGhoStorage();
    if ($.ratePerSecond == 0) return $.yieldIndex;

    uint256 timeSinceLastUpdate = block.timestamp - $.lastUpdate;
    if (timeSinceLastUpdate == 0) return $.yieldIndex;

    // Linear interest calculation for this update period: newIndex = oldIndex * (1 + rate * time)
    // True compounding occurs through multiple updates as each update builds on the previous index
    uint256 accumulatedRate = $.ratePerSecond * timeSinceLastUpdate;
    uint256 growthFactor = RAY + accumulatedRate;

    return (($.yieldIndex * growthFactor) / RAY).toUint176();
  }

  /**
   * @notice Updates the yield index to accrue yield up to the current timestamp.
   * @dev This function modifies state and is called before any operation that depends on the yield index.
   * Uses SafeCast to prevent overflow when casting to uint176. If overflow occurs, the transaction will revert
   * instead of silently wrapping, protecting user rewards.
   */
  function _updateYieldIndex() internal {
    sGhoStorage storage $ = _getSGhoStorage();
    if ($.lastUpdate != block.timestamp) {
      uint176 newYieldIndex = _getCurrentYieldIndex();
      $.yieldIndex = newYieldIndex;
      $.lastUpdate = uint64(block.timestamp);
      emit ExchangeRateUpdated(block.timestamp, newYieldIndex);
    }
  }
}
