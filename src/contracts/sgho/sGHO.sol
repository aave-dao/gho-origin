// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {ERC20PermitUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import {ERC20Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol';
import {PausableUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol';
import {IERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {RescuableACL} from 'lib/aave-v3-origin/lib/solidity-utils/src/contracts/utils/RescuableACL.sol';
import {RescuableBase, IRescuableBase} from 'lib/aave-v3-origin/lib/solidity-utils/src/contracts/utils/RescuableBase.sol';
import {IsGHO} from './interfaces/IsGHO.sol';

/**
 * @title sGHO Token
 * @author @kpk
 * @notice sGHO is an ERC4626 vault that allows users to deposit GHO and earn yield.
 * @dev This contract implements the ERC4626 standard for tokenized vaults, where the underlying asset is GHO.
 * It also includes functionalities for yield generation based on a target rate, and administrative roles for managing the contract.
 */
contract sGHO is
  Initializable,
  ERC4626Upgradeable,
  ERC20PermitUpgradeable,
  AccessControlUpgradeable,
  RescuableACL,
  PausableUpgradeable,
  IsGHO
{
  using Math for uint256;
  using SafeCast for uint256;

  // RAY is used for high-precision mathematical operations to avoid rounding errors
  uint176 private constant RAY = 1e27;

  /// @custom:storage-location erc7201:gho.storage.sGHO
  struct sGHOStorage {
    // Storage variables - Optimally packed for gas efficiency
    uint176 yieldIndex; // 22 bytes - current yield index for share/asset conversion
    uint64 lastUpdate; // 8 bytes - timestamp of last yield index update
    uint16 targetRate; // 2 bytes - target annual yield rate in basis points (e.g., 1000 = 10%)
    uint160 supplyCap; // 20 bytes - maximum total assets allowed in the vault
    uint96 ratePerSecond; // 12 bytes - cached rate per second for gas efficiency
  }

  // keccak256(abi.encode(uint256(keccak256("gho.storage.sGHO")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant sGHOStorageLocation =
    0xfdf74a24098989caa4d9d232df283137a30d85fb47ad37b31478f919573b9800;

  function _getsGHOStorage() private pure returns (sGHOStorage storage $) {
    assembly {
      $.slot := sGHOStorageLocation
    }
  }

  // Constants (stored in bytecode, not storage)
  uint16 public constant MAX_SAFE_RATE = 5000; // Maximum safe annual yield rate in basis points (50%)
  bytes32 public constant FUNDS_ADMIN_ROLE = 'FUNDS_ADMIN'; // Role for managing rescued funds
  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER'; // Role for managing yield rates and supply caps
  bytes32 public constant PAUSE_GUARDIAN_ROLE = 'PAUSE_GUARDIAN_ROLE'; // Role for managing pause and unpause

  /**
   * @dev Disable initializers on the implementation contract
   */
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializer for the sGHO vault.
   * @param gho_       Address of the underlying GHO token.
   * @param supplyCap_ The total supply cap for the vault.
   * @param executor_  The address that will be granted the DEFAULT_ADMIN_ROLE.
   */
  function initialize(
    address gho_,
    uint160 supplyCap_,
    address executor_
  ) public payable initializer {
    if (gho_ == address(0) || executor_ == address(0)) revert ZeroAddressNotAllowed();

    __ERC20_init('sGHO', 'sGHO');
    __ERC4626_init(IERC20(gho_));
    __ERC20Permit_init('sGHO');
    __AccessControl_init();
    __Pausable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, executor_);
    _grantRole(PAUSE_GUARDIAN_ROLE, executor_);

    sGHOStorage storage $ = _getsGHOStorage();
    $.supplyCap = supplyCap_;
    $.yieldIndex = RAY;
    $.lastUpdate = uint64(block.timestamp);
    $.ratePerSecond = 0; // Initial rate is 0, so ratePerSecond is 0 (no yield initially)
    $.targetRate = 0;
  }

  /**
   * @notice The receive function is implemented to reject direct Ether transfers to the contract.
   * @dev sGHO does not handle ETH directly. All deposits must be made in the GHO token.
   */
  receive() external payable {
    revert NoEthAllowed();
  }

  // --- ERC4626 Logic ---

  /**
   * @inheritdoc IERC4626
   */
  function maxWithdraw(address owner) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxWithdrawAssets = super.maxWithdraw(owner);
    return maxWithdrawAssets < ghoBalance ? maxWithdrawAssets : ghoBalance;
  }

  /**
   * @inheritdoc IERC4626
   */
  function maxRedeem(address owner) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxRedeemShares = super.maxRedeem(owner);
    uint256 sharesForBalance = convertToShares(ghoBalance);
    return maxRedeemShares < sharesForBalance ? maxRedeemShares : sharesForBalance;
  }

  /**
   * @inheritdoc IERC4626
   */
  function maxDeposit(address) public view override returns (uint256) {
    if (paused()) {
      return 0;
    }

    sGHOStorage storage $ = _getsGHOStorage();
    uint256 currentAssets = totalAssets();
    return currentAssets >= $.supplyCap ? 0 : $.supplyCap - currentAssets;
  }

  /**
   * @inheritdoc IERC4626
   */
  function maxMint(address receiver) public view override returns (uint256) {
    return convertToShares(maxDeposit(receiver));
  }

  /**
   * @inheritdoc IsGHO
   */
  function depositWithPermit(
    uint256 assets,
    address receiver,
    uint256 deadline,
    SignatureParams memory sig
  ) external returns (uint256) {
    // Use permit to approve the vault to spend the user's GHO tokens
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

  /**
   * @inheritdoc IERC4626
   */
  function totalAssets() public view override returns (uint256) {
    return _convertToAssets(totalSupply(), Math.Rounding.Floor);
  }

  /// @inheritdoc IsGHO
  function pause() external onlyRole(PAUSE_GUARDIAN_ROLE) {
    _pause();
  }

  /// @inheritdoc IsGHO
  function unpause() external onlyRole(PAUSE_GUARDIAN_ROLE) {
    _unpause();
  }

  /**
   * @inheritdoc IsGHO
   */
  function setTargetRate(uint16 newRate) public onlyRole(YIELD_MANAGER_ROLE) {
    sGHOStorage storage $ = _getsGHOStorage();
    // Update the yield index before changing the rate to ensure proper accrual
    if (newRate > MAX_SAFE_RATE) {
      revert RateMustBeLessThanMaxRate();
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

  /**
   * @inheritdoc IsGHO
   */
  function setSupplyCap(uint160 newSupplyCap) public onlyRole(YIELD_MANAGER_ROLE) {
    _getsGHOStorage().supplyCap = newSupplyCap;
    emit SupplyCapUpdated(newSupplyCap);
  }

  /**
   * @inheritdoc IRescuableBase
   */
  function maxRescue(
    address erc20Token
  ) public view override(IRescuableBase, RescuableBase) returns (uint256) {
    if (erc20Token == asset()) {
      return 0; // Cannot rescue GHO
    }
    return IERC20(erc20Token).balanceOf(address(this));
  }

  function _update(address from, address to, uint256 value) internal override whenNotPaused {
    _updateYieldIndex();
    super._update(from, to, value);
  }

  /**
   * @notice Override _checkRescueGuardian to check for FUNDS_ADMIN role
   * @dev This function reverts if the caller doesn't have the FUNDS_ADMIN role
   */
  function _checkRescueGuardian() internal view override {
    if (!hasRole(FUNDS_ADMIN_ROLE, _msgSender())) {
      revert AccessControlUnauthorizedAccount(_msgSender(), FUNDS_ADMIN_ROLE);
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
    sGHOStorage storage $ = _getsGHOStorage();
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
    sGHOStorage storage $ = _getsGHOStorage();
    if ($.lastUpdate != block.timestamp) {
      uint176 newYieldIndex = _getCurrentYieldIndex();
      $.yieldIndex = newYieldIndex;
      $.lastUpdate = uint64(block.timestamp);
      emit ExchangeRateUpdate(block.timestamp, newYieldIndex);
    }
  }

  // --- Public Getters for Storage Variables ---

  /**
   * @inheritdoc IERC20Metadata
   */
  function decimals() public pure override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
    return 18;
  }

  /**
   * @inheritdoc IsGHO
   */
  function lastUpdate() public view returns (uint64) {
    return _getsGHOStorage().lastUpdate;
  }

  /**
   * @inheritdoc IsGHO
   */
  function targetRate() public view returns (uint16) {
    return _getsGHOStorage().targetRate;
  }

  /**
   * @inheritdoc IsGHO
   */
  function GHO() public view returns (address) {
    return asset();
  }

  /**
   * @inheritdoc IsGHO
   */
  function supplyCap() public view returns (uint160) {
    return _getsGHOStorage().supplyCap;
  }

  /**
   * @inheritdoc IsGHO
   */
  function yieldIndex() public view returns (uint176) {
    return _getsGHOStorage().yieldIndex;
  }

  /**
   * @inheritdoc IsGHO
   */
  function ratePerSecond() public view returns (uint96) {
    return _getsGHOStorage().ratePerSecond;
  }
}
