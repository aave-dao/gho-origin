// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoTargetRateSchedule is TestSGhoBase {
  // ========================================
  // SCHEDULING
  // ========================================

  function test_schedule_storesPendingWithoutCheckpoint() external {
    uint256 indexBefore = sgho.yieldIndex();
    uint256 lastUpdateBefore = sgho.lastUpdate();
    uint40 effectiveAt = uint40(block.timestamp + 1 days);

    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 2000, 'Pending rate not stored');
    assertEq(pendingEffectiveAt, effectiveAt, 'Pending effective timestamp not stored');

    // Current rate and checkpoint are untouched until the update is effective
    assertEq(sgho.targetRate(), 1000, 'Current rate must not change on scheduling');
    assertEq(sgho.yieldIndex(), indexBefore, 'Index must not be checkpointed on scheduling');
    assertEq(sgho.lastUpdate(), lastUpdateBefore, 'lastUpdate must not change on scheduling');
  }

  function test_schedule_event() external {
    uint40 effectiveAt = uint40(block.timestamp + 1 days);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.TargetRateUpdated(2000, effectiveAt);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);
  }

  function test_revert_schedule_notYieldManager() external {
    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        user1,
        sgho.YIELD_MANAGER_ROLE()
      )
    );
    sgho.setTargetRate(2000, uint40(block.timestamp + 1 days));
    vm.stopPrank();
  }

  function test_revert_schedule_maxRateExceeded() external {
    vm.prank(yManager);
    vm.expectRevert(IsGho.MaxRateExceeded.selector);
    sgho.setTargetRate(MAX_SAFE_RATE + 1, uint40(block.timestamp + 1 days));
  }

  function test_revert_schedule_effectiveTimestampInPast() external {
    vm.prank(yManager);
    vm.expectRevert(IsGho.EffectiveTimestampInPast.selector);
    sgho.setTargetRate(2000, uint40(block.timestamp - 1));
  }

  function test_schedule_effectiveAtNow_appliesImmediately() external {
    vm.warp(block.timestamp + 30 days);
    uint256 expectedIndex = _emulateYieldIndex(sgho.yieldIndex(), 1000, 30 days);

    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(block.timestamp, expectedIndex);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.TargetRateUpdated(2000, block.timestamp);
    vm.prank(yManager);
    sgho.setTargetRate(2000, uint40(block.timestamp));

    assertEq(sgho.targetRate(), 2000, 'Rate not applied immediately');
    assertEq(sgho.yieldIndex(), expectedIndex, 'Index not checkpointed at the old rate');
    assertEq(sgho.lastUpdate(), block.timestamp, 'lastUpdate not advanced');
    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 0, 'No pending rate expected');
    assertEq(pendingEffectiveAt, 0, 'No pending timestamp expected');
  }

  function test_schedule_effectiveAtMaxUint40() external {
    vm.prank(yManager);
    sgho.setTargetRate(2000, type(uint40).max);

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 2000, 'Pending rate not stored');
    assertEq(pendingEffectiveAt, type(uint40).max, 'Pending effective timestamp not stored');
    assertEq(sgho.targetRate(), 1000, 'Current rate must not change');
  }

  // ========================================
  // ACCRUAL AROUND THE EFFECTIVE TIMESTAMP
  // ========================================

  function test_schedule_rateSwitchesExactlyAtEffectiveTime() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    // One second before: still accruing at the old rate, update still pending
    vm.warp(effectiveAt - 1);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(index0, 1000, 10 days - 1),
      'Old rate must apply until the effective timestamp'
    );
    assertEq(sgho.targetRate(), 1000, 'Rate must not switch early');

    // At the effective timestamp: checkpoint at the old rate, new rate in force
    vm.warp(effectiveAt);
    uint256 indexAtEffective = _emulateYieldIndex(index0, 1000, 10 days);
    assertEq(sgho.convertToAssets(RAY), indexAtEffective, 'Index at the effective timestamp');
    assertEq(sgho.targetRate(), 2000, 'Rate must switch at the effective timestamp');

    // After: accrues at the new rate from the effective timestamp
    vm.warp(effectiveAt + 5 days);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(indexAtEffective, 2000, 5 days),
      'New rate must accrue from the effective timestamp'
    );
  }

  function test_schedule_zeroRate_stopsAccrualAtEffectiveTime() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(0, effectiveAt);

    vm.warp(effectiveAt + 365 days);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(index0, 1000, 10 days),
      'Index must freeze at the effective timestamp'
    );
    assertEq(sgho.targetRate(), 0, 'Rate must be zero after the effective timestamp');
  }

  function test_schedule_fromZeroRate() external {
    vm.prank(yManager);
    sgho.setTargetRate(0);
    uint256 index0 = sgho.yieldIndex();

    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(1000, effectiveAt);

    vm.warp(effectiveAt);
    assertEq(sgho.convertToAssets(RAY), index0, 'Index must stay flat at zero rate');

    vm.warp(effectiveAt + 365 days);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(index0, 1000, 365 days),
      'Index must accrue from the effective timestamp'
    );
  }

  function test_schedule_gettersReflectDueUpdateBeforePersisting() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 lastUpdateBefore = uint40(block.timestamp);
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 30 days);

    // Getters resolve the due update as if it had been persisted at its effective timestamp
    uint256 indexAtEffective = _emulateYieldIndex(index0, 1000, 10 days);
    assertEq(sgho.yieldIndex(), indexAtEffective, 'yieldIndex must reflect the due update');
    assertEq(sgho.lastUpdate(), effectiveAt, 'lastUpdate must reflect the due update');
    assertEq(sgho.targetRate(), 2000, 'targetRate must reflect the due update');
    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 0, 'A due update is no longer pending');
    assertEq(pendingEffectiveAt, 0, 'A due update is no longer pending');

    // While raw storage is untouched (lazy application)
    (uint120 rawIndex, uint40 rawLastUpdate, uint16 rawRate, uint40 rawEffectiveAt, ) = _rawStorage(
      sgho
    );
    assertEq(rawIndex, index0, 'Raw index must be untouched');
    assertEq(rawLastUpdate, lastUpdateBefore, 'Raw lastUpdate must be untouched');
    assertEq(rawRate, 1000, 'Raw rate must be untouched');
    assertEq(rawEffectiveAt, effectiveAt, 'Raw pending timestamp must be untouched');
  }

  function test_schedule_operationsDoNotPersistDueUpdate() external {
    uint40 lastUpdateBefore = uint40(block.timestamp);
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 30 days);

    // Deposits, withdrawals and transfers must not checkpoint, as before
    vm.startPrank(user1);
    sgho.deposit(100 ether, user1);
    sgho.withdraw(10 ether, user1, user1);
    sgho.transfer(user2, 1 ether);
    vm.stopPrank();

    (, uint40 rawLastUpdate, uint16 rawRate, uint40 rawEffectiveAt, ) = _rawStorage(sgho);
    assertEq(rawLastUpdate, lastUpdateBefore, 'Operations must not checkpoint');
    assertEq(rawRate, 1000, 'Operations must not apply the pending rate');
    assertEq(rawEffectiveAt, effectiveAt, 'Operations must not clear the pending rate');
  }

  function test_schedule_conversionsUseDueUpdateIndex() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 5 days);
    uint256 liveIndex = _emulateYieldIndex(_emulateYieldIndex(index0, 1000, 10 days), 2000, 5 days);

    vm.prank(user1);
    uint256 shares = sgho.deposit(100 ether, user1);
    assertEq(shares, (100 ether * RAY) / liveIndex, 'Deposit must convert at the live index');
    assertEq(sgho.previewRedeem(shares), (shares * liveIndex) / RAY, 'Redeem preview mismatch');
  }

  // ========================================
  // PERSISTENCE OF A DUE UPDATE
  // ========================================

  function test_schedule_dueUpdatePersistedOnNextImmediateSet() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 30 days);
    uint256 indexAtEffective = _emulateYieldIndex(index0, 1000, 10 days);
    uint256 indexNow = _emulateYieldIndex(indexAtEffective, 2000, 30 days);

    // The due update is checkpointed at its effective timestamp, then the new rate at `now`
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(effectiveAt, indexAtEffective);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(block.timestamp, indexNow);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.TargetRateUpdated(3000, block.timestamp);
    vm.prank(yManager);
    sgho.setTargetRate(3000);

    (
      uint120 rawIndex,
      uint40 rawLastUpdate,
      uint16 rawRate,
      uint40 rawEffectiveAt,
      uint16 rawPendingRate
    ) = _rawStorage(sgho);
    assertEq(rawIndex, indexNow, 'Index not persisted');
    assertEq(rawLastUpdate, block.timestamp, 'lastUpdate not persisted');
    assertEq(rawRate, 3000, 'Rate not persisted');
    assertEq(rawEffectiveAt, 0, 'Pending timestamp not cleared');
    assertEq(rawPendingRate, 0, 'Pending rate not cleared');
  }

  function test_schedule_dueUpdatePersistedOnNextSchedule() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 30 days);
    uint256 indexAtEffective = _emulateYieldIndex(index0, 1000, 10 days);
    uint40 nextEffectiveAt = uint40(block.timestamp + 10 days);

    // Scheduling persists the due update at its effective timestamp, without a checkpoint at `now`
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.ExchangeRateUpdated(effectiveAt, indexAtEffective);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.TargetRateUpdated(3000, nextEffectiveAt);
    vm.prank(yManager);
    sgho.setTargetRate(3000, nextEffectiveAt);

    (
      uint120 rawIndex,
      uint40 rawLastUpdate,
      uint16 rawRate,
      uint40 rawEffectiveAt,
      uint16 rawPendingRate
    ) = _rawStorage(sgho);
    assertEq(rawIndex, indexAtEffective, 'Index not checkpointed at the effective timestamp');
    assertEq(rawLastUpdate, effectiveAt, 'lastUpdate must be the effective timestamp');
    assertEq(rawRate, 2000, 'Due rate not persisted');
    assertEq(rawEffectiveAt, nextEffectiveAt, 'New pending timestamp not stored');
    assertEq(rawPendingRate, 3000, 'New pending rate not stored');
  }

  // ========================================
  // OVERWRITING A PENDING UPDATE
  // ========================================

  function test_schedule_overwritesPendingBeforeEffective() external {
    uint256 index0 = sgho.yieldIndex();
    uint40 effectiveAt1 = uint40(block.timestamp + 10 days);
    uint40 effectiveAt2 = uint40(block.timestamp + 20 days);

    vm.startPrank(yManager);
    sgho.setTargetRate(2000, effectiveAt1);
    sgho.setTargetRate(3000, effectiveAt2);
    vm.stopPrank();

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 3000, 'Last scheduled rate must win');
    assertEq(pendingEffectiveAt, effectiveAt2, 'Last scheduled timestamp must win');

    // The overwritten update must never take effect
    vm.warp(effectiveAt1 + 1 days);
    assertEq(sgho.targetRate(), 1000, 'Overwritten update must not take effect');

    vm.warp(effectiveAt2 + 365 days);
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(_emulateYieldIndex(index0, 1000, 20 days), 3000, 365 days),
      'Accrual must follow the overwriting schedule only'
    );
  }

  function test_schedule_immediateSetDiscardsPending() external {
    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.startPrank(yManager);
    sgho.setTargetRate(2000, effectiveAt);
    sgho.setTargetRate(1500);
    vm.stopPrank();

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 0, 'Pending rate not discarded');
    assertEq(pendingEffectiveAt, 0, 'Pending timestamp not discarded');
    assertEq(sgho.targetRate(), 1500, 'Immediate rate not applied');

    vm.warp(effectiveAt + 1 days);
    assertEq(sgho.targetRate(), 1500, 'Discarded update must not take effect');
  }

  // ========================================
  // CROSS-CHAIN SYNC PROPERTIES
  // ========================================

  /// @dev Two deployments receiving the same scheduled updates at different execution times
  /// (multi-chain AIP skew) must hold a bit-identical index at all times.
  function test_schedule_crossChainDeterminism() external {
    sGho chainA = _deploySGho();
    sGho chainB = _deploySGho();
    vm.startPrank(yManager);
    chainA.setTargetRate(1000);
    chainB.setTargetRate(1000);
    vm.stopPrank();

    uint40 effectiveAt1 = uint40(block.timestamp + 10 days);
    uint40 effectiveAt2 = uint40(block.timestamp + 20 days);

    // First AIP: chain A executes 1 day before chain B
    vm.prank(yManager);
    chainA.setTargetRate(2000, effectiveAt1);
    vm.warp(block.timestamp + 1 days);
    vm.prank(yManager);
    chainB.setTargetRate(2000, effectiveAt1);
    _assertInSync(chainA, chainB);

    // Second AIP, executed after the first is effective: persists the first checkpoint,
    // again at skewed execution times
    vm.warp(effectiveAt1 + 1 days);
    vm.prank(yManager);
    chainA.setTargetRate(3000, effectiveAt2);
    _assertInSync(chainA, chainB);
    vm.warp(block.timestamp + 1 days);
    vm.prank(yManager);
    chainB.setTargetRate(3000, effectiveAt2);
    _assertInSync(chainA, chainB);

    // Both chains persisted the first checkpoint at different times, yet raw storage is identical
    (
      uint120 rawIndexA,
      uint40 rawLastUpdateA,
      uint16 rawRateA,
      uint40 rawEffectiveAtA,
      uint16 rawPendingRateA
    ) = _rawStorage(chainA);
    (
      uint120 rawIndexB,
      uint40 rawLastUpdateB,
      uint16 rawRateB,
      uint40 rawEffectiveAtB,
      uint16 rawPendingRateB
    ) = _rawStorage(chainB);
    assertEq(rawIndexA, rawIndexB, 'Raw index diverged');
    assertEq(rawLastUpdateA, rawLastUpdateB, 'Raw lastUpdate diverged');
    assertEq(rawRateA, rawRateB, 'Raw rate diverged');
    assertEq(rawEffectiveAtA, rawEffectiveAtB, 'Raw pending timestamp diverged');
    assertEq(rawPendingRateA, rawPendingRateB, 'Raw pending rate diverged');

    // In sync through the second effective timestamp
    vm.warp(effectiveAt2);
    _assertInSync(chainA, chainB);

    // Third AIP: a same-rate re-schedule also checkpoints (splitting the floored accrual), so it
    // must be mirrored on every chain like any other update
    uint40 effectiveAt3 = uint40(block.timestamp + 30 days);
    vm.prank(yManager);
    chainA.setTargetRate(3000, effectiveAt3);
    _assertInSync(chainA, chainB);
    vm.warp(block.timestamp + 1 days);
    vm.prank(yManager);
    chainB.setTargetRate(3000, effectiveAt3);
    _assertInSync(chainA, chainB);

    vm.warp(effectiveAt3 + 365 days);
    _assertInSync(chainA, chainB);
  }

  function test_schedule_crossChainDeterminism_fuzz(
    uint16 rate1,
    uint16 rate2,
    uint32 executionSkew,
    uint32 timeToEffective,
    uint32 timeAfterEffective
  ) external {
    rate1 = uint16(bound(rate1, 0, MAX_SAFE_RATE));
    rate2 = uint16(bound(rate2, 0, MAX_SAFE_RATE));
    timeToEffective = uint32(bound(timeToEffective, 1, 30 days));
    executionSkew = uint32(bound(executionSkew, 0, timeToEffective - 1));
    timeAfterEffective = uint32(bound(timeAfterEffective, 0, 3650 days));

    sGho chainA = _deploySGho();
    sGho chainB = _deploySGho();
    vm.startPrank(yManager);
    chainA.setTargetRate(rate1);
    chainB.setTargetRate(rate1);
    vm.stopPrank();

    // Both chains schedule the same update with the same effective timestamp, at skewed times
    uint40 effectiveAt = uint40(block.timestamp + timeToEffective);
    vm.prank(yManager);
    chainA.setTargetRate(rate2, effectiveAt);
    vm.warp(block.timestamp + executionSkew);
    vm.prank(yManager);
    chainB.setTargetRate(rate2, effectiveAt);
    _assertInSync(chainA, chainB);

    vm.warp(effectiveAt + timeAfterEffective);
    // Persist on chain A only (via a same-rate schedule far in the future); chain B stays lazy
    vm.prank(yManager);
    chainA.setTargetRate(rate2, uint40(block.timestamp + 365 days));
    _assertInSync(chainA, chainB);

    vm.warp(block.timestamp + 180 days);
    _assertInSync(chainA, chainB);
  }

  function _assertInSync(sGho chainA, sGho chainB) internal view {
    assertEq(chainA.convertToAssets(RAY), chainB.convertToAssets(RAY), 'Live index diverged');
    assertEq(chainA.yieldIndex(), chainB.yieldIndex(), 'Checkpoint index diverged');
    assertEq(chainA.lastUpdate(), chainB.lastUpdate(), 'Checkpoint timestamp diverged');
    assertEq(chainA.targetRate(), chainB.targetRate(), 'Rate diverged');
  }

  // ========================================
  // CONTINUITY & CONSISTENCY
  // ========================================

  function test_schedule_indexContinuity_fuzz(uint16 newRate, uint32 timeAfterEffective) external {
    newRate = uint16(bound(newRate, 0, MAX_SAFE_RATE));
    timeAfterEffective = uint32(bound(timeAfterEffective, 1, 365 days));

    uint40 effectiveAt = uint40(block.timestamp + 10 days);
    vm.prank(yManager);
    sgho.setTargetRate(newRate, effectiveAt);

    vm.warp(effectiveAt - 1);
    uint256 indexJustBefore = sgho.convertToAssets(RAY);
    vm.warp(effectiveAt);
    uint256 indexAtEffective = sgho.convertToAssets(RAY);
    vm.warp(effectiveAt + timeAfterEffective);
    uint256 indexAfter = sgho.convertToAssets(RAY);

    // The index never jumps or decreases across the rate switch
    assertGe(indexAtEffective, indexJustBefore, 'Index decreased at the effective timestamp');
    // At most one second of old-rate accrual, plus one wei of flooring drift
    assertLe(
      indexAtEffective - indexJustBefore,
      _emulateYieldIndex(RAY, 1000, 1) - RAY + 1,
      'Index jumped at the effective timestamp'
    );
    assertGe(indexAfter, indexAtEffective, 'Index decreased after the effective timestamp');
  }

  function test_schedule_holderValueGrowsThroughRateSwitch() external {
    vm.prank(user1);
    sgho.deposit(100 ether, user1);
    uint256 shares = sgho.balanceOf(user1);

    uint40 effectiveAt = uint40(block.timestamp + 182 days);
    vm.prank(yManager);
    sgho.setTargetRate(2000, effectiveAt);

    // 182 days at 10% + 183 days at 20%, linear across the switch
    vm.warp(block.timestamp + 365 days);
    uint256 expectedIndex = _emulateYieldIndex(
      _emulateYieldIndex(RAY, 1000, 182 days),
      2000,
      183 days
    );
    assertEq(
      sgho.previewRedeem(shares),
      (shares * expectedIndex) / RAY,
      'Holder value must accrue linearly across the rate switch'
    );
  }
}
