// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../TestGhoBase.t.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

/**
 * @title TestPermissionedGsmAccess
 * @dev Covers the swap gating added by `PermissionedGsm`/`PermissionedGsm4626`, which the
 * inherited GSM suites do not exercise since they grant the Buy and Sell Asset Roles to every
 * originator
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
    USDX_4626_TOKEN.approve(address(GHO_GSM_4626), type(uint256).max);
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

  function testRoleIdentifiers() public view {
    assertEq(
      IPermissionedGsm(address(GHO_GSM)).BUY_ASSET_ROLE(),
      GSM_BUY_ASSET_ROLE,
      'Unexpected Buy Asset Role identifier'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM)).SELL_ASSET_ROLE(),
      GSM_SELL_ASSET_ROLE,
      'Unexpected Sell Asset Role identifier'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM_4626)).BUY_ASSET_ROLE(),
      GSM_BUY_ASSET_ROLE,
      'Unexpected Buy Asset Role identifier on the 4626 flavour'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM_4626)).SELL_ASSET_ROLE(),
      GSM_SELL_ASSET_ROLE,
      'Unexpected Sell Asset Role identifier on the 4626 flavour'
    );
  }

  function testRevertBuyAssetUnauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAssetUnauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertBuyAsset4626Unauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM_4626.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAsset4626Unauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM_4626.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertBuyAssetWithOnlySellRole() public {
    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAssetWithOnlyBuyRole() public {
    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertBuyAsset4626WithOnlySellRole() public {
    GHO_GSM_4626.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM_4626.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testRevertSellAsset4626WithOnlyBuyRole() public {
    GHO_GSM_4626.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
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
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        signer,
        GSM_BUY_ASSET_ROLE
      )
    );
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

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        signer,
        GSM_SELL_ASSET_ROLE
      )
    );
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
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the Sell Asset Role'
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

  function testBuyAssetAfterBuyRoleGranted() public {
    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, ) = GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
  }

  function testSellAssetAfterSellRoleGranted() public {
    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, ) = GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
  }

  function testRevertBuyAssetAfterBuyRoleRevoked() public {
    assertTrue(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, ALICE),
      'Alice does not hold the Buy Asset Role'
    );
    GHO_GSM.revokeRole(GSM_BUY_ASSET_ROLE, ALICE);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        ALICE,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(ALICE);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
  }

  function testSellAssetAfterBuyRoleRevoked() public {
    GHO_GSM.revokeRole(GSM_BUY_ASSET_ROLE, ALICE);
    vm.prank(FAUCET);
    USDX_TOKEN.mint(ALICE, DEFAULT_GSM_USDX_AMOUNT);

    vm.startPrank(ALICE);
    USDX_TOKEN.approve(address(GHO_GSM), DEFAULT_GSM_USDX_AMOUNT);
    (uint256 assetAmount, ) = GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
    vm.stopPrank();
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
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

  function testPermissionedByDefault() public view {
    assertFalse(
      IPermissionedGsm(address(GHO_GSM)).getIsPermissionless(),
      'Unexpected permissionless status'
    );
    assertFalse(
      IPermissionedGsm(address(GHO_GSM_4626)).getIsPermissionless(),
      'Unexpected permissionless status on the 4626 flavour'
    );
  }

  function testSetPermissionless() public {
    vm.expectEmit(true, true, true, true, address(GHO_GSM));
    emit IPermissionedGsm.PermissionlessUpdated(address(this), true);
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);
    assertTrue(
      IPermissionedGsm(address(GHO_GSM)).getIsPermissionless(),
      'Unexpected permissionless status'
    );

    vm.expectEmit(true, true, true, true, address(GHO_GSM));
    emit IPermissionedGsm.PermissionlessUpdated(address(this), false);
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(false);
    assertFalse(
      IPermissionedGsm(address(GHO_GSM)).getIsPermissionless(),
      'Unexpected permissionless status'
    );
  }

  function testSetPermissionless4626() public {
    vm.expectEmit(true, true, true, true, address(GHO_GSM_4626));
    emit IPermissionedGsm.PermissionlessUpdated(address(this), true);
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(true);
    assertTrue(
      IPermissionedGsm(address(GHO_GSM_4626)).getIsPermissionless(),
      'Unexpected permissionless status'
    );

    vm.expectEmit(true, true, true, true, address(GHO_GSM_4626));
    emit IPermissionedGsm.PermissionlessUpdated(address(this), false);
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(false);
    assertFalse(
      IPermissionedGsm(address(GHO_GSM_4626)).getIsPermissionless(),
      'Unexpected permissionless status'
    );
  }

  function testRevertSetPermissionlessUnauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_CONFIGURATOR_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);
  }

  function testRevertSetPermissionless4626Unauthorized() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_CONFIGURATOR_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(true);
  }

  function testRevertSetPermissionlessAlreadyPermissionless() public {
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);

    vm.expectRevert('GSM_ALREADY_PERMISSIONLESS');
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);
  }

  function testRevertSetPermissionlessAlreadyPermissioned() public {
    vm.expectRevert('GSM_ALREADY_PERMISSIONED');
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(false);
  }

  function testSwapWhenPermissionless() public {
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);

    vm.startPrank(unauthorizedAddr);
    (uint256 soldAmount, ) = GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    (uint256 boughtAmount, ) = GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    vm.stopPrank();

    assertEq(soldAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
    assertEq(boughtAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
  }

  function testSwap4626WhenPermissionless() public {
    IPermissionedGsm(address(GHO_GSM_4626)).setPermissionless(true);
    _mintVaultAssets(USDX_4626_TOKEN, USDX_TOKEN, unauthorizedAddr, DEFAULT_GSM_USDX_AMOUNT);

    vm.startPrank(unauthorizedAddr);
    (uint256 soldAmount, ) = GHO_GSM_4626.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    (uint256 boughtAmount, ) = GHO_GSM_4626.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
    vm.stopPrank();

    assertEq(soldAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
    assertEq(boughtAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
  }

  function testRevertSwapAfterPermissionlessDisabled() public {
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(false);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, unauthorizedAddr);
  }

  function testBuyAssetWithSigUnauthorizedSignerWhenPermissionless() public {
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);

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

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, ) = GHO_GSM.buyAssetWithSig(
      signer,
      DEFAULT_GSM_USDX_AMOUNT,
      signer,
      deadline,
      abi.encodePacked(r, s, v)
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
  }
}
