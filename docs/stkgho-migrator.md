# StkGhoMigrator - One-tx migration from stkGHO to sGHO

## Overview

**StkGhoMigrator** is a helper contract that migrates a user's full **stkGHO** position into the **sGHO** ERC4626 vault in a single transaction. It batches cooldown, redeem, and deposit so users do not have to interact with `stkGHO` and `sGHO` separately.

Today the `stkGHO` cooldown period is `0` seconds, which makes the full flow possible atomically. The contract enforces this precondition at runtime: if the cooldown is ever changed back to a non-zero value, `migrate(uint256)` reverts and the migrator becomes a no-op until the cooldown is set back to `0`.

## Flow

The user calls [`migrate(minGhoRedeemed)`](/src/contracts/misc/StkGhoMigrator.sol):

1. The migrator reads the caller's `stkGHO` share balance.
2. It calls `cooldownOnBehalfOf(msg.sender)` and then `redeemOnBehalf(msg.sender, address(this), shares)` on `stkGHO`, receiving the redeemed GHO in the migrator contract.
3. It checks that the GHO received is at least `minGhoRedeemed`, and reverts with `UnexpectedGhoRedeemed` otherwise.
4. It calls `SGHO.deposit(redeemedGho, msg.sender)`, using the user address as the receiver so the user directly receives the minted `sGHO` shares.

The migrator does not assume a 1:1 `stkGHO` exchange rate. Callers should pass `STKGHO.previewRedeem(STKGHO.balanceOf(user))` as `minGhoRedeemed`, so the migration reverts if the rate moves against the user before it executes.

The migrator approves `sGHO` for `type(uint256).max` of GHO once, in the constructor, so no per-call approval is required.

## Access Control & Roles

| Role on `StkGhoMigrator`                | Description                                                                                          |
| :-------------------------------------- | :--------------------------------------------------------------------------------------------------- |
| `owner` (`Ownable2StepWithGuardian`)    | Can update the guardian, set the `stkGHO` claim helper pending admin, rescue ERC20, and `unpause()`. |
| `guardian` (`Ownable2StepWithGuardian`) | Can `pause()` `migrate(uint256)` in case of emergency.                                               |

- `pause()` is callable by the `owner` or the `guardian`; `unpause()` is callable by the `owner` only.
- The `guardian` is updated via `updateGuardian(newGuardian)`, callable by the `owner` or the current `guardian`.
- Ownership uses a two-step transfer (`Ownable2StepWithGuardian`): the current owner calls `transferOwnership(newOwner)`, and the new owner must call `acceptOwnership()` to take over.

### `CLAIM_HELPER` role on `stkGHO`

For `migrate(uint256)` to be callable, the migrator contract must hold the `CLAIM_HELPER` role (`role id = 2`) on the `stkGHO` contract. The role is required to call `cooldownOnBehalfOf` and `redeemOnBehalf`.

Onboarding the role is a two-step handshake driven by `stkGHO`'s `RoleManager`:

1. The current `CLAIM_HELPER` admin calls `setPendingAdmin(2, migrator)` on `stkGHO`.
2. Anyone calls [`claimHelperRole()`](/src/contracts/misc/StkGhoMigrator.sol) on the migrator, which in turn calls `claimRoleAdmin(2)` on `stkGHO`.

To transfer the role away from the migrator later (e.g. when the migration window ends), the migrator owner calls `setClaimHelperPendingAdmin(newAdmin)`, and the new admin claims it via the same `RoleManager` flow.

## Important Notes

- The `CLAIM_HELPER` role on `stkGHO` is effectively a single-address role. Assigning it to the migrator means other `onlyClaimHelper` functions, such as `claimRewardsOnBehalf` and `claimRewardsAndRedeemOnBehalf`, are no longer callable by the previous helper. This is acceptable for this migration because `stkGHO` rewards are not used and the contract is being treated as legacy.
- `migrate(uint256)` migrates the caller's **full** `stkGHO` balance; there is no partial-migration mode by design.
- `rescue(token, to, amount)` is restricted to the owner and is intended for ERC20 tokens accidentally sent to the contract.

## Testing

The migrator depends on the live `stkGHO` and `sGHO` deployments, so its tests run against a mainnet fork.

To run them, set `RPC_MAINNET` to an Ethereum mainnet RPC URL in your environment (or in a local `.env` file, which is gitignored):

```sh
export RPC_MAINNET=https://...
forge test --match-path 'tests/misc/StkGhoMigrator*' -vvv
```

If `RPC_MAINNET` is not set, the fork tests are skipped automatically (the rest of the suite runs normally).
