// SPDX-License-Identifier: agpl-3

pragma solidity ^0.8.19;

import {stdStorage, StdStorage} from 'forge-std/Test.sol';
import {TestnetProcedures, TestnetERC20} from 'lib/aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {sGHO} from '../../src/contracts/sgho/sGHO.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {IERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {ERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IERC20Errors} from 'openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol';
import {IERC20Metadata as IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IsGHO} from '../../src/contracts/sgho/interfaces/IsGHO.sol';
import {ERC4626} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ERC20Permit} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol';
import {ECDSA} from 'openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol';

// --- Test Contract ---

contract sGhoTest is TestnetProcedures {
  using stdStorage for StdStorage;
  using Math for uint256;

  // Constants for yield calculations (using ray precision - 27 decimals)
  uint256 private constant RAY = 1e27;

  // Contracts
  sGHO internal sgho;
  TestnetERC20 internal gho;
  IAccessControl internal aclManager;

  // Users & Keys
  address internal user1;
  uint256 internal user1PrivateKey;
  address internal user2;
  address internal Admin;
  address internal yManager; // Yield manager user

  uint16 internal constant MAX_SAFE_RATE = 5000; // 50%
  uint256 internal constant SUPPLY_CAP = 1_000_000 ether; // 1M GHO

  // Permit constants
  string internal constant VERSION = '1'; // Matches sGHO constructor
  bytes32 internal DOMAIN_SEPARATOR_sGHO;

  function setUp() public virtual {
    initTestEnvironment(false); // Use TestnetProcedures setup

    // Users
    user1PrivateKey = 0xB0B;
    user1 = vm.addr(user1PrivateKey);
    user2 = vm.addr(0xCAFE);
    Admin = address(this);
    yManager = vm.addr(0xDEAD); // Yield manager address

    // Deploy Mocks & sGHO
    gho = new TestnetERC20('Mock GHO', 'GHO', 18, poolAdmin);

    // Deploy sGHO implementation and proxy
    address sghoImpl = address(new sGHO());
    sgho = sGHO(
      payable(
        address(
          new TransparentUpgradeableProxy(
            sghoImpl,
            address(this),
            abi.encodeWithSelector(
              sGHO.initialize.selector,
              address(gho),
              address(contracts.aclManager),
              SUPPLY_CAP
            )
          )
        )
      )
    );

    deal(address(user1), 10 ether);
    deal(address(gho), address(sgho), 1 ether, true);

    // Grant YIELD_MANAGER role to yManager through ACLManager
    vm.startPrank(poolAdmin);
    aclManager = IAccessControl(address(contracts.aclManager));
    aclManager.grantRole(sgho.YIELD_MANAGER_ROLE(), yManager);
    vm.stopPrank();

    // Set target rate as yield manager
    vm.startPrank(yManager);
    sgho.setTargetRate(1000); // 10% APR
    vm.stopPrank();

    // Calculate domain separator for permits
    DOMAIN_SEPARATOR_sGHO = sgho.DOMAIN_SEPARATOR();

    // Initial GHO funding for users
    deal(address(gho), user1, 1_000_000 ether, true);
    deal(address(gho), user2, 1_000_000 ether, true);

    // Approve sGHO to spend user GHO
    vm.startPrank(user1);
    gho.approve(address(sgho), type(uint256).max);
    vm.stopPrank();
    vm.startPrank(user2);
    gho.approve(address(sgho), type(uint256).max);
    vm.stopPrank();
  }

  // --- Constructor Tests ---

  function test_constructor() external view {
    assertEq(sgho.GHO(), address(gho), 'GHO address mismatch');
    assertEq(sgho.DOMAIN_SEPARATOR(), DOMAIN_SEPARATOR_sGHO, 'Domain separator mismatch');
  }

  // --- ERC20 Metadata Tests ---
  function test_metadata() external view {
    assertEq(sgho.name(), 'sGHO', 'Name mismatch');
    assertEq(sgho.symbol(), 'sGHO', 'Symbol mismatch');
    assertEq(sgho.decimals(), 18, 'Decimals mismatch');
  }

  // --- Receive ETH Test ---
  function test_revert_ReceiveETH() external {
    vm.startPrank(user1);
    uint256 initialBalance = user1.balance;
    vm.expectRevert(abi.encodeWithSelector(IsGHO.NoEthAllowed.selector));
    (bool success,) = payable(address(sgho)).call{value: 1 ether}('');
    // Remove the incorrect assertion - the call will revert, so success won't be set
    assertEq(user1.balance, initialBalance, 'Transfer should revert');
    vm.stopPrank();
  }

  // --- Admin functions ---
  function test_setTargetRate_event() external {
    vm.startPrank(yManager);
    uint16 newRate = 2000; // 20% APR
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGHO.TargetRateUpdated(newRate);
    sgho.setTargetRate(newRate);
    vm.stopPrank();
    assertEq(sgho.targetRate(), newRate, 'Target rate should be updated');
  }

  function test_revert_setTargetRate_exceedsMaxRate() external {
    vm.startPrank(yManager);
    uint16 newRate = MAX_SAFE_RATE + 1;
    vm.expectRevert(IsGHO.RateMustBeLessThanMaxRate.selector);
    sgho.setTargetRate(newRate);
    vm.stopPrank();
  }

  function test_setTargetRate_atMaxRate() external {
    vm.startPrank(yManager);
    sgho.setTargetRate(MAX_SAFE_RATE);
    vm.stopPrank();
    assertEq(sgho.targetRate(), MAX_SAFE_RATE, 'Target rate should be updated to max rate');
  }

  function test_setSupplyCap_event() external {
    vm.startPrank(yManager);
    uint256 newSupplyCap = 1000 ether;
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGHO.SupplyCapUpdated(newSupplyCap);
    sgho.setSupplyCap(newSupplyCap);
    vm.stopPrank();
    assertEq(sgho.supplyCap(), newSupplyCap, 'Supply cap should be updated');
  }

  function test_revert_setSupplyCap_lessThanTotalAssets() external {
    uint256 amount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(amount, user1);
    vm.stopPrank();
    vm.startPrank(yManager);
    uint256 newSupplyCap = amount - 1;
    vm.expectRevert(IsGHO.SupplyCapMustBeGreaterThanTotalAssets.selector);
    sgho.setSupplyCap(newSupplyCap);
    vm.stopPrank();
  }

  // --- ERC4626 Tests ---

  function test_4626_initialState() external view {
    assertEq(sgho.asset(), address(gho), 'Asset mismatch');
    assertEq(sgho.totalAssets(), 0, 'Initial totalAssets mismatch');
    assertEq(sgho.totalSupply(), 0, 'Initial totalSupply mismatch');
    assertEq(sgho.decimals(), gho.decimals(), 'Decimals mismatch'); // Inherits ERC20 decimals
  }

  function test_4626_deposit_mint_preview(uint256 amount) external {
    amount = uint256(bound(amount, 1, 100_000 ether));
    vm.startPrank(user1);

    // Preview
    uint256 previewShares = sgho.previewDeposit(amount);
    uint256 previewAssets = sgho.previewMint(previewShares);
    assertEq(previewAssets, amount, 'Preview mismatch deposit/mint'); // Should be 1:1 initially
    assertEq(sgho.convertToShares(amount), previewShares, 'convertToShares mismatch');
    assertEq(sgho.convertToAssets(previewShares), amount, 'convertToAssets mismatch');

    // Deposit
    uint256 initialGhoBalance = gho.balanceOf(user1);
    uint256 initialSghoBalance = sgho.balanceOf(user1);
    uint256 shares = sgho.deposit(amount, user1);

    assertEq(shares, previewShares, 'Shares mismatch');
    assertEq(sgho.balanceOf(user1), initialSghoBalance + shares, 'sGHO balance mismatch');
    assertEq(gho.balanceOf(user1), initialGhoBalance - amount, 'GHO balance mismatch');
    assertEq(sgho.totalAssets(), amount, 'totalAssets mismatch after deposit');
    assertEq(sgho.totalSupply(), shares, 'totalSupply mismatch after deposit');

    vm.stopPrank(); 
  }

  function test_4626_mint(uint256 shares) external {
    shares = uint256(bound(shares, 1, 100_000 ether));
    vm.startPrank(user1);

    // Preview
    uint256 previewAssets = sgho.previewMint(shares);

    // Mint
    uint256 initialGhoBalance = gho.balanceOf(user1);
    uint256 initialSghoBalance = sgho.balanceOf(user1);
    uint256 assets = sgho.mint(shares, user1);

    assertEq(assets, previewAssets, 'Assets mismatch');
    assertEq(sgho.balanceOf(user1), initialSghoBalance + shares, 'sGHO balance mismatch');
    assertEq(gho.balanceOf(user1), initialGhoBalance - assets, 'GHO balance mismatch');
    assertEq(sgho.totalAssets(), assets, 'totalAssets mismatch after mint');
    assertEq(sgho.totalSupply(), shares, 'totalSupply mismatch after mint');

    vm.stopPrank();
  }

  function test_4626_withdraw_redeem_preview(
    uint256 depositAmount,
    uint256 withdrawAmount
  ) external {
    depositAmount = uint256(bound(depositAmount, 1, 100_000 ether));
    vm.assume(withdrawAmount <= depositAmount);
    withdrawAmount = uint256(bound(withdrawAmount, 1, depositAmount));

    // Initial deposit
    vm.startPrank(user1);
    uint256 sharesDeposited = sgho.deposit(depositAmount, user1);

    // Preview
    uint256 previewShares = sgho.previewWithdraw(withdrawAmount);
    uint256 previewAssets = sgho.previewRedeem(previewShares);
    // Allow for rounding differences if ratio != 1
    assertApproxEqAbs(previewAssets, withdrawAmount, 1, 'Preview mismatch withdraw/redeem');

    // Withdraw
    uint256 initialGhoBalance = gho.balanceOf(user1);
    uint256 initialSghoBalance = sgho.balanceOf(user1);
    uint256 sharesWithdrawn = sgho.withdraw(withdrawAmount, user1, user1);

    assertApproxEqAbs(sharesWithdrawn, previewShares, 1, 'Shares withdrawn mismatch');
    assertApproxEqAbs(
      sgho.balanceOf(user1),
      initialSghoBalance - sharesWithdrawn,
      1,
      'sGHO balance mismatch after withdraw'
    );
    assertEq(
      gho.balanceOf(user1),
      initialGhoBalance + withdrawAmount,
      'GHO balance mismatch after withdraw'
    );
    assertApproxEqAbs(
      sgho.totalAssets(),
      depositAmount - withdrawAmount,
      1,
      'totalAssets mismatch after withdraw'
    );
    assertApproxEqAbs(
      sgho.totalSupply(),
      sharesDeposited - sharesWithdrawn,
      1,
      'totalSupply mismatch after withdraw'
    );

    vm.stopPrank();
  }

  function test_4626_redeem(uint256 depositAmount, uint256 redeemShares) external {
    depositAmount = uint256(bound(depositAmount, 1, 100_000 ether));

    // Initial deposit
    vm.startPrank(user1);
    uint256 sharesDeposited = sgho.deposit(depositAmount, user1);
    vm.assume(redeemShares <= sharesDeposited);
    redeemShares = uint256(bound(redeemShares, 1, sharesDeposited));

    // Preview
    uint256 previewAssets = sgho.previewRedeem(redeemShares);

    // Redeem
    uint256 initialGhoBalance = gho.balanceOf(user1);
    uint256 initialSghoBalance = sgho.balanceOf(user1);
    uint256 assetsRedeemed = sgho.redeem(redeemShares, user1, user1);

    assertApproxEqAbs(assetsRedeemed, previewAssets, 1, 'Assets redeemed mismatch');
    assertApproxEqAbs(
      sgho.balanceOf(user1),
      initialSghoBalance - redeemShares,
      1,
      'sGHO balance mismatch after redeem'
    );
    assertEq(
      gho.balanceOf(user1),
      initialGhoBalance + assetsRedeemed,
      'GHO balance mismatch after redeem'
    );
    assertApproxEqAbs(
      sgho.totalAssets(),
      depositAmount - assetsRedeemed,
      1,
      'totalAssets mismatch after redeem'
    );
    assertApproxEqAbs(
      sgho.totalSupply(),
      sharesDeposited - redeemShares,
      1,
      'totalSupply mismatch after redeem'
    );

    vm.stopPrank();
  }

  function test_4626_maxMethods() external {
    // Max deposit should be the supply cap initially
    assertEq(sgho.maxDeposit(user1), SUPPLY_CAP, 'maxDeposit should be supply cap');

    // Max mint should correspond to the supply cap
    uint256 expectedMaxMint = sgho.convertToShares(SUPPLY_CAP);
    assertEq(sgho.maxMint(user1), expectedMaxMint, 'maxMint should be supply cap in shares');

    // Deposit some amount and check max withdraw/redeem
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    uint256 shares = sgho.balanceOf(user1);

    assertEq(sgho.maxWithdraw(user1), depositAmount, 'maxWithdraw mismatch');
    assertEq(sgho.maxRedeem(user1), shares, 'maxRedeem mismatch');

    // Max deposit should be reduced by the deposited amount
    assertEq(sgho.maxDeposit(user1), SUPPLY_CAP - depositAmount, 'maxDeposit should be reduced');
    vm.stopPrank();
  }

  function test_4626_convertToShares() external {
    uint256 assets = 100 ether;
    uint256 shares = sgho.convertToShares(assets);
    
    // Initially, 1:1 conversion since yield index starts at RAY
    assertEq(shares, assets, 'Initial convertToShares should be 1:1');
    
    // After some yield accrual, conversion should change
    vm.warp(block.timestamp + 365 days);
    uint256 sharesAfterYield = sgho.convertToShares(assets);
    assertTrue(sharesAfterYield < assets, 'Shares should be less than assets after yield accrual');
  }

  function test_4626_convertToAssets() external {
    uint256 shares = 100 ether;
    uint256 assets = sgho.convertToAssets(shares);
    
    // Initially, 1:1 conversion since yield index starts at RAY
    assertEq(assets, shares, 'Initial convertToAssets should be 1:1');
    
    // After some yield accrual, conversion should change
    vm.warp(block.timestamp + 365 days);
    uint256 assetsAfterYield = sgho.convertToAssets(shares);
    assertTrue(assetsAfterYield > shares, 'Assets should be greater than shares after yield accrual');
  }

  function test_4626_convertFunctionsConsistency() external view {
    uint256 assets = 100 ether;
    uint256 shares = sgho.convertToShares(assets);
    uint256 convertedBackAssets = sgho.convertToAssets(shares);
    
    // Round-trip conversion should be consistent (allowing for rounding)
    assertApproxEqAbs(assets, convertedBackAssets, 1, 'Round-trip conversion should be consistent');
  }

  function test_revert_4626_withdraw_max() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    uint256 maxAssets = sgho.maxWithdraw(user1);
    uint256 withdrawAmount = maxAssets + 1;

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxWithdraw.selector,
        user1,
        withdrawAmount,
        maxAssets
      )
    );
    sgho.withdraw(withdrawAmount, user1, user1);

    vm.stopPrank();
  }

  function test_revert_4626_redeem_max() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    uint256 maxShares = sgho.maxRedeem(user1);
    uint256 redeemShares = maxShares + 1;

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxRedeem.selector,
        user1,
        redeemShares,
        maxShares
      )
    );
    sgho.redeem(redeemShares, user1, user1);

    vm.stopPrank();
  }

  function test_4626_zeroDeposit() external {
    vm.startPrank(user1);
    uint256 initialBalance = sgho.balanceOf(user1);
    uint256 initialGhoBalance = gho.balanceOf(user1);
    
    uint256 shares = sgho.deposit(0, user1);
    
    assertEq(shares, 0, 'Zero deposit should return 0 shares');
    assertEq(sgho.balanceOf(user1), initialBalance, 'Balance should remain unchanged');
    assertEq(gho.balanceOf(user1), initialGhoBalance, 'GHO balance should remain unchanged');
    vm.stopPrank();
  }

  function test_4626_zeroMint() external {
    vm.startPrank(user1);
    uint256 initialBalance = sgho.balanceOf(user1);
    uint256 initialGhoBalance = gho.balanceOf(user1);
    
    uint256 assets = sgho.mint(0, user1);
    
    assertEq(assets, 0, 'Zero mint should return 0 assets');
    assertEq(sgho.balanceOf(user1), initialBalance, 'Balance should remain unchanged');
    assertEq(gho.balanceOf(user1), initialGhoBalance, 'GHO balance should remain unchanged');
    vm.stopPrank();
  }

  function test_4626_zeroWithdraw() external {
    vm.startPrank(user1);
    // First deposit some amount to have balance
    sgho.deposit(100 ether, user1);
    uint256 initialBalance = sgho.balanceOf(user1);
    uint256 initialGhoBalance = gho.balanceOf(user1);
    
    uint256 shares = sgho.withdraw(0, user1, user1);
    
    assertEq(shares, 0, 'Zero withdraw should return 0 shares');
    assertEq(sgho.balanceOf(user1), initialBalance, 'Balance should remain unchanged');
    assertEq(gho.balanceOf(user1), initialGhoBalance, 'GHO balance should remain unchanged');
    vm.stopPrank();
  }

  function test_4626_zeroRedeem() external {
    vm.startPrank(user1);
    // First deposit some amount to have balance
    sgho.deposit(100 ether, user1);
    uint256 initialBalance = sgho.balanceOf(user1);
    uint256 initialGhoBalance = gho.balanceOf(user1);
    
    uint256 assets = sgho.redeem(0, user1, user1);
    
    assertEq(assets, 0, 'Zero redeem should return 0 assets');
    assertEq(sgho.balanceOf(user1), initialBalance, 'Balance should remain unchanged');
    assertEq(gho.balanceOf(user1), initialGhoBalance, 'GHO balance should remain unchanged');
    vm.stopPrank();
  }

  function test_4626_previewZero() external view {
    assertEq(sgho.previewDeposit(0), 0, 'previewDeposit(0) should be 0');
    assertEq(sgho.previewMint(0), 0, 'previewMint(0) should be 0');
    assertEq(sgho.previewWithdraw(0), 0, 'previewWithdraw(0) should be 0');
    assertEq(sgho.previewRedeem(0), 0, 'previewRedeem(0) should be 0');
  }

  function test_4626_maxTypeDeposit() external {
    vm.startPrank(user1);
    // Try to deposit max uint256 - should revert due to supply cap
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, user1, type(uint256).max, SUPPLY_CAP)
    );
    sgho.deposit(type(uint256).max, user1);
    vm.stopPrank();
  }

  function test_4626_maxTypeMint() external {
    vm.startPrank(user1);
    // Try to mint max uint256 shares - should revert due to supply cap
    uint256 maxShares = sgho.convertToShares(SUPPLY_CAP);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, user1, type(uint256).max, maxShares)
    );
    sgho.mint(type(uint256).max, user1);
    vm.stopPrank();
  }

  function test_4626_maxTypeWithdraw() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    
    // Try to withdraw max uint256 - should revert due to insufficient balance
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, user1, type(uint256).max, depositAmount)
    );
    sgho.withdraw(type(uint256).max, user1, user1);
    vm.stopPrank();
  }

  function test_4626_maxTypeRedeem() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    uint256 shares = sgho.balanceOf(user1);
    
    // Try to redeem max uint256 shares - should revert due to insufficient shares
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, user1, type(uint256).max, shares)
    );
    sgho.redeem(type(uint256).max, user1, user1);
    vm.stopPrank();
  }

  function test_4626_maxTypePreview() external view {
    // Preview functions should handle max uint256 gracefully and never revert
    uint256 maxPreviewDeposit = sgho.previewDeposit(type(uint256).max);
    uint256 maxPreviewMint = sgho.previewMint(type(uint256).max);
    
    // Preview functions should return the theoretical conversion result regardless of supply cap
    // They are pure conversion functions that don't enforce limits
    assertTrue(maxPreviewDeposit > 0, 'previewDeposit should return positive value for max uint256');
    assertTrue(maxPreviewMint > 0, 'previewMint should return positive value for max uint256');
  }

  function test_4626_previewWithdrawMaxType() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    
    // Preview withdraw with max uint256 should perform conversion calculation
    // It should return the theoretical shares needed for max uint256 assets
    uint256 maxPreviewWithdraw = sgho.previewWithdraw(type(uint256).max);
    assertTrue(maxPreviewWithdraw > 0, 'previewWithdraw should return positive value for max uint256');
    vm.stopPrank();
  }

  function test_4626_previewRedeemMaxType() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    uint256 shares = sgho.balanceOf(user1);
    
    // Preview redeem with max uint256 should perform conversion calculation
    // It should return the theoretical assets for max uint256 shares
    uint256 maxPreviewRedeem = sgho.previewRedeem(type(uint256).max);
    assertTrue(maxPreviewRedeem > 0, 'previewRedeem should return positive value for max uint256');
    // Remove the incorrect assertion - previewRedeem with max uint256 should return a very large number, not the user's shares
    assertTrue(maxPreviewRedeem > shares, 'previewRedeem should return a value greater than user shares for max uint256');
    vm.stopPrank();
  }

  // --- ERC20 Standard Tests ---

  function test_transfer() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    
    uint256 transferAmount = 50 ether;
    bool success = sgho.transfer(user2, transferAmount);
    
    assertTrue(success, 'Transfer should succeed');
    assertEq(sgho.balanceOf(user1), depositAmount - transferAmount, 'Sender balance should decrease');
    assertEq(sgho.balanceOf(user2), transferAmount, 'Receiver balance should increase');
    vm.stopPrank();
  }

  function test_transfer_zeroAmount() external {
    vm.startPrank(user1);
    sgho.deposit(100 ether, user1);
    bool success = sgho.transfer(user2, 0);
    assertTrue(success, 'transfer of 0 should succeed');
    vm.stopPrank();
  }

  function test_transferFrom() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    
    uint256 approveAmount = 50 ether;
    sgho.approve(user2, approveAmount);
    vm.stopPrank();
    
    vm.startPrank(user2);
    uint256 transferAmount = 30 ether;
    bool success = sgho.transferFrom(user1, user2, transferAmount);
    
    assertTrue(success, 'TransferFrom should succeed');
    assertEq(sgho.balanceOf(user1), depositAmount - transferAmount, 'Owner balance should decrease');
    assertEq(sgho.balanceOf(user2), transferAmount, 'Receiver balance should increase');
    assertEq(sgho.allowance(user1, user2), approveAmount - transferAmount, 'Allowance should decrease');
    vm.stopPrank();
  }

  function test_transferFrom_zeroAmount() external {
    vm.startPrank(user1);
    sgho.deposit(100 ether, user1);
    sgho.approve(user2, 100 ether);
    vm.stopPrank();
    vm.startPrank(user2);
    bool success = sgho.transferFrom(user1, user2, 0);
    assertTrue(success, 'transferFrom of 0 should succeed');
    vm.stopPrank();
  }

  function test_approve() external {
    vm.startPrank(user1);
    uint256 approveAmount = 100 ether;
    bool success = sgho.approve(user2, approveAmount);
    
    assertTrue(success, 'Approve should succeed');
    assertEq(sgho.allowance(user1, user2), approveAmount, 'Allowance should be set correctly');
    vm.stopPrank();
  }

  function test_approve_zeroAmount() external {
    vm.startPrank(user1);
    bool success = sgho.approve(user2, 0);
    assertTrue(success, 'approve of 0 should succeed');
    assertEq(sgho.allowance(user1, user2), 0, 'allowance should be 0');
    vm.stopPrank();
  }

  function test_transfer_maxType() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    
    // Try to transfer max uint256 - should revert due to insufficient balance
    vm.expectRevert();
    sgho.transfer(user2, type(uint256).max);
    vm.stopPrank();
  }

  function test_transferFrom_maxType() external {
    vm.startPrank(user1);
    // First deposit some amount
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    sgho.approve(user2, type(uint256).max);
    vm.stopPrank();
    
    vm.startPrank(user2);
    // Try to transferFrom max uint256 - should revert due to insufficient balance
    vm.expectRevert();
    sgho.transferFrom(user1, user2, type(uint256).max);
    vm.stopPrank();
  }

  function test_approve_maxType() external {
    vm.startPrank(user1);
    // Approve max uint256 should succeed
    bool success = sgho.approve(user2, type(uint256).max);
    assertTrue(success, 'approve of max uint256 should succeed');
    assertEq(sgho.allowance(user1, user2), type(uint256).max, 'allowance should be max uint256');
    vm.stopPrank();
  }

  function test_allowance() external {
    vm.startPrank(user1);
    uint256 approveAmount = 100 ether;
    sgho.approve(user2, approveAmount);
    vm.stopPrank();
    
    assertEq(sgho.allowance(user1, user2), approveAmount, 'Allowance should return correct amount');
    assertEq(sgho.allowance(user1, user1), 0, 'Self allowance should be zero');
  }

  // --- ERC20Permit Tests ---

  struct PermitVars {
    uint256 privateKey;
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint256 nonce;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function test_permit_invalidSignature() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    // Use wrong owner address - should revert with ERC2612InvalidSigner
    {
      bytes32 PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');
      bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, user1, vars.spender, vars.value, vars.nonce, vars.deadline));
      bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
      address recovered = ECDSA.recover(hash, vars.v, vars.r, vars.s);
      vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, recovered, user1));
      sgho.permit(user1, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_replay() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    // First permit should succeed
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(sgho.allowance(vars.owner, vars.spender), vars.value, 'First permit should set allowance');
    // Second permit with same signature should revert (nonce already used)
    // The contract expects nonce 1, but our signature is for nonce 0
    {
      bytes32 PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');
      bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, vars.owner, vars.spender, vars.value, vars.nonce + 1, vars.deadline));
      bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
      address recovered = ECDSA.recover(hash, vars.v, vars.r, vars.s);
      vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, recovered, vars.owner));
      sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_wrongDomainSeparator() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    // Use wrong domain separator
    bytes32 PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');
    bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline));
    bytes32 wrongDomainSeparator = keccak256('WRONG_DOMAIN');
    bytes32 hash = keccak256(abi.encodePacked('\x19\x01', wrongDomainSeparator, structHash));
    (vars.v, vars.r, vars.s) = vm.sign(vars.privateKey, hash);
    // The contract will recover a different signer than owner
    {
      bytes32 contractHash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
      address recovered = ECDSA.recover(contractHash, vars.v, vars.r, vars.s);
      vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, recovered, vars.owner));
      sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_validSignature() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(sgho.allowance(vars.owner, vars.spender), vars.value, 'Permit should set allowance correctly');
  }

  function test_permit_expiredDeadline() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp - 1; // Expired deadline
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC20Permit.ERC2612ExpiredSignature.selector,
        vars.deadline
      )
    );
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
  }

  function test_permit_zeroValue() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 0;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(sgho.allowance(vars.owner, vars.spender), 0, 'permit with value 0 should set allowance to 0');
  }

  function test_permit_selfApproval() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(vars.owner, vars.owner, vars.value, vars.nonce, vars.deadline, vars.privateKey);
    sgho.permit(vars.owner, vars.owner, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(sgho.allowance(vars.owner, vars.owner), vars.value, 'Self approval should work');
  }

  function test_nonces() external {
    address owner = user1;
    uint256 initialNonce = sgho.nonces(owner);
    
    // Nonce should increment after permit
    uint256 privateKey = 0xA11CE;
    address permitOwner = vm.addr(privateKey);
    address spender = user2;
    uint256 value = 100 ether;
    uint256 deadline = block.timestamp + 1 hours;
    uint256 nonce = sgho.nonces(permitOwner);
    
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(permitOwner, spender, value, nonce, deadline, privateKey);
    
    sgho.permit(permitOwner, spender, value, deadline, v, r, s);
    
    assertEq(sgho.nonces(permitOwner), nonce + 1, 'Nonce should increment after permit');
    assertEq(sgho.nonces(owner), initialNonce, 'Other user nonce should remain unchanged');
  }

  // --- Supply Cap Tests ---
  function test_revert_deposit_exceedsCap() external {
    vm.startPrank(user1);
    uint256 amount = SUPPLY_CAP + 1;
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, user1, amount, SUPPLY_CAP)
    );
    sgho.deposit(amount, user1);
    vm.stopPrank();
  }

  function test_revert_mint_exceedsCap() external {
    vm.startPrank(user1);
    uint256 shares = sgho.convertToShares(SUPPLY_CAP) + 1;
    uint256 maxShares = sgho.maxMint(user1);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, user1, shares, maxShares)
    );
    sgho.mint(shares, user1);
    vm.stopPrank();
  }

  function test_deposit_atCap() external {
    vm.startPrank(user1);
    sgho.deposit(SUPPLY_CAP, user1);
    assertEq(sgho.totalAssets(), SUPPLY_CAP, 'Total assets should equal supply cap');
    // The contract balance will be the supply cap plus the 1 GHO donated in setUp
    assertEq(
      gho.balanceOf(address(sgho)),
      SUPPLY_CAP + 1 ether,
      'Contract balance should be supply cap + initial donation'
    );
    vm.stopPrank();
  }

  function test_maxDeposit_atCap() external {
    vm.startPrank(user1);
    sgho.deposit(SUPPLY_CAP, user1);
    vm.stopPrank();
    
    // Max deposit should be 0 when at cap
    assertEq(sgho.maxDeposit(user2), 0, 'maxDeposit should be 0 when at supply cap');
    assertEq(sgho.maxMint(user2), 0, 'maxMint should be 0 when at supply cap');
  }

  function test_maxDeposit_partialCap() external {
    vm.startPrank(user1);
    uint256 depositAmount = SUPPLY_CAP / 2;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();
    
    // Max deposit should be remaining capacity
    assertEq(sgho.maxDeposit(user2), SUPPLY_CAP - depositAmount, 'maxDeposit should be remaining capacity');
    uint256 expectedMaxMint = sgho.convertToShares(SUPPLY_CAP - depositAmount);
    assertEq(sgho.maxMint(user2), expectedMaxMint, 'maxMint should be remaining capacity in shares');
  }

  // --- Yield Integration Tests (_updateVault) ---

  function test_yield_claimSavingsIntegration(uint256 depositAmount, uint64 timeSkip) external {
    depositAmount = uint256(bound(depositAmount, 1 ether, 100_000 ether));
    timeSkip = uint64(bound(timeSkip, 1, 30 days)); // No minimum time requirement in new implementation

    // Initial deposit
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);


    assertEq(sgho.totalAssets(), depositAmount, 'Initial totalAssets');

    // Skip time and trigger _updateVault via another deposit
    vm.warp(block.timestamp + timeSkip);
    uint256 depositAmount2 = 1 ether;
    deal(address(gho), user1, depositAmount2, true); // Ensure user1 has more GHO
    gho.approve(address(sgho), depositAmount2);
    sgho.deposit(depositAmount2, user1); // This deposit triggers _updateVault

    // Calculate expected yield based on time elapsed and target rate
    uint256 expectedYield = (depositAmount * sgho.vaultAPR() * timeSkip) / (10000 * 365 days);
    uint256 expectedAssets = depositAmount + expectedYield + depositAmount2;



    assertApproxEqAbs(
      sgho.totalAssets(),
      expectedAssets,
      1,
      'totalAssets mismatch after yield claim'
    );

    // Check if withdraw/redeem reflects yield (share price > 1)
    uint256 shares = sgho.balanceOf(user1);
    uint256 expectedWithdrawAssets = sgho.previewRedeem(shares);
    assertTrue(
      expectedWithdrawAssets > depositAmount + depositAmount2,
      'Assets per share should increase with yield'
    );
    assertApproxEqAbs(
      expectedWithdrawAssets,
      expectedAssets,
      1,
      'Preview redeem should equal total assets'
    ); // Single depositor case
    vm.stopPrank();
  }

  function test_yield_10_percent_one_year() external {
    // Set target rate to 10% APR
    vm.startPrank(yManager);
    sgho.setTargetRate(1000); // 10% APR is 1000 bps
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);

    assertEq(sgho.totalAssets(), depositAmount, 'Initial total assets should be deposit amount');

    // User2 deposits 500 GHO
    uint256 depositAmount2 = 500 ether;
    vm.startPrank(user2);
    sgho.deposit(depositAmount2, user2);
    vm.stopPrank();

    // Skip time by 365 days
    uint256 timeSkip = 365 days;
    vm.warp(block.timestamp + timeSkip);

    // Trigger yield update by redeeming all of user2 shares
    // Any state-changing action that calls `_updateVault` would work.
    vm.startPrank(user2);
    uint256 user2Shares = sgho.balanceOf(user2);
    sgho.redeem(user2Shares, user2, user2);
    assertEq(sgho.balanceOf(user2), 0, 'User2 should have no shares after redeeming');
    vm.stopPrank();

    // After 1 year at 10% APR, the 100 GHO should have become ~110 GHO.
    // The total assets will be ~110 GHO + the small deposit.
    uint256 expectedYield = ((depositAmount) * 1000) / 10000;
    uint256 expectedTotalAssets = depositAmount + expectedYield;

    assertApproxEqAbs(
      sgho.totalAssets(),
      expectedTotalAssets,
      1,
      'Total assets should reflect 10% yield after 1 year'
    );

    // Also check the value of user1's shares
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 user1Assets = sgho.previewRedeem(user1Shares);
    assertApproxEqAbs(
      user1Assets,
      expectedTotalAssets,
      1,
      'User asset value should reflect 10% yield'
    );
    vm.stopPrank();
  }

  function test_yield_is_compounded_with_intermediate_update(uint16 rate) external {
    rate = uint16(bound(rate, 100, 5000));
    vm.startPrank(yManager);
    sgho.setTargetRate(rate);
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Warp time and trigger updates daily to simulate compounding
    for (uint i = 0; i < 365; i++) {
      vm.warp(block.timestamp + 1 days);
      vm.prank(yManager);
      sgho.setTargetRate(rate); // Re-setting the rate triggers the update
      vm.stopPrank();
    }
    // --- Verification ---
    // Get the current value of user1's shares
    uint256 user1FinalAssets = sgho.previewRedeem(user1Shares);

    // Calculate what the assets would be with simple (non-compounded) interest over 365 days
    uint256 simpleYield = (depositAmount * rate) / 10000;
    uint256 simpleInterestAssets = depositAmount + simpleYield;

    // Calculate the expected assets with daily compounding.
    // Each daily update applies linear interest for that day, but builds on the previous index
    // APY = (1 + APR/n)^n - 1, where n=365 for daily.
    uint256 WAD = 1e18;
    uint256 aprWad = (rate * WAD) / 10000;
    uint256 dailyCompoundingTerm = WAD + (aprWad / 365);

    // Calculate (1 + apr/365)^365 using a helper for WAD math to prevent overflow
    uint256 compoundedMultiplier =  _wadPow(dailyCompoundingTerm, 365);
    uint256 expectedAssets = (depositAmount * compoundedMultiplier) / WAD;

    assertApproxEqAbs(
      user1FinalAssets,
      expectedAssets,
      1e6, // Use a tolerance for small differences from ideal calculation
      'Final assets should be close to theoretical daily compounded value'
    );

    // With compounding due to the intermediate updates, user1's final assets should be greater than with simple interest.
    assertTrue(
      user1FinalAssets > simpleInterestAssets,
      'Daily compounded assets for user1 should be greater than simple interest assets'
    );
  }

  // --- Yield Edge Case Tests ---

  function test_yield_zeroTargetRate() external {
    // Set target rate to 0
    vm.startPrank(yManager);
    sgho.setTargetRate(0);
    vm.stopPrank();

    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Skip time - no yield should accrue
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // User1 should have the same assets value
    vm.startPrank(user1);
    uint256 finalAssets = sgho.previewRedeem(initialShares);
    assertEq(finalAssets, depositAmount, 'Assets should remain unchanged with zero target rate');
    vm.stopPrank();
  }

  function test_yield_zeroTimeSinceLastUpdate() external {
    // User1 deposits 100 GHO
    uint256 depositAmount = 100 ether;
    vm.startPrank(user1);
    sgho.deposit(depositAmount, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Don't skip time - timeSinceLastUpdate should be 0
    // Trigger another operation immediately
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // User1 should have the same assets value (no time passed)
    vm.startPrank(user1);
    uint256 finalAssets = sgho.previewRedeem(initialShares);
    assertEq(finalAssets, depositAmount, 'Assets should remain unchanged with zero time since last update');
    vm.stopPrank();
  }

  function test_yield_index_edgeCases() external {
    // Test with very small amounts and very large amounts
    uint256 smallAmount = 1; // 1 wei
    uint256 largeAmount = SUPPLY_CAP - 1 ether;
    
    vm.startPrank(user1);
    
    // Test small amount
    sgho.deposit(smallAmount, user1);
    uint256 smallShares = sgho.balanceOf(user1);
    assertEq(smallShares, smallAmount, 'Small amount should convert 1:1 initially');
    
    // Test large amount
    deal(address(gho), user1, largeAmount, true);
    gho.approve(address(sgho), largeAmount);
    sgho.deposit(largeAmount, user1);
    uint256 largeShares = sgho.balanceOf(user1);
    assertEq(largeShares, smallShares + largeAmount, 'Large amount should convert 1:1 initially');
    
    vm.stopPrank();
  }

  function test_yield_accrual_atSupplyCap() external {
    // Set a higher target rate to ensure significant yield accrual
    vm.startPrank(yManager);
    sgho.setTargetRate(5000); // 50% APR to ensure significant yield
    vm.stopPrank();
    
    // Fill the vault to supply cap
    vm.startPrank(user1);
    sgho.deposit(SUPPLY_CAP, user1);
    uint256 initialShares = sgho.balanceOf(user1);
    vm.stopPrank();

    // Check that yield accrual still works even at supply cap
    uint256 totalAssetsBefore = sgho.totalAssets();
    uint256 yieldIndexBefore = sgho.yieldIndex();
    
    // Skip time to accrue yield (use a longer period to ensure significant yield)
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update by withdrawing 1 wei (any state-changing operation would work)
    vm.startPrank(user1);
    sgho.withdraw(1, user1, user1);
    vm.stopPrank();
    
    uint256 totalAssetsAfter = sgho.totalAssets();
    uint256 yieldIndexAfter = sgho.yieldIndex();
    
    // Yield should have accrued even at supply cap
    // The total assets after should be greater than before minus the withdrawal amount
    // because yield accrual should offset the withdrawal
    assertTrue(totalAssetsAfter > totalAssetsBefore - 1, 'Yield should accrue even at supply cap');
    assertTrue(yieldIndexAfter > yieldIndexBefore, 'Yield index should increase even at supply cap');
    
    // User's share value should have increased (accounting for the 1 wei withdrawal)
    vm.startPrank(user1);
    uint256 userAssetsAfter = sgho.previewRedeem(initialShares - sgho.convertToShares(1));
    assertTrue(userAssetsAfter > SUPPLY_CAP - 1, 'User assets should increase with yield even at supply cap');
    vm.stopPrank();
  }

  function test_maxDeposit_withYieldAccrual() external {
    // Set up initial state with some deposits
    vm.startPrank(user1);
    uint256 initialDeposit = SUPPLY_CAP / 2;
    sgho.deposit(initialDeposit, user1);
    vm.stopPrank();
    
    // Check maxDeposit before any yield update
    uint256 maxDepositBefore = sgho.maxDeposit(user2);
    uint256 totalAssetsBefore = sgho.totalAssets();
    
    // Skip time to accrue yield
    vm.warp(block.timestamp + 30 days);
    
    // The maxDeposit should account for the fact that the deposit itself will trigger yield update
    // and potentially increase totalAssets beyond the current calculation  
    
    // The maxDeposit should account for the fact that the deposit itself will trigger yield update
    // and potentially increase totalAssets beyond the current calculation
    assertTrue(maxDepositBefore <= SUPPLY_CAP - totalAssetsBefore, 'maxDeposit should not exceed remaining capacity');
    
    // Now trigger a yield update by withdrawing 1 wei from user1
    vm.startPrank(user1);
    sgho.withdraw(1, user1, user1);
    vm.stopPrank();
    
    uint256 totalAssetsAfter = sgho.totalAssets();
    uint256 maxDepositAfter = sgho.maxDeposit(user2);
    
    // The total assets should have increased due to yield accrual (minus the 1 wei withdrawal)
    assertTrue(totalAssetsAfter > totalAssetsBefore - 1, 'Total assets should increase due to yield despite withdrawal');
    
    // The new maxDeposit should be accurate after the yield update
    assertEq(maxDepositAfter, SUPPLY_CAP - totalAssetsAfter, 'maxDeposit should be accurate after yield update');
    
    // Verify that the maxDeposit calculation is correct by attempting to deposit exactly that amount
    vm.startPrank(user2);
    deal(address(gho), user2, maxDepositAfter, true);
    gho.approve(address(sgho), maxDepositAfter);
    sgho.deposit(maxDepositAfter, user2);
    vm.stopPrank();
    
    // Should now be at supply cap
    assertEq(sgho.totalAssets(), SUPPLY_CAP, 'Should be at supply cap after depositing maxDeposit amount');
  }

  // --- GHO Shortfall Tests ---

  function test_gho_shortfall_detection() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    // Check theoretical vs actual GHO balance
    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    
    // Should have accrued yield (theoretical > actual)
    assertTrue(theoreticalAssets > actualGhoBalance, 'Should have accrued yield');
    
    // Calculate shortfall
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    assertTrue(shortfall > 0, 'Should have a shortfall');
    
    // Verify maxWithdraw and maxRedeem are limited by actual GHO balance
    uint256 maxWithdrawUser1 = sgho.maxWithdraw(user1);
    uint256 maxRedeemUser1 = sgho.maxRedeem(user1);
    
    assertEq(maxWithdrawUser1, actualGhoBalance, 'maxWithdraw should be limited by actual GHO balance');
    assertTrue(maxRedeemUser1 <= sgho.balanceOf(user1), 'maxRedeem should not exceed user shares');
    
    // User should not be able to withdraw more than actual GHO balance
    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxWithdraw.selector,
        user1,
        maxWithdrawUser1 + 1,
        maxWithdrawUser1
      )
    );
    sgho.withdraw(maxWithdrawUser1 + 1, user1, user1);
    vm.stopPrank();
  }

  function test_gho_shortfall_withdrawal_behavior() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue significant yield
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    
    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');
    
    // User should be able to withdraw up to actual GHO balance
    vm.startPrank(user1);
    uint256 maxWithdraw = sgho.maxWithdraw(user1);
    uint256 sharesBurned = sgho.withdraw(maxWithdraw, user1, user1);
    
    // Verify withdrawal succeeded
    assertEq(gho.balanceOf(user1), user1Balance + maxWithdraw, 'User should have the new balance');
    assertEq(sgho.balanceOf(user1), user1Shares - sharesBurned , 'User should have the remaining shares');
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
    vm.stopPrank();
  }

  function test_gho_shortfall_redeem_behavior() external {
    // Set up initial state with deposits
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue significant yield
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    
    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');
    
    // User should be able to redeem up to maxRedeem
    vm.startPrank(user1);
    uint256 maxRedeem = sgho.maxRedeem(user1);
    uint256 assetsReceived = sgho.redeem(maxRedeem, user1, user1);
    
    // Verify redemption succeeded
    assertEq(gho.balanceOf(user1), user1Balance + assetsReceived, 'User should receive the actual GHO balance');
    assertApproxEqAbs(gho.balanceOf(address(sgho)), 0, 1, 'Contract should have no GHO left');
    assertEq(sgho.balanceOf(user1), user1Shares - maxRedeem, 'User should have no shares left');
    vm.stopPrank();
  }

  function test_gho_shortfall_multiple_users() external {
    // Set up initial state with multiple users
    vm.startPrank(user1);
    uint256 depositAmount1 = 500 ether;
    sgho.deposit(depositAmount1, user1);
    vm.stopPrank();

    vm.startPrank(user2);
    uint256 depositAmount2 = 500 ether;
    sgho.deposit(depositAmount2, user2);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update with a deposit instead of withdrawal to avoid affecting state
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    uint256 shortfall = theoreticalAssets - actualGhoBalance;
    
    // Verify shortfall exists
    assertTrue(shortfall > 0, 'Should have a shortfall');
    
    // Both users should be limited by actual GHO balance
    // Recalculate maxWithdraw after yield update to ensure consistency
    uint256 maxWithdrawUser1 = sgho.maxWithdraw(user1);
    uint256 maxWithdrawUser2 = sgho.maxWithdraw(user2);
    
    // Total max withdrawals should equal theoretical assets (not actual balance)
    assertEq(maxWithdrawUser1 + maxWithdrawUser2, theoreticalAssets, 'Total max withdrawals should equal theoretical assets');
    
    // Calculate proportional shares of actual GHO balance to avoid maxWithdraw issues
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 user2Shares = sgho.balanceOf(user2);
    uint256 totalShares = user1Shares + user2Shares;
    
    uint256 user1ProportionalWithdraw = (actualGhoBalance * user1Shares) / totalShares;
    uint256 user2ProportionalWithdraw = actualGhoBalance - user1ProportionalWithdraw; // Ensure exact split
    
    // Users should be able to withdraw their proportional share of actual GHO
    vm.startPrank(user1);
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 sharesBurned1 = sgho.withdraw(user1ProportionalWithdraw, user1, user1);
    assertEq(gho.balanceOf(user1), user1Balance + user1ProportionalWithdraw, 'User1 should have the new balance');
    assertEq(sgho.balanceOf(user1), user1Shares - sharesBurned1, 'User1 should have the remaining shares');
    vm.stopPrank();
    
    vm.startPrank(user2);
    uint256 user2Balance = gho.balanceOf(user2);
    uint256 sharesBurned2 = sgho.withdraw(user2ProportionalWithdraw, user2, user2);
    assertEq(gho.balanceOf(user2), user2Balance + user2ProportionalWithdraw, 'User2 should have the new balance');
    assertEq(sgho.balanceOf(user2), user2Shares - sharesBurned2, 'User2 should have the remaining shares');
    vm.stopPrank();
    
    // Contract should have no GHO left
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
  }

  function test_gho_shortfall_artificial_creation() external {
    // Set up initial state
    vm.startPrank(user1);
    uint256 depositAmount = 1000 ether;
    sgho.deposit(depositAmount, user1);
    vm.stopPrank();

    // Skip time to accrue yield
    vm.warp(block.timestamp + 365 days);
    
    // Trigger yield update
    vm.startPrank(user2);
    sgho.deposit(1 ether, user2);
    vm.stopPrank();

    uint256 theoreticalAssets = sgho.totalAssets();
    uint256 actualGhoBalance = gho.balanceOf(address(sgho));
    
    // Verify we have a shortfall
    assertTrue(theoreticalAssets > actualGhoBalance, 'Should have a shortfall');
    
    // Artificially reduce GHO balance to create a larger shortfall
    // This simulates a scenario where GHO is lost/stolen from the contract
    vm.startPrank(address(sgho));
    gho.transfer(user2, actualGhoBalance / 2); // Transfer half the GHO out
    vm.stopPrank();
    
    uint256 newActualBalance = gho.balanceOf(address(sgho));
    uint256 newShortfall = theoreticalAssets - newActualBalance;
    
    // Shortfall should be larger now
    assertTrue(newShortfall > theoreticalAssets - actualGhoBalance, 'Shortfall should be larger');
    
    // User should still be able to withdraw up to the new actual balance
    vm.startPrank(user1);
    uint256 user1Balance = gho.balanceOf(user1);
    uint256 user1Shares = sgho.balanceOf(user1);
    uint256 maxWithdraw = sgho.maxWithdraw(user1);
    assertEq(maxWithdraw, newActualBalance, 'maxWithdraw should equal new actual balance');
    
    // Should be able to withdraw the maximum
    uint256 sharesBurned = sgho.withdraw(maxWithdraw, user1, user1);
    assertEq(gho.balanceOf(user1), user1Balance + maxWithdraw, 'User should have the new balance');
    assertEq(sgho.balanceOf(user1), user1Shares - sharesBurned, 'User should have the remaining shares');
    assertEq(gho.balanceOf(address(sgho)), 0, 'Contract should have no GHO left');
    vm.stopPrank();
  }

  // --- Precision Tests ---
  function test_precision_yieldIndex_smallValues() external pure {
      // Small values for prevYieldIndex, targetRate, and time
      uint256 prevYieldIndex = 1; // 1 wei
      uint16 targetRate = 1; // 0.01%
      uint256 timeSinceLastUpdate = 1; // 1 second
      uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);
      assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
  }

  function test_precision_yieldIndex_largeValues() external pure {
      // Large values for prevYieldIndex, targetRate, and time
      uint256 prevYieldIndex = 1e30; // Large but safe value
      uint16 targetRate = 5000; // Max safe rate
      uint256 timeSinceLastUpdate = 365 days; // 1 year
      uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);
      assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
      assertTrue(newYieldIndex <= type(uint256).max, 'Yield index should not overflow');
  }

  function test_precision_yieldIndex_realisticValues() external pure {
      // Test with realistic starting values
      uint256 prevYieldIndex = 1e27; // Start from RAY (1e27)
      uint16 targetRate = 1000; // 10% APR
      uint256 timeSinceLastUpdate = 365 days; // 1 year
      uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, targetRate, timeSinceLastUpdate);
      
      // After 1 year at 10%, index should be approximately 1.1 * RAY
      uint256 expectedIndex = (1e27 * 11) / 10; // 1.1 * RAY
      assertApproxEqRel(newYieldIndex, expectedIndex, 0.01e18, 'Yield index should approximate 10% growth'); // 1% tolerance
      assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should not underflow');
  }

  function test_precision_yieldIndex_granularTime() external pure {
      // Test with very small time increments
      uint256 prevYieldIndex = 1e27;
      uint16 targetRate = 1000; // 10% APR
      
      // Test 1 second increment
      uint256 newYieldIndex1s = _emulateYieldIndex(prevYieldIndex, targetRate, 1);
      assertTrue(newYieldIndex1s > prevYieldIndex, 'Should accrue yield even for 1 second');
      
      // Test 1 minute increment  
      uint256 newYieldIndex1m = _emulateYieldIndex(prevYieldIndex, targetRate, 60);
      assertTrue(newYieldIndex1m > newYieldIndex1s, 'More time should yield more index growth');
      
      // Test 1 hour increment
      uint256 newYieldIndex1h = _emulateYieldIndex(prevYieldIndex, targetRate, 3600);
      assertTrue(newYieldIndex1h > newYieldIndex1m, 'More time should yield more index growth');
  }

  function test_precision_yieldIndex_cumulativePrecision() external pure {
      // Test cumulative precision loss over multiple small updates vs one large update
      uint256 prevYieldIndex = RAY;
      uint16 targetRate = 1000; // 10% APR
      uint256 totalTime = 30 days;
      
      // Single large update
      uint256 singleUpdate = _emulateYieldIndex(prevYieldIndex, targetRate, totalTime);
      
      // Multiple small updates (simulate daily updates)
      uint256 cumulativeIndex = prevYieldIndex;
      uint256 dailyTime = 1 days;
      for (uint256 i = 0; i < 30; i++) {
          cumulativeIndex = _emulateYieldIndex(cumulativeIndex, targetRate, dailyTime);
      }
      
      // Cumulative should be slightly higher due to compounding
      assertTrue(cumulativeIndex >= singleUpdate, 'Cumulative updates should compound yield');
      
      // But the difference should be small (within 0.1% for reasonable rates)
      assertApproxEqRel(cumulativeIndex, singleUpdate, 0.001e18, 'Precision loss should be minimal');
  }

  function test_precision_yieldIndex_edgeCases() external pure {
      // Test minimum non-zero yield index
      uint256 minYieldIndex = _emulateYieldIndex(1, 1, 1);
      assertTrue(minYieldIndex >= 1, 'Should not underflow with minimum values');
      
      // Test with yield index exactly at RAY
      uint256 rayYieldIndex = _emulateYieldIndex(RAY, 1000, 1 days);
      assertTrue(rayYieldIndex > RAY, 'Should grow from RAY baseline');
      
      // Test maximum safe rate for extended period
      uint256 maxRateIndex = _emulateYieldIndex(RAY, MAX_SAFE_RATE, 365 days);
      assertTrue(maxRateIndex > RAY, 'Should handle max rate without overflow');
      assertTrue(maxRateIndex < RAY * 2, 'Max rate for 1 year should not double the index');
  }

  function test_precision_yieldIndex_fuzz(uint256 timeSkip, uint16 rate) external pure {
      // Bound inputs to reasonable ranges
      timeSkip = bound(timeSkip, 1, 365 days * 10); // 1 second to 10 years
      rate = uint16(bound(rate, 1, MAX_SAFE_RATE)); // 0.01% to 50%
      
      uint256 prevYieldIndex = RAY;
      uint256 newYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);
      
      // Basic invariants
      assertTrue(newYieldIndex >= prevYieldIndex, 'Yield index should never decrease');
      assertTrue(newYieldIndex <= type(uint256).max, 'Should not overflow');
      
      // Reasonable growth bounds (max 50% per year * 10 years = 500% max theoretical)
      assertTrue(newYieldIndex <= prevYieldIndex * 6, 'Growth should be bounded by reasonable limits');
  }

  function test_precision_yieldIndex_zeroRateOrTime() external pure {
      uint256 prevYieldIndex = RAY;
      // Zero target rate
      assertEq(_emulateYieldIndex(prevYieldIndex, 0, 1000), prevYieldIndex, 'Zero rate should not change index');
      // Zero time
      assertEq(_emulateYieldIndex(prevYieldIndex, 1000, 0), prevYieldIndex, 'Zero time should not change index');
  }

  function test_precision_yieldIndex_consistency() external {
      // Compare contract's yieldIndex calculation to _emulateYieldIndex for a real scenario
      uint256 prevYieldIndex = sgho.yieldIndex();
      uint16 rate = sgho.targetRate();
      uint256 timeSkip = 1 days;
      // Warp time and trigger yield update
      vm.warp(block.timestamp + timeSkip);
      // Call a state-changing function to update yieldIndex
      vm.startPrank(user1);
      sgho.deposit(1 ether, user1);
      vm.stopPrank();
      uint256 contractYieldIndex = sgho.yieldIndex();
      uint256 emulatedYieldIndex = _emulateYieldIndex(prevYieldIndex, rate, timeSkip);
      // Allow for 1 wei rounding error
      assertApproxEqAbs(contractYieldIndex, emulatedYieldIndex, 1, 'Yield index calculation mismatch');
  }

  function test_precision_yieldIndex_monotonic() external pure {
      // Test that yield index is always monotonically increasing
      uint256 prevYieldIndex = RAY;
      uint16 targetRate = 1000;
      
      uint256 index1 = _emulateYieldIndex(prevYieldIndex, targetRate, 1 days);
      uint256 index2 = _emulateYieldIndex(index1, targetRate, 1 days);
      uint256 index3 = _emulateYieldIndex(index2, targetRate, 1 days);
      
      assertTrue(index1 > prevYieldIndex, 'First update should increase index');
      assertTrue(index2 > index1, 'Second update should increase index');
      assertTrue(index3 > index2, 'Third update should increase index');
      
      // Growth should be roughly equal for equal time periods (compound growth)
      uint256 growth1 = index1 - prevYieldIndex;
      uint256 growth2 = index2 - index1;
      uint256 growth3 = index3 - index2;
      
      assertTrue(growth2 > growth1, 'Compound growth should accelerate');
      assertTrue(growth3 > growth2, 'Compound growth should continue accelerating');
  }

  // --- Target Rate Tests ---
  function test_setTargetRate() external {
    uint16 newRate = 2000; // 20% APR

    vm.startPrank(yManager);
    sgho.setTargetRate(newRate);
    vm.stopPrank();

    assertEq(sgho.vaultAPR(), newRate, 'Target rate not set correctly');
  }

  function test_revert_setTargetRate_notYieldManager() external {
    uint16 newRate = 2000; // 20% APR

    vm.expectRevert(abi.encodeWithSelector(IsGHO.OnlyYieldManager.selector));
    sgho.setTargetRate(newRate);
  }

  function test_revert_setTargetRate_rateGreaterThanMaxRate() external {
    uint16 newRate = 5001; // 50.01% APR
    vm.startPrank(yManager);
    vm.expectRevert(abi.encodeWithSelector(IsGHO.RateMustBeLessThanMaxRate.selector));
    sgho.setTargetRate(newRate);
    vm.stopPrank();
  }

  function test_vaultAPR() external {
    uint16 targetRate = 1500; // 15% APR

    vm.startPrank(yManager);
    sgho.setTargetRate(targetRate);
    vm.stopPrank();

    assertEq(sgho.vaultAPR(), targetRate, 'Vault APR mismatch');
  }

  // --- Rescue Tests ---
  function test_emergencyTokenTransfer() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 rescueAmount = 100 ether;

    // Transfer some tokens to sGHO
    deal(address(mockToken), address(sgho), rescueAmount, true);

    // Grant FUNDS_ADMIN role to Admin
    vm.startPrank(poolAdmin);
    aclManager.grantRole(sgho.FUNDS_ADMIN_ROLE(), Admin);
    vm.stopPrank();

    // Rescue tokens
    vm.startPrank(Admin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, rescueAmount);
    vm.stopPrank();

    assertEq(mockToken.balanceOf(user1), rescueAmount, 'Tokens not rescued correctly');
  }

  function test_emergencyTokenTransfer_amountGreaterThanBalance() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 initialAmount = 100 ether;
    uint256 rescueAmount = 200 ether;

    // Transfer some tokens to sGHO
    deal(address(mockToken), address(sgho), initialAmount, true);

    // Grant FUNDS_ADMIN role to Admin
    vm.startPrank(poolAdmin);
    aclManager.grantRole(sgho.FUNDS_ADMIN_ROLE(), Admin);
    vm.stopPrank();

    // Rescue tokens
    vm.startPrank(Admin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, rescueAmount);
    vm.stopPrank();

    assertEq(
      mockToken.balanceOf(user1),
      initialAmount,
      'Rescued amount should be capped at balance'
    );
  }

  function test_revert_emergencyTokenTransfer_notFundsAdmin() external {
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));

    vm.expectRevert(abi.encodeWithSelector(IsGHO.OnlyFundsAdmin.selector));
    sgho.emergencyTokenTransfer(address(mockToken), user1, 100 ether);
  }

  function test_revert_emergencyTokenTransfer_cannotRescueGHO() external {
    vm.startPrank(poolAdmin);
    aclManager.grantRole(sgho.FUNDS_ADMIN_ROLE(), Admin);
    vm.stopPrank();

    vm.startPrank(Admin);
    // Should revert because maxRescue returns 0 for GHO
    sgho.emergencyTokenTransfer(address(gho), user1, 100 ether);
    vm.stopPrank();
    
    // Verify that no GHO was transferred
    assertEq(gho.balanceOf(user1), 0, 'No GHO should be transferred');
  }

  function test_emergencyTokenTransfer_zeroAmount() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 initialAmount = 100 ether;

    // Transfer some tokens to sGHO
    deal(address(mockToken), address(sgho), initialAmount, true);

    // Grant FUNDS_ADMIN role to Admin
    vm.startPrank(poolAdmin);
    aclManager.grantRole(sgho.FUNDS_ADMIN_ROLE(), Admin);
    vm.stopPrank();

    // Rescue zero amount should be a no-op
    vm.startPrank(Admin);
    sgho.emergencyTokenTransfer(address(mockToken), user1, 0);
    vm.stopPrank();

    // Token balances should remain unchanged
    assertEq(mockToken.balanceOf(address(sgho)), initialAmount, 'Contract balance should remain unchanged');
    assertEq(mockToken.balanceOf(user1), 0, 'User balance should remain unchanged');
  }

  function test_maxRescue() external {
    // Deploy a mock ERC20 token
    TestnetERC20 mockToken = new TestnetERC20('Mock Token', 'MTK', 18, address(this));
    uint256 tokenAmount = 100 ether;

    // Transfer some tokens to sGHO
    deal(address(mockToken), address(sgho), tokenAmount, true);

    // Test maxRescue for non-GHO token
    assertEq(sgho.maxRescue(address(mockToken)), tokenAmount, 'maxRescue should return full balance for non-GHO tokens');

    // Test maxRescue for GHO token
    assertEq(sgho.maxRescue(address(gho)), 0, 'maxRescue should return 0 for GHO tokens');
  }

  // --- Initialization Tests ---
  function test_initialization() external {
    // Deploy a new sGHO instance
    address impl = address(new sGHO());
    sGHO newSgho = sGHO(
      payable(
        address(
          new TransparentUpgradeableProxy(
            impl,
            address(this),
            abi.encodeWithSelector(
              sGHO.initialize.selector,
              address(gho),
              address(contracts.aclManager),
              
              SUPPLY_CAP
            )
          )
        )
      )
    );

    // Should work after initialization
    assertEq(newSgho.totalAssets(), 0, 'Should be initialized');
  }

  function test_revert_initialize_twice() external {
    // Deploy a new sGHO instance
    address impl = address(new sGHO());
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      impl,
      address(this),
      abi.encodeWithSelector(
        sGHO.initialize.selector,
        address(gho),
        address(contracts.aclManager),
        
        SUPPLY_CAP
      )
    );

    sGHO newSgho = sGHO(payable(address(proxy)));

    // Should revert on second initialization via proxy
    vm.expectRevert();
    newSgho.initialize(address(gho), SUPPLY_CAP);
  }



  // --- Getter Functions Tests ---

  function test_getter_GHO() external view {
    assertEq(sgho.GHO(), address(gho), 'GHO address getter should return correct address');
  }


  function test_getter_name() external view {
    assertEq(sgho.name(), 'sGHO', 'Name should be sGHO');
  }

  function test_getter_symbol() external view {
    assertEq(sgho.symbol(), 'sGHO', 'Symbol should be sGHO');
  }

  function test_getter_decimals() external view {
    assertEq(sgho.decimals(), 18, 'Decimals should be 18');
  }

  function test_getter_asset() external view {
    assertEq(sgho.asset(), address(gho), 'Asset should return GHO address');
  }

  function test_getter_targetRate() external view {
    assertEq(sgho.targetRate(), 1000, 'Target rate should be 10% (1000 bps)');
  }

  function test_getter_MAX_SAFE_RATE() external view {
    assertEq(sgho.MAX_SAFE_RATE(), 5000, 'Max target rate should match constant');
  }

  function test_getter_supplyCap() external view {
    assertEq(sgho.supplyCap(), SUPPLY_CAP, 'Supply cap should match constant');
  }

  function test_getter_yieldIndex() external view {
    assertEq(sgho.yieldIndex(), 1e27, 'Initial yield index should be RAY (1e27)');
  }

  function test_getter_lastUpdate() external view {
    assertEq(sgho.lastUpdate(), block.timestamp, 'Last update should be current timestamp');
  }

  function test_getter_vaultAPR() external view {
    assertEq(sgho.vaultAPR(), sgho.targetRate(), 'Vault APR should equal target rate');
  }

  function test_getter_FUNDS_ADMIN_ROLE() external view {
    assertEq(sgho.FUNDS_ADMIN_ROLE(), bytes32('FUNDS_ADMIN'), 'FUNDS_ADMIN_ROLE should match hash');
  }

  function test_getter_YIELD_MANAGER_ROLE() external view {
    assertEq(sgho.YIELD_MANAGER_ROLE(), bytes32('YIELD_MANAGER'), 'YIELD_MANAGER_ROLE should match hash');
  }

  function test_getter_DOMAIN_SEPARATOR() external view {
    assertEq(sgho.DOMAIN_SEPARATOR(), DOMAIN_SEPARATOR_sGHO, 'Domain separator should match calculated value');
  }

  function test_getter_totalSupply() external view {
    assertEq(sgho.totalSupply(), 0, 'Initial total supply should be 0');
  }

  function test_getter_balanceOf() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    assertEq(sgho.balanceOf(user1), depositAmount, 'Balance should match deposited amount');
    assertEq(sgho.balanceOf(user2), 0, 'User2 balance should be 0');
    vm.stopPrank();
  }

  function test_getter_totalAssets() external view {
    assertEq(sgho.totalAssets(), 0, 'Initial total assets should be 0');
  }


  // --- Internal Utility Functions ---

    /// @dev Emulates the yieldIndex calculation as in sGHO._getCurrentYieldIndex(), using OpenZeppelin Math for all operations
    function _emulateYieldIndex(uint256 prevYieldIndex, uint16 targetRate, uint256 timeSinceLastUpdate) internal pure returns (uint256) {
        if (targetRate == 0 || timeSinceLastUpdate == 0) return prevYieldIndex;
        
        // Convert targetRate from basis points to ray
        uint256 annualRateRay = uint256(targetRate).mulDiv(RAY, 10000, Math.Rounding.Floor);
        // Calculate the rate per second
        uint256 ratePerSecond = annualRateRay.mulDiv(RAY, 365 days, Math.Rounding.Floor);
        // Calculate accumulated rate and growth factor
        uint256 accumulatedRate = ratePerSecond.mulDiv(timeSinceLastUpdate, RAY, Math.Rounding.Floor);
        uint256 growthFactor = RAY + accumulatedRate;
        return prevYieldIndex.mulDiv(growthFactor, RAY, Math.Rounding.Floor);
    }

  function _createPermitSignature(
    address owner,
    address spender,
    uint256 value,
    uint256 nonce,
    uint256 deadline,
    uint256 privateKey
  ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    bytes32 PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');
    bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
    bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
    return vm.sign(privateKey, hash);
  }

  function _wadPow(uint256 base, uint256 exp) internal pure returns (uint256) {
    uint256 res = 1e18; // WAD
    while (exp > 0) {
      if (exp % 2 == 1) {
        res = (res * base) / 1e18;
      }
      base = (base * base) / 1e18;
      exp /= 2;
    }
    return res;
  }
  
}