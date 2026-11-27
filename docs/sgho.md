# sGHO

## Overview

sGHO is an [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault over GHO. Its share price follows a yield index set by governance, not the GHO the vault holds. The DAO funds the yield by sending GHO to the vault.

## Yield

- The index compounds every second at `targetRate`, an annual rate in basis points capped at `MAX_SAFE_RATE`: `index * (1 + targetRate / year) ^ elapsed` from the last checkpoint, rounding down at every step.
- Growth over a period depends only on its length and the rate, not on how often users interact.
- The index is checkpointed only when a rate change takes effect, as of that change's timestamp. `yieldIndex()` and `lastUpdate()` return that checkpoint, while `convertToAssets` returns the live value.

## Multi-chain synchronization

sGHO can run on several chains with an identical yield index, as long as every checkpoint happens at the same timestamp on every chain.

- `setTargetRate(newRate, effectiveAt)` schedules a rate change at an absolute timestamp. A multi-chain AIP passes the same `effectiveAt` on every chain, so the rate switches at the same instant everywhere even though the payload executes at different times.
- A due update is applied lazily: views resolve it, and the next rate update, deposit or withdrawal persists it, checkpointed at `effectiveAt`. Transfers do not persist it.
- To keep chains in sync, every scheduled update should be mirrored on all of them. A pending update can be overwritten by the next `setTargetRate` or dropped by `cancelPendingTargetRate`. To stay in sync, do either before the pending `effectiveAt` on every chain.
- `effectiveAt == now` applies the update immediately at the chain-local time, for single-chain deployments.
- A new chain is initialized from a live chain's `yieldIndex()`, `lastUpdate()` and `targetRate()`, with `lastUpdate` possibly in the past. A pending update on the source chain is not carried over and has to be scheduled on the new chain too. There is no function to overwrite the checkpoint after initialization.

## Supply cap

`supplyCap` is in whole GHO units (no decimals), stored as `uint40`. `maxDeposit` and `maxMint` stop at the cap.

## Roles

| Role                  | Can                                                                          |
| :-------------------- | :--------------------------------------------------------------------------- |
| `PAUSE_GUARDIAN_ROLE` | Pause and unpause deposits, withdrawals and transfers                        |
| `TOKEN_RESCUER_ROLE`  | Rescue tokens sent to the vault by mistake, except GHO                       |
| `YIELD_MANAGER_ROLE`  | Set or schedule the target rate, cancel a scheduled rate, set the supply cap |

## Integrator notes

- **Pricing**: use `convertToAssets` or `previewRedeem`. `yieldIndex()` can be months old.
- **Withdrawals**: first come, first served. `maxWithdraw` and `maxRedeem` are limited by the GHO the vault holds, which can be below `totalAssets` until the DAO funds it.
- **Pausing**: blocks deposits, withdrawals and transfers. The `max*` functions return 0 while paused.
