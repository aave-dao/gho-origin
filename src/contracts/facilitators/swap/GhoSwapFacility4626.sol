// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {GhoSwapFacility} from 'src/contracts/facilitators/swap/GhoSwapFacility.sol';

/// @title GhoSwapFacility4626
/// @author Aave Labs
/// @notice Swaps GHO against the shares of an ERC4626 vault, whose underlying asset is worth one GHO
/// per unit (decimals adjusted).
/// @dev `ASSET` is the vault share token. Shares are valued with `convertToAssets`, so vault yield
/// shows up as pool surplus and is skimmed to the treasury as shares. Storage is the base contract's
/// namespaced struct; this contract adds no state.
contract GhoSwapFacility4626 is GhoSwapFacility {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address gho, address vault, address reserve) GhoSwapFacility(gho, vault, reserve) {}

  /// @dev Prices in the vault's underlying asset.
  function _pricingDecimals(address vault) internal view override returns (uint8) {
    return IERC20Metadata(IERC4626(vault).asset()).decimals();
  }

  function _toGho(uint256 shares) internal view override returns (uint256) {
    return IERC4626(ASSET).convertToAssets(shares) * SCALE;
  }

  function _fromGho(uint256 ghoAmount) internal view override returns (uint256) {
    return IERC4626(ASSET).convertToShares(ghoAmount / SCALE);
  }

  /// @dev `previewWithdraw` rounds up, so the pool always keeps enough shares.
  function _backing(uint256 ghoAmount) internal view override returns (uint256) {
    return IERC4626(ASSET).previewWithdraw(Math.ceilDiv(ghoAmount, SCALE));
  }
}
