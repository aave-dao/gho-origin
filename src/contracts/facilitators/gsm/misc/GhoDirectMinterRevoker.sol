// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {Ownable2StepWithGuardian} from 'solidity-utils/contracts/access-control/Ownable2StepWithGuardian.sol';
import {IGhoDirectFacilitator} from 'src/contracts/facilitators/gsm/interfaces/IGhoDirectFacilitator.sol';
import {IGhoDirectMinterRevoker} from 'src/contracts/facilitators/gsm/misc/IGhoDirectMinterRevoker.sol';

/**
 * @title GhoDirectMinterRevoker
 * @notice Emergency contract to revoke MINTER_ROLE on any GhoDirectFacilitator.
 * @dev Must hold DEFAULT_ADMIN_ROLE on the target facilitator.
 */
contract GhoDirectMinterRevoker is IGhoDirectMinterRevoker, Ownable2StepWithGuardian {
  constructor(address owner, address guardian) Ownable2StepWithGuardian(owner, guardian) {}

  /// @inheritdoc IGhoDirectMinterRevoker
  function revokeMinter(address facilitator, address account) external onlyOwnerOrGuardian {
    IGhoDirectFacilitator(facilitator).revokeRole(
      IGhoDirectFacilitator(facilitator).MINTER_ROLE(),
      account
    );
  }
}
