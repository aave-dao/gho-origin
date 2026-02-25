// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from 'forge-std/Test.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';
import {GhoOrchestration} from 'src/deployments/projects/aave-v3-gho-facilitator/GhoOrchestration.sol';
import {GhoReportTypes} from 'src/deployments/types/GhoReportTypes.sol';

contract TestGhoDeployment is Test {
  address internal ghoAdmin;
  address internal treasury;
  address internal poolAddressesProvider;
  GhoReportTypes.GhoReport internal ghoReport;

  uint256 public constant FLASH_MINTER_FEE = 100;

  function setUp() public {
    ghoAdmin = makeAddr('ghoAdmin');
    treasury = makeAddr('treasury');
    poolAddressesProvider = makeAddr('poolAddressesProvider');
    address aclManager = makeAddr('aclManager');

    vm.mockCall(
      poolAddressesProvider,
      abi.encodeWithSignature('getACLManager()'),
      abi.encode(aclManager)
    );

    ghoReport = _deployGhoTestnet({
      deployer: ghoAdmin,
      flashMinterFee: FLASH_MINTER_FEE,
      treasury_: treasury,
      poolAddressesProvider_: poolAddressesProvider
    });
  }

  function test_GhoDeployment() public view {
    assertNotEq(ghoReport.ghoTokenReport.ghoToken, address(0), 'ghoToken');
    assertNotEq(ghoReport.ghoTokenReport.upgradeableGhoToken, address(0), 'upgradeableGhoToken');
    assertNotEq(ghoReport.ghoTokenReport.ghoOracle, address(0), 'ghoOracle');
    assertNotEq(ghoReport.ghoFlashMinterReport.ghoFlashMinter, address(0), 'ghoFlashMinter');

    GhoFlashMinter ghoFlashMinter = GhoFlashMinter(ghoReport.ghoFlashMinterReport.ghoFlashMinter);
    assertEq(
      address(ghoFlashMinter.GHO_TOKEN()),
      ghoReport.ghoTokenReport.ghoToken,
      'GHO_TOKEN in FlashMinter does not match ghoToken address'
    );
    assertEq(ghoFlashMinter.getFee(), FLASH_MINTER_FEE, 'Unexpected Fee in FlashMinter');
    assertEq(
      ghoFlashMinter.getGhoTreasury(),
      treasury,
      'Treasury in FlashMinter does not match treasury address'
    );
    assertEq(
      address(ghoFlashMinter.ADDRESSES_PROVIDER()),
      poolAddressesProvider,
      'ADDRESSES_PROVIDER in FlashMinter does not match poolAddressesProvider address'
    );
  }

  function _deployGhoTestnet(
    address deployer,
    uint256 flashMinterFee,
    address treasury_,
    address poolAddressesProvider_
  ) internal returns (GhoReportTypes.GhoReport memory ghoReport_) {
    vm.startPrank(deployer);
    ghoReport_ = GhoOrchestration.deployGho(
      deployer,
      flashMinterFee,
      treasury_,
      poolAddressesProvider_
    );
    vm.stopPrank();
  }
}
