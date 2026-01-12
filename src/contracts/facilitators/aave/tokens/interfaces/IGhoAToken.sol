// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAToken} from 'aave-v3-origin/contracts/interfaces/IAToken.sol';
import {IGhoFacilitator} from 'src/contracts/gho/interfaces/IGhoFacilitator.sol';

/**
 * @title IGhoAToken
 * @author Aave
 * @notice Defines the basic interface of the GhoAToken
 */
interface IGhoAToken is IAToken, IGhoFacilitator {
  /**
   * @dev Emitted when variable debt contract is set
   * @param variableDebtToken The address of the GhoVariableDebtToken contract
   */
  event VariableDebtTokenSet(address indexed variableDebtToken);

  /**
   * @notice Sets a reference to the GHO variable debt token
   * @param ghoVariableDebtToken The address of the GhoVariableDebtToken contract
   */
  function setVariableDebtToken(address ghoVariableDebtToken) external;

  /**
   * @notice Returns the address of the GHO variable debt token
   * @return The address of the GhoVariableDebtToken contract
   */
  function getVariableDebtToken() external view returns (address);

  /**
   * @notice Handles repayment of GHO debt
   * @dev Called by the GhoVariableDebtToken during burn (repay) to properly handle the interest vs principal
   * @param caller The address of the repayer
   * @param onBehalfOf The address of the user who's debt is being repaid
   * @param amount The amount being repaid
   */
  function handleRepayment(address caller, address onBehalfOf, uint256 amount) external;
}
