// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Gsm} from 'src/contracts/facilitators/gsm/Gsm.sol';
import {Gsm4626} from 'src/contracts/facilitators/gsm/Gsm4626.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

/**
 * @title PermissionedGsm4626
 * @author Aave
 * @notice GHO Stability Module for ERC4626 vault shares with access restrictions on buy/sell
 * facilities between GHO and the ERC4626 vault shares
 * @dev To be covered by a proxy contract.
 */
contract PermissionedGsm4626 is Gsm4626, IPermissionedGsm {
  /// @inheritdoc IPermissionedGsm
  bytes32 public constant BUY_ASSET_ROLE = keccak256('BUY_ASSET_ROLE');

  /// @inheritdoc IPermissionedGsm
  bytes32 public constant SELL_ASSET_ROLE = keccak256('SELL_ASSET_ROLE');

  bool internal _isBuyPermissionless;
  bool internal _isSellPermissionless;

  /**
   * @dev Constructor
   * @dev Buys and sells are role restricted by default
   * @param ghoToken The address of the GHO token contract
   * @param underlyingAsset The address of the ERC4626 vault
   * @param priceStrategy The address of the price strategy
   */
  constructor(
    address ghoToken,
    address underlyingAsset,
    address priceStrategy
  ) Gsm4626(ghoToken, underlyingAsset, priceStrategy) {
    // Intentionally left blank
  }

  /// @inheritdoc IPermissionedGsm
  function setBuyPermissionless(bool enable) external onlyRole(CONFIGURATOR_ROLE) {
    if (enable) {
      require(!_isBuyPermissionless, 'GSM_BUY_ALREADY_PERMISSIONLESS');
    } else {
      require(_isBuyPermissionless, 'GSM_BUY_ALREADY_PERMISSIONED');
    }
    _isBuyPermissionless = enable;
    emit BuyPermissionlessUpdated(msg.sender, enable);
  }

  /// @inheritdoc IPermissionedGsm
  function setSellPermissionless(bool enable) external onlyRole(CONFIGURATOR_ROLE) {
    if (enable) {
      require(!_isSellPermissionless, 'GSM_SELL_ALREADY_PERMISSIONLESS');
    } else {
      require(_isSellPermissionless, 'GSM_SELL_ALREADY_PERMISSIONED');
    }
    _isSellPermissionless = enable;
    emit SellPermissionlessUpdated(msg.sender, enable);
  }

  /// @inheritdoc IPermissionedGsm
  function getIsBuyPermissionless() external view returns (bool) {
    return _isBuyPermissionless;
  }

  /// @inheritdoc IPermissionedGsm
  function getIsSellPermissionless() external view returns (bool) {
    return _isSellPermissionless;
  }

  /// @inheritdoc Gsm
  function _buyAsset(
    address originator,
    uint256 minAmount,
    address receiver
  ) internal override returns (uint256, uint256) {
    if (!_isBuyPermissionless) {
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
    if (!_isSellPermissionless) {
      _checkRole(SELL_ASSET_ROLE, originator);
    }
    return super._sellAsset(originator, maxAmount, receiver);
  }
}
