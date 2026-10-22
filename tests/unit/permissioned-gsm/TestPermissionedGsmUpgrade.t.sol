// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../TestGhoBase.t.sol';
import {IPermissionedGsm} from 'src/contracts/facilitators/gsm/interfaces/IPermissionedGsm.sol';

abstract contract TestPermissionedGsmUpgradeBase is TestGhoBase {
  Gsm internal GSM;
  IERC20 internal UNDERLYING;

  function setUp() public {
    GSM = _gsm();
    UNDERLYING = _underlying();

    _mintUnderlying(ALICE, DEFAULT_GSM_USDX_AMOUNT * 2);
    vm.startPrank(ALICE);
    UNDERLYING.approve(address(GSM), type(uint256).max);
    GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
    vm.stopPrank();
  }

  function _gsm() internal view virtual returns (Gsm);

  function _underlying() internal view virtual returns (IERC20);

  function _mintUnderlying(address to, uint256 amount) internal virtual;

  function _newPermissionedImpl() internal virtual returns (address);

  function _newPlainImpl() internal virtual returns (address);

  function testUpgradeToPermissioned() public {
    bytes32[] memory beforeSnapshot = _getStorageSnapshot();
    address impl = _newPermissionedImpl();

    vm.expectEmit(true, true, true, true, address(GSM));
    emit IERC1967.Upgraded(impl);
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(impl);

    bytes32[] memory afterSnapshot = _getStorageSnapshot();
    for (uint256 i = 0; i < afterSnapshot.length; i++) {
      assertEq(afterSnapshot[i], beforeSnapshot[i], 'Unexpected storage value updated');
    }
    assertFalse(
      IPermissionedGsm(address(GSM)).getIsBuyPermissionless(),
      'Unexpected buy permissionless status'
    );
    assertFalse(
      IPermissionedGsm(address(GSM)).getIsSellPermissionless(),
      'Unexpected sell permissionless status'
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        ALICE,
        GSM_SELL_ASSET_ROLE
      )
    );
    vm.prank(ALICE);
    GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        ALICE,
        GSM_BUY_ASSET_ROLE
      )
    );
    vm.prank(ALICE);
    GSM.buyAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
  }

  function testRevertReinitializeAfterUpgradeToPermissioned() public {
    address permissionedImpl = _newPermissionedImpl();
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(permissionedImpl);
    assertEq(GSM.GSM_REVISION(), 1, 'Unexpected GSM revision');

    vm.expectRevert('Contract instance has already been initialized');
    vm.prank(ALICE);
    GSM.initialize(ALICE, TREASURY, DEFAULT_GSM_USDX_EXPOSURE, address(GHO_RESERVE));
  }

  function testUpgradeFromPermissionedToPlain() public {
    address permissionedImpl = _newPermissionedImpl();
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(permissionedImpl);

    bytes32[] memory beforeSnapshot = _getStorageSnapshot();
    address impl = _newPlainImpl();

    vm.expectEmit(true, true, true, true, address(GSM));
    emit IERC1967.Upgraded(impl);
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(impl);

    bytes32[] memory afterSnapshot = _getStorageSnapshot();
    for (uint256 i = 0; i < afterSnapshot.length; i++) {
      assertEq(afterSnapshot[i], beforeSnapshot[i], 'Unexpected storage value updated');
    }

    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GSM)).getIsBuyPermissionless();
    vm.expectRevert(bytes(''));
    IPermissionedGsm(address(GSM)).getIsSellPermissionless();

    vm.prank(ALICE);
    (uint256 assetAmount, ) = GSM.sellAsset(DEFAULT_GSM_USDX_AMOUNT, ALICE);
    assertEq(assetAmount, DEFAULT_GSM_USDX_AMOUNT, 'Unexpected sold asset amount');
  }

  function testPermissionlessStatusKeptAcrossPlainUpgrade() public {
    address permissionedImpl = _newPermissionedImpl();
    address plainImpl = _newPlainImpl();

    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(permissionedImpl);
    IPermissionedGsm(address(GSM)).setBuyPermissionless(true);

    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(plainImpl);
    vm.prank(SHORT_EXECUTOR);
    AdminUpgradeabilityProxy(payable(address(GSM))).upgradeTo(permissionedImpl);

    assertTrue(
      IPermissionedGsm(address(GSM)).getIsBuyPermissionless(),
      'Unexpected buy permissionless status'
    );
    assertFalse(
      IPermissionedGsm(address(GSM)).getIsSellPermissionless(),
      'Unexpected sell permissionless status'
    );
  }

  function _getStorageSnapshot() internal view returns (bytes32[] memory) {
    // lastInitializedRevision (slot 1) and GSM storage (56-60), the permissionless flags pack into 60
    bytes32[] memory data = new bytes32[](6);
    data[0] = vm.load(address(GSM), bytes32(uint256(1)));
    for (uint256 i = 1; i < data.length; i++) {
      data[i] = vm.load(address(GSM), bytes32(uint256(55 + i)));
    }
    return data;
  }
}

contract TestPermissionedGsmUpgrade is TestPermissionedGsmUpgradeBase {
  function _gsm() internal view override returns (Gsm) {
    return GHO_GSM;
  }

  function _underlying() internal view override returns (IERC20) {
    return IERC20(address(USDX_TOKEN));
  }

  function _mintUnderlying(address to, uint256 amount) internal override {
    vm.prank(FAUCET);
    USDX_TOKEN.mint(to, amount);
  }

  function _newPermissionedImpl() internal override returns (address) {
    return
      address(
        new PermissionedGsm(
          address(GHO_TOKEN),
          address(USDX_TOKEN),
          address(GHO_GSM_FIXED_PRICE_STRATEGY)
        )
      );
  }

  function _newPlainImpl() internal override returns (address) {
    return
      address(
        new Gsm(address(GHO_TOKEN), address(USDX_TOKEN), address(GHO_GSM_FIXED_PRICE_STRATEGY))
      );
  }
}

contract TestPermissionedGsm4626Upgrade is TestPermissionedGsmUpgradeBase {
  function _gsm() internal view override returns (Gsm) {
    return Gsm(address(GHO_GSM_4626));
  }

  function _underlying() internal view override returns (IERC20) {
    return IERC20(address(USDX_4626_TOKEN));
  }

  function _mintUnderlying(address to, uint256 amount) internal override {
    _mintVaultAssets(USDX_4626_TOKEN, USDX_TOKEN, to, amount);
  }

  function _newPermissionedImpl() internal override returns (address) {
    return
      address(
        new PermissionedGsm4626(
          address(GHO_TOKEN),
          address(USDX_4626_TOKEN),
          address(GHO_GSM_4626_FIXED_PRICE_STRATEGY)
        )
      );
  }

  function _newPlainImpl() internal override returns (address) {
    return
      address(
        new Gsm4626(
          address(GHO_TOKEN),
          address(USDX_4626_TOKEN),
          address(GHO_GSM_4626_FIXED_PRICE_STRATEGY)
        )
      );
  }
}
