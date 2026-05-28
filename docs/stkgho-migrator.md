# StkGhoMigrator - One-tx migration from stkGHO to sGHO

## Overview

**StkGhoMigrator** is a helper contract that migrates a user's full **stkGHO** position into the **sGHO** ERC4626 vault in a single transaction. It batches cooldown, redeem, and deposit so users do not have to interact with `stkGHO` and `sGHO` separately.

Today the `stkGHO` cooldown period is `0` seconds, which makes the full flow possible atomically. The contract enforces this precondition at runtime: if the cooldown is ever changed back to a non-zero value, `migrate()` reverts and the migrator becomes a no-op until the cooldown is set back to `0`.

## Flow

The user calls [`migrate()`](/src/contracts/misc/StkGhoMigrator.sol):

1. The migrator reads the caller's `stkGHO` share balance.
2. It calls `cooldownOnBehalfOf(msg.sender)` and then `redeemOnBehalf(msg.sender, address(this), shares)` on `stkGHO`, receiving the redeemed GHO in the migrator contract.
3. It sanity-checks that the GHO received equals the share amount redeemed (the current exchange rate is 1:1; the migrator reverts with `UnexpectedGhoRedeemed` if this invariant breaks).
4. It calls `SGHO.deposit(redeemedGho, msg.sender)`, using the user address as the receiver so the user directly receives the minted `sGHO` shares.

The migrator approves `sGHO` for `type(uint256).max` of GHO once, in the constructor, so no per-call approval is required.

## Access Control & Roles

| Role on `StkGhoMigrator` | Description                                                                                |
| :----------------------- | :----------------------------------------------------------------------------------------- |
| `owner` (OpenZeppelin)   | Can set the pause guardian, set the `stkGHO` claim helper pending admin, and rescue ERC20. |
| `pauseGuardian`          | Can pause and unpause `migrate()` in case of emergency. Can also be updated by the owner.  |

Both `owner` and `pauseGuardian` can call `pause()` / `unpause()`.

### `CLAIM_HELPER` role on `stkGHO`

For `migrate()` to be callable, the migrator contract must hold the `CLAIM_HELPER` role (`role id = 2`) on the `stkGHO` contract. The role is required to call `cooldownOnBehalfOf` and `redeemOnBehalf`.

Onboarding the role is a two-step handshake driven by `stkGHO`'s `RoleManager`:

1. The current `CLAIM_HELPER` admin calls `setPendingAdmin(2, migrator)` on `stkGHO`.
2. Anyone calls [`claimHelperRole()`](/src/contracts/misc/StkGhoMigrator.sol) on the migrator, which in turn calls `claimRoleAdmin(2)` on `stkGHO`.

To transfer the role away from the migrator later (e.g. when the migration window ends), the migrator owner calls `setClaimHelperPendingAdmin(newAdmin)`, and the new admin claims it via the same `RoleManager` flow.

## Important Notes

- The `CLAIM_HELPER` role on `stkGHO` is effectively a single-address role. Assigning it to the migrator means other `onlyClaimHelper` functions, such as `claimRewardsOnBehalf` and `claimRewardsAndRedeemOnBehalf`, are no longer callable by the previous helper. This is acceptable for this migration because `stkGHO` rewards are not used and the contract is being treated as legacy.
- `migrate()` migrates the caller's **full** `stkGHO` balance; there is no partial-migration mode by design.
- `rescue(token, to, amount)` is restricted to the owner and is intended for ERC20 tokens accidentally sent to the contract.

## Testing

The migrator depends on the live `stkGHO` and `sGHO` deployments, so its tests run against a mainnet fork.

To run them, set `RPC_MAINNET` to an Ethereum mainnet RPC URL in your environment (or in a local `.env` file, which is gitignored):

```sh
export RPC_MAINNET=https://...
forge test --match-path 'tests/misc/StkGhoMigrator*' -vvv
```

If `RPC_MAINNET` is not set, the fork tests are skipped automatically (the rest of the suite runs normally).
