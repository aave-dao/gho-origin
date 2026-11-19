// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';

/**
 * @title MockReentrantGsm
 * @notice Minimal GSM stub that re-enters the router mid-swap.
 */
contract MockReentrantGsm {
  address public immutable GHO_TOKEN;
  address public immutable UNDERLYING_ASSET;
  IGhoRouter public immutable ROUTER;

  constructor(address gho, address underlying, address router) {
    GHO_TOKEN = gho;
    UNDERLYING_ASSET = underlying;
    ROUTER = IGhoRouter(router);
  }

  /// @dev Sell path (token -> GHO): re-enters the router while it is mid-swap.
  function sellAsset(uint256, address) external returns (uint256, uint256) {
    _reenter();
    return (0, 0);
  }

  /// @dev Buy path (GHO -> token): re-enters the router while it is mid-swap.
  function buyAsset(uint256, address) external returns (uint256, uint256) {
    _reenter();
    return (0, 0);
  }

  function getAssetAmountForBuyAsset(
    uint256 maxGhoAmount
  ) external pure returns (uint256, uint256, uint256, uint256) {
    return (1, maxGhoAmount, 0, 0);
  }

  function _reenter() internal {
    ROUTER.swap(UNDERLYING_ASSET, GHO_TOKEN, address(this), 1, 0, msg.sender, block.timestamp);
  }
}
