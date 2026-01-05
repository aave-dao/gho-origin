// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGelatoOracleSwapFreezer {
  function performUpkeep(bytes calldata) external;

  function checkUpkeep(bytes calldata) external view returns (bool, bytes memory);
}
