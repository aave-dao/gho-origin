# sGHO

## Overview

sGHO is an [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault over GHO. Its share price follows a yield index set by governance, not the GHO the vault holds. The DAO funds the yield by sending GHO to the vault.

## Yield

- The index compounds every second at `targetRate`, an annual rate in basis points capped at `MAX_SAFE_RATE`: `index * (1 + targetRate / year) ^ elapsed` from the last checkpoint, rounding down at every step.
- Growth over a period depends only on its length and the rate, not on how often users interact.
- The index is checkpointed only when the rate changes. `yieldIndex()` and `lastUpdate()` return that checkpoint, while `convertToAssets` returns the live value.

## Supply cap

`supplyCap` is in whole GHO units (no decimals), stored as `uint40`. `maxDeposit` and `maxMint` stop at the cap.

## Roles

| Role                  | Can                                                    |
| :-------------------- | :----------------------------------------------------- |
| `PAUSE_GUARDIAN_ROLE` | Pause and unpause deposits, withdrawals and transfers  |
| `TOKEN_RESCUER_ROLE`  | Rescue tokens sent to the vault by mistake, except GHO |
| `YIELD_MANAGER_ROLE`  | Set the target rate and the supply cap                 |

## Integrator notes

- **Pricing**: use `convertToAssets` or `previewRedeem`. `yieldIndex()` can be months old.
- **Withdrawals**: first come, first served. `maxWithdraw` and `maxRedeem` are limited by the GHO the vault holds, which can be below `totalAssets` until the DAO funds it.
- **Pausing**: blocks deposits, withdrawals and transfers. The `max*` functions return 0 while paused.
