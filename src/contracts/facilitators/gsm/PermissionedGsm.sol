// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Gsm} from 'src/contracts/facilitators/gsm/Gsm.sol';

/**
 * @title PermissionedGsm
 * @author Aave
 * @notice GHO Stability Module restricted to addresses holding the Swapper Role
 * @dev The role is checked against the originator of the request, so that signature-based swaps
 * are gated by the signer and not by the relayer submitting the transaction
 * @dev To be covered by a proxy contract.
 */
contract PermissionedGsm is Gsm {
  /**
   * @notice Returns the identifier of the Swapper Role
   * @return The bytes32 id hash of the Swapper role
   */
  bytes32 public constant SWAPPER_ROLE = keccak256('SWAPPER_ROLE');

  /**
   * @dev Constructor
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

  /// @inheritdoc Gsm
  function _buyAsset(
    address originator,
    uint256 minAmount,
    address receiver
  ) internal override returns (uint256, uint256) {
    _checkRole(SWAPPER_ROLE, originator);
    return super._buyAsset(originator, minAmount, receiver);
  }

  /// @inheritdoc Gsm
  function _sellAsset(
    address originator,
    uint256 maxAmount,
    address receiver
  ) internal override returns (uint256, uint256) {
    _checkRole(SWAPPER_ROLE, originator);
    return super._sellAsset(originator, maxAmount, receiver);
  }
}
