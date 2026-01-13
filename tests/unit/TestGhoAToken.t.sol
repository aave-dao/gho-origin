// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';
import {IInitializableAToken} from 'aave-v3-origin/contracts/interfaces/IInitializableAToken.sol';
import {TransparentUpgradeableProxy} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract TestGhoAToken is TestGhoBase {
  function testConstructor() public {
    GhoAToken aToken = new GhoAToken(IPool(address(POOL)), address(0));
    assertEq(aToken.name(), 'GHO_ATOKEN_IMPL', 'Wrong default ERC20 name');
    assertEq(aToken.symbol(), 'GHO_ATOKEN_IMPL', 'Wrong default ERC20 symbol');
    assertEq(aToken.decimals(), 0, 'Wrong default ERC20 decimals');
  }

  function testInitialize() public {
    address proxyAdmin = makeAddr('PROXY_ADMIN');
    GhoAToken aTokenImpl = new GhoAToken(IPool(address(POOL)), address(0));
    string memory tokenName = 'Aave GHO';
    string memory tokenSymbol = 'aGHO';
    bytes memory empty;

    TransparentUpgradeableProxy aTokenProxy = new TransparentUpgradeableProxy(
      address(aTokenImpl),
      proxyAdmin,
      abi.encodeWithSelector(
        IInitializableAToken.initialize.selector,
        IPool(address(POOL)),
        address(GHO_TOKEN),
        uint8(18),
        tokenName,
        tokenSymbol,
        empty
      )
    );
    GhoAToken aToken = GhoAToken(address(aTokenProxy));

    assertEq(aToken.name(), tokenName, 'Wrong initialized name');
    assertEq(aToken.symbol(), tokenSymbol, 'Wrong initialized symbol');
    assertEq(aToken.decimals(), 18, 'Wrong ERC20 decimals');
  }

  function testInitializePoolRevert() public {
    address proxyAdmin = makeAddr('PROXY_ADMIN');
    string memory tokenName = 'Aave GHO';
    string memory tokenSymbol = 'aGHO';
    bytes memory empty;

    GhoAToken aTokenImpl = new GhoAToken(IPool(address(POOL)), address(0));

    vm.expectRevert(Errors.PoolAddressesDoNotMatch.selector);
    new TransparentUpgradeableProxy(
      address(aTokenImpl),
      proxyAdmin,
      abi.encodeWithSelector(
        IInitializableAToken.initialize.selector,
        IPool(address(0)), // Wrong pool - should revert
        address(GHO_TOKEN),
        uint8(18),
        tokenName,
        tokenSymbol,
        empty
      )
    );
  }

  function testReInitRevert() public {
    string memory tokenName = 'Aave GHO';
    string memory tokenSymbol = 'aGHO';
    bytes memory empty;

    vm.expectRevert(bytes('Contract instance has already been initialized'));
    GHO_ATOKEN.initialize(
      IPool(address(POOL)),
      address(GHO_TOKEN),
      18,
      tokenName,
      tokenSymbol,
      empty
    );
  }

  function testUnderlying() public view {
    assertEq(
      GHO_ATOKEN.UNDERLYING_ASSET_ADDRESS(),
      address(GHO_TOKEN),
      'Underlying should match token'
    );
  }

  function testGetVariableDebtToken() public view {
    assertEq(
      GHO_ATOKEN.getVariableDebtToken(),
      address(GHO_DEBT_TOKEN),
      'Variable debt token getter should match Gho Variable Debt Token'
    );
  }

  function testRevision() public view {
    assertEq(GHO_ATOKEN.ATOKEN_REVISION(), 1, 'Gho aToken revision should be 1');
  }

  function testUnauthorizedMint() public {
    vm.startPrank(ALICE);
    vm.expectRevert(Errors.CallerMustBePool.selector);
    GHO_ATOKEN.mint(ALICE, ALICE, 0, 0);
  }

  function testUnauthorizedBurn() public {
    vm.startPrank(ALICE);

    vm.expectRevert(Errors.CallerMustBePool.selector);
    GHO_ATOKEN.burn(ALICE, ALICE, 0, 0, 0);
  }

  function testUnauthorizedMintToTreasury() public {
    vm.startPrank(ALICE);

    vm.expectRevert(Errors.CallerMustBePool.selector);
    GHO_ATOKEN.mintToTreasury(0, 0);
  }

  function testUnauthorizedTransferOnLiquidation() public {
    vm.startPrank(ALICE);

    vm.expectRevert(Errors.CallerMustBePool.selector);
    GHO_ATOKEN.transferOnLiquidation(ALICE, ALICE, 0, 0, 0);
  }

  function testUnauthorizedTransferUnderlyingTo() public {
    vm.startPrank(ALICE);

    vm.expectRevert(Errors.CallerMustBePool.selector);
    GHO_ATOKEN.transferUnderlyingTo(ALICE, 0);
  }

  function testUnauthorizedHandleRepayment() public {
    vm.startPrank(ALICE);

    vm.expectRevert(bytes('CALLER_NOT_POOL_OR_DEBT_TOKEN'));
    GHO_ATOKEN.handleRepayment(ALICE, ALICE, 0);
  }

  function testUnauthorizedRescueTokens() public {
    GhoAToken aToken = new GhoAToken(IPool(address(POOL)), address(0));

    vm.startPrank(ALICE);
    ACL_MANAGER.setState(false);

    vm.expectRevert(Errors.CallerNotPoolAdmin.selector);
    aToken.rescueTokens(address(GHO_TOKEN), ALICE, 0);
  }

  function testUnauthorizedSetVariableDebtToken() public {
    GhoAToken aToken = new GhoAToken(IPool(address(POOL)), address(0));

    vm.startPrank(ALICE);
    ACL_MANAGER.setState(false);

    vm.expectRevert(Errors.CallerNotPoolAdmin.selector);
    aToken.setVariableDebtToken(ALICE);
  }

  function testSetVariableDebtToken() public {
    GhoAToken aToken = new GhoAToken(IPool(address(POOL)), address(0));

    vm.expectEmit(address(aToken));
    emit VariableDebtTokenSet(address(GHO_DEBT_TOKEN));

    aToken.setVariableDebtToken(address(GHO_DEBT_TOKEN));
  }

  function testUpdateVariableDebtToken() public {
    vm.startPrank(ALICE);
    vm.expectRevert(bytes('VARIABLE_DEBT_TOKEN_ALREADY_SET'));
    GHO_ATOKEN.setVariableDebtToken(ALICE);
  }

  function testZeroVariableDebtToken() public {
    GhoAToken aToken = new GhoAToken(IPool(address(POOL)), address(0));

    vm.startPrank(ALICE);
    vm.expectRevert(bytes('ZERO_ADDRESS_NOT_VALID'));
    aToken.setVariableDebtToken(address(0));
  }

  function testMintRevert() public {
    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(address(POOL));
    GHO_ATOKEN.mint(CHARLES, CHARLES, 1, 1);
  }

  function testPermitRevert() public {
    bytes32 empty;

    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(address(POOL));
    GHO_ATOKEN.permit(CHARLES, CHARLES, 1, 1, 1, empty, empty);
  }

  function testBurnRevert() public {
    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(address(POOL));
    GHO_ATOKEN.burn(CHARLES, CHARLES, 1, 1, 1);
  }

  function testMintToTreasuryRevert() public {
    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(address(POOL));
    GHO_ATOKEN.mintToTreasury(1, 1);
  }

  function testTransferOnLiquidationRevert() public {
    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(address(POOL));
    GHO_ATOKEN.transferOnLiquidation(CHARLES, CHARLES, 1, 1, 1);
  }

  function testStandardTransferRevert() public {
    vm.expectRevert(Errors.OperationNotSupported.selector);
    vm.prank(CHARLES);
    GHO_ATOKEN.transfer(ALICE, 0);
  }

  function testBalanceOfAlwaysZero() public view {
    uint256 balance = GHO_ATOKEN.balanceOf(CHARLES);
    assertEq(balance, 0, 'AToken balance should always be zero');
  }

  function testTotalSupplyReturnsBucketCapacity() public view {
    uint256 supply = GHO_ATOKEN.totalSupply();
    (uint256 bucketCapacity, ) = GHO_TOKEN.getFacilitatorBucket(address(GHO_ATOKEN));
    assertEq(supply, bucketCapacity, 'AToken total supply should equal bucket capacity');
  }

  function testReserveTreasuryAddress() public view {
    assertEq(
      GHO_ATOKEN.RESERVE_TREASURY_ADDRESS(),
      TREASURY,
      'AToken treasury address should match the initialized address'
    );

    assertEq(
      GHO_ATOKEN.getGhoTreasury(),
      TREASURY,
      'AToken gho treasury address should match the getter'
    );
  }

  function testDistributeFees() public {
    borrowAction(CHARLES, 1000e18);
    vm.warp(block.timestamp + 640000);

    ghoFaucet(CHARLES, 5e18);

    repayAction(CHARLES, GHO_DEBT_TOKEN.balanceOf(CHARLES));

    vm.expectEmit(address(GHO_ATOKEN));
    emit FeesDistributedToTreasury(
      TREASURY,
      address(GHO_TOKEN),
      GHO_TOKEN.balanceOf(address(GHO_ATOKEN))
    );
    GHO_ATOKEN.distributeFeesToTreasury();
  }

  function testRescueToken() public {
    vm.prank(FAUCET);
    AAVE_TOKEN.mint(address(GHO_ATOKEN), 1);

    GHO_ATOKEN.rescueTokens(address(AAVE_TOKEN), CHARLES, 1);

    assertEq(AAVE_TOKEN.balanceOf(CHARLES), 1, 'Token rescue should transfer 1 wei');
  }

  function testRescueTokenRevertIfUnderlying() public {
    vm.expectRevert(Errors.UnderlyingCannotBeRescued.selector);
    vm.prank(FAUCET);
    GHO_ATOKEN.rescueTokens(address(GHO_TOKEN), CHARLES, 1);
  }

  function testUpdateGhoTreasuryRevertIfZero() public {
    vm.expectRevert(bytes('ZERO_ADDRESS_NOT_VALID'));
    GHO_ATOKEN.updateGhoTreasury(address(0));
  }

  function testUpdateGhoTreasury() public {
    vm.expectEmit(address(GHO_ATOKEN));
    emit GhoTreasuryUpdated(TREASURY, ALICE);
    GHO_ATOKEN.updateGhoTreasury(ALICE);

    assertEq(GHO_ATOKEN.getGhoTreasury(), ALICE);
  }

  function testUnauthorizedUpdateGhoTreasuryRevert() public {
    ACL_MANAGER.setState(false);

    vm.prank(ALICE);

    vm.expectRevert(Errors.CallerNotPoolAdmin.selector);
    GHO_ATOKEN.updateGhoTreasury(ALICE);
  }

  function testDomainSeparator() public view {
    bytes32 EIP712_DOMAIN = keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
    bytes memory EIP712_REVISION = bytes('1');
    bytes32 expected = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        keccak256(bytes(GHO_ATOKEN.name())),
        keccak256(EIP712_REVISION),
        block.chainid,
        address(GHO_ATOKEN)
      )
    );
    bytes32 result = GHO_ATOKEN.DOMAIN_SEPARATOR();
    assertEq(result, expected, 'Unexpected domain separator');
  }

  function testNonces() public view {
    assertEq(GHO_ATOKEN.nonces(ALICE), 0, 'Unexpected non-zero nonce');
    assertEq(GHO_ATOKEN.nonces(BOB), 0, 'Unexpected non-zero nonce');
    assertEq(GHO_ATOKEN.nonces(CHARLES), 0, 'Unexpected non-zero nonce');
  }
}
