// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/// @notice copied from aave-stk-v1-5 IGhoVariableDebtTokenTransferHook
interface IGhoVariableDebtTokenTransferHook {
  /**
   * @dev updates the discount when discount token is transferred
   * @dev Only callable by discount token
   * @param sender address of sender
   * @param recipient address of recipient
   * @param senderDiscountTokenBalance sender discount token balance
   * @param recipientDiscountTokenBalance recipient discount token balance
   * @param amount amount of discount token being transferred
   **/
  function updateDiscountDistribution(
    address sender,
    address recipient,
    uint256 senderDiscountTokenBalance,
    uint256 recipientDiscountTokenBalance,
    uint256 amount
  ) external;
}
