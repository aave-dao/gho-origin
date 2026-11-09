// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Gsm} from 'src/contracts/facilitators/gsm/Gsm.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

/**
 * @title PermissionedGsm
 * @author Aave
 * @notice GHO Stability Module with access restrictions on buy/sell facilities between GHO and the
 * underlying asset
 * @dev A user's authorization to buy/sell can be verified using `AccessControl` `hasRole` function, with the corresponding `BUY_ASSET_ROLE` and `SELL_ASSET_ROLE` roles
 * @dev To be covered by a proxy contract.
 */
contract PermissionedGsm is Gsm, IPermissionedGsm {
  /// @inheritdoc IPermissionedGsm
  bytes32 public constant BUY_ASSET_ROLE = keccak256('BUY_ASSET_ROLE');

  /// @inheritdoc IPermissionedGsm
  bytes32 public constant SELL_ASSET_ROLE = keccak256('SELL_ASSET_ROLE');

  /// @inheritdoc IPermissionedGsm
  bytes32 public constant SWAP_ACCESS_MANAGER_ROLE = keccak256('SWAP_ACCESS_MANAGER_ROLE');

  bool internal _isBuyAccessOpen;
  bool internal _isSellAccessOpen;

  /**
   * @dev Constructor
   * @dev Buys and sells are role restricted by default
   * @param ghoToken The address of the GHO token contract
   * @param underlyingAsset The address of the collateral asset
   * @param priceStrategy The address of the price strategy
   */
  constructor(
    address ghoToken,
    address underlyingAsset,
    address priceStrategy
  ) Gsm(ghoToken, underlyingAsset, priceStrategy) {
    // Intentionally left blank
  }

  /**
   * @notice GSM initializer
   * @dev The `SWAP_ACCESS_MANAGER_ROLE` administers the `BUY_ASSET_ROLE` and `SELL_ASSET_ROLE`
   * @param admin The address of the default admin role
   * @param ghoTreasury The address of the GHO treasury
   * @param exposureCap Maximum amount of user-supplied underlying asset in GSM
   * @param ghoReserve The address of the GHO reserve to use tokens from
   */
  function initialize(
    address admin,
    address ghoTreasury,
    uint128 exposureCap,
    address ghoReserve
  ) public override {
    super.initialize(admin, ghoTreasury, exposureCap, ghoReserve);
    _setRoleAdmin(BUY_ASSET_ROLE, SWAP_ACCESS_MANAGER_ROLE);
    _setRoleAdmin(SELL_ASSET_ROLE, SWAP_ACCESS_MANAGER_ROLE);
  }

  /// @inheritdoc IPermissionedGsm
  function setBuyAccessOpen(bool open) external onlyRole(SWAP_ACCESS_MANAGER_ROLE) {
    require(open != _isBuyAccessOpen, 'GSM_NO_CHANGE_IN_BUY_ACCESS');
    _isBuyAccessOpen = open;
    emit BuyAccessOpenUpdated(msg.sender, open);
  }

  /// @inheritdoc IPermissionedGsm
  function setSellAccessOpen(bool open) external onlyRole(SWAP_ACCESS_MANAGER_ROLE) {
    require(open != _isSellAccessOpen, 'GSM_NO_CHANGE_IN_SELL_ACCESS');
    _isSellAccessOpen = open;
    emit SellAccessOpenUpdated(msg.sender, open);
  }

  /// @inheritdoc IPermissionedGsm
  function getIsBuyAccessOpen() external view returns (bool) {
    return _isBuyAccessOpen;
  }

  /// @inheritdoc IPermissionedGsm
  function getIsSellAccessOpen() external view returns (bool) {
    return _isSellAccessOpen;
  }

  /// @inheritdoc Gsm
  function _buyAsset(
    address originator,
    uint256 minAmount,
    address receiver
  ) internal override returns (uint256, uint256) {
    if (!_isBuyAccessOpen) {
      _checkRole(BUY_ASSET_ROLE, originator);
    }
    return super._buyAsset(originator, minAmount, receiver);
  }

  /// @inheritdoc Gsm
  function _sellAsset(
    address originator,
    uint256 maxAmount,
    address receiver
  ) internal override returns (uint256, uint256) {
    if (!_isSellAccessOpen) {
      _checkRole(SELL_ASSET_ROLE, originator);
    }
    return super._sellAsset(originator, maxAmount, receiver);
  }
}
