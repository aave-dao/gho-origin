# sGhoSteward - Steward for Savings GHO Vault

## Overview

**sGhoSteward** is a steward contract designed to manage and update configuration parameters of `sGHO`.
It provides role-based access-controlled mechanisms to safely adjust the `targetRate` and `supplyCap` for the Savings GHO Vault.

## Key features

- Allows updating of `targetRate` and `supplyCap` of `sGHO` through this contract.
- Implements the `targetRate` formula as a composition of three parameters (with `AMPLIFICATION_DENOMINATOR` fixed at 100_00):

  `targetRate = AmplificationFactor / AMPLIFICATION_DENOMINATOR * FloatRate + FixedRate`

- Supports updating with each rate parameter _individually_ or _multiple parameters simultaneously_.
- Integrates **Role-Based Access Control** from OpenZeppelin, enabling secure assignment, modification, and revocation of roles.
- Provides functions to view the current configuration and pre-calculate the `targetRate` for any given configuration.
- Enforces a hard cap of `MAX_SAFE_RATE` in `sGho` for the computed `targetRate`, reverting the transaction if the changes do not meet the condition.

## Access Control

The `DEFAULT_ADMIN_ROLE` is set exclusively for governance initially, which has full authority to delegate, assign, or revoke roles for specific addresses.

In addition to the admin role, there are four specialized manager roles:

| Role                       | Description                                    |
| :------------------------- | :--------------------------------------------- |
| AMPLIFICATION_MANAGER_ROLE | Authorized to update the Amplification Factor. |
| FLOAT_RATE_MANAGER_ROLE    | Authorized to update the Float Rate.           |
| FIXED_RATE_MANAGER_ROLE    | Authorized to update the Fixed Rate.           |
| SUPPLY_CAP_MANAGER_ROLE    | Authorized to update the Supply Cap.           |

Initially, all roles are assigned to the `ghoCommittee`, a 3-of-4 multisig composed of service providers.
Over time, **Aave DAO** may choose to delegate or reassign these roles to other addresses as it deems appropriate - for example, allowing oracles to control certain components while councils or other entities manage others.

## Target Rate Configuration

As described in the [Aave Governance Forum discussion](https://governance.aave.com/t/arfc-gho-savings-upgrade/21680/3), the `targetRate` inside `sGHO` consists of three independently updatable components:
**Amplification Factor**, **Float Rate**, and **Fixed Rate**.

The formula for calculating the `targetRate` applied in `sGHO` is as follows:

`targetRate = AmplificationFactor * FloatRate + FixedRate`

All updates occur via the `setRateConfig(newConfig)` function, which takes a `RateConfig` struct as input.

- If a parameter in the new configuration matches the current one, it will be skipped.
- If a parameter differs, the contract verifies that the caller holds the appropriate manager role before applying the update.
- The function reverts if the computed target rate exceeds 50%.

**NOTE:** Setting a parameter to `0` or to any other value different from the current one is considered **an update** and requires the corresponding role.

### Example 1

Current configuration:

```solidity
amplification: 50_00   // 0.5
floatRate:     4_00    // 4%
fixedRate:     2_00    // 2%
```

Current `targetRate` is calculated as `50_00 * 4_00 / 100_00 + 2_00 = 4_00`. `4_00` refers to 4%.
`100_00` is `AMPLIFICATION_FACTOR`, which is constant. Every parameter has `uint16` type with max value up to `65_535`.

New configuration (input to `setRateConfig(...)`):

```solidity
amplification: 100_00  // 1
floatRate:     5_00    // 5%
fixedRate:     2_00    // 2%
```

In this case:

- The function will check that the caller has both `AMPLIFICATION_MANAGER_ROLE` and `FLOAT_RATE_MANAGER_ROLE`.
- Since `fixedRate` remains unchanged, that role check is skipped for update.

If the role checks succeed, the new configuration is applied:

`targetRate = 100_00 * 5_00 / 100_00 + 2_00 = 7_00`.

This value is then passed to `sGHO` for update, and all parameters are stored locally.

### Example 2

Current configuration is the same:

```solidity
amplification: 50_00   // 0.5
floatRate:     4_00    // 4%
fixedRate:     2_00    // 2%
```

New configuration:

```solidity
amplification: 50_00   // 0.5
floatRate:     4_00    // 4%
fixedRate:     50_00   // 50%
```

Here only the `FIXED_RATE_MANAGER_ROLE` is required, since `fixedRate` is the only modified parameter.

However, during computation: `targetRate = 0.5 * 4% + 50% = 52%`

Because the computed value exceeds the maximum allowed rate of 50%, the transaction reverts.

## Supply Cap Management

The `setSupplyCap()` function allows authorized users to update the `sGHO` `supplyCap`.

- Access is restricted to addresses with the `SUPPLY_CAP_MANAGER_ROLE`.
- The maximum cap allowed within sGHO is `uint160` (less than the `uint256` input type of this function). Any attempt to set a value above this threshold results in a revert.
- Similarly, attempting to set the same value as the current `supplyCap` will also cause the transaction to revert.

## Contract Summary

| Function                               | Description                                        | Required Role               |
| :------------------------------------- | :------------------------------------------------- | :-------------------------- |
| `setRateConfig(RateConfig newConfig)`  | Updates amplification, float, and fixed rates      | Corresponding Manager Roles |
| `setSupplyCap(uint256 newSupplyCap)`   | Updates the maximum allowed sGHO supply            | `SUPPLY_CAP_MANAGER_ROLE`   |
| `getRateConfig()`                      | Returns the current rate configuration             | Public                      |
| `previewTargetRate(RateConfig config)` | Computes the target rate for a given configuration | Public                      |
| `sGHO()`                               | Returns current `sGHO` address                     | Public                      |
| `MAX_RATE()`                           | Returns max available `targetRate` that can be set | Public                      |
