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
import {IGhoReserve} from 'src/contracts/facilitators/gsm/interfaces/IGhoReserve.sol';
import {IGhoSwapFacility} from 'src/contracts/facilitators/swap/interfaces/IGhoSwapFacility.sol';

/// @title GhoSwapFacility
/// @author Aave Labs
/// @notice Swaps GHO against an ERC20 asset. GHO comes from a `GhoReserve`.
/// @dev Value model: one unit of the asset is worth one GHO, adjusted for decimals. Derived contracts
/// change it by overriding `_toGho`, `_fromGho`, `_backing` and `_pricingDecimals` (see
/// `GhoSwapFacility4626`). Each pool keeps exactly enough asset to back the GHO it drew (`used`);
/// anything above that is surplus (yield, for a yield-bearing asset) and is sent to the treasury in the
/// asset before every swap. Because the skim never mints GHO, it does not depend on the reserve limit,
/// and a swap of GHO for the asset can always restore up to `used`.
///
/// `swap`, `skim`, `repay` and `claimFees` are permissionless: anyone can trade on the public pool, and
/// only its owner on a private pool. Admin functions, including `setPaused`, go through an
/// OpenZeppelin AccessManager.
///
/// Upgradeability: deploy behind a proxy and call `initialize`. Mutable state lives in an ERC-7201
/// namespaced struct, as do the OpenZeppelin parents, so implementations can add fields at the end of
/// `GhoSwapFacilityStorage` without slot collisions. `GHO`, `ASSET` and `RESERVE` are immutables of the
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
  address public immutable ASSET;

  /// @inheritdoc IGhoSwapFacility
  address public immutable RESERVE;

  /// @dev 10 ** (18 - pricing decimals): converts priced units to GHO units.
  uint256 internal immutable SCALE;

  /// @custom:storage-location erc7201:aave.storage.GhoSwapFacility
  struct GhoSwapFacilityStorage {
    address treasury;
    bool paused;
    uint256 accruedFees;
    mapping(address pool => Pool) pools;
  }

  // keccak256(abi.encode(uint256(keccak256("aave.storage.GhoSwapFacility")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant STORAGE_LOCATION =
    0xb0080694905adb0789279695150c0aca9abdb23a81cdfdff45895a20089e0500;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address gho, address asset, address reserve) {
    if (gho == address(0) || asset == address(0) || reserve == address(0)) revert ZeroAddress();
    address reserveToken = IGhoReserve(reserve).GHO_TOKEN();
    if (reserveToken != gho) revert ReserveTokenMismatch(reserveToken);
    uint8 decimals = _pricingDecimals(asset);
    if (decimals > 18) revert UnsupportedDecimals(decimals);

    GHO = gho;
    ASSET = asset;
    RESERVE = reserve;
    SCALE = 10 ** (18 - decimals);

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
    address tokenIn,
    uint256 amountIn,
    uint256 minAmountOut,
    address receiver
  ) external nonReentrant returns (uint256 amountOut) {
    GhoSwapFacilityStorage storage $ = _getStorage();
    if ($.paused) revert SwapsPaused();
    if (receiver == address(0)) revert ZeroAddress();
    if (amountIn == 0) revert ZeroAmount();

    address pool = poolOf(msg.sender);
    _skim(pool);
    Pool storage p = $.pools[pool];

    uint256 fee;
    if (tokenIn == ASSET) {
      uint256 gross;
      (amountOut, fee, gross) = _quoteAssetIn(p.assetInBps, amountIn);
      uint256 newUsed = p.used + gross;
      if (newUsed > p.cap) revert PoolCapExceeded(pool, newUsed, p.cap);
      _checkOut(amountOut, minAmountOut);

      p.used = newUsed.toUint128();
      p.balance += amountIn.toUint128();
      $.accruedFees += fee;

      IERC20(ASSET).safeTransferFrom(msg.sender, address(this), amountIn);
      IGhoReserve(RESERVE).use(gross);
      IERC20(GHO).safeTransfer(receiver, amountOut);
    } else if (tokenIn == GHO) {
      uint256 net;
      (amountOut, fee, net) = _quoteGhoIn(p.ghoInBps, amountIn);
      if (amountOut > p.balance || net > p.used) revert InsufficientLiquidity(pool);
      _checkOut(amountOut, minAmountOut);

      p.balance -= amountOut.toUint128();
      p.used -= net.toUint128();
      $.accruedFees += fee;

      IERC20(GHO).safeTransferFrom(msg.sender, address(this), amountIn);
      IGhoReserve(RESERVE).restore(net);
      IERC20(ASSET).safeTransfer(receiver, amountOut);
    } else {
      revert InvalidToken(tokenIn);
    }

    emit Swap(pool, msg.sender, receiver, tokenIn, amountIn, amountOut, fee);
  }

  /// @inheritdoc IGhoSwapFacility
  function skim(address pool) external nonReentrant returns (uint256) {
    return _skim(pool);
  }

  /// @inheritdoc IGhoSwapFacility
  function repay(address pool, uint256 amount) external nonReentrant returns (uint256) {
    Pool storage p = _getStorage().pools[pool];
    uint256 value = _toGho(p.balance);
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
  ) external restricted nonReentrant returns (uint256 amount) {
    if (to == address(0)) revert ZeroAddress();
    Pool storage p = _getStorage().pools[pool];
    amount = p.balance;
    p.balance = 0;
    p.cap = 0;
    IERC20(ASSET).safeTransfer(to, amount);
    emit PoolCapSet(pool, 0);
    emit PoolSeized(pool, to, amount, p.used);
  }

  /// @inheritdoc IGhoSwapFacility
  function makePublic(address pool) external restricted nonReentrant {
    if (pool == PUBLIC_POOL) revert NotPrivatePool();
    GhoSwapFacilityStorage storage $ = _getStorage();
    Pool storage priv = $.pools[pool];
    Pool storage pub = $.pools[PUBLIC_POOL];
    _skim(pool);
    _skim(PUBLIC_POOL);

    Pool memory moved = priv;
    delete $.pools[pool];
    pub.balance += moved.balance;
    pub.used += moved.used;
    pub.cap += moved.cap;

    emit PoolMadePublic(pool, moved.balance, moved.used, moved.cap);
    emit PoolCapSet(pool, 0);
    emit PoolCapSet(PUBLIC_POOL, pub.cap);
  }

  /// @inheritdoc IGhoSwapFacility
  function setPoolCap(address pool, uint128 cap) external restricted {
    _getStorage().pools[pool].cap = cap;
    emit PoolCapSet(pool, cap);
  }

  /// @inheritdoc IGhoSwapFacility
  function setPoolFees(address pool, uint16 assetInBps, uint16 ghoInBps) external restricted {
    if (assetInBps > BPS) revert InvalidFee(assetInBps);
    if (ghoInBps > BPS) revert InvalidFee(ghoInBps);
    Pool storage p = _getStorage().pools[pool];
    p.assetInBps = assetInBps;
    p.ghoInBps = ghoInBps;
    emit PoolFeesSet(pool, assetInBps, ghoInBps);
  }

  /// @inheritdoc IGhoSwapFacility
  function setTreasury(address treasury_) external restricted {
    _setTreasury(treasury_);
  }

  /// @inheritdoc IGhoSwapFacility
  function setPaused(bool paused_) external restricted {
    _getStorage().paused = paused_;
    emit PausedSet(paused_);
  }

  /// @inheritdoc IGhoSwapFacility
  function paused() external view returns (bool) {
    return _getStorage().paused;
  }

  /// @inheritdoc IGhoSwapFacility
  function quote(
    address account,
    address tokenIn,
    uint256 amountIn
  ) external view returns (uint256 amountOut, uint256 fee) {
    Pool storage p = _getStorage().pools[poolOf(account)];
    if (tokenIn == ASSET) {
      (amountOut, fee, ) = _quoteAssetIn(p.assetInBps, amountIn);
    } else if (tokenIn == GHO) {
      (amountOut, fee, ) = _quoteGhoIn(p.ghoInBps, amountIn);
    } else {
      revert InvalidToken(tokenIn);
    }
  }

  /// @inheritdoc IGhoSwapFacility
  function poolOf(address account) public view returns (address) {
    return _getStorage().pools[account].cap != 0 ? account : PUBLIC_POOL;
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
    return SafeCast.toInt256(_toGho(p.balance)) - SafeCast.toInt256(p.used);
  }

  /// @dev Sends the asset above what backs `p.used` to the treasury. Rounds in favor of the pool.
  function _skim(address pool) internal returns (uint256 excess) {
    GhoSwapFacilityStorage storage $ = _getStorage();
    Pool storage p = $.pools[pool];
    uint256 keep = _backing(p.used);
    if (p.balance <= keep) return 0;
    excess = p.balance - keep;
    p.balance = keep.toUint128();
    IERC20(ASSET).safeTransfer($.treasury, excess);
    emit Skimmed(pool, excess);
  }

  /// @return amountOut GHO sent out.
  /// @return fee GHO fee.
  /// @return gross GHO drawn from the reserve (amountOut + fee).
  function _quoteAssetIn(
    uint256 feeBps,
    uint256 amount
  ) internal view returns (uint256 amountOut, uint256 fee, uint256 gross) {
    gross = _toGho(amount);
    fee = Math.mulDiv(gross, feeBps, BPS, Math.Rounding.Ceil);
    amountOut = gross - fee;
  }

  /// @return amountOut Asset sent out.
  /// @return fee GHO fee.
  /// @return net GHO restored to the reserve (amountIn - fee).
  function _quoteGhoIn(
    uint256 feeBps,
    uint256 ghoIn
  ) internal view returns (uint256 amountOut, uint256 fee, uint256 net) {
    fee = Math.mulDiv(ghoIn, feeBps, BPS, Math.Rounding.Ceil);
    net = ghoIn - fee;
    amountOut = _fromGho(net);
  }

  /// @dev Decimals of the unit the asset is priced in. Called once, from the constructor.
  function _pricingDecimals(address asset) internal view virtual returns (uint8) {
    return IERC20Metadata(asset).decimals();
  }

  /// @dev GHO value of `amount` of asset, rounded down.
  function _toGho(uint256 amount) internal view virtual returns (uint256) {
    return amount * SCALE;
  }

  /// @dev Asset bought by `ghoAmount` GHO, rounded down.
  function _fromGho(uint256 ghoAmount) internal view virtual returns (uint256) {
    return ghoAmount / SCALE;
  }

  /// @dev Asset needed to back `ghoAmount` GHO, rounded up.
  function _backing(uint256 ghoAmount) internal view virtual returns (uint256) {
    return Math.ceilDiv(ghoAmount, SCALE);
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
