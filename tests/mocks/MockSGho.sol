// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {Initializable} from 'openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract MockSGho is Initializable, AccessControlUpgradeable {
  /// @custom:storage-location erc7201:gho.storage.sGHO
  struct sGHOStorage {
    uint176 yieldIndex;
    uint64 lastUpdate;
    uint16 targetRate;
    uint160 supplyCap;
    uint96 ratePerSecond;
  }

  // keccak256(abi.encode(uint256(keccak256("gho.storage.sGHO")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant sGHOStorageLocation =
    0xfdf74a24098989caa4d9d232df283137a30d85fb47ad37b31478f919573b9800;

  function _getsGHOStorage() private pure returns (sGHOStorage storage $) {
    assembly {
      $.slot := sGHOStorageLocation
    }
  }

  error RateMustBeLessThanMaxRate();
  event TargetRateUpdated(uint256 newRate);
  event SupplyCapUpdated(uint256 newSupplyCap);

  uint176 private constant RAY = 1e27;
  uint16 public constant MAX_SAFE_RATE = 5000; // Maximum safe annual yield rate in basis points (50%)
  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER'; // Role for managing yield rates and supply caps

  function initialize(address admin) public initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  function setTargetRate(uint16 newRate) public onlyRole(YIELD_MANAGER_ROLE) {
    sGHOStorage storage $ = _getsGHOStorage();

    if (newRate > MAX_SAFE_RATE) {
      revert RateMustBeLessThanMaxRate();
    }

    $.targetRate = newRate;

    uint256 annualRateRay = (uint256(newRate) * RAY) / 10000;
    $.ratePerSecond = uint96(annualRateRay / 365 days);

    emit TargetRateUpdated(newRate);
  }

  function setSupplyCap(uint160 newSupplyCap) public onlyRole(YIELD_MANAGER_ROLE) {
    _getsGHOStorage().supplyCap = newSupplyCap;
    emit SupplyCapUpdated(newSupplyCap);
  }

  function targetRate() public view returns (uint16) {
    return _getsGHOStorage().targetRate;
  }

  function supplyCap() public view returns (uint160) {
    return _getsGHOStorage().supplyCap;
  }

  function ratePerSecond() public view returns (uint96) {
    return _getsGHOStorage().ratePerSecond;
  }
}
