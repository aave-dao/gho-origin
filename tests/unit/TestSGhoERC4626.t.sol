// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoERC4626 is TestSGhoBase {
  // ========================================
  // ERC4626 VAULT FUNCTIONALITY TESTS
  // ========================================

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
    assertEq(sgho.balanceOf(user1), initialSghoBalance + shares, 'sGho balance mismatch');
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
    assertEq(sgho.balanceOf(user1), initialSghoBalance + shares, 'sGho balance mismatch');
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
      'sGho balance mismatch after withdraw'
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
      'sGho balance mismatch after redeem'
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
    assertTrue(
      assetsAfterYield > shares,
      'Assets should be greater than shares after yield accrual'
    );
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
    assertLt(sgho.supplyCap(), type(uint256).max, 'Supply cap should be less than max uint256');
    vm.startPrank(user1);
    // Try to deposit max uint256 - should revert due to supply cap
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxDeposit.selector,
        user1,
        type(uint256).max,
        SUPPLY_CAP
      )
    );
    sgho.deposit(type(uint256).max, user1);
    vm.stopPrank();
  }

  function test_4626_maxTypeMint() external {
    assertLt(sgho.supplyCap(), type(uint256).max, 'Supply cap should be less than max uint256');
    vm.startPrank(user1);
    // Try to mint max uint256 shares - should revert due to supply cap
    uint256 maxShares = sgho.convertToShares(SUPPLY_CAP);
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxMint.selector,
        user1,
        type(uint256).max,
        maxShares
      )
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
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxWithdraw.selector,
        user1,
        type(uint256).max,
        depositAmount
      )
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
      abi.encodeWithSelector(
        ERC4626.ERC4626ExceededMaxRedeem.selector,
        user1,
        type(uint256).max,
        shares
      )
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
    assertTrue(
      maxPreviewDeposit > 0,
      'previewDeposit should return positive value for max uint256'
    );
    assertTrue(maxPreviewMint > 0, 'previewMint should return positive value for max uint256');
  }

  function test_4626_previewWithdrawMaxType() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);

    // Preview withdraw with max uint256 should perform conversion calculation
    // It should return the theoretical shares needed for max uint256 assets
    uint256 maxPreviewWithdraw = sgho.previewWithdraw(type(uint256).max);
    assertTrue(
      maxPreviewWithdraw > 0,
      'previewWithdraw should return positive value for max uint256'
    );
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
    assertTrue(
      maxPreviewRedeem > shares,
      'previewRedeem should return a value greater than user shares for max uint256'
    );
    vm.stopPrank();
  }

  // ========================================
  // SUPPLY CAP & LIMITS TESTS
  // ========================================

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
    assertEq(
      sgho.maxDeposit(user2),
      SUPPLY_CAP - depositAmount,
      'maxDeposit should be remaining capacity'
    );
    uint256 expectedMaxMint = sgho.convertToShares(SUPPLY_CAP - depositAmount);
    assertEq(
      sgho.maxMint(user2),
      expectedMaxMint,
      'maxMint should be remaining capacity in shares'
    );
  }
}
