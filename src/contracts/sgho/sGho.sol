// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';
import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';
import {MathUtils} from 'aave-v3-origin/contracts/protocol/libraries/math/MathUtils.sol';
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
abstract contract sGho is
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

  /// @custom:storage-location erc7201:gho.storage.sGHO
  struct sGhoStorage {
    // Storage variables - Optimally packed so the hot path only touches the first slot
    uint120 yieldIndex; // 15 bytes - current yield index for share/asset conversion
    uint40 lastUpdate; // 5 bytes - timestamp of the last yield index checkpoint
    uint16 targetRate; // 2 bytes - target annual yield rate in basis points (e.g., 1000 = 10%)
    uint40 supplyCap; // 5 bytes - maximum total assets allowed in the vault, in whole GHO units
    uint40 pendingRateEffectiveAt; // 5 bytes - timestamp of the scheduled rate change (0 = none)
    uint16 pendingTargetRate; // 2 bytes (second slot) - scheduled target rate in basis points
  }

  // keccak256(abi.encode(uint256(keccak256("gho.storage.sGho")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant sGhoStorageLocation =
    0x52190d4bcaca04cac5a7c2ae78ea3854d285be3b91819fb1b3ed9862d9a9a400;

  function _getSGhoStorage() internal pure returns (sGhoStorage storage $) {
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
   * @dev Initializes the vault state. Must be called within an initializer or reinitializer.
   * @dev The yield index checkpoint is an input so a deployment on a new chain can cold start in
   * sync, from a checkpoint read from a live deployment; a genesis deployment starts at
   * (RAY, current timestamp, 0).
   * @param gho Address of the underlying GHO token.
   * @param initialSupplyCap The supply cap for the vault, in whole GHO units.
   * @param owner The address that will be granted the DEFAULT_ADMIN_ROLE.
   * @param initialYieldIndex The initial yield index (RAY scale, at least RAY).
   * @param initialLastUpdate The initial checkpoint timestamp (must not be in the future).
   * @param initialTargetRate The initial target rate in basis points.
   */
  function __sGho_init(
    address gho,
    uint40 initialSupplyCap,
    address owner,
    uint120 initialYieldIndex,
    uint40 initialLastUpdate,
    uint16 initialTargetRate
  ) internal onlyInitializing {
    if (gho == address(0) || owner == address(0)) revert ZeroAddressNotAllowed();

    __ERC20_init('sGho', 'sGho');
    __ERC4626_init(IERC20(gho));
    __ERC20Permit_init('sGho');
    __AccessControl_init();
    __Pausable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, owner);
    _grantRole(PAUSE_GUARDIAN_ROLE, owner);

    _getSGhoStorage().supplyCap = initialSupplyCap;
    _syncYieldIndex(initialYieldIndex, initialLastUpdate, initialTargetRate);
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
  function setTargetRate(uint16 newRate, uint40 effectiveAt) public onlyRole(YIELD_MANAGER_ROLE) {
    if (newRate > MAX_SAFE_RATE) {
      revert MaxRateExceeded();
    }
    if (effectiveAt < block.timestamp) {
      revert EffectiveTimestampInPast();
    }

    _applyPendingTargetRate();

    sGhoStorage storage $ = _getSGhoStorage();
    if (effectiveAt == block.timestamp) {
      // Checkpoint the index with the old rate before changing it
      uint120 newYieldIndex = _getCurrentYieldIndex();
      bool alreadyCheckpointed = $.lastUpdate == block.timestamp;
      _setCheckpoint(newYieldIndex, block.timestamp.toUint40(), newRate);
      if (!alreadyCheckpointed) {
        emit ExchangeRateUpdated(block.timestamp, newYieldIndex);
      }
    } else {
      $.pendingRateEffectiveAt = effectiveAt;
      $.pendingTargetRate = newRate;
    }
    emit TargetRateUpdated(newRate, effectiveAt);
  }

  /// @inheritdoc IsGho
  function syncYieldIndex(
    uint120 newYieldIndex,
    uint40 newLastUpdate,
    uint16 newTargetRate
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _syncYieldIndex(newYieldIndex, newLastUpdate, newTargetRate);
  }

  /// @inheritdoc IsGho
  function setSupplyCap(uint256 newSupplyCap) public onlyRole(YIELD_MANAGER_ROLE) {
    _getSGhoStorage().supplyCap = newSupplyCap.toUint40();
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
  function lastUpdate() public view returns (uint256) {
    (, uint40 timestamp, , ) = _getCheckpoint();
    return timestamp;
  }

  /// @inheritdoc IsGho
  function targetRate() public view returns (uint16) {
    (, , uint16 rate, ) = _getCheckpoint();
    return rate;
  }

  /// @inheritdoc IsGho
  function pendingTargetRate() public view returns (uint16, uint40) {
    sGhoStorage storage $ = _getSGhoStorage();
    uint40 effectiveAt = $.pendingRateEffectiveAt;
    if (effectiveAt == 0 || block.timestamp >= effectiveAt) {
      return (0, 0);
    }
    return ($.pendingTargetRate, effectiveAt);
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

    uint256 cap = uint256(_getSGhoStorage().supplyCap) * 10 ** decimals();
    uint256 currentAssets = totalAssets();
    return currentAssets >= cap ? 0 : cap - currentAssets;
  }

  /// @inheritdoc IERC4626
  function maxMint(address receiver) public view override returns (uint256) {
    return convertToShares(maxDeposit(receiver));
  }

  /// @inheritdoc IsGho
  function supplyCap() public view returns (uint256) {
    return _getSGhoStorage().supplyCap;
  }

  /**
   * @notice Returns the total supply of vault tokens, converted to assets, rounded down
   */
  function totalAssets() public view override returns (uint256) {
    return _convertToAssets(totalSupply(), Math.Rounding.Floor);
  }

  /// @inheritdoc IsGho
  function yieldIndex() public view returns (uint256) {
    (uint120 index, , , ) = _getCheckpoint();
    return index;
  }

  /**
   * @dev Override `ERC20._update`
   * @dev Can only be called when the contract is not paused.
   * @param from Address to deduct tokens from
   * @param to Address to accrue tokens to
   * @param value Amount of tokens to move
   */
  function _update(address from, address to, uint256 value) internal override whenNotPaused {
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
    return assets.mulDiv(WadRayMath.RAY, currentYieldIndex, rounding);
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
    return shares.mulDiv(currentYieldIndex, WadRayMath.RAY, rounding);
  }

  /**
   * @notice Resolves the current checkpoint, folding in a scheduled rate change once it is due.
   * @dev When a scheduled change is due, the index is checkpointed exactly at its effective
   * timestamp, so the resolved state is identical across chains no matter when each chain
   * executes the update or first touches storage afterwards.
   * @return index The yield index at the checkpoint.
   * @return timestamp The checkpoint timestamp.
   * @return rate The target rate in force since the checkpoint.
   * @return pendingDue Whether a due scheduled rate change was folded in (not yet persisted).
   */
  function _getCheckpoint() internal view returns (uint120, uint40, uint16, bool) {
    sGhoStorage storage $ = _getSGhoStorage();
    uint40 effectiveAt = $.pendingRateEffectiveAt;
    if (effectiveAt != 0 && block.timestamp >= effectiveAt) {
      uint120 index = ($.yieldIndex + _accruedYield($.targetRate, effectiveAt - $.lastUpdate))
        .toUint120();
      return (index, effectiveAt, $.pendingTargetRate, true);
    }
    return ($.yieldIndex, $.lastUpdate, $.targetRate, false);
  }

  /**
   * @notice Calculates the current yield index, accruing yield since the last checkpoint.
   * @dev Yield accrues linearly at a fixed APR: newIndex = lastIndex + targetRate * timeElapsed / year.
   * Dividing by the year last keeps a full APR period exact and never compounds, since the index is
   * only checkpointed when the rate changes. Uses SafeCast to revert on overflow.
   * @return The current yield index.
   */
  function _getCurrentYieldIndex() internal view returns (uint120) {
    (uint120 index, uint40 timestamp, uint16 rate, ) = _getCheckpoint();
    if (rate == 0 || block.timestamp == timestamp) return index;

    return (index + _accruedYield(rate, block.timestamp - timestamp)).toUint120();
  }

  /**
   * @notice Calculates the yield accrued at a fixed APR over a time period, in RAY.
   * @param rate The annual yield rate in basis points.
   * @param timeDelta The elapsed time in seconds.
   * @return The accrued yield in RAY.
   */
  function _accruedYield(uint256 rate, uint256 timeDelta) internal pure returns (uint256) {
    return
      (rate * WadRayMath.RAY * timeDelta) /
      (PercentageMath.PERCENTAGE_FACTOR * MathUtils.SECONDS_PER_YEAR);
  }

  /**
   * @notice Persists a scheduled rate change once it is due, checkpointing the yield index at its
   * effective timestamp.
   */
  function _applyPendingTargetRate() internal {
    (uint120 index, uint40 timestamp, uint16 rate, bool pendingDue) = _getCheckpoint();
    if (!pendingDue) return;

    _setCheckpoint(index, timestamp, rate);
    emit ExchangeRateUpdated(timestamp, index);
  }

  /**
   * @notice Validates and overwrites the yield index checkpoint, discarding any scheduled rate change.
   * @dev Backs both `syncYieldIndex` and the checkpoint initialization in `__sGho_init`.
   * @param newYieldIndex The new yield index (RAY scale, at least RAY).
   * @param newLastUpdate The new checkpoint timestamp (must not be in the future).
   * @param newTargetRate The new target rate in basis points.
   */
  function _syncYieldIndex(
    uint120 newYieldIndex,
    uint40 newLastUpdate,
    uint16 newTargetRate
  ) internal {
    if (newTargetRate > MAX_SAFE_RATE) {
      revert MaxRateExceeded();
    }
    if (newLastUpdate > block.timestamp) {
      revert SyncTimestampInFuture();
    }
    if (newYieldIndex < WadRayMath.RAY) {
      revert YieldIndexTooLow();
    }

    _setCheckpoint(newYieldIndex, newLastUpdate, newTargetRate);
    emit YieldIndexSynced(newYieldIndex, newLastUpdate, newTargetRate);
  }

  /**
   * @notice Persists the yield index checkpoint, discarding any scheduled rate change.
   * @dev Only invoked when the rate changes or is synced. Leaving the index untouched on regular
   * operations prevents accrual from being lost to rounding when actions happen in quick succession.
   * @param index The yield index at the checkpoint.
   * @param timestamp The checkpoint timestamp.
   * @param rate The target rate in force from the checkpoint.
   */
  function _setCheckpoint(uint120 index, uint40 timestamp, uint16 rate) internal {
    sGhoStorage storage $ = _getSGhoStorage();
    $.yieldIndex = index;
    $.lastUpdate = timestamp;
    $.targetRate = rate;
    $.pendingRateEffectiveAt = 0;
    $.pendingTargetRate = 0;
  }
}
