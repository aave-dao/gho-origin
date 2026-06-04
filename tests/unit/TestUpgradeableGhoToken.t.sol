// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ProxyAdmin} from 'openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol';
import './TestGhoBase.t.sol';

contract TestUpgradeableGhoToken is TestGhoBase {
  address internal PROXY_ADMIN_OWNER = makeAddr('PROXY_ADMIN_OWNER');

  UpgradeableGhoToken internal ghoToken;
  address internal ghoTokenImplementation;

  function setUp() public {
    ghoTokenImplementation = _deployUpgradeableGhoTokenImpl();
    ghoToken = UpgradeableGhoToken(
      _deployUpgradeableGhoTokenProxy({
        implementation: ghoTokenImplementation,
        proxyAdminOwner: PROXY_ADMIN_OWNER,
        tokenAdmin: address(this)
      })
    );

    ghoToken.grantRole(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, address(this));
    ghoToken.grantRole(GHO_TOKEN_BUCKET_MANAGER_ROLE, address(this));

    ghoToken.addFacilitator(address(GHO_FLASH_MINTER), 'Flash Minter', DEFAULT_CAPACITY);
    ghoToken.addFacilitator(FAUCET, 'Faucet Facilitator', type(uint128).max);
  }

  function _getProxyAdmin() internal view returns (address) {
    return vm.computeCreateAddress(address(ghoToken), 1);
  }

  function testInit() public {
    UpgradeableGhoToken ghoTokenImple = new UpgradeableGhoToken();
    bytes memory ghoTokenImpleParams = abi.encodeCall(
      UpgradeableGhoToken.initialize,
      (address(this))
    );

    vm.expectEmit(
      true,
      true,
      true,
      true,
      vm.computeCreateAddress(address(this), vm.getNonce(address(this)))
    );
    emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, address(this), address(this));
    TransparentUpgradeableProxy ghoTokenProxy = new TransparentUpgradeableProxy(
      address(ghoTokenImple),
      PROXY_ADMIN_OWNER,
      ghoTokenImpleParams
    );

    assertEq(ghoTokenImple.decimals(), 18, 'Wrong default ERC20 decimals');
    vm.expectRevert('Initializable: contract is already initialized');
    ghoTokenImple.initialize(address(this));

    UpgradeableGhoToken token = UpgradeableGhoToken(address(ghoTokenProxy));

    assertEq(token.name(), 'Gho Token', 'Wrong default ERC20 name');
    assertEq(token.symbol(), 'GHO', 'Wrong default ERC20 symbol');
    assertEq(token.decimals(), 18, 'Wrong default ERC20 decimals');
    assertEq(token.getFacilitatorsList().length, 0, 'Facilitator list not empty');
  }

  function testGetFacilitatorData() public view {
    IGhoToken.Facilitator memory data = ghoToken.getFacilitator(address(GHO_FLASH_MINTER));
    assertEq(data.label, 'Flash Minter', 'Unexpected facilitator label');
    assertEq(data.bucketCapacity, DEFAULT_CAPACITY, 'Unexpected bucket capacity');
    assertEq(data.bucketLevel, 0, 'Unexpected bucket level');
  }

  function testGetNonFacilitatorData() public view {
    IGhoToken.Facilitator memory data = ghoToken.getFacilitator(ALICE);
    assertEq(data.label, '', 'Unexpected facilitator label');
    assertEq(data.bucketCapacity, 0, 'Unexpected bucket capacity');
    assertEq(data.bucketLevel, 0, 'Unexpected bucket level');
  }

  function testGetFacilitatorBucket() public view {
    (uint256 capacity, uint256 level) = ghoToken.getFacilitatorBucket(address(GHO_FLASH_MINTER));
    assertEq(capacity, DEFAULT_CAPACITY, 'Unexpected bucket capacity');
    assertEq(level, 0, 'Unexpected bucket level');
  }

  function testGetNonFacilitatorBucket() public view {
    (uint256 capacity, uint256 level) = ghoToken.getFacilitatorBucket(ALICE);
    assertEq(capacity, 0, 'Unexpected bucket capacity');
    assertEq(level, 0, 'Unexpected bucket level');
  }

  function testGetPopulatedFacilitatorsList() public view {
    address[] memory facilitatorList = ghoToken.getFacilitatorsList();
    assertEq(facilitatorList.length, 2, 'Unexpected number of facilitators');
    assertEq(
      facilitatorList[0],
      address(GHO_FLASH_MINTER),
      'Unexpected address for mock facilitator 1'
    );
    assertEq(facilitatorList[1], FAUCET, 'Unexpected address for mock facilitator 5');
  }

  function testAddFacilitator() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorAdded(ALICE, keccak256(abi.encodePacked('Alice')), DEFAULT_CAPACITY);
    ghoToken.addFacilitator(ALICE, 'Alice', DEFAULT_CAPACITY);
  }

  function testAddFacilitatorWithRole() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IAccessControl.RoleGranted(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, ALICE, address(this));
    ghoToken.grantRole(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, ALICE);
    vm.prank(ALICE);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorAdded(ALICE, keccak256(abi.encodePacked('Alice')), DEFAULT_CAPACITY);
    ghoToken.addFacilitator(ALICE, 'Alice', DEFAULT_CAPACITY);
  }

  function testRevertAddExistingFacilitator() public {
    vm.expectRevert('FACILITATOR_ALREADY_EXISTS');
    ghoToken.addFacilitator(address(GHO_FLASH_MINTER), 'Flash Minter', DEFAULT_CAPACITY);
  }

  function testRevertAddFacilitatorNoLabel() public {
    vm.expectRevert('INVALID_LABEL');
    ghoToken.addFacilitator(ALICE, '', DEFAULT_CAPACITY);
  }

  function testRevertAddFacilitatorNoRole() public {
    vm.expectRevert(
      AccessControlErrorsLib.MISSING_ROLE(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, address(ALICE))
    );
    vm.prank(ALICE);
    ghoToken.addFacilitator(ALICE, 'Alice', DEFAULT_CAPACITY);
  }

  function testRevertSetBucketCapacityNonFacilitator() public {
    vm.expectRevert('FACILITATOR_DOES_NOT_EXIST');
    ghoToken.setFacilitatorBucketCapacity(ALICE, DEFAULT_CAPACITY);
  }

  function testSetNewBucketCapacity() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketCapacityUpdated(address(GHO_FLASH_MINTER), DEFAULT_CAPACITY, 0);
    ghoToken.setFacilitatorBucketCapacity(address(GHO_FLASH_MINTER), 0);
  }

  function testSetNewBucketCapacityAsManager() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IAccessControl.RoleGranted(GHO_TOKEN_BUCKET_MANAGER_ROLE, ALICE, address(this));
    ghoToken.grantRole(GHO_TOKEN_BUCKET_MANAGER_ROLE, ALICE);
    vm.prank(ALICE);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketCapacityUpdated(address(GHO_FLASH_MINTER), DEFAULT_CAPACITY, 0);
    ghoToken.setFacilitatorBucketCapacity(address(GHO_FLASH_MINTER), 0);
  }

  function testRevertSetNewBucketCapacityNoRole() public {
    vm.expectRevert(
      AccessControlErrorsLib.MISSING_ROLE(GHO_TOKEN_BUCKET_MANAGER_ROLE, address(ALICE))
    );
    vm.prank(ALICE);
    ghoToken.setFacilitatorBucketCapacity(address(GHO_FLASH_MINTER), 0);
  }

  function testRevertRemoveNonFacilitator() public {
    vm.expectRevert('FACILITATOR_DOES_NOT_EXIST');
    ghoToken.removeFacilitator(ALICE);
  }

  function testRevertRemoveFacilitatorNonZeroBucket() public {
    vm.prank(FAUCET);
    ghoToken.mint(ALICE, 1);

    vm.expectRevert('FACILITATOR_BUCKET_LEVEL_NOT_ZERO');
    ghoToken.removeFacilitator(FAUCET);
  }

  function testRemoveFacilitator() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorRemoved(address(GHO_FLASH_MINTER));
    ghoToken.removeFacilitator(address(GHO_FLASH_MINTER));
  }

  function testRemoveFacilitatorWithRole() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IAccessControl.RoleGranted(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, ALICE, address(this));
    ghoToken.grantRole(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, ALICE);
    vm.prank(ALICE);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorRemoved(address(GHO_FLASH_MINTER));
    ghoToken.removeFacilitator(address(GHO_FLASH_MINTER));
  }

  function testRevertRemoveFacilitatorNoRole() public {
    vm.expectRevert(
      AccessControlErrorsLib.MISSING_ROLE(GHO_TOKEN_FACILITATOR_MANAGER_ROLE, address(ALICE))
    );
    vm.prank(ALICE);
    ghoToken.removeFacilitator(address(GHO_FLASH_MINTER));
  }

  function testRevertMintBadFacilitator() public {
    vm.prank(ALICE);
    vm.expectRevert('FACILITATOR_BUCKET_CAPACITY_EXCEEDED');
    ghoToken.mint(ALICE, DEFAULT_BORROW_AMOUNT);
  }

  function testRevertMintExceedCapacity() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectRevert('FACILITATOR_BUCKET_CAPACITY_EXCEEDED');
    ghoToken.mint(ALICE, DEFAULT_CAPACITY + 1);
  }

  function testMint() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IERC20.Transfer(address(0), ALICE, DEFAULT_CAPACITY);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketLevelUpdated(address(GHO_FLASH_MINTER), 0, DEFAULT_CAPACITY);
    ghoToken.mint(ALICE, DEFAULT_CAPACITY);
  }

  function testRevertZeroMint() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectRevert('INVALID_MINT_AMOUNT');
    ghoToken.mint(ALICE, 0);
  }

  function testRevertZeroBurn() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectRevert('INVALID_BURN_AMOUNT');
    ghoToken.burn(0);
  }

  function testRevertBurnMoreThanMinted() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketLevelUpdated(address(GHO_FLASH_MINTER), 0, DEFAULT_CAPACITY);
    ghoToken.mint(address(GHO_FLASH_MINTER), DEFAULT_CAPACITY);

    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectRevert(stdError.arithmeticError);
    ghoToken.burn(DEFAULT_CAPACITY + 1);
  }

  function testRevertBurnOthersTokens() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IERC20.Transfer(address(0), ALICE, DEFAULT_CAPACITY);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketLevelUpdated(address(GHO_FLASH_MINTER), 0, DEFAULT_CAPACITY);
    ghoToken.mint(ALICE, DEFAULT_CAPACITY);

    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectRevert(stdError.arithmeticError);
    ghoToken.burn(DEFAULT_CAPACITY);
  }

  function testBurn() public {
    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IERC20.Transfer(address(0), address(GHO_FLASH_MINTER), DEFAULT_CAPACITY);
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketLevelUpdated(address(GHO_FLASH_MINTER), 0, DEFAULT_CAPACITY);
    ghoToken.mint(address(GHO_FLASH_MINTER), DEFAULT_CAPACITY);

    vm.prank(address(GHO_FLASH_MINTER));
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorBucketLevelUpdated(
      address(GHO_FLASH_MINTER),
      DEFAULT_CAPACITY,
      DEFAULT_CAPACITY - DEFAULT_BORROW_AMOUNT
    );
    ghoToken.burn(DEFAULT_BORROW_AMOUNT);
  }

  function testOffboardFacilitator() public {
    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorAdded(ALICE, keccak256(abi.encodePacked('Alice')), DEFAULT_CAPACITY);
    ghoToken.addFacilitator(ALICE, 'Alice', DEFAULT_CAPACITY);

    vm.prank(ALICE);
    ghoToken.mint(ALICE, DEFAULT_CAPACITY / 2);
    (uint256 bucketCapacity, uint256 bucketLevel) = ghoToken.getFacilitatorBucket(ALICE);
    assertEq(bucketCapacity, DEFAULT_CAPACITY, 'Unexpected bucket capacity of facilitator');
    assertEq(bucketLevel, DEFAULT_CAPACITY / 2, 'Unexpected bucket level of facilitator');

    vm.expectRevert('FACILITATOR_BUCKET_LEVEL_NOT_ZERO');
    ghoToken.removeFacilitator(ALICE);

    ghoToken.setFacilitatorBucketCapacity(ALICE, 0);

    vm.prank(ALICE);
    vm.expectRevert('FACILITATOR_BUCKET_CAPACITY_EXCEEDED');
    ghoToken.mint(ALICE, 1);

    vm.prank(ALICE);
    ghoToken.burn(bucketLevel);

    vm.expectEmit(true, true, true, true, address(ghoToken));
    emit IGhoToken.FacilitatorRemoved(address(ALICE));
    ghoToken.removeFacilitator(address(ALICE));
  }

  function testDomainSeparator() public view {
    bytes32 EIP712_DOMAIN = keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
    bytes memory EIP712_REVISION = bytes('1');
    bytes32 expected = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        keccak256(bytes(ghoToken.name())),
        keccak256(EIP712_REVISION),
        block.chainid,
        address(ghoToken)
      )
    );
    bytes32 result = ghoToken.DOMAIN_SEPARATOR();
    assertEq(result, expected, 'Unexpected domain separator');
  }

  function testDomainSeparatorNewChain() public {
    vm.chainId(31338);
    bytes32 EIP712_DOMAIN = keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
    bytes memory EIP712_REVISION = bytes('1');
    bytes32 expected = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        keccak256(bytes(ghoToken.name())),
        keccak256(EIP712_REVISION),
        block.chainid,
        address(ghoToken)
      )
    );
    bytes32 result = ghoToken.DOMAIN_SEPARATOR();
    assertEq(result, expected, 'Unexpected domain separator');
  }

  function testPermitAndVerifyNonce() public {
    (address david, uint256 davidKey) = makeAddrAndKey('david');
    ghoFaucet(david, 1e18);
    bytes32 PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, david, BOB, 1e18, 0, 1 hours));
    bytes32 outerHash = keccak256(
      abi.encodePacked('\x19\x01', ghoToken.DOMAIN_SEPARATOR(), innerHash)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(davidKey, outerHash);
    ghoToken.permit(david, BOB, 1e18, 1 hours, v, r, s);

    assertEq(ghoToken.allowance(david, BOB), 1e18, 'Unexpected allowance');
    assertEq(ghoToken.nonces(david), 1, 'Unexpected nonce');
  }

  function testRevertPermitInvalidSignature() public {
    (, uint256 davidKey) = makeAddrAndKey('david');
    bytes32 PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, ALICE, BOB, 1e18, 0, 1 hours));
    bytes32 outerHash = keccak256(
      abi.encodePacked('\x19\x01', ghoToken.DOMAIN_SEPARATOR(), innerHash)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(davidKey, outerHash);
    vm.expectRevert(bytes('INVALID_SIGNER'));
    ghoToken.permit(ALICE, BOB, 1e18, 1 hours, v, r, s);
  }

  function testRevertPermitInvalidDeadline() public {
    vm.expectRevert(bytes('PERMIT_DEADLINE_EXPIRED'));
    ghoToken.permit(ALICE, BOB, 1e18, block.timestamp - 1, 0, 0, 0);
  }

  function testInitialization() public {
    uint256 version = uint8(uint256(vm.load(address(ghoToken), bytes32(uint256(0)))));
    assertEq(version, 1);
    assertEq(_getProxyAdmin(), getProxyAdminAddress(address(ghoToken)), 'proxy admin is wrong');

    assertEq(
      ghoTokenImplementation,
      getProxyImplementationAddress(address(ghoToken)),
      'proxy implementation is wrong'
    );
    assertEq(
      UpgradeableGhoToken(ghoTokenImplementation).decimals(),
      18,
      'Wrong default ERC20 decimals'
    );
    vm.expectRevert('Initializable: contract is already initialized');
    UpgradeableGhoToken(ghoTokenImplementation).initialize(address(this));

    assertEq(ghoToken.name(), 'Gho Token', 'Wrong default ERC20 name');
    assertEq(ghoToken.symbol(), 'GHO', 'Wrong default ERC20 symbol');
    assertEq(ghoToken.decimals(), 18, 'Wrong default ERC20 decimals');
    assertEq(ghoToken.totalSupply(), 0, 'Wrong total supply');
  }

  function testProxyAdminOwner() public view {
    assertEq(
      ProxyAdmin(_getProxyAdmin()).owner(),
      PROXY_ADMIN_OWNER,
      'Unexpected proxy admin owner'
    );
  }

  function testUpgrade() public {
    MockUpgradeable newImpl = new MockUpgradeable();
    bytes memory mockImpleParams = abi.encodeCall(MockUpgradeable.initialize, ());
    vm.prank(_getProxyAdmin());
    ITransparentUpgradeableProxy(payable(address(ghoToken))).upgradeToAndCall(
      address(newImpl),
      mockImpleParams
    );

    uint256 version = uint8(uint256(vm.load(address(ghoToken), bytes32(uint256(0)))));
    assertEq(version, 2);
  }

  function testRevertUpgradeUnauthorized() public {
    vm.expectRevert();
    ITransparentUpgradeableProxy(payable(address(ghoToken))).upgradeToAndCall(
      address(0),
      bytes('')
    );
  }
}
