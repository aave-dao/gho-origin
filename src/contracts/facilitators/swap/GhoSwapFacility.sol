// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {AccessManagedUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IGhoReserve} from 'src/contracts/facilitators/gsm/interfaces/IGhoReserve.sol';
import {IGhoSwapFacility} from 'src/contracts/facilitators/swap/interfaces/IGhoSwapFacility.sol';

/// @title GhoSwapFacility
/// @author Aave Labs
/// @notice Swaps GHO 1:1 against the asset of an ERC4626 vault. GHO comes from a `GhoReserve`.
/// @dev Value model: one unit of the vault asset is worth one GHO (decimals adjusted), and shares are
/// valued with `convertToAssets`. Each pool keeps exactly enough shares to back the GHO it drew
/// (`used`); anything above that is yield and is sent to the treasury as shares before every swap.
/// Because the skim never mints GHO, it does not depend on the reserve limit, and a swap of GHO for
/// shares can always restore up to `used`.
///
/// Permissions go through an OpenZeppelin AccessManager. `swap` is `restricted`: make it public with
/// `setTargetFunctionRole(facility, [swap], PUBLIC_ROLE)`, or gate it behind a role. To freeze swaps,
/// point `swap` at a role nobody holds. `skim`, `repay` and `claimFees` are permissionless.
///
/// Upgradeability: deploy behind a proxy and call `initialize`. Mutable state lives in an ERC-7201
/// namespaced struct, as do the OpenZeppelin parents, so implementations can add fields at the end of
/// `GhoSwapFacilityStorage` without slot collisions. `GHO`, `VAULT` and `RESERVE` are immutables of the
/// implementation: a new implementation must be deployed with the same values.
contract GhoSwapFacility is
  IGhoSwapFacility,
  Initializable,
  AccessManagedUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  uint256 internal constant BPS = 10_000;

  /// @inheritdoc IGhoSwapFacility
  address public constant PUBLIC_POOL = address(0);

  /// @inheritdoc IGhoSwapFacility
  address public immutable GHO;

  /// @inheritdoc IGhoSwapFacility
  address public immutable VAULT;

  /// @inheritdoc IGhoSwapFacility
  address public immutable RESERVE;

  /// @dev 10 ** (18 - vault asset decimals): converts vault assets to GHO units.
  uint256 internal immutable SCALE;

  /// @custom:storage-location erc7201:aave.storage.GhoSwapFacility
  struct GhoSwapFacilityStorage {
    address treasury;
    uint256 accruedFees;
    mapping(address pool => Pool) pools;
    mapping(address account => FeeTier) feeTiers;
  }

  // keccak256(abi.encode(uint256(keccak256("aave.storage.GhoSwapFacility")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant STORAGE_LOCATION =
    0xb0080694905adb0789279695150c0aca9abdb23a81cdfdff45895a20089e0500;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address gho, address vault, address reserve) {
    if (gho == address(0) || vault == address(0) || reserve == address(0)) revert ZeroAddress();
    address reserveToken = IGhoReserve(reserve).GHO_TOKEN();
    if (reserveToken != gho) revert ReserveTokenMismatch(reserveToken);
    uint8 assetDecimals = IERC20Metadata(IERC4626(vault).asset()).decimals();
    if (assetDecimals > 18) revert UnsupportedDecimals(assetDecimals);

    GHO = gho;
    VAULT = vault;
    RESERVE = reserve;
    SCALE = 10 ** (18 - assetDecimals);

    _disableInitializers();
  }

  /// @inheritdoc IGhoSwapFacility
  function initialize(address authority, address treasury_) external initializer {
    if (authority == address(0)) revert ZeroAddress();
    __AccessManaged_init(authority);
    __ReentrancyGuard_init();
    _setTreasury(treasury_);
    IERC20(GHO).forceApprove(RESERVE, type(uint256).max);
  }

  /// @inheritdoc IGhoSwapFacility
  function swap(
    address pool,
    address tokenIn,
    uint256 amountIn,
    uint256 minAmountOut,
    address receiver
  ) external restricted nonReentrant returns (uint256 amountOut) {
    if (pool != PUBLIC_POOL && pool != msg.sender) revert PoolAccessDenied(pool, msg.sender);
    if (receiver == address(0)) revert ZeroAddress();
    if (amountIn == 0) revert ZeroAmount();

    GhoSwapFacilityStorage storage $ = _getStorage();
    Pool storage p = $.pools[pool];
    _skim(pool, p);

    uint256 fee;
    if (tokenIn == VAULT) {
      uint256 gross;
      (amountOut, fee, gross) = _quoteSharesIn(msg.sender, amountIn);
      uint256 newUsed = p.used + gross;
      if (newUsed > p.cap) revert PoolCapExceeded(pool, newUsed, p.cap);
      _checkOut(amountOut, minAmountOut);

      p.used = newUsed.toUint128();
      p.shares += amountIn.toUint128();
      $.accruedFees += fee;

      IERC20(VAULT).safeTransferFrom(msg.sender, address(this), amountIn);
      IGhoReserve(RESERVE).use(gross);
      IERC20(GHO).safeTransfer(receiver, amountOut);
    } else if (tokenIn == GHO) {
      uint256 net;
      (amountOut, fee, net) = _quoteGhoIn(msg.sender, amountIn);
      if (amountOut > p.shares || net > p.used) revert InsufficientLiquidity(pool);
      _checkOut(amountOut, minAmountOut);

      p.shares -= amountOut.toUint128();
      p.used -= net.toUint128();
      $.accruedFees += fee;

      IERC20(GHO).safeTransferFrom(msg.sender, address(this), amountIn);
      IGhoReserve(RESERVE).restore(net);
      IERC20(VAULT).safeTransfer(receiver, amountOut);
    } else {
      revert InvalidToken(tokenIn);
    }

    emit Swap(pool, msg.sender, receiver, tokenIn, amountIn, amountOut, fee);
  }

  /// @inheritdoc IGhoSwapFacility
  function skim(address pool) external nonReentrant returns (uint256) {
    return _skim(pool, _getStorage().pools[pool]);
  }

  /// @inheritdoc IGhoSwapFacility
  function repay(address pool, uint256 amount) external nonReentrant returns (uint256) {
    Pool storage p = _getStorage().pools[pool];
    uint256 value = _sharesToGho(p.shares);
    if (value >= p.used) revert NoDeficit(pool);

    uint256 repaid = Math.min(amount, p.used - value);
    if (repaid == 0) revert ZeroAmount();
    p.used -= repaid.toUint128();

    IERC20(GHO).safeTransferFrom(msg.sender, address(this), repaid);
    IGhoReserve(RESERVE).restore(repaid);
    emit DeficitRepaid(pool, msg.sender, repaid);
    return repaid;
  }

  /// @inheritdoc IGhoSwapFacility
  function claimFees() external nonReentrant returns (uint256 amount) {
    GhoSwapFacilityStorage storage $ = _getStorage();
    amount = $.accruedFees;
    if (amount == 0) return 0;
    $.accruedFees = 0;
    IERC20(GHO).safeTransfer($.treasury, amount);
    emit FeesClaimed($.treasury, amount);
  }

  /// @inheritdoc IGhoSwapFacility
  function seize(
    address pool,
    address to
  ) external restricted nonReentrant returns (uint256 shares) {
    if (to == address(0)) revert ZeroAddress();
    Pool storage p = _getStorage().pools[pool];
    shares = p.shares;
    p.shares = 0;
    p.cap = 0;
    IERC20(VAULT).safeTransfer(to, shares);
    emit PoolCapSet(pool, 0);
    emit PoolSeized(pool, to, shares, p.used);
  }

  /// @inheritdoc IGhoSwapFacility
  function makePublic(address pool) external restricted nonReentrant {
    if (pool == PUBLIC_POOL) revert NotPrivatePool();
    GhoSwapFacilityStorage storage $ = _getStorage();
    Pool storage priv = $.pools[pool];
    Pool storage pub = $.pools[PUBLIC_POOL];
    _skim(pool, priv);
    _skim(PUBLIC_POOL, pub);

    Pool memory moved = priv;
    delete $.pools[pool];
    pub.shares += moved.shares;
    pub.used += moved.used;
    pub.cap += moved.cap;

    emit PoolMadePublic(pool, moved.shares, moved.used, moved.cap);
    emit PoolCapSet(pool, 0);
    emit PoolCapSet(PUBLIC_POOL, pub.cap);
  }

  /// @inheritdoc IGhoSwapFacility
  function setPoolCap(address pool, uint128 cap) external restricted {
    _getStorage().pools[pool].cap = cap;
    emit PoolCapSet(pool, cap);
  }

  /// @inheritdoc IGhoSwapFacility
  function setFeeTier(address account, uint16 sharesInBps, uint16 ghoInBps) external restricted {
    if (sharesInBps > BPS) revert InvalidFee(sharesInBps);
    if (ghoInBps > BPS) revert InvalidFee(ghoInBps);
    _getStorage().feeTiers[account] = FeeTier({
      sharesInBps: sharesInBps,
      ghoInBps: ghoInBps,
      isSet: true
    });
    emit FeeTierSet(account, sharesInBps, ghoInBps);
  }

  /// @inheritdoc IGhoSwapFacility
  function clearFeeTier(address account) external restricted {
    delete _getStorage().feeTiers[account];
    emit FeeTierCleared(account);
  }

  /// @inheritdoc IGhoSwapFacility
  function setTreasury(address treasury_) external restricted {
    _setTreasury(treasury_);
  }

  /// @inheritdoc IGhoSwapFacility
  function quote(
    address account,
    address tokenIn,
    uint256 amountIn
  ) external view returns (uint256 amountOut, uint256 fee) {
    if (tokenIn == VAULT) {
      (amountOut, fee, ) = _quoteSharesIn(account, amountIn);
    } else if (tokenIn == GHO) {
      (amountOut, fee, ) = _quoteGhoIn(account, amountIn);
    } else {
      revert InvalidToken(tokenIn);
    }
  }

  /// @inheritdoc IGhoSwapFacility
  function getFeeTier(address account) public view returns (FeeTier memory tier) {
    GhoSwapFacilityStorage storage $ = _getStorage();
    tier = $.feeTiers[account];
    if (!tier.isSet) tier = $.feeTiers[PUBLIC_POOL];
  }

  /// @inheritdoc IGhoSwapFacility
  function getPool(address pool) external view returns (Pool memory) {
    return _getStorage().pools[pool];
  }

  /// @inheritdoc IGhoSwapFacility
  function treasury() external view returns (address) {
    return _getStorage().treasury;
  }

  /// @inheritdoc IGhoSwapFacility
  function accruedFees() external view returns (uint256) {
    return _getStorage().accruedFees;
  }

  /// @inheritdoc IGhoSwapFacility
  function getSurplus(address pool) external view returns (int256) {
    Pool memory p = _getStorage().pools[pool];
    return SafeCast.toInt256(_sharesToGho(p.shares)) - SafeCast.toInt256(p.used);
  }

  /// @dev Sends the shares above what backs `p.used` to the treasury. Rounds in favor of the pool.
  function _skim(address pool, Pool storage p) internal returns (uint256 excess) {
    uint256 keep = IERC4626(VAULT).previewWithdraw(Math.ceilDiv(p.used, SCALE));
    if (p.shares <= keep) return 0;
    excess = p.shares - keep;
    p.shares = keep.toUint128();
    IERC20(VAULT).safeTransfer(_getStorage().treasury, excess);
    emit YieldSkimmed(pool, excess);
  }

  /// @return amountOut GHO sent out.
  /// @return fee GHO fee.
  /// @return gross GHO drawn from the reserve (amountOut + fee).
  function _quoteSharesIn(
    address account,
    uint256 shares
  ) internal view returns (uint256 amountOut, uint256 fee, uint256 gross) {
    gross = _sharesToGho(shares);
    fee = Math.mulDiv(gross, getFeeTier(account).sharesInBps, BPS, Math.Rounding.Ceil);
    amountOut = gross - fee;
  }

  /// @return amountOut Shares sent out.
  /// @return fee GHO fee.
  /// @return net GHO restored to the reserve (amountIn - fee).
  function _quoteGhoIn(
    address account,
    uint256 ghoIn
  ) internal view returns (uint256 amountOut, uint256 fee, uint256 net) {
    fee = Math.mulDiv(ghoIn, getFeeTier(account).ghoInBps, BPS, Math.Rounding.Ceil);
    net = ghoIn - fee;
    amountOut = IERC4626(VAULT).convertToShares(net / SCALE);
  }

  function _sharesToGho(uint256 shares) internal view returns (uint256) {
    return IERC4626(VAULT).convertToAssets(shares) * SCALE;
  }

  function _checkOut(uint256 amountOut, uint256 minAmountOut) internal pure {
    if (amountOut == 0) revert ZeroAmount();
    if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);
  }

  function _setTreasury(address treasury_) internal {
    if (treasury_ == address(0)) revert ZeroAddress();
    _getStorage().treasury = treasury_;
    emit TreasurySet(treasury_);
  }

  function _getStorage() private pure returns (GhoSwapFacilityStorage storage $) {
    assembly {
      $.slot := STORAGE_LOCATION
    }
  }
}
