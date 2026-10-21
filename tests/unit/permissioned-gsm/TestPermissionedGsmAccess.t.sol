// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../TestGhoBase.t.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

/**
 * @title TestPermissionedGsmAccess
 * @dev Covers the swap gating added by `PermissionedGsm`/`PermissionedGsm4626`, which the
 * inherited GSM suites do not exercise since they grant the `BUY_ASSET_ROLE` and `SELL_ASSET_ROLE`
 * to every originator
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
      'Unexpected BUY_ASSET_ROLE identifier'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM)).SELL_ASSET_ROLE(),
      GSM_SELL_ASSET_ROLE,
      'Unexpected SELL_ASSET_ROLE identifier'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM_4626)).BUY_ASSET_ROLE(),
      GSM_BUY_ASSET_ROLE,
      'Unexpected BUY_ASSET_ROLE identifier on the 4626 flavour'
    );
    assertEq(
      IPermissionedGsm(address(GHO_GSM_4626)).SELL_ASSET_ROLE(),
      GSM_SELL_ASSET_ROLE,
      'Unexpected SELL_ASSET_ROLE identifier on the 4626 flavour'
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

    bytes memory signature;
    {
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
      signature = abi.encodePacked(r, s, v);
    }

    assertTrue(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, gsmSignerAddr),
      'Signer does not hold the SELL_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the SELL_ASSET_ROLE'
    );

    uint256 signerGhoBefore = GHO_TOKEN.balanceOf(gsmSignerAddr);
    uint256 signerUsdxBefore = USDX_TOKEN.balanceOf(gsmSignerAddr);
    uint256 relayerGhoBefore = GHO_TOKEN.balanceOf(unauthorizedAddr);
    uint256 relayerUsdxBefore = USDX_TOKEN.balanceOf(unauthorizedAddr);

    // The relayer holds no role, but the signed originator does
    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, uint256 ghoBought) = GHO_GSM.sellAssetWithSig(
      gsmSignerAddr,
      DEFAULT_GSM_USDX_AMOUNT,
      gsmSignerAddr,
      deadline,
      signature
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
    assertEq(
      GHO_TOKEN.balanceOf(gsmSignerAddr),
      signerGhoBefore + ghoBought,
      'Unexpected signer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(gsmSignerAddr),
      signerUsdxBefore - assetAmount,
      'Unexpected signer USDX balance'
    );
    assertEq(
      GHO_TOKEN.balanceOf(unauthorizedAddr),
      relayerGhoBefore,
      'Unexpected relayer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(unauthorizedAddr),
      relayerUsdxBefore,
      'Unexpected relayer USDX balance'
    );
  }

  function testBuyAssetWithSigAuthorizedSignerUnauthorizedRelayer() public {
    uint256 deadline = block.timestamp + 1 hours;
    ghoFaucet(gsmSignerAddr, DEFAULT_GSM_GHO_AMOUNT * 2);
    vm.prank(gsmSignerAddr);
    GHO_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    bytes memory signature;
    {
      bytes32 digest = _getBuyAssetTypedDataHash(
        address(GHO_GSM),
        EIP712Types.BuyAssetWithSig({
          originator: gsmSignerAddr,
          minAmount: DEFAULT_GSM_USDX_AMOUNT,
          receiver: gsmSignerAddr,
          nonce: GHO_GSM.nonces(gsmSignerAddr),
          deadline: deadline
        })
      );
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(gsmSignerKey, digest);
      signature = abi.encodePacked(r, s, v);
    }

    assertTrue(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, gsmSignerAddr),
      'Signer does not hold the BUY_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the BUY_ASSET_ROLE'
    );

    uint256 signerGhoBefore = GHO_TOKEN.balanceOf(gsmSignerAddr);
    uint256 signerUsdxBefore = USDX_TOKEN.balanceOf(gsmSignerAddr);
    uint256 relayerGhoBefore = GHO_TOKEN.balanceOf(unauthorizedAddr);
    uint256 relayerUsdxBefore = USDX_TOKEN.balanceOf(unauthorizedAddr);

    // The relayer holds no role, but the signed originator does
    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, uint256 ghoSold) = GHO_GSM.buyAssetWithSig(
      gsmSignerAddr,
      DEFAULT_GSM_USDX_AMOUNT,
      gsmSignerAddr,
      deadline,
      signature
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
    assertEq(
      GHO_TOKEN.balanceOf(gsmSignerAddr),
      signerGhoBefore - ghoSold,
      'Unexpected signer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(gsmSignerAddr),
      signerUsdxBefore + assetAmount,
      'Unexpected signer USDX balance'
    );
    assertEq(
      GHO_TOKEN.balanceOf(unauthorizedAddr),
      relayerGhoBefore,
      'Unexpected relayer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(unauthorizedAddr),
      relayerUsdxBefore,
      'Unexpected relayer USDX balance'
    );
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
      'Alice does not hold the BUY_ASSET_ROLE'
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

    bytes memory signature;
    {
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
      signature = abi.encodePacked(r, s, v);
    }

    assertFalse(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, signer),
      'Signer unexpectedly holds the BUY_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the BUY_ASSET_ROLE'
    );

    uint256 signerGhoBefore = GHO_TOKEN.balanceOf(signer);
    uint256 signerUsdxBefore = USDX_TOKEN.balanceOf(signer);
    uint256 relayerGhoBefore = GHO_TOKEN.balanceOf(unauthorizedAddr);
    uint256 relayerUsdxBefore = USDX_TOKEN.balanceOf(unauthorizedAddr);

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, uint256 ghoSold) = GHO_GSM.buyAssetWithSig(
      signer,
      DEFAULT_GSM_USDX_AMOUNT,
      signer,
      deadline,
      signature
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
    assertEq(
      GHO_TOKEN.balanceOf(signer),
      signerGhoBefore - ghoSold,
      'Unexpected signer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(signer),
      signerUsdxBefore + assetAmount,
      'Unexpected signer USDX balance'
    );
    assertEq(
      GHO_TOKEN.balanceOf(unauthorizedAddr),
      relayerGhoBefore,
      'Unexpected relayer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(unauthorizedAddr),
      relayerUsdxBefore,
      'Unexpected relayer USDX balance'
    );
  }

  function testSellAssetWithSigUnauthorizedSignerWhenPermissionless() public {
    IPermissionedGsm(address(GHO_GSM)).setPermissionless(true);

    uint256 deadline = block.timestamp + 1 hours;
    (address signer, uint256 signerKey) = makeAddrAndKey('unauthorizedSigner');
    vm.prank(FAUCET);
    USDX_TOKEN.mint(signer, DEFAULT_GSM_USDX_AMOUNT);
    vm.prank(signer);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    bytes memory signature;
    {
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
      signature = abi.encodePacked(r, s, v);
    }

    assertFalse(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, signer),
      'Signer unexpectedly holds the SELL_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr),
      'Relayer unexpectedly holds the SELL_ASSET_ROLE'
    );

    uint256 signerGhoBefore = GHO_TOKEN.balanceOf(signer);
    uint256 signerUsdxBefore = USDX_TOKEN.balanceOf(signer);
    uint256 relayerGhoBefore = GHO_TOKEN.balanceOf(unauthorizedAddr);
    uint256 relayerUsdxBefore = USDX_TOKEN.balanceOf(unauthorizedAddr);

    vm.prank(unauthorizedAddr);
    (uint256 assetAmount, uint256 ghoBought) = GHO_GSM.sellAssetWithSig(
      signer,
      DEFAULT_GSM_USDX_AMOUNT,
      signer,
      deadline,
      signature
    );
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
    assertEq(
      GHO_TOKEN.balanceOf(signer),
      signerGhoBefore + ghoBought,
      'Unexpected signer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(signer),
      signerUsdxBefore - assetAmount,
      'Unexpected signer USDX balance'
    );
    assertEq(
      GHO_TOKEN.balanceOf(unauthorizedAddr),
      relayerGhoBefore,
      'Unexpected relayer GHO balance'
    );
    assertEq(
      USDX_TOKEN.balanceOf(unauthorizedAddr),
      relayerUsdxBefore,
      'Unexpected relayer USDX balance'
    );
  }

  function testSwapRolesAdminIsDefaultAdmin() public view {
    assertEq(
      GHO_GSM.getRoleAdmin(GSM_BUY_ASSET_ROLE),
      DEFAULT_ADMIN_ROLE,
      'Unexpected BUY_ASSET_ROLE admin'
    );
    assertEq(
      GHO_GSM.getRoleAdmin(GSM_SELL_ASSET_ROLE),
      DEFAULT_ADMIN_ROLE,
      'Unexpected SELL_ASSET_ROLE admin'
    );
  }

  function testAdminGrantsAndRevokesSwapRoles() public {
    assertTrue(GHO_GSM.hasRole(DEFAULT_ADMIN_ROLE, address(this)), 'Test is not the admin');

    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);
    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);
    assertTrue(GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr), 'BUY_ASSET_ROLE not granted');
    assertTrue(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr),
      'SELL_ASSET_ROLE not granted'
    );

    GHO_GSM.revokeRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);
    GHO_GSM.revokeRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);
    assertFalse(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr),
      'BUY_ASSET_ROLE not revoked'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr),
      'SELL_ASSET_ROLE not revoked'
    );
  }

  function testRevertSwapRolesManagedByNonAdmin() public {
    bytes32[6] memory roles = [
      GSM_CONFIGURATOR_ROLE,
      GSM_TOKEN_RESCUER_ROLE,
      GSM_SWAP_FREEZER_ROLE,
      GSM_LIQUIDATOR_ROLE,
      GSM_BUY_ASSET_ROLE,
      GSM_SELL_ASSET_ROLE
    ];
    for (uint256 i = 0; i < roles.length; i++) {
      address holder = makeAddr(string.concat('roleHolder', vm.toString(i)));
      GHO_GSM.grantRole(roles[i], holder);

      vm.expectRevert(
        abi.encodeWithSelector(
          IAccessControl.AccessControlUnauthorizedAccount.selector,
          holder,
          DEFAULT_ADMIN_ROLE
        )
      );
      vm.prank(holder);
      GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);

      vm.expectRevert(
        abi.encodeWithSelector(
          IAccessControl.AccessControlUnauthorizedAccount.selector,
          holder,
          DEFAULT_ADMIN_ROLE
        )
      );
      vm.prank(holder);
      GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);

      vm.expectRevert(
        abi.encodeWithSelector(
          IAccessControl.AccessControlUnauthorizedAccount.selector,
          holder,
          DEFAULT_ADMIN_ROLE
        )
      );
      vm.prank(holder);
      GHO_GSM.revokeRole(GSM_BUY_ASSET_ROLE, ALICE);

      vm.expectRevert(
        abi.encodeWithSelector(
          IAccessControl.AccessControlUnauthorizedAccount.selector,
          holder,
          DEFAULT_ADMIN_ROLE
        )
      );
      vm.prank(holder);
      GHO_GSM.revokeRole(GSM_SELL_ASSET_ROLE, ALICE);
    }
  }

  function testBuyAssetToReceiverWithoutRole() public {
    address receiver = makeAddr('receiver');
    ghoFaucet(ALICE, DEFAULT_GSM_GHO_AMOUNT * 2);
    vm.prank(ALICE);
    GHO_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    assertTrue(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, ALICE),
      'Alice does not hold the BUY_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, receiver),
      'Receiver unexpectedly holds the BUY_ASSET_ROLE'
    );

    uint256 aliceGhoBefore = GHO_TOKEN.balanceOf(ALICE);
    uint256 aliceUsdxBefore = USDX_TOKEN.balanceOf(ALICE);

    vm.prank(ALICE);
    (uint256 assetAmount, uint256 ghoSold) = GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, receiver);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected bought asset amount');
    assertEq(GHO_TOKEN.balanceOf(ALICE), aliceGhoBefore - ghoSold, 'Unexpected Alice GHO balance');
    assertEq(USDX_TOKEN.balanceOf(ALICE), aliceUsdxBefore, 'Unexpected Alice USDX balance');
    assertEq(USDX_TOKEN.balanceOf(receiver), assetAmount, 'Unexpected receiver USDX balance');
    assertEq(GHO_TOKEN.balanceOf(receiver), 0, 'Unexpected receiver GHO balance');
  }

  function testSellAssetToReceiverWithoutRole() public {
    address receiver = makeAddr('receiver');
    vm.prank(FAUCET);
    USDX_TOKEN.mint(ALICE, DEFAULT_GSM_USDX_AMOUNT);
    vm.prank(ALICE);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    assertTrue(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, ALICE),
      'Alice does not hold the SELL_ASSET_ROLE'
    );
    assertFalse(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, receiver),
      'Receiver unexpectedly holds the SELL_ASSET_ROLE'
    );

    uint256 aliceGhoBefore = GHO_TOKEN.balanceOf(ALICE);
    uint256 aliceUsdxBefore = USDX_TOKEN.balanceOf(ALICE);

    vm.prank(ALICE);
    (uint256 assetAmount, uint256 ghoBought) = GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, receiver);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
    assertEq(
      USDX_TOKEN.balanceOf(ALICE),
      aliceUsdxBefore - assetAmount,
      'Unexpected Alice USDX balance'
    );
    assertEq(GHO_TOKEN.balanceOf(ALICE), aliceGhoBefore, 'Unexpected Alice GHO balance');
    assertEq(GHO_TOKEN.balanceOf(receiver), ghoBought, 'Unexpected receiver GHO balance');
    assertEq(USDX_TOKEN.balanceOf(receiver), 0, 'Unexpected receiver USDX balance');
  }

  function testRevertBuyAssetUnauthorizedToReceiverWithRole() public {
    assertTrue(
      GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, ALICE),
      'Alice does not hold the BUY_ASSET_ROLE'
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
  }

  function testRevertSellAssetUnauthorizedToReceiverWithRole() public {
    assertTrue(
      GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, ALICE),
      'Alice does not hold the SELL_ASSET_ROLE'
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
  }

  function testFuzzRevertBuyAssetUnauthorizedOriginator(address originator) public {
    // The proxy admin cannot call through the proxy
    vm.assume(originator != SHORT_EXECUTOR);
    vm.assume(!GHO_GSM.hasRole(GSM_BUY_ASSET_ROLE, originator));

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        originator,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(originator);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, originator);
  }

  function testFuzzRevertSellAssetUnauthorizedOriginator(address originator) public {
    // The proxy admin cannot call through the proxy
    vm.assume(originator != SHORT_EXECUTOR);
    vm.assume(!GHO_GSM.hasRole(GSM_SELL_ASSET_ROLE, originator));

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        originator,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(originator);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, originator);
  }

  function testRevertBuyAssetUnauthorizedBeforeZeroAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(0, unauthorizedAddr);

    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);
    vm.expectRevert('INVALID_AMOUNT');
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(0, unauthorizedAddr);
  }

  function testRevertSellAssetUnauthorizedBeforeZeroAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(0, unauthorizedAddr);

    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);
    vm.expectRevert('INVALID_AMOUNT');
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(0, unauthorizedAddr);
  }

  function testRevertBuyAssetUnauthorizedBeforeInsufficientLiquidity() public {
    uint256 amount = GHO_GSM.getAvailableLiquidity() + 1;

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(amount, unauthorizedAddr);

    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, unauthorizedAddr);
    vm.expectRevert('INSUFFICIENT_AVAILABLE_EXOGENOUS_ASSET_LIQUIDITY');
    vm.prank(unauthorizedAddr);
    GHO_GSM.buyAsset(amount, unauthorizedAddr);
  }

  function testRevertSellAssetUnauthorizedBeforeExposureCap() public {
    uint256 amount = uint256(GHO_GSM.getExposureCap()) + 1;

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        unauthorizedAddr,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(amount, unauthorizedAddr);

    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, unauthorizedAddr);
    vm.expectRevert('EXOGENOUS_ASSET_EXPOSURE_TOO_HIGH');
    vm.prank(unauthorizedAddr);
    GHO_GSM.sellAsset(amount, unauthorizedAddr);
  }

  function testRevertBuyAssetUnauthorizedBeforeInsufficientBalance() public {
    address originator = makeAddr('noBalance');
    vm.prank(originator);
    GHO_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        originator,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(originator);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, originator);

    GHO_GSM.grantRole(GSM_BUY_ASSET_ROLE, originator);
    vm.expectRevert(stdError.arithmeticError);
    vm.prank(originator);
    GHO_GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, originator);
  }

  function testRevertSellAssetUnauthorizedBeforeInsufficientBalance() public {
    address originator = makeAddr('noBalance');
    vm.prank(originator);
    USDX_TOKEN.approve(address(GHO_GSM), type(uint256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        originator,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(originator);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, originator);

    GHO_GSM.grantRole(GSM_SELL_ASSET_ROLE, originator);
    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientBalance.selector,
        originator,
        0,
        DEFAULT_GSM_USDX_AMOUNT
      )
    );
    vm.prank(originator);
    GHO_GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, originator);
  }
}
