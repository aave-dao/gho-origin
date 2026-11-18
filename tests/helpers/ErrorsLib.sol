// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Strings} from 'openzeppelin-contracts/contracts/utils/Strings.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

library AccessControlErrorsLib {
  function MISSING_ROLE(bytes32 role, address account) external pure returns (bytes memory) {
    return
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(account),
        ' is missing role ',
        Strings.toHexString(uint256(role), 32)
      );
  }

  function UNAUTHORIZED_ACCOUNT(
    bytes32 role,
    address account
  ) external pure returns (bytes memory) {
    return
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        account,
        role
      );
  }

  function test_coverage_ignore() public {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }
}
