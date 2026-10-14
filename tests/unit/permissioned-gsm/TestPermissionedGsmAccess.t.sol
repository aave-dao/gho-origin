// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../TestGhoBase.t.sol';

/**
 * @title TestPermissionedGsmAccess
 * @dev Covers the swap gating added by `PermissionedGsm`/`PermissionedGsm4626`, which the
 * inherited GSM suites do not exercise since they grant the Swapper Role to every originator
 */
contract TestPermissionedGsmAccess is TestGhoBase {
  address internal unauthorizedAddr;
  address internal gsmSignerAddr;
  uint256 internal gsmSignerKey;

  function setUp() public {
    unauthorizedAddr = makeAddr('unauthorized');
    (gsmSignerAddr, gsmSignerKey) = makeAddrAndKey('gsmSigner');

    // Fund the unauthorized user so that a missing role is the only reason a swap can fail
    ghoFaucet(unauthorizedAddr, DEFAULT_GSM_GHO_AMOUNT * 2);
    vm.prank(FAUCET);
    USDX_TOKEN.mint(unauthorizedAddr, DEFAULT_GSM_USDX_AMOUNT);
    vm.startPrank(unauthorizedAddr);
    GHO_TOKEN.approve(address(GHO_GSM), type(uint256).max);
    GHO_TOKEN.approve(address(GHO_GSM_4626), type(uint256).max);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);
    vm.stopPrank();

    // Seed the GSM with underlying so that `buyAsset` has something to sell
    vm.prank(FAUCET);
    USDX_TOKEN.mint(ALICE, DEFAULT_GSM_USDX_AMOUNT);
    vm.startPrank(ALICE);
    USDX_TOKEN.approve(address(GHO_GSM), DEFAULT_GSM_USDX_AMOUNT);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
    vm.stopPrank();
  }

  function _isPermissionedGsm() internal pure override returns (bool) {
    return true;
  }

  function _expectMissingSwapperRole(address account) internal {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        account,
        GSM_SWAPPER_ROLE
      )
    );
  }

  function testSwapperRoleIdentifier() public view {
    assertEq(
      PermissionedGsm(address(GHO_GSM)).SWAPPER_ROLE(),
      GSM_SWAPPER_ROLE,
      'Unexpected Swapper Role identifier'
    );
    assertEq(
      PermissionedGsm4626(address(GHO_GSM_4626)).SWAPPER_ROLE(),
      GSM_SWAPPER_ROLE,
      'Unexpected Swapper Role identifier on the 4626 flavour'
    );
  }

  function testRevertBuyAssetUnauthorized() public {
    _expectMissingSwapperRole(unauthorizedAddr);
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAssetUnauthorized() public {
    _expectMissingSwapperRole(unauthorizedAddr);
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertBuyAsset4626Unauthorized() public {
    _expectMissingSwapperRole(unauthorizedAddr);
    vm.prank(unauthorizedAddr);
    GHO_GSM_4626.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAsset4626Unauthorized() public {
    _expectMissingSwapperRole(unauthorizedAddr);
    vm.prank(unauthorizedAddr);
    GHO_GSM_4626.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertBuyAssetWithSigUnauthorizedSigner() public {
    uint256 deadline = block.timestamp + 1 hours;
    (address signer, uint256 signerKey) = makeAddrAndKey('unauthorizedSigner');
    ghoFaucet(signer, DEFAULT_GSM_GHO_AMOUNT * 2);
    vm.prank(signer);
    GHO_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    bytes32 digest = _getBuyAssetTypedDataHash(
      address(GHO_GSM),
      EIP712Types.BuyAssetWithSig({
        originator: signer,
        minAmount: DEFAULT_GSM_USDX_AMOUNT,
        receiver: signer,
        nonce: GHO_GSM.nonces(signer),
        deadline: deadline
      })
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

    // Relayed by an address that does hold the role: the signer is the one being gated
    _expectMissingSwapperRole(signer);
    vm.prank(ALICE);
    GHO_GSM.buyAssetWithSig(
      signer,
      DEFAULT_GSM_USDX_AMOUNT,
      signer,
      deadline,
      abi.encodePacked(r, s, v)
    );
  }

  function testRevertSellAssetWithSigUnauthorizedSigner() public {
    uint256 deadline = block.timestamp + 1 hours;
    (address signer, uint256 signerKey) = makeAddrAndKey('unauthorizedSigner');
    vm.prank(FAUCET);
    USDX_TOKEN.mint(signer, DEFAULT_GSM_USDX_AMOUNT);
    vm.prank(signer);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    bytes32 digest = _getSellAssetTypedDataHash(
      address(GHO_GSM),
      EIP712Types.SellAssetWithSig({
        originator: signer,
        maxAmount: DEFAULT_GSM_USDX_AMOUNT,
        receiver: signer,
        nonce: GHO_GSM.nonces(signer),
        deadline: deadline
      })
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

    _expectMissingSwapperRole(signer);
    vm.prank(ALICE);
    GHO_GSM.sellAssetWithSig(
      signer,
      DEFAULT_GSM_USDX_AMOUNT,
      signer,
      deadline,
      abi.encodePacked(r, s, v)
    );
  }

  function testSellAssetWithSigAuthorizedSignerUnauthorizedRelayer() public {
    uint256 deadline = block.timestamp + 1 hours;
    vm.prank(FAUCET);
    USDX_TOKEN.mint(gsmSignerAddr, DEFAULT_GSM_USDX_AMOUNT);
    vm.prank(gsmSignerAddr);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    bytes32 digest = _getSellAssetTypedDataHash(
      address(GHO_GSM),
      EIP712Types.SellAssetWithSig({
        originator: gsmSignerAddr,
        maxAmount: DEFAULT_GSM_USDX_AMOUNT,
        receiver: gsmSignerAddr,
        nonce: GHO_GSM.nonces(gsmSignerAddr),
        deadline: deadline
      })
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(gsmSignerKey, digest);

    assertFalse(
      GHO_GSM.hasRole(GSM_SWAPPER_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the Swapper Role'
    );

    // The relayer holds no role, but the signed originator does
    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, ) = GHO_GSM.sellAssetWithSig(
      gsmSignerAddr,
      DEFAULT_GSM_USDX_AMOUNT,
      gsmSignerAddr,
      deadline,
      abi.encodePacked(r, s, v)
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
  }

  function testSwapAfterRoleGranted() public {
    GHO_GSM.grantRole(GSM_SWAPPER_ROLE, unauthorizedAddr);

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, ) = GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
  }

  function testRevertSwapAfterRoleRevoked() public {
    assertTrue(GHO_GSM.hasRole(GSM_SWAPPER_ROLE, ALICE), 'Alice does not hold the Swapper Role');
    GHO_GSM.revokeRole(GSM_SWAPPER_ROLE, ALICE);

    _expectMissingSwapperRole(ALICE);
    vm.prank(ALICE);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
  }

  function testRevertFrozenBeforeRoleCheck() public {
    vm.prank(address(GHO_GSM_SWAP_FREEZER));
    GHO_GSM.setSwapFreeze(true);

    // The freeze modifier runs before the role check, so the freeze is the reported reason
    vm.expectRevert('GSM_FROZEN');
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSeizedBeforeRoleCheck() public {
    vm.prank(address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
    GHO_GSM.seize();

    vm.expectRevert('GSM_SEIZED');
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }
}
