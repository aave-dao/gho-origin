// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/access/AccessControl.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {IGhoDirectFacilitator} from 'src/contracts/facilitators/gsm/interfaces/IGhoDirectFacilitator.sol';

/**
 * @title GhoDirectFacilitator
 * @author Aave/TokenLogic
 * @notice Basic facilitator for minting and burning tokens to and from an account, controlled by an access control list.
 */
contract GhoDirectFacilitator is AccessControl, IGhoDirectFacilitator {
  /// @inheritdoc IGhoDirectFacilitator
  bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

  /// @inheritdoc IGhoDirectFacilitator
  bytes32 public constant BURNER_ROLE = keccak256('MINTER_ROLE');

  /// @inheritdoc IGhoDirectFacilitator
  address public immutable GHO_TOKEN;

  /**
   * @dev Constructor
   * @param admin The address of the initial owner
   * @param gho The address of GHO token
   */
  constructor(address admin, address gho) {
    require(admin != address(0), 'ZERO_ADDRESS_NOT_VALID');
    require(gho != address(0), 'ZERO_ADDRESS_NOT_VALID');

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MINTER_ROLE, admin);
    _grantRole(BURNER_ROLE, admin);

    GHO_TOKEN = gho;
  }

  /// @inheritdoc IGhoDirectFacilitator
  function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
    IGhoToken(GHO_TOKEN).mint(account, amount);
  }

  /// @inheritdoc IGhoDirectFacilitator
  function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
    IGhoToken(GHO_TOKEN).burn(amount);
  }
}
