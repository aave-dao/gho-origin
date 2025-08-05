// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {ERC20PermitUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {IsGHO} from './interfaces/IsGHO.sol';
import {ERC20Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol';
import {RescuableACL} from 'lib/aave-v3-origin/lib/solidity-utils/src/contracts/utils/RescuableACL.sol';
import {RescuableBase, IRescuableBase} from 'lib/aave-v3-origin/lib/solidity-utils/src/contracts/utils/RescuableBase.sol';
/**
 * @title sGHO Token
 * @author @kpk
 * @notice sGHO is an ERC4626 vault that allows users to deposit GHO and earn yield.
 * @dev This contract implements the ERC4626 standard for tokenized vaults, where the underlying asset is GHO.
 * It also includes functionalities for yield generation based on a target rate, and administrative roles for managing the contract.
 */
contract sGHO is Initializable, ERC4626Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, RescuableACL, IsGHO {
  using Math for uint256;

  // Constants for yield calculations (using ray precision - 27 decimals)
  uint256 private constant RAY = 1e27;

  /// @custom:storage-location erc7201:gho.storage.sGHO
  struct sGHOStorage {
    // Storage variables - Optimally packed for gas efficiency
    uint64 lastUpdate; // 8 bytes
    uint16 targetRate; // 2 bytes
    uint256 supplyCap; // 32 bytes
    uint256 yieldIndex; // 32 bytes
    uint256 ratePerSecond; // 32 bytes - cached rate per second for gas efficiency
  }

  // keccak256(abi.encode(uint256(keccak256("gho.storage.sGHO")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant sGHOStorageLocation = 0x8c1d8f3b479c8f3b8c1d8f3b479c8f3b8c1d8f3b479c8f3b8c1d8f3b479c8f3b;

  function _getsGHOStorage() private pure returns (sGHOStorage storage $) {
    assembly {
      $.slot := sGHOStorageLocation
    }
  }

  // Constants (stored in bytecode, not storage)
  uint16 public constant MAX_SAFE_RATE = 5000;
  bytes32 public constant FUNDS_ADMIN_ROLE = 'FUNDS_ADMIN';
  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER';


  

  /**
   * @dev Disable initializers on the implementation contract
   */
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializer for the sGHO vault.
   * @param _gho       Address of the underlying GHO token.
   * @param _supplyCap The total supply cap for the vault.
   */
  function initialize(
    address _gho,
    uint256 _supplyCap
  ) public payable initializer {
    if (_gho == address(0)) revert ZeroAddressNotAllowed();

    __ERC20_init('sGHO', 'sGHO');
    __ERC4626_init(IERC20(_gho));
    __ERC20Permit_init('sGHO');
    __AccessControl_init();

    sGHOStorage storage $ = _getsGHOStorage();
    $.supplyCap = _supplyCap;
    $.yieldIndex = RAY;
    $.lastUpdate = uint64(block.timestamp);
    $.ratePerSecond = 0; // Initial rate is 0, so ratePerSecond is 0
  }

  /**
   * @notice The receive function is implemented to reject direct Ether transfers to the contract.
   * @dev sGHO does not handle ETH directly. All deposits must be made in the GHO token.
   */
  receive() external payable {
    revert NoEthAllowed();
  }




  // --- Approve by signature ---
  /**
   * @notice Overload of the `permit` function that accepts v, r, and s as separate arguments.
   * @dev This is a convenience function for platforms that do not handle the single `bytes` signature format.
   * @param owner The address of the user who owns the tokens.
   * @param spender The address of the spender to be approved.
   * @param value The amount of tokens to approve.
   * @param deadline The deadline after which the signature is no longer valid.
   * @param v The v component of the signature.
   * @param r The r component of the signature.
   * @param s The s component of the signature.
   */
  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public virtual override(IsGHO, ERC20PermitUpgradeable) {
    super.permit(owner, spender, value, deadline, v, r, s);
  }

  /**
   * @dev See {IERC20Permit-nonces}.
   */
  function nonces(
    address owner
  ) public view virtual override(ERC20PermitUpgradeable) returns (uint256) {
    return super.nonces(owner);
  }

  function decimals()
    public
    view
    virtual
    override(ERC20Upgradeable, ERC4626Upgradeable)
    returns (uint8)
  {
    return super.decimals();
  }

  // --- ERC4626 Logic ---

  /**
   * @notice Returns the maximum amount of GHO that can be withdrawn by an owner.
   * @dev This is the minimum of the amount of assets the owner has and the total GHO balance of the contract.
   * @param owner The address of the user who owns the shares.
   * @return The maximum amount of GHO that can be withdrawn.
   */
  function maxWithdraw(address owner) public view override(ERC4626Upgradeable) returns (uint256) {
    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxWithdrawAssets = super.maxWithdraw(owner);
    return maxWithdrawAssets < ghoBalance ? maxWithdrawAssets : ghoBalance;
  }

  /**
   * @notice Returns the maximum amount of sGHO shares that can be redeemed by an owner.
   * @dev This is the minimum of the owner's share balance and the number of shares corresponding to the contract's total GHO balance.
   * @param owner The address of the user who owns the shares.
   * @return The maximum amount of sGHO shares that can be redeemed.
   */
  function maxRedeem(address owner) public view override(ERC4626Upgradeable) returns (uint256) {
    uint256 ghoBalance = IERC20(asset()).balanceOf(address(this));
    uint256 maxRedeemShares = super.maxRedeem(owner);
    uint256 sharesForBalance = convertToShares(ghoBalance);
    return maxRedeemShares < sharesForBalance ? maxRedeemShares : sharesForBalance;
  }

  function maxDeposit(address) public view override(ERC4626Upgradeable) returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    uint256 currentAssets = totalAssets();
    return currentAssets >= $.supplyCap ? 0 : $.supplyCap - currentAssets;
  }

  function maxMint(address) public view override(ERC4626Upgradeable) returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    uint256 currentAssets = totalAssets();
    return currentAssets >= $.supplyCap ? 0 : convertToShares($.supplyCap - currentAssets);
  }

  /**
   * @notice Deposits GHO into the vault and mints sGHO shares to the receiver.
   * @dev The yield index is updated before the deposit to ensure correct share calculation.
   * @param assets The amount of GHO to deposit.
   * @param receiver The address that will receive the sGHO shares.
   * @return The amount of sGHO shares minted.
   */
  function deposit(
    uint256 assets,
    address receiver
  ) public override(ERC4626Upgradeable) returns (uint256) {
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    }

    _updateYieldIndex();
    uint256 shares = previewDeposit(assets);
    _deposit(_msgSender(), receiver, assets, shares);

    return shares;
  }

  /**
   * @notice Mints sGHO shares to the receiver by depositing a corresponding amount of GHO.
   * @dev The yield index is updated before the mint to ensure correct asset calculation.
   * @param shares The amount of sGHO shares to mint.
   * @param receiver The address that will receive the sGHO shares.
   * @return The amount of GHO deposited.
   */
  function mint(
    uint256 shares,
    address receiver
  ) public override(ERC4626Upgradeable) returns (uint256) {
    uint256 maxShares = maxMint(receiver);
    if (shares > maxShares) {
      revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
    }

    _updateYieldIndex();
    uint256 assets = previewMint(shares);

    _deposit(_msgSender(), receiver, assets, shares);

    return assets;
  }

  /**
   * @notice Withdraws GHO from the vault by burning sGHO shares from the owner.
   * @dev The yield index is updated before the withdrawal.
   * @param assets The amount of GHO to withdraw.
   * @param receiver The address that will receive the GHO.
   * @param owner The address from which to burn sGHO shares.
   * @return The amount of sGHO shares burned.
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) public override(ERC4626Upgradeable) returns (uint256) {
    uint256 maxAssets = maxWithdraw(owner);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
    }

    _updateYieldIndex();
    uint256 shares = previewWithdraw(assets);
    _withdraw(_msgSender(), receiver, owner, assets, shares);

    return shares;
  }

  /**
   * @notice Redeems a specific amount of sGHO shares for GHO.
   * @dev The yield index is updated before the redemption.
   * @param shares The amount of sGHO shares to redeem.
   * @param receiver The address that will receive the GHO.
   * @param owner The address from which to burn sGHO shares.
   * @return The amount of GHO received.
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public override(ERC4626Upgradeable) returns (uint256) {
    uint256 maxShares = maxRedeem(owner);
    if (shares > maxShares) {
      revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    }

    _updateYieldIndex();
    uint256 assets = previewRedeem(shares);
    _withdraw(_msgSender(), receiver, owner, assets, shares);

    return assets;
  }

  /**
   * @notice Returns the total amount of GHO managed by the vault.
   * @dev This is calculated based on the total supply of sGHO and the current yield index.
   * @return The total amount of GHO assets.
   */
  function totalAssets() public view override(ERC4626Upgradeable) returns (uint256) {
    return _convertToAssets(totalSupply(), Math.Rounding.Floor);
  }

  /**
   * @inheritdoc IsGHO
   */
  function vaultAPR() external view returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.targetRate;
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
    
    // Calculate and cache the new rate per second for gas efficiency
    if (newRate == 0) {
      $.ratePerSecond = 0;
    } else {
      // Convert targetRate from basis points to ray (1e27 scale)
      // targetRate is in basis points (e.g., 1000 = 10%)
      uint256 annualRateRay = uint256(newRate).mulDiv(RAY, 10000, Math.Rounding.Floor);
      // Calculate the rate per second
      $.ratePerSecond = annualRateRay.mulDiv(RAY, 365 days, Math.Rounding.Floor);
    }
    
    emit TargetRateUpdated(newRate);
  }

  /**
   * @inheritdoc IsGHO
   */
  function setSupplyCap(uint256 newSupplyCap) public onlyRole(YIELD_MANAGER_ROLE) {
    sGHOStorage storage $ = _getsGHOStorage();
    if (newSupplyCap < totalAssets()) {
      revert SupplyCapMustBeGreaterThanTotalAssets();
    }
    $.supplyCap = newSupplyCap;
    emit SupplyCapUpdated(newSupplyCap);
  }

  /**
   * @notice Override maxRescue to prevent rescuing GHO tokens
   * @param erc20Token The address of the ERC20 token to check
   * @return The maximum amount that can be rescued (0 for GHO, full balance for others)
   */
  function maxRescue(address erc20Token) public view override(IRescuableBase, RescuableBase) returns (uint256) {
    if (erc20Token == asset()) {
      return 0; // Cannot rescue GHO
    }
    return IERC20(erc20Token).balanceOf(address(this));
  }

  /**
   * @notice Override _checkRescueGuardian to check for FUNDS_ADMIN role
   * @dev This function reverts if the caller doesn't have the FUNDS_ADMIN role
   */
  function _checkRescueGuardian() internal view override {
    if (!hasRole(FUNDS_ADMIN_ROLE, _msgSender())) {
      revert OnlyFundsAdmin();
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
   * @return The current yield index.
   */
  function _getCurrentYieldIndex() internal view returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    if ($.ratePerSecond == 0) return $.yieldIndex;

    uint256 timeSinceLastUpdate = block.timestamp - $.lastUpdate;
    if (timeSinceLastUpdate == 0) return $.yieldIndex;

    // Linear interest calculation for this update period: newIndex = oldIndex * (1 + rate * time)
    // True compounding occurs through multiple updates as each update builds on the previous index
    uint256 accumulatedRate = $.ratePerSecond.mulDiv(timeSinceLastUpdate, RAY, Math.Rounding.Floor);
    uint256 growthFactor = RAY + accumulatedRate;

    return $.yieldIndex.mulDiv(growthFactor, RAY, Math.Rounding.Floor);
  }

  /**
   * @notice Updates the yield index to accrue yield up to the current timestamp.
   * @dev This function modifies state and is called before any operation that depends on the yield index.
   */
  function _updateYieldIndex() internal {
    sGHOStorage storage $ = _getsGHOStorage();
    uint256 newYieldIndex = _getCurrentYieldIndex();
    if (newYieldIndex != $.yieldIndex) {
      $.yieldIndex = newYieldIndex;
      $.lastUpdate = uint64(block.timestamp);
    }
  }



  // Public getters for storage variables
  function lastUpdate() public view returns (uint64) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.lastUpdate;
  }

  function targetRate() public view returns (uint16) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.targetRate;
  }

  function GHO() public view returns (address) {
    return asset();
  }



  function supplyCap() public view returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.supplyCap;
  }

  function yieldIndex() public view returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.yieldIndex;
  }

  function ratePerSecond() public view returns (uint256) {
    sGHOStorage storage $ = _getsGHOStorage();
    return $.ratePerSecond;
  }
}
