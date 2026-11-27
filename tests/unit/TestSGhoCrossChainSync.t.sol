// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

/// @dev Several sGho deployments stand in for chains. They receive the same scheduled rate updates
/// at different execution times, and users act on each chain at different times and frequencies.
/// The yield index must stay bit-identical across chains and equal to the index derived from the
/// schedule alone.
contract TestSGhoCrossChainSync is TestSGhoBase {
  using SafeCast for uint256;

  uint256 internal constant CHAINS = 3;
  uint256 internal constant ROUNDS = 6;
  uint256 internal constant MAX_ACTIONS_PER_ROUND = 6;

  struct Event {
    uint256 time;
    uint256 chain;
    bool isSchedule;
    uint256 seed;
  }

  sGho[] internal chains;
  address[] internal actors;

  // The schedule, as the reference model sees it
  uint40 internal genesis;
  uint16 internal genesisRate;
  uint40[] internal effectiveAts;
  uint16[] internal scheduledRates;

  // ========================================
  // RANDOM SCHEDULES AND ACTIONS
  // ========================================

  /// @dev Each round schedules one update on every chain, at a random time between the previous
  /// effective timestamp and the new one, while each chain sees its own random number of user
  /// actions at random times. The sync is checked after every single event.
  function test_crossChain_randomSchedulesAndActions_fuzz(uint256 seed) external {
    _deployChains(_rate(seed, 0));

    for (uint256 round = 0; round < ROUNDS; round++) {
      uint256 roundSeed = uint256(keccak256(abi.encode(seed, round)));
      uint256 start = block.timestamp;
      uint256 effectiveAt = start + bound(roundSeed, 1 hours, 120 days);
      // Repeating the current rate and switching to 0 are both covered
      uint16 rate = (roundSeed >> 128) % 4 == 0 ? _currentScheduledRate() : _rate(roundSeed, 1);

      effectiveAts.push(effectiveAt.toUint40());
      scheduledRates.push(rate);

      Event[] memory events = _roundEvents({
        roundSeed: roundSeed,
        start: start,
        effectiveAt: effectiveAt
      });
      for (uint256 i = 0; i < events.length; i++) {
        vm.warp(events[i].time);
        if (events[i].isSchedule) {
          vm.prank(yManager);
          chains[events[i].chain].setTargetRate(rate, effectiveAt.toUint40());
        } else {
          _act(chains[events[i].chain], events[i].seed);
        }
        _assertAllInSync();
      }

      vm.warp(effectiveAt);
      _assertAllInSync();
    }

    vm.warp(block.timestamp + bound(seed >> 64, 0, 3650 days));
    _assertAllInSync();
  }

  // ========================================
  // ACTION FREQUENCY
  // ========================================

  /// @dev Chain 0 sees an action every 6 hours, chain 1 none at all, and chain 2 one action at
  /// each effective timestamp and the seconds around it.
  function test_crossChain_actionFrequencyExtremes() external {
    _deployChains(1000);
    uint16[4] memory rates = [uint16(2500), 2500, 0, 4000];

    for (uint256 k = 0; k < rates.length; k++) {
      uint256 start = block.timestamp;
      uint256 effectiveAt = start + 30 days;
      effectiveAts.push(effectiveAt.toUint40());
      scheduledRates.push(rates[k]);

      // Chains execute the schedule 10 days apart, while chain 0 sees an action every 6 hours
      uint256 scheduled;
      for (uint256 t = start; t < effectiveAt; t += 6 hours) {
        vm.warp(t);
        if (scheduled < CHAINS && t == start + scheduled * 10 days) {
          vm.prank(yManager);
          chains[scheduled++].setTargetRate(rates[k], effectiveAt.toUint40());
        }
        _act(chains[0], uint256(keccak256(abi.encode(k, t))));
        _assertAllInSync();
      }

      // Chain 2: actions one second before, at and one second after the effective timestamp
      for (uint256 t = effectiveAt - 1; t <= effectiveAt + 1; t++) {
        vm.warp(t);
        _act(chains[2], uint256(keccak256(abi.encode(k, t, 'boundary'))));
        _assertAllInSync();
      }
    }

    vm.warp(block.timestamp + 365 days);
    _assertAllInSync();
  }

  /// @dev A deposit a day after the effective timestamp persists the update as of that
  /// timestamp, against a chain that only reads it lazily a year later.
  function test_crossChain_persistLateVsLazy() external {
    _deployChains(1000);
    uint40 effectiveAt = (block.timestamp + 10 days).toUint40();
    _scheduleOnAll(3000, effectiveAt);

    vm.warp(effectiveAt + 1 days);
    _act(chains[0], 0); // deposit
    (, uint40 persistedAt, , , ) = _rawStorage(chains[0]);
    assertEq(persistedAt, effectiveAt, 'Not persisted as of the effective timestamp');
    (, uint40 lazyAt, , , ) = _rawStorage(chains[1]);
    assertEq(lazyAt, genesis, 'Lazy chain persisted');
    _assertAllInSync();

    vm.warp(effectiveAt + 365 days);
    _assertAllInSync();
  }

  // ========================================
  // EXECUTION SKEW
  // ========================================

  /// @dev One chain executes the schedule a second before it is effective, another months
  /// before it.
  function test_crossChain_executionSkewUpToTheLastSecond() external {
    _deployChains(1000);
    uint40 effectiveAt = (block.timestamp + 180 days).toUint40();

    vm.prank(yManager);
    chains[0].setTargetRate(2000, effectiveAt);
    _act(chains[0], 1);
    vm.warp(effectiveAt - 1);
    vm.prank(yManager);
    chains[1].setTargetRate(2000, effectiveAt);
    vm.prank(yManager);
    chains[2].setTargetRate(2000, effectiveAt);
    _assertAllInSync();

    effectiveAts.push(effectiveAt);
    scheduledRates.push(2000);
    vm.warp(effectiveAt + 365 days);
    _assertAllInSync();
  }

  /// @dev Pausing blocks deposits and withdrawals on one chain, so it persists nothing, while the
  /// schedule still executes there.
  function test_crossChain_pausedChainStaysInSync() external {
    _deployChains(1000);
    chains[1].pause();

    uint40 effectiveAt = (block.timestamp + 30 days).toUint40();
    _scheduleOnAll(2000, effectiveAt);
    vm.warp(effectiveAt + 1 days);
    _act(chains[0], 0);
    _assertAllInSync();

    chains[1].unpause();
    vm.warp(block.timestamp + 90 days);
    _act(chains[1], 0);
    _assertAllInSync();
  }

  // ========================================
  // OPERATIONAL RULES
  // ========================================

  /// @dev A scheduled update cancelled on every chain before it is effective, at skewed times,
  /// leaves the chains in sync and accruing as if it had never been scheduled.
  function test_crossChain_mirroredCancelStaysInSync() external {
    _deployChains(1000);
    uint40 effectiveAt = (block.timestamp + 30 days).toUint40();
    for (uint256 c = 0; c < CHAINS; c++) {
      vm.warp(genesis + c * 1 days);
      vm.prank(yManager);
      chains[c].setTargetRate(2000, effectiveAt);
      _act(chains[c], c);
    }
    for (uint256 c = 0; c < CHAINS; c++) {
      vm.warp(effectiveAt - 10 days + c * 4 days);
      vm.prank(yManager);
      chains[c].cancelPendingTargetRate();
      _act(chains[c], c + 10);
    }

    // Nothing is pushed to the schedule: the reference model accrues at the genesis rate
    vm.warp(effectiveAt + 365 days);
    _assertAllInSync();
    assertEq(chains[0].lastUpdate(), genesis, 'Cancel created a checkpoint');
  }

  /// @dev A same-rate update on one chain only checkpoints, and so rounds, its index there. The
  /// indexes then differ by rounding, so every update must be mirrored.
  function test_crossChain_unmirroredSameRateUpdateDesyncs() external {
    _deployChains(1000);
    uint40 effectiveAt = (block.timestamp + 180 days).toUint40();

    vm.prank(yManager);
    chains[0].setTargetRate(1000, effectiveAt);

    vm.warp(effectiveAt + 365 days);
    uint256 indexA = chains[0].convertToAssets(RAY);
    uint256 indexB = chains[1].convertToAssets(RAY);
    assertTrue(indexA != indexB, 'A checkpoint on one chain only must desync');
    // Only rounding, at most about one ray unit per second elapsed
    assertApproxEqAbs(indexA, indexB, 2 * (180 days + 365 days), 'Desync beyond rounding');
  }

  /// @dev An update applied immediately (`effectiveAt == block.timestamp`) is checkpointed at the
  /// chain-local execution time, so it is only suitable for single-chain deployments.
  function test_crossChain_immediateUpdatesAtDifferentTimesDesync() external {
    _deployChains(1000);
    vm.warp(block.timestamp + 30 days);
    vm.prank(yManager);
    chains[0].setTargetRate(2000, block.timestamp.toUint40());
    vm.warp(block.timestamp + 1 hours);
    vm.prank(yManager);
    chains[1].setTargetRate(2000, block.timestamp.toUint40());

    vm.warp(block.timestamp + 365 days);
    assertTrue(
      chains[0].convertToAssets(RAY) != chains[1].convertToAssets(RAY),
      'Immediate updates at different times must desync'
    );
  }

  // ========================================
  // HELPERS
  // ========================================

  function _deployChains(uint16 rate) internal {
    genesis = block.timestamp.toUint40();
    genesisRate = rate;
    actors.push(user1);
    actors.push(user2);
    actors.push(makeAddr('user3'));

    for (uint256 c = 0; c < CHAINS; c++) {
      sGho chain = _deploySGho();
      vm.prank(yManager);
      chain.setTargetRate(rate, genesis);
      // Reserve so withdrawals of accrued yield are never limited by the vault balance
      deal(address(gho), address(chain), 100_000_000 ether, true);
      for (uint256 a = 0; a < actors.length; a++) {
        vm.prank(actors[a]);
        gho.approve(address(chain), type(uint256).max);
      }
      chains.push(chain);
    }
    for (uint256 a = 0; a < actors.length; a++) {
      deal(address(gho), actors[a], 10_000_000 ether, true);
    }
  }

  function _scheduleOnAll(uint16 rate, uint40 effectiveAt) internal {
    for (uint256 c = 0; c < CHAINS; c++) {
      vm.prank(yManager);
      chains[c].setTargetRate(rate, effectiveAt);
    }
    effectiveAts.push(effectiveAt);
    scheduledRates.push(rate);
  }

  /// @dev Builds one round's events, sorted by time: one schedule execution per chain, strictly
  /// before `effectiveAt`, and a random number of user actions per chain within the round.
  function _roundEvents(
    uint256 roundSeed,
    uint256 start,
    uint256 effectiveAt
  ) internal pure returns (Event[] memory events) {
    uint256[] memory actionCounts = new uint256[](CHAINS);
    uint256 total = CHAINS;
    for (uint256 c = 0; c < CHAINS; c++) {
      actionCounts[c] =
        uint256(keccak256(abi.encode(roundSeed, c, 'count'))) %
        (MAX_ACTIONS_PER_ROUND + 1);
      total += actionCounts[c];
    }

    events = new Event[](total);
    uint256 n;
    for (uint256 c = 0; c < CHAINS; c++) {
      uint256 scheduleSeed = uint256(keccak256(abi.encode(roundSeed, c, 'schedule')));
      events[n++] = Event({
        time: start + (scheduleSeed % (effectiveAt - start)),
        chain: c,
        isSchedule: true,
        seed: 0
      });
      for (uint256 a = 0; a < actionCounts[c]; a++) {
        uint256 actionSeed = uint256(keccak256(abi.encode(roundSeed, c, a)));
        events[n++] = Event({
          time: start + (actionSeed % (effectiveAt - start + 1)),
          chain: c,
          isSchedule: false,
          seed: actionSeed >> 64
        });
      }
    }

    // Insertion sort by time
    for (uint256 i = 1; i < events.length; i++) {
      Event memory current = events[i];
      uint256 j = i;
      while (j > 0 && events[j - 1].time > current.time) {
        events[j] = events[j - 1];
        j--;
      }
      events[j] = current;
    }
  }

  /// @dev A random deposit, mint, withdraw, redeem or transfer by a random actor, skipped when
  /// the actor cannot perform it.
  function _act(sGho chain, uint256 seed) internal {
    address actor = actors[seed % actors.length];
    uint256 kind = (seed >> 8) % 5;
    uint256 amount = bound(seed >> 16, 1, 50_000 ether);

    vm.startPrank(actor);
    if (kind == 0) {
      amount = _min(amount, chain.maxDeposit(actor));
      if (amount > 0) chain.deposit(amount, actor);
    } else if (kind == 1) {
      amount = _min(amount, chain.maxMint(actor));
      if (amount > 0) chain.mint(amount, actor);
    } else if (kind == 2) {
      amount = _min(amount, chain.maxWithdraw(actor));
      if (amount > 0) chain.withdraw(amount, actor, actor);
    } else if (kind == 3) {
      amount = _min(amount, chain.maxRedeem(actor));
      if (amount > 0) chain.redeem(amount, actor, actor);
    } else {
      amount = _min(amount, chain.balanceOf(actor));
      if (amount > 0) chain.transfer(actors[(seed >> 200) % actors.length], amount);
    }
    vm.stopPrank();
  }

  /// @dev Every chain matches chain 0 and the index derived from the schedule alone.
  function _assertAllInSync() internal view {
    uint256 expected = _referenceIndex(block.timestamp);
    for (uint256 c = 0; c < CHAINS; c++) {
      assertEq(chains[c].convertToAssets(RAY), expected, 'Live index differs from the schedule');
      assertEq(chains[c].yieldIndex(), chains[0].yieldIndex(), 'Checkpoint index diverged');
      assertEq(chains[c].lastUpdate(), chains[0].lastUpdate(), 'Checkpoint timestamp diverged');
      assertEq(chains[c].targetRate(), chains[0].targetRate(), 'Rate diverged');
    }
  }

  /// @dev The index implied by the schedule: checkpointed at genesis and at every effective
  /// timestamp reached, accruing at the rate in force in between.
  function _referenceIndex(uint256 timestamp) internal view returns (uint256 index) {
    index = RAY;
    uint256 from = genesis;
    uint16 rate = genesisRate;
    for (uint256 k = 0; k < effectiveAts.length && effectiveAts[k] <= timestamp; k++) {
      index = _emulateYieldIndex(index, rate, effectiveAts[k] - from);
      from = effectiveAts[k];
      rate = scheduledRates[k];
    }
    index = _emulateYieldIndex(index, rate, timestamp - from);
  }

  function _currentScheduledRate() internal view returns (uint16) {
    return scheduledRates.length == 0 ? genesisRate : scheduledRates[scheduledRates.length - 1];
  }

  function _rate(uint256 seed, uint256 salt) internal pure returns (uint16) {
    uint256 r = uint256(keccak256(abi.encode(seed, salt, 'rate')));
    // One in five rates is 0, the rest spread up to the maximum
    return r % 5 == 0 ? 0 : (bound(r >> 8, 1, MAX_SAFE_RATE)).toUint16();
  }

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}
