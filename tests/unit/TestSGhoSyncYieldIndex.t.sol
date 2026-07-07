// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoSyncYieldIndex is TestSGhoBase {
  function setUp() public override {
    super.setUp();
    // Headroom for checkpoints in the past
    vm.warp(block.timestamp + 365 days);
  }

  // ========================================
  // BASIC BEHAVIOR
  // ========================================

  function test_sync_setsStateAndEmits() external {
    uint120 newIndex = uint120((11 * RAY) / 10);
    uint40 newLastUpdate = uint40(block.timestamp - 30 days);

    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.YieldIndexSynced(newIndex, newLastUpdate, 2000);
    sgho.syncYieldIndex(newIndex, newLastUpdate, 2000);

    (
      uint120 rawIndex,
      uint40 rawLastUpdate,
      uint16 rawRate,
      uint40 rawEffectiveAt,
      uint16 rawPendingRate
    ) = _rawStorage(sgho);
    assertEq(rawIndex, newIndex, 'Index not synced');
    assertEq(rawLastUpdate, newLastUpdate, 'lastUpdate not synced');
    assertEq(rawRate, 2000, 'Rate not synced');
    assertEq(rawEffectiveAt, 0, 'Pending timestamp must be cleared');
    assertEq(rawPendingRate, 0, 'Pending rate must be cleared');

    // Accrual resumes from the synced checkpoint
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(newIndex, 2000, 30 days),
      'Accrual must resume from the synced checkpoint'
    );
  }

  function test_sync_timestampNow() external {
    uint120 newIndex = uint120((12 * RAY) / 10);
    sgho.syncYieldIndex(newIndex, uint40(block.timestamp), 1500);

    assertEq(sgho.yieldIndex(), newIndex, 'Index not synced');
    assertEq(sgho.lastUpdate(), block.timestamp, 'lastUpdate not synced');
    assertEq(sgho.targetRate(), 1500, 'Rate not synced');
    assertEq(sgho.convertToAssets(RAY), newIndex, 'Live index must equal the synced index');
  }

  function test_sync_indexAtRayFloor() external {
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), 0);
    assertEq(sgho.yieldIndex(), RAY, 'RAY must be an accepted index');
  }

  // ========================================
  // REVERTS
  // ========================================

  function test_revert_sync_notAdmin() external {
    address[2] memory callers = [user1, yManager];
    for (uint256 i = 0; i < callers.length; i++) {
      vm.startPrank(callers[i]);
      vm.expectRevert(
        abi.encodeWithSelector(
          IAccessControl.AccessControlUnauthorizedAccount.selector,
          callers[i],
          sgho.DEFAULT_ADMIN_ROLE()
        )
      );
      sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), 1000);
      vm.stopPrank();
    }
  }

  function test_revert_sync_timestampInFuture() external {
    vm.expectRevert(IsGho.SyncTimestampInFuture.selector);
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp + 1), 1000);
  }

  function test_revert_sync_maxRateExceeded() external {
    vm.expectRevert(IsGho.MaxRateExceeded.selector);
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), MAX_SAFE_RATE + 1);
  }

  function test_revert_sync_indexBelowRay() external {
    vm.expectRevert(IsGho.YieldIndexTooLow.selector);
    sgho.syncYieldIndex(uint120(RAY - 1), uint40(block.timestamp), 1000);
  }

  // ========================================
  // INTERACTION WITH SCHEDULED UPDATES
  // ========================================

  function test_sync_discardsPendingUpdate() external {
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(3000, effectiveAt);

    uint120 newIndex = uint120((11 * RAY) / 10);
    sgho.syncYieldIndex(newIndex, uint40(block.timestamp), 1000);

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 0, 'Pending rate not discarded');
    assertEq(pendingEffectiveAt, 0, 'Pending timestamp not discarded');

    vm.warp(effectiveAt + 1 days);
    assertEq(sgho.targetRate(), 1000, 'Discarded update must not take effect');
  }

  function test_sync_discardsDueUnappliedUpdate() external {
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(3000, effectiveAt);
    vm.warp(effectiveAt + 10 days);

    // The sync is authoritative: the due-but-unpersisted update is discarded, not folded in
    uint120 newIndex = uint120((11 * RAY) / 10);
    uint40 newLastUpdate = uint40(block.timestamp - 1 days);
    sgho.syncYieldIndex(newIndex, newLastUpdate, 1000);

    assertEq(sgho.yieldIndex(), newIndex, 'Synced index must win');
    assertEq(sgho.lastUpdate(), newLastUpdate, 'Synced timestamp must win');
    assertEq(sgho.targetRate(), 1000, 'Synced rate must win');
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(newIndex, 1000, 1 days),
      'Accrual must resume from the synced checkpoint'
    );
  }

  function test_sync_thenSchedule_samePayload() external {
    // A reconciliation payload can restore the checkpoint and re-schedule an upcoming update
    uint120 newIndex = uint120((11 * RAY) / 10);
    uint40 newLastUpdate = uint40(block.timestamp - 10 days);
    uint40 effectiveAt = uint40(block.timestamp + 5 days);

    sgho.syncYieldIndex(newIndex, newLastUpdate, 1000);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 10 days);
    uint256 indexAtEffective = _emulateYieldIndex(newIndex, 1000, 15 days);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(indexAtEffective, 2000, 10 days),
      'Accrual must chain the synced checkpoint and the scheduled update'
    );
  }

  // ========================================
  // SHARE VALUE EFFECTS
  // ========================================

  function test_sync_canDecreaseShareValue() external {
    // Deposit at a known RAY index
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), 1000);
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    vm.warp(block.timestamp + 365 days);
    assertEq(sgho.previewRedeem(shares), 110 ether, 'Yield must have accrued');

    // Reconciliation may legitimately rewind over-accrual, decreasing share value
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), 1000);
    assertEq(sgho.previewRedeem(shares), 100 ether, 'Share value must follow the synced index');
  }

  function test_sync_canIncreaseShareValue() external {
    // Deposit at a known RAY index
    sgho.syncYieldIndex(uint120(RAY), uint40(block.timestamp), 1000);
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    // Syncing to a higher checkpoint (missed accrual) increases share value
    sgho.syncYieldIndex(uint120((11 * RAY) / 10), uint40(block.timestamp), 1000);
    assertEq(sgho.previewRedeem(shares), 110 ether, 'Share value must follow the synced index');
  }

  // ========================================
  // COLD START & RECONCILIATION FLOWS
  // ========================================

  /// @dev Cold start: a brand-new deployment is synced from the logical checkpoint of a live
  /// chain and accrues identically from then on.
  function test_sync_coldStartMatchesSourceChain() external {
    // Source chain with organic history: immediate update, then a lazily-applied scheduled one
    sGho source = _deploySGho();
    vm.prank(yManager);
    source.setTargetRate(1000);
    vm.warp(block.timestamp + 100 days);
    vm.prank(yManager);
    source.setTargetRate(2000);
    vm.prank(yManager);
    source.setTargetRate(3000, uint40(block.timestamp + 10 days));
    vm.warp(block.timestamp + 60 days);

    // New chain: deploy and sync from the source's logical checkpoint
    sGho newChain = _deploySGho();
    newChain.syncYieldIndex(
      uint120(source.yieldIndex()),
      uint40(source.lastUpdate()),
      source.targetRate()
    );
    _assertInSync(source, newChain);

    // Still bit-identical much later and across a subsequent synchronized update
    vm.warp(block.timestamp + 200 days);
    _assertInSync(source, newChain);

    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.startPrank(yManager);
    source.setTargetRate(1500, effectiveAt);
    newChain.setTargetRate(1500, effectiveAt);
    vm.stopPrank();
    vm.warp(effectiveAt + 100 days);
    _assertInSync(source, newChain);
  }

  /// @dev Reconciliation: a chain that missed a multi-chain rate update is brought back in sync
  /// from a healthy chain's logical checkpoint.
  function test_sync_reconciliationAfterMissedUpdate() external {
    sGho chainA = _deploySGho();
    sGho chainB = _deploySGho();
    vm.startPrank(yManager);
    chainA.setTargetRate(1000);
    chainB.setTargetRate(1000);
    vm.stopPrank();

    // The multi-chain AIP lands on chain A but fails on chain B
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    chainA.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 30 days);
    assertTrue(
      chainA.convertToAssets(RAY) != chainB.convertToAssets(RAY),
      'Chains must have diverged'
    );

    // Reconciliation AIP: copy chain A's logical checkpoint (the due update folded in at its
    // effective timestamp) onto chain B
    chainB.syncYieldIndex(
      uint120(chainA.yieldIndex()),
      uint40(chainA.lastUpdate()),
      chainA.targetRate()
    );
    _assertInSync(chainA, chainB);

    vm.warp(block.timestamp + 365 days);
    _assertInSync(chainA, chainB);
  }

  function test_sync_fuzz(uint120 newIndex, uint32 checkpointAge, uint16 newRate) external {
    newIndex = uint120(bound(newIndex, RAY, 1000 * RAY));
    checkpointAge = uint32(bound(checkpointAge, 0, 365 days));
    newRate = uint16(bound(newRate, 0, MAX_SAFE_RATE));

    uint40 newLastUpdate = uint40(block.timestamp - checkpointAge);
    sgho.syncYieldIndex(newIndex, newLastUpdate, newRate);

    assertEq(sgho.yieldIndex(), newIndex, 'Index not synced');
    assertEq(sgho.lastUpdate(), newLastUpdate, 'lastUpdate not synced');
    assertEq(sgho.targetRate(), newRate, 'Rate not synced');
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(newIndex, newRate, checkpointAge),
      'Accrual must resume from the synced checkpoint'
    );
  }

  function _assertInSync(sGho chainA, sGho chainB) internal view {
    assertEq(chainA.convertToAssets(RAY), chainB.convertToAssets(RAY), 'Live index diverged');
    assertEq(chainA.yieldIndex(), chainB.yieldIndex(), 'Checkpoint index diverged');
    assertEq(chainA.lastUpdate(), chainB.lastUpdate(), 'Checkpoint timestamp diverged');
    assertEq(chainA.targetRate(), chainB.targetRate(), 'Rate diverged');
  }
}
