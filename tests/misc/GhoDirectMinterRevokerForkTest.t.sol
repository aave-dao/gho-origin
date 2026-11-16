// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from 'forge-std/Test.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';
import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {GhoDirectMinterRevoker} from 'src/contracts/facilitators/gsm/misc/GhoDirectMinterRevoker.sol';
import {IGhoDirectFacilitator} from 'src/contracts/facilitators/gsm/interfaces/IGhoDirectFacilitator.sol';

contract GhoDirectMinterRevokerForkTest is Test {
  bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
  bytes32 internal constant MINTER_ROLE = keccak256('MINTER_ROLE');
  bytes32 internal constant BURNER_ROLE = keccak256('BURNER_ROLE');

  // aave-address-book: GovernanceV3Ethereum.EXECUTOR_LVL_1
  address internal constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;

  // aave-address-book: GhoEthereum.RISK_COUNCIL
  address internal constant RISK_COUNCIL = 0x8513e6F37dBc52De87b166980Fa3F50639694B60;

  // aave-address-book: GhoEthereum.GHO_TOKEN
  IGhoToken internal constant GHO_TOKEN = IGhoToken(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);

  // aave-address-book: GhoEthereum.GHO_DIRECT_FACILITATOR_MAINNET_GSMS
  IGhoDirectFacilitator internal constant FACILITATOR_MAINNET_GSMS =
    IGhoDirectFacilitator(0xE9ac5231fAecb633dA0Fe85Fcb2785b8363427d2);

  // aave-address-book: GhoEthereum.GHO_DIRECT_FACILITATOR_PLASMA_GSMS
  IGhoDirectFacilitator internal constant FACILITATOR_PLASMA_GSMS =
    IGhoDirectFacilitator(0x2bd010Ab5393AB51b601B99C4B33ba148d9466e9);

  address internal constant GUARDIAN = address(0xB0B);
  address internal constant ALICE = address(0x1111);

  GhoDirectMinterRevoker internal revoker;

  function setUp() public {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc);
    revoker = new GhoDirectMinterRevoker(EXECUTOR_LVL_1, GUARDIAN);

    vm.startPrank(EXECUTOR_LVL_1);
    FACILITATOR_MAINNET_GSMS.grantRole(DEFAULT_ADMIN_ROLE, address(revoker));
    FACILITATOR_PLASMA_GSMS.grantRole(DEFAULT_ADMIN_ROLE, address(revoker));
    vm.stopPrank();
  }

  function test_Constructor() public view {
    assertEq(revoker.owner(), EXECUTOR_LVL_1);
    assertEq(revoker.guardian(), GUARDIAN);
  }

  function test_RevertConstructorZeroOwner() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new GhoDirectMinterRevoker(address(0), GUARDIAN);
  }

  function test_ConstructorZeroGuardian() public {
    GhoDirectMinterRevoker noGuardian = new GhoDirectMinterRevoker(EXECUTOR_LVL_1, address(0));
    vm.prank(EXECUTOR_LVL_1);
    FACILITATOR_PLASMA_GSMS.grantRole(DEFAULT_ADMIN_ROLE, address(noGuardian));

    assertEq(noGuardian.owner(), EXECUTOR_LVL_1);
    assertEq(noGuardian.guardian(), address(0));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));

    vm.prank(EXECUTOR_LVL_1);
    noGuardian.revokeMinter(address(FACILITATOR_PLASMA_GSMS), EXECUTOR_LVL_1);

    assertFalse(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
  }

  function test_RevokeMinterByGovernance() public {
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.prank(EXECUTOR_LVL_1);
    revoker.revokeMinter(address(FACILITATOR_PLASMA_GSMS), EXECUTOR_LVL_1);

    assertFalse(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
  }

  function test_RevokeMinterByGuardian() public {
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(BURNER_ROLE, RISK_COUNCIL));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));

    vm.prank(GUARDIAN);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);

    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(BURNER_ROLE, RISK_COUNCIL));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
  }

  function test_RevokeMinterBlocksMint() public {
    (, uint256 levelBefore) = GHO_TOKEN.getFacilitatorBucket(address(FACILITATOR_MAINNET_GSMS));

    // bucket is full on mainnet, so reaching the GHO token proves the role check passed
    vm.expectRevert(bytes('FACILITATOR_BUCKET_CAPACITY_EXCEEDED'));
    vm.prank(RISK_COUNCIL);
    FACILITATOR_MAINNET_GSMS.mint(RISK_COUNCIL, 1 ether);

    vm.prank(GUARDIAN);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);

    // live facilitators use OZ v4 AccessControl string reverts
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account ',
          vm.toLowercase(vm.toString(RISK_COUNCIL)),
          ' is missing role ',
          vm.toString(MINTER_ROLE)
        )
      )
    );
    vm.prank(RISK_COUNCIL);
    FACILITATOR_MAINNET_GSMS.mint(RISK_COUNCIL, 1 ether);

    (, uint256 levelAfter) = GHO_TOKEN.getFacilitatorBucket(address(FACILITATOR_MAINNET_GSMS));
    assertEq(levelAfter, levelBefore);
  }

  function test_RevokeAllLiveMinters() public {
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));

    vm.startPrank(GUARDIAN);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), EXECUTOR_LVL_1);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);
    revoker.revokeMinter(address(FACILITATOR_PLASMA_GSMS), EXECUTOR_LVL_1);
    vm.stopPrank();

    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_PLASMA_GSMS.hasRole(MINTER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(BURNER_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
    assertTrue(FACILITATOR_PLASMA_GSMS.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR_LVL_1));
  }

  function test_RevertRevokeMinterInvalidCaller() public {
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));

    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, ALICE)
    );
    vm.prank(ALICE);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);

    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
  }

  function test_RevertRevokeMinterNotAdmin() public {
    GhoDirectMinterRevoker unauthorized = new GhoDirectMinterRevoker(EXECUTOR_LVL_1, GUARDIAN);

    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(unauthorized)));

    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account ',
          vm.toLowercase(vm.toString(address(unauthorized))),
          ' is missing role ',
          vm.toString(DEFAULT_ADMIN_ROLE)
        )
      )
    );
    vm.prank(GUARDIAN);
    unauthorized.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);

    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(unauthorized)));
  }

  function test_RevertRevokeMinterAfterAdminRevoked() public {
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));

    vm.prank(EXECUTOR_LVL_1);
    FACILITATOR_MAINNET_GSMS.revokeRole(DEFAULT_ADMIN_ROLE, address(revoker));

    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));

    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account ',
          vm.toLowercase(vm.toString(address(revoker))),
          ' is missing role ',
          vm.toString(DEFAULT_ADMIN_ROLE)
        )
      )
    );
    vm.prank(GUARDIAN);
    revoker.revokeMinter(address(FACILITATOR_MAINNET_GSMS), RISK_COUNCIL);

    assertTrue(FACILITATOR_MAINNET_GSMS.hasRole(MINTER_ROLE, RISK_COUNCIL));
    assertFalse(FACILITATOR_MAINNET_GSMS.hasRole(DEFAULT_ADMIN_ROLE, address(revoker)));
  }
}
