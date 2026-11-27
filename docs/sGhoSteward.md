# sGhoSteward

## Overview

`sGhoSteward` lets the risk council update the `targetRate` and `supplyCap` of `sGHO`, and fund `sGHO` with GHO from the collector, without a governance vote. `sGHO` enforces its own limits, such as `MAX_SAFE_RATE`.

## Roles

| Role                      | Can                                      |
| :------------------------ | :--------------------------------------- |
| `DEFAULT_ADMIN_ROLE`      | Grant and revoke every role              |
| `RATE_MANAGER_ROLE`       | Set, schedule or cancel the `targetRate` |
| `SUPPLY_CAP_MANAGER_ROLE` | Set the `supplyCap`                      |
| `FUNDING_MANAGER_ROLE`    | Fund `sGHO` from the collector           |

Governance holds `DEFAULT_ADMIN_ROLE`. Every other role starts with the risk council. The steward needs `YIELD_MANAGER_ROLE` on `sGHO` and `FUNDS_ADMIN_ROLE` on the collector.

## Target rate

- `setTargetRate(targetRate, effectiveAt)` sets the rate in force from `effectiveAt`. It reverts with `RateUnchanged` if `targetRate` is already in force, and overwrites any scheduled update.
- `cancelTargetRate()` drops a scheduled update that is not yet effective.
- Passing the same `targetRate` and `effectiveAt` to the stewards of every chain keeps the yield indexes in sync. `effectiveAt == now` applies immediately, for single-chain deployments.

## Supply cap

`setSupplyCap(supplyCap)` takes whole GHO units (no decimals). It reverts with `SupplyCapUnchanged` if the value is already set, and above `uint40`.

## Funding

`sGHO` pays yield out of the GHO it holds, so the DAO keeps it funded. The steward sends GHO from the collector to `sGHO`, from one of three sources:

- `fundSGho(amount)`: GHO held by the collector.
- `fundSGhoFromAToken(aToken, amount)`: GHO withdrawn from an Aave v3 pool, using a GHO aToken held by the collector. `aToken` must be the GHO aToken of its own pool.
- `fundSGhoFromVault(vault, amount)`: GHO withdrawn from an ERC-4626 vault over GHO, such as a static aToken, using shares held by the collector. Shares the vault does not burn go back to the collector.

Every funding is limited in three ways:

- At most one funding per `MINIMUM_DELAY` (one day), from any source.
- At most `getMaxFundingAmount()` per funding. Only `DEFAULT_ADMIN_ROLE` can change it.
- After the funding, `sGHO` holds at most its liabilities (`totalAssets`) plus `FUNDING_BUFFER_DURATION` of yield at the current `targetRate`. `getFundingHeadroom()` returns how much can be funded now.
