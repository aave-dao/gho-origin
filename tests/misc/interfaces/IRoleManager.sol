// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IRoleManager {
  function getAdmin(uint256 role) external view returns (address);

  function getPendingAdmin(uint256 role) external view returns (address);

  function setPendingAdmin(uint256 role, address newPendingAdmin) external;

  function claimRoleAdmin(uint256 role) external;
}
