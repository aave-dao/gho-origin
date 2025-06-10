pragma solidity ^0.8.0;

/// @notice minimal mock interface for MockStakedToken, adapted from IStakedAaveV3 from aave-stake-v1-5
interface IMockStakedToken {
  /**
   * @dev Allows staking a specified amount of STAKED_TOKEN
   * @param to The address to receiving the shares
   * @param amount The amount of assets to be staked
   */
  function stake(address to, uint256 amount) external;
}
