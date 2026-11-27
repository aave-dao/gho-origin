# sGhoSteward

## Overview

`sGhoSteward` lets the risk council update the `targetRate` and `supplyCap` of `sGHO` without a governance vote. `sGHO` enforces its own limits, such as `MAX_SAFE_RATE`.

## Roles

| Role                      | Can                                      |
| :------------------------ | :--------------------------------------- |
| `DEFAULT_ADMIN_ROLE`      | Grant and revoke every role              |
| `RATE_MANAGER_ROLE`       | Set, schedule or cancel the `targetRate` |
| `SUPPLY_CAP_MANAGER_ROLE` | Set the `supplyCap`                      |

Governance holds `DEFAULT_ADMIN_ROLE`. Every other role starts with the risk council. The steward needs `YIELD_MANAGER_ROLE` on `sGHO`.

## Target rate

- `setTargetRate(targetRate, effectiveAt)` sets the rate in force from `effectiveAt`. It reverts with `RateUnchanged` if `targetRate` is already in force, and overwrites any scheduled update.
- `cancelTargetRate()` drops a scheduled update that is not yet effective.
- Passing the same `targetRate` and `effectiveAt` to the stewards of every chain keeps the yield indexes in sync. `effectiveAt == now` applies immediately, for single-chain deployments.

## Supply cap

`setSupplyCap(supplyCap)` takes whole GHO units (no decimals). It reverts with `SupplyCapUnchanged` if the value is already set, and above `uint40`.
