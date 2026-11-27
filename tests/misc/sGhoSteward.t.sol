// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {TestSGhoBase} from '../unit/TestSGhoBase.t.sol';

import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import {sGho, IsGho} from 'src/contracts/sgho/sGho.sol';
import {sGhoSteward, IsGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';

contract sGhoStewardTest is TestSGhoBase {
  using SafeCast for uint256;

  sGhoSteward public steward;

  address public riskCouncil = makeAddr('riskCouncil');
  address public governance = makeAddr('governance');

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
  bytes32 public constant RATE_MANAGER_ROLE = keccak256('RATE_MANAGER_ROLE');
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');

  function setUp() public override {
    super.setUp();

    steward = new sGhoSteward(governance, riskCouncil, address(sgho));
    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), address(steward));
  }

  // ========================================
  // SETUP & ACCESS CONTROL
  // ========================================

  function test_wrongSetUp() public {
    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(address(0), riskCouncil, address(sgho));

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(governance, address(0), address(sgho));

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(governance, riskCouncil, address(0));
  }

  function test_initial() public view {
    assertEq(steward.RATE_MANAGER_ROLE(), RATE_MANAGER_ROLE);
    assertEq(steward.SUPPLY_CAP_MANAGER_ROLE(), SUPPLY_CAP_MANAGER_ROLE);

    assertTrue(steward.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertFalse(steward.hasRole(DEFAULT_ADMIN_ROLE, riskCouncil));

    assertTrue(steward.hasRole(RATE_MANAGER_ROLE, riskCouncil));
    assertTrue(steward.hasRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil));

    assertFalse(steward.hasRole(RATE_MANAGER_ROLE, governance));
    assertFalse(steward.hasRole(SUPPLY_CAP_MANAGER_ROLE, governance));

    assertEq(address(steward.sGHO()), address(sgho));
  }

  function test_riskCouncilCannotGrantRoles() public {
    address user = makeAddr('user');

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(RATE_MANAGER_ROLE, user);

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(SUPPLY_CAP_MANAGER_ROLE, user);
  }

  function test_revert_setTargetRate_notRateManager(address caller) public {
    vm.assume(caller != riskCouncil);

    vm.expectRevert(_craftError(caller, RATE_MANAGER_ROLE));
    vm.prank(caller);
    steward.setTargetRate(2000, block.timestamp.toUint40());
  }

  function test_revert_setTargetRate_afterRoleRevoked() public {
    vm.prank(governance);
    steward.revokeRole(RATE_MANAGER_ROLE, riskCouncil);

    vm.expectRevert(_craftError(riskCouncil, RATE_MANAGER_ROLE));
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, block.timestamp.toUint40());
  }

  // ========================================
  // TARGET RATE
  // ========================================

  function test_setTargetRate_immediate() public {
    vm.warp(block.timestamp + 30 days);
    uint256 indexBefore = sgho.convertToAssets(RAY);

    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.TargetRateUpdated(riskCouncil, 400, block.timestamp.toUint40());
    vm.prank(riskCouncil);
    steward.setTargetRate(400, block.timestamp.toUint40());

    assertEq(sgho.targetRate(), 400, 'Rate not applied');
    assertEq(sgho.yieldIndex(), indexBefore, 'Index not checkpointed at the old rate');
    assertEq(sgho.lastUpdate(), block.timestamp, 'Checkpoint not taken now');
  }

  function test_setTargetRate_scheduled() public {
    uint40 effectiveAt = (block.timestamp + 1 days).toUint40();

    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.TargetRateUpdated(riskCouncil, 400, effectiveAt);
    vm.prank(riskCouncil);
    steward.setTargetRate(400, effectiveAt);

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 400);
    assertEq(pendingEffectiveAt, effectiveAt);
    assertEq(sgho.targetRate(), 1000);

    vm.warp(effectiveAt);
    assertEq(sgho.targetRate(), 400);
  }

  function test_setTargetRate_fuzz(uint16 rate, uint32 delay) public {
    rate = (bound(rate, 0, MAX_SAFE_RATE)).toUint16();
    vm.assume(rate != sgho.targetRate());
    uint40 effectiveAt = (block.timestamp + delay).toUint40();

    vm.prank(riskCouncil);
    steward.setTargetRate(rate, effectiveAt);

    vm.warp(effectiveAt);
    assertEq(sgho.targetRate(), rate, 'Rate not in force at effectiveAt');
  }

  function test_revert_setTargetRate_pastEffectiveAt() public {
    vm.expectRevert(IsGho.EffectiveTimestampInPast.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(400, (block.timestamp - 1).toUint40());
  }

  function test_revert_setTargetRate_aboveMax(uint16 rate) public {
    rate = (bound(rate, uint256(MAX_SAFE_RATE) + 1, type(uint16).max)).toUint16();

    vm.expectRevert(IsGho.MaxRateExceeded.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(rate, block.timestamp.toUint40());
  }

  // ========================================
  // SAME-RATE UPDATES
  // ========================================

  function test_revert_setTargetRate_unchanged() public {
    vm.expectRevert(IsGhoSteward.RateUnchanged.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(1000, block.timestamp.toUint40());

    vm.expectRevert(IsGhoSteward.RateUnchanged.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(1000, (block.timestamp + 1 days).toUint40());
  }

  /// @dev A due update counts as in force even before sGho persists it
  function test_revert_setTargetRate_unchangedAfterDueUpdate() public {
    uint40 effectiveAt = (block.timestamp + 1 days).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt + 1);
    (, , , uint40 rawEffectiveAt, ) = _rawStorage(sgho);
    assertEq(rawEffectiveAt, effectiveAt, 'Update already persisted');

    vm.expectRevert(IsGhoSteward.RateUnchanged.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, (block.timestamp + 1 days).toUint40());
  }

  /// @dev The rate in force is rejected even with an update pending; cancelling goes through
  /// `cancelTargetRate`
  function test_revert_setTargetRate_currentRateWithPending() public {
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);

    vm.expectRevert(IsGhoSteward.RateUnchanged.selector);
    vm.prank(riskCouncil);
    steward.setTargetRate(1000, effectiveAt);
  }

  /// @dev Passing the pending rate again with another timestamp moves it
  function test_setTargetRate_pendingRateRescheduled() public {
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    uint40 laterEffectiveAt = (block.timestamp + 20 days).toUint40();
    vm.startPrank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);
    steward.setTargetRate(2000, laterEffectiveAt);
    vm.stopPrank();

    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 2000);
    assertEq(pendingEffectiveAt, laterEffectiveAt);

    vm.warp(effectiveAt);
    assertEq(sgho.targetRate(), 1000, 'Moved update applied early');
    vm.warp(laterEffectiveAt);
    assertEq(sgho.targetRate(), 2000, 'Moved update not applied');
  }

  /// @dev The steward reverts on a same-rate update exactly when the rate is in force, whatever
  /// is scheduled
  function test_setTargetRate_unchangedRule_fuzz(
    uint16 scheduledRate,
    uint16 newRate,
    uint32 delay,
    uint32 elapsed
  ) public {
    scheduledRate = (bound(scheduledRate, 0, MAX_SAFE_RATE)).toUint16();
    // Hit the rate in force before and after the update as often as any other rate
    uint256 pick = newRate % 3;
    newRate = pick == 0 ? 1000 : pick == 1
      ? scheduledRate
      : (bound(newRate, 0, MAX_SAFE_RATE)).toUint16();
    delay = (bound(delay, 1, 365 days)).toUint32();
    elapsed = (bound(elapsed, 0, 730 days)).toUint32();
    vm.assume(scheduledRate != sgho.targetRate());

    uint40 effectiveAt = (block.timestamp + delay).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(scheduledRate, effectiveAt);
    vm.warp(block.timestamp + elapsed);

    uint16 rateInForce = block.timestamp < effectiveAt ? 1000 : scheduledRate;
    if (newRate == rateInForce) {
      vm.expectRevert(IsGhoSteward.RateUnchanged.selector);
    }
    vm.prank(riskCouncil);
    steward.setTargetRate(newRate, (block.timestamp + 1 days).toUint40());
  }

  // ========================================
  // CANCEL
  // ========================================

  function test_cancelTargetRate() public {
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);
    (uint120 rawIndex, uint40 rawLastUpdate, uint16 rawRate, , ) = _rawStorage(sgho);

    vm.warp(block.timestamp + 1 days);
    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.PendingTargetRateCancelled(2000, effectiveAt);
    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.TargetRateCancelled(riskCouncil);
    vm.prank(riskCouncil);
    steward.cancelTargetRate();

    // The pending update is gone and the checkpoint is untouched
    (uint16 pendingRate, uint40 pendingEffectiveAt) = sgho.pendingTargetRate();
    assertEq(pendingRate, 0, 'Pending rate not cleared');
    assertEq(pendingEffectiveAt, 0, 'Pending timestamp not cleared');
    assertEq(
      _encodeRawStorage(sgho),
      abi.encode(rawIndex, rawLastUpdate, rawRate, uint40(0), uint16(0)),
      'Cancel must only clear the pending update'
    );

    // Accrual is exactly as if nothing had been scheduled
    vm.warp(effectiveAt + 365 days);
    assertEq(sgho.targetRate(), 1000, 'Cancelled rate applied');
    assertEq(
      sgho.convertToAssets(RAY),
      _emulateYieldIndex(rawIndex, 1000, block.timestamp - rawLastUpdate),
      'Accrual differs from never scheduling'
    );
  }

  function test_revert_cancelTargetRate_notRateManager(address caller) public {
    vm.assume(caller != riskCouncil);
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, (block.timestamp + 10 days).toUint40());

    vm.expectRevert(_craftError(caller, RATE_MANAGER_ROLE));
    vm.prank(caller);
    steward.cancelTargetRate();
  }

  function test_revert_cancelTargetRate_nothingPending() public {
    vm.expectRevert(IsGho.NoPendingTargetRate.selector);
    vm.prank(riskCouncil);
    steward.cancelTargetRate();
  }

  /// @dev A due update is effective even before sGho persists it, so it cannot be cancelled
  function test_revert_cancelTargetRate_alreadyEffective() public {
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);

    vm.warp(effectiveAt);
    vm.expectRevert(IsGho.NoPendingTargetRate.selector);
    vm.prank(riskCouncil);
    steward.cancelTargetRate();

    // Persisted by a deposit, still not cancellable
    vm.warp(effectiveAt + 1 days);
    vm.prank(user1);
    sgho.deposit(1 ether, user1);
    vm.expectRevert(IsGho.NoPendingTargetRate.selector);
    vm.prank(riskCouncil);
    steward.cancelTargetRate();
    assertEq(sgho.targetRate(), 2000, 'Effective rate lost');
  }

  function test_cancelTargetRate_thenReschedule() public {
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    vm.startPrank(riskCouncil);
    steward.setTargetRate(2000, effectiveAt);
    steward.cancelTargetRate();
    steward.setTargetRate(3000, effectiveAt);
    vm.stopPrank();

    vm.warp(effectiveAt);
    assertEq(sgho.targetRate(), 3000, 'Rescheduled rate not applied');
  }

  // ========================================
  // SUPPLY CAP
  // ========================================

  function test_supplyCap() public {
    uint256 initialSupplyCap = sgho.supplyCap();
    assertEq(initialSupplyCap, SUPPLY_CAP_UNITS);

    vm.expectEmit(true, true, true, true, address(sgho));
    emit IsGho.SupplyCapUpdated(type(uint40).max);
    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.SupplyCapUpdated(riskCouncil, type(uint40).max);
    vm.prank(riskCouncil);
    steward.setSupplyCap(type(uint40).max);

    uint256 supplyCapAfterUpdate = sgho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint40).max);

    vm.prank(governance);
    steward.revokeRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);

    vm.startPrank(riskCouncil);

    vm.expectRevert(_craftError(riskCouncil, SUPPLY_CAP_MANAGER_ROLE));
    steward.setSupplyCap(1e6);
  }

  function test_invalidSupplyCap(uint256 newSupplyCap) public {
    newSupplyCap = bound(newSupplyCap, uint256(type(uint40).max) + 1, type(uint256).max);

    uint256 initialSupplyCap = sgho.supplyCap();
    assertEq(initialSupplyCap, SUPPLY_CAP_UNITS);

    vm.startPrank(riskCouncil);

    steward.setSupplyCap(type(uint40).max);

    uint256 supplyCapAfterUpdate = sgho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint40).max);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.SupplyCapUnchanged.selector));
    steward.setSupplyCap(type(uint40).max);

    vm.expectRevert(
      abi.encodeWithSignature('SafeCastOverflowedUintDowncast(uint8,uint256)', 40, newSupplyCap)
    );
    steward.setSupplyCap(newSupplyCap);
  }

  // ========================================
  // MULTI-CHAIN
  // ========================================

  /// @dev A new chain cold-started from a live checkpoint, rate included, stays in sync with no
  /// steward call of its own; the first rate change scheduled on both stewards keeps them in sync.
  function test_coldStart_staysInSyncThroughMirroredUpdate() public {
    vm.warp(block.timestamp + 180 days);
    (sGho l2, sGhoSteward l2Steward) = _coldStartFrom(sgho);
    assertEq(l2.convertToAssets(RAY), sgho.convertToAssets(RAY), 'Not in sync at deployment');

    vm.warp(block.timestamp + 100 days);
    assertEq(l2.convertToAssets(RAY), sgho.convertToAssets(RAY), 'Diverged before any update');

    // One rate change scheduled on both stewards at the same effectiveAt, executed 12h apart
    uint256 checkpointIndex = sgho.yieldIndex();
    uint256 checkpointTime = sgho.lastUpdate();
    uint40 effectiveAt = (block.timestamp + 1 days).toUint40();
    vm.prank(riskCouncil);
    steward.setTargetRate(1500, effectiveAt);
    vm.warp(block.timestamp + 12 hours);
    vm.prank(riskCouncil);
    l2Steward.setTargetRate(1500, effectiveAt);

    vm.warp(effectiveAt + 365 days);
    uint256 expectedIndex = _emulateYieldIndex(
      _emulateYieldIndex(checkpointIndex, 1000, effectiveAt - checkpointTime),
      1500,
      365 days
    );
    assertEq(sgho.convertToAssets(RAY), expectedIndex, 'Source index off spec');
    assertEq(l2.convertToAssets(RAY), expectedIndex, 'L2 index off spec');
    assertEq(l2.targetRate(), 1500, 'L2 rate not applied');
  }

  /// @dev Setting a rate through the new chain's steward on its own checkpoints that chain only,
  /// so it accrues on a different base than the source from then on.
  function test_coldStart_standaloneStewardUpdateDesyncs() public {
    vm.warp(block.timestamp + 180 days);
    (sGho l2, sGhoSteward l2Steward) = _coldStartFrom(sgho);

    vm.prank(riskCouncil);
    l2Steward.setTargetRate(1200, block.timestamp.toUint40());

    vm.warp(block.timestamp + 365 days);
    assertTrue(
      l2.convertToAssets(RAY) != sgho.convertToAssets(RAY),
      'A standalone update must desync'
    );
  }

  /// @dev Two chains receive the same steward calls at skewed times, each strictly before the
  /// effective timestamp and after the previous one, including cancels. Both chains accept or
  /// both reject every call, and their indexes match each other and the schedule.
  function test_stewards_crossChain_fuzz(uint256 seed) public {
    (sGho l2, sGhoSteward l2Steward) = _coldStartFrom(sgho);
    uint256 expectedIndex = sgho.yieldIndex();
    uint256 from = sgho.lastUpdate();
    uint16 rate = sgho.targetRate();

    for (uint256 k = 0; k < 5; k++) {
      uint256 roundSeed = uint256(keccak256(abi.encode(seed, k)));
      uint256 effectiveAt = block.timestamp + bound(roundSeed, 2, 90 days);
      // One in three rounds repeats the rate in force, which both stewards must reject
      uint16 newRate = (roundSeed >> 64) % 3 == 0
        ? rate
        : (bound(roundSeed >> 128, 0, MAX_SAFE_RATE)).toUint16();

      bool applied = _crossChainRound({
        l2Steward: l2Steward,
        roundSeed: roundSeed,
        newRate: newRate,
        effectiveAt: effectiveAt,
        rateInForce: rate
      });

      vm.warp(effectiveAt);
      if (applied) {
        expectedIndex = _emulateYieldIndex(expectedIndex, rate, effectiveAt - from);
        from = effectiveAt;
        rate = newRate;
      }
      vm.warp(effectiveAt + bound(roundSeed >> 160, 0, 30 days));
      uint256 live = _emulateYieldIndex(expectedIndex, rate, block.timestamp - from);
      assertEq(sgho.convertToAssets(RAY), live, 'Source index off spec');
      assertEq(l2.convertToAssets(RAY), live, 'L2 index off spec');
    }
  }

  /// @dev Runs one round of mirrored steward calls and returns whether the update stays scheduled.
  /// One in three accepted updates is then cancelled on both chains, at skewed times after both
  /// executions and before it is effective.
  function _crossChainRound(
    sGhoSteward l2Steward,
    uint256 roundSeed,
    uint16 newRate,
    uint256 effectiveAt,
    uint16 rateInForce
  ) internal returns (bool) {
    uint256 execA = block.timestamp + ((roundSeed >> 32) % (effectiveAt - block.timestamp));
    uint256 execB = block.timestamp + ((roundSeed >> 96) % (effectiveAt - block.timestamp));

    bool acceptedA;
    bool acceptedB;
    if (execA <= execB) {
      acceptedA = _stewardCallAt(steward, newRate, effectiveAt, execA);
      acceptedB = _stewardCallAt(l2Steward, newRate, effectiveAt, execB);
    } else {
      acceptedB = _stewardCallAt(l2Steward, newRate, effectiveAt, execB);
      acceptedA = _stewardCallAt(steward, newRate, effectiveAt, execA);
    }
    assertEq(acceptedA, acceptedB, 'Chains disagreed on the same call');
    assertEq(acceptedA, newRate != rateInForce, 'Same-rate rule not applied');
    if (!acceptedA || (roundSeed >> 200) % 3 != 0) return acceptedA;

    uint256 lastExec = execA > execB ? execA : execB;
    uint256 cancelA = lastExec + ((roundSeed >> 208) % (effectiveAt - lastExec));
    uint256 cancelB = lastExec + ((roundSeed >> 216) % (effectiveAt - lastExec));
    if (cancelA <= cancelB) {
      _stewardCancelAt(steward, cancelA);
      _stewardCancelAt(l2Steward, cancelB);
    } else {
      _stewardCancelAt(l2Steward, cancelB);
      _stewardCancelAt(steward, cancelA);
    }
    return false;
  }

  // ========================================
  // HELPERS
  // ========================================

  /// @dev Calls the steward at `timestamp` and returns whether it accepted the update.
  function _stewardCallAt(
    sGhoSteward target,
    uint16 rate,
    uint256 effectiveAt,
    uint256 timestamp
  ) internal returns (bool accepted) {
    vm.warp(timestamp);
    vm.prank(riskCouncil);
    try target.setTargetRate(rate, effectiveAt.toUint40()) {
      accepted = true;
    } catch (bytes memory reason) {
      assertEq(bytes4(reason), IsGhoSteward.RateUnchanged.selector, 'Unexpected revert');
    }
  }

  function _encodeRawStorage(sGho target) internal view returns (bytes memory) {
    (
      uint120 index,
      uint40 lastUpdate_,
      uint16 rate,
      uint40 pendingEffectiveAt,
      uint16 pendingRate
    ) = _rawStorage(target);
    return abi.encode(index, lastUpdate_, rate, pendingEffectiveAt, pendingRate);
  }

  function _stewardCancelAt(sGhoSteward target, uint256 timestamp) internal {
    vm.warp(timestamp);
    vm.prank(riskCouncil);
    target.cancelTargetRate();
  }

  function _craftError(address account, bytes32 role) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        account,
        role
      );
  }

  function _coldStartFrom(sGho source) internal returns (sGho l2, sGhoSteward l2Steward) {
    l2 = _deploySGho(
      source.yieldIndex().toUint120(),
      source.lastUpdate().toUint40(),
      source.targetRate()
    );
    l2Steward = new sGhoSteward(governance, riskCouncil, address(l2));
    l2.grantRole(l2.YIELD_MANAGER_ROLE(), address(l2Steward));
  }
}
