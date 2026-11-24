# sGhoSteward - Steward for Savings GHO Vault

## Overview

**sGhoSteward** is a steward contract designed to manage and update configuration parameters of `sGHO`.
It provides role-based access-controlled mechanisms to safely adjust the `targetRate` and `supplyCap` for the Savings GHO Vault.

## Key features

- Allows updating of `targetRate` and `supplyCap` of `sGHO` through this contract.
- Integrates **Role-Based Access Control** from OpenZeppelin, enabling secure assignment, modification, and revocation of roles.
- Relies on `sGHO` to enforce `MAX_SAFE_RATE` on the `targetRate`.

## Access Control

The `DEFAULT_ADMIN_ROLE` is set exclusively for governance initially, which has full authority to delegate, assign, or revoke roles for specific addresses.

In addition to the admin role, there are two specialized manager roles:

| Role                    | Description                           |
| :---------------------- | :------------------------------------ |
| RATE_MANAGER_ROLE       | Authorized to update the Target Rate. |
| SUPPLY_CAP_MANAGER_ROLE | Authorized to update the Supply Cap.  |

Initially, both roles are assigned to the `riskCouncil`, a 3-of-4 multisig composed of service providers.
Over time, **Aave DAO** may choose to delegate or reassign these roles to other addresses as it deems appropriate.

## Target Rate Management

The `setTargetRate(targetRate, effectiveAt)` function sets the `sGHO` target rate, an annual rate in basis points compounded continuously, effective at `effectiveAt`.

- Access is restricted to addresses with the `RATE_MANAGER_ROLE`.
- `sGHO` reverts if the rate exceeds `MAX_SAFE_RATE` or if `effectiveAt` is in the past.
- The function reverts with `RateUnchanged` if `targetRate` is already in force. A scheduled update on `sGHO` is overwritten by the next call.
- `cancelTargetRate()` drops the scheduled update without a checkpoint. It reverts if nothing is scheduled or the update is already effective, and across chains it must execute before the pending `effectiveAt` on every chain.
- Submitting the same `targetRate` and `effectiveAt` on the stewards of every chain keeps the yield indexes in sync. Passing the current timestamp applies immediately (single-chain deployments only).

## Supply Cap Management

The `setSupplyCap()` function allows authorized users to update the `sGHO` `supplyCap`.

- Access is restricted to addresses with the `SUPPLY_CAP_MANAGER_ROLE`.
- The cap is in whole GHO units (no decimals). sGHO stores it as `uint40`, so any larger value reverts.
- Similarly, attempting to set the same value as the current `supplyCap` will also cause the transaction to revert.

## Contract Summary

| Function                                               | Description                                         | Required Role             |
| :----------------------------------------------------- | :-------------------------------------------------- | :------------------------ |
| `setTargetRate(uint16 targetRate, uint40 effectiveAt)` | Updates the target rate, effective at `effectiveAt` | `RATE_MANAGER_ROLE`       |
| `cancelTargetRate()`                                   | Cancels the scheduled target rate update            | `RATE_MANAGER_ROLE`       |
| `setSupplyCap(uint256 newSupplyCap)`                   | Updates the maximum allowed sGHO supply             | `SUPPLY_CAP_MANAGER_ROLE` |
| `sGHO()`                                               | Returns current `sGHO` address                      | Public                    |
