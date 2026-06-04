// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Strings} from 'openzeppelin-contracts/contracts/utils/Strings.sol';

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

  function test_coverage_ignore() public {
    // Intentionally left blank.
    // Excludes contract from coverage.
  }
}
