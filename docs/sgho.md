# sGHO - Savings GHO Vault

## Overview

sGHO is an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vault that allows users to earn yield on their GHO tokens. The vault automatically accrues and distributes yield to depositors through internal accounting, with all logic self-contained in the sGHO contract.

## Key Features

- **Full EIP-4626 Compliance**: Complete implementation of the ERC-4626 standard for tokenized vaults
- **Fixed-Rate Yield**: Yield compounds continuously at a fixed target rate, tracked via a yield index
- **Role-Based Access Control**: Granular permissions for yield management and emergency operations
- **Permit Support**: Gasless deposits using EIP-2612 permits
- **Supply Cap Management**: Configurable maximum vault capacity, set in whole GHO units (no decimals)

## Architecture

### Core Components

**sGHO.sol**: The main vault contract implementing:

- ERC-4626 vault functionality (deposit, withdraw, mint, redeem)
- ERC-20 token standard with permit support
- Automatic yield accrual via yield index mechanism
- Role-based access control using OpenZeppelin's AccessControl
- Pausability mechanism for emergency situations
- Emergency token rescue functionality

## Yield Mechanism

### How It Works

1. **Yield Index**: Tracks the accumulated value per share (in RAY precision, 1e27)
2. **Continuous Compounding**: The index grows to `index * e^(targetRate * timeElapsed / year)` from its last checkpoint, using the Aave v3 approximation `1 + x + x^2 / 2 + x^3 / 6`. It is only checkpointed when a rate change takes effect, as of that change's timestamp, or by `syncYieldIndex`, so user actions and their timing never change it. The approximation falls short of `e^x` by about `x^4 / 24`, so the yield is slightly lower the longer a rate stays unchanged. In between, conversions read the live accrued value
3. **Share Conversion**: Asset/share conversions use the current yield index

### Key Parameters

- **Target Rate**: Fixed annual rate in basis points, compounded continuously (max 50% = 5000)
- **Yield Index**: Index used for share/asset conversions

## Multi-Chain Synchronization

sGHO can be deployed on multiple chains with an identical yield index, as long as every checkpoint happens at the same timestamp on every chain.

### Scheduled Rate Updates

`setTargetRate(newRate, effectiveAt)` schedules a rate change at an absolute timestamp. A multi-chain AIP passes the same `effectiveAt` on every chain, for example the expected execution time plus a 24-hour margin. The payload executes at a different moment on each chain, but the rate switches at the same instant everywhere.

The update is applied lazily. Views resolve it once it is due. The next rate update, deposit or withdrawal persists it, with the checkpoint taken at `effectiveAt` rather than at execution or interaction time. Transfers do not persist it, so they stay free of the extra storage read. Because every chain checkpoints at the same `effectiveAt`, the index is identical across chains.

Rules for operators:

- Every scheduled update must be mirrored on all chains, including a same-rate one. Each checkpoint restarts the compounding approximation, so a checkpoint on one chain only changes its accrual.
- A pending update that is not yet effective is overwritten by the next `setTargetRate`. Across chains, the overwrite must execute either before the pending `effectiveAt` on every chain or after it on every chain. If it straddles that timestamp, some chains skip the pending rate and others apply it, and the indexes desync until reconciled with `syncYieldIndex`.
- `effectiveAt == now` applies the update immediately at the chain-local time. Use it on single-chain deployments only.

### Cold Start & Reconciliation

`syncYieldIndex(newYieldIndex, newLastUpdate, newTargetRate)` (DEFAULT_ADMIN only) overwrites the checkpoint with values read from an in-sync deployment: `yieldIndex()`, `lastUpdate()` and `targetRate()`. Those getters already fold in a due scheduled update. The checkpoint timestamp may be in the past, so both deployments accrue identically from that point on. Any pending update on the synced chain is discarded and has to be re-scheduled.

- **Cold start**: `initialize` takes the same checkpoint values, target rate included, so a new chain starts in sync from a live deployment's checkpoint and needs no rate update of its own. A genesis deployment starts at `(RAY, now, 0)`. Do not configure the new chain's steward on its own: `setRateConfig` checkpoints that chain only. Its stored config stays `(0, 0, 0)` until the first rate change scheduled on all chains, and on that first change it counts every field as changed, so the caller needs all three manager roles.
- **Reconciliation**: if a rate update missed one chain, or an overwrite straddled a pending `effectiveAt`, sync the affected chain from a healthy one.

The steward is not affected by a sync. If it scheduled the discarded update, it still holds that config, and submitting the same config again reverts with `RateUnchanged`. To re-schedule it, submit a different config first and then the intended one, both with the same future `effectiveAt`. The second call overwrites the first pending update, so no checkpoint is created.

Syncing rewrites the index directly and can decrease the asset value of existing shares, which is why it is restricted to DEFAULT_ADMIN (governance).

## Role Management

- `PAUSE_GUARDIAN_ROLE` : This role has permissions to pause/unpause any action related to sGho shares including deposits, withdrawals and transfers.
- `TOKEN_RESCUER_ROLE` : This role has permissions to rescue tokens held on the contract
- `YIELD_MANAGER_ROLE` : This role has permissions to update the yield target rate (immediately or scheduled) and the supply cap.
- `DEFAULT_ADMIN_ROLE` : Besides managing roles, this role has permissions to overwrite the yield index checkpoint via `syncYieldIndex`.

## Security Considerations

### Built-in Protections

- **Supply Cap**: Limits maximum vault capacity
- **Rate Limits**: Maximum 50% annual rate, compounded continuously, to prevent excessive yield.
- **Balance Checks**: Withdrawals limited by actual GHO balance

### Important Limitations

- **First-Come-First-Served**: Withdrawals depend on available GHO balance of the contract
- **No Yield Buffer**: No explicit buffer for yield payments, so available yield is not guaranteed at any given time
- **DAO Dependency**: Relies on DAO to maintain adequate GHO balance based on the yield index

### Shortfall Risk

The vault operates on a first-come, first-served basis. If the contract's GHO balance falls below the theoretical total assets, some users may be unable to withdraw their full balance until additional GHO is provided.

## Upgrade Notes (Ethereum Mainnet)

The live vault migrates to this layout through `sGhoInstanceStoragePatch`, in one governance payload:

1. Grant the executor `YIELD_MANAGER_ROLE` and call the legacy `setTargetRate(currentRate)`. The patch reverts unless the index was checkpointed in the same block.
2. `upgradeAndCall` to `sGhoInstanceStoragePatch` with `initialize()`. This consumes revision 2.
3. `upgradeAndCall` to `sGhoInstance` with empty calldata. Its `initialize` is locked because revision 2 is already used.

The deployed `sGhoSteward` calls `setTargetRate(uint16)` and `setSupplyCap(uint160)`, selectors that no longer exist, so a new steward must be deployed in the same payload and granted `YIELD_MANAGER_ROLE` in place of the old one. Configuring it with the current rate config checkpoints mainnet only, so do it while mainnet is the only live chain. Once other chains are live, the config is set by the next rate change scheduled on all chains.

## Math

sGHO uses high-precision arithmetic to ensure accurate yield calculations and prevent precision loss during share/asset conversions.
The following are key considerations for arithmetic precision in math operations:

- **Yield Index**: Stored with RAY precision (1e27) to maintain accuracy over long periods
- **Rate Calculations**: The growth factor since the last checkpoint is the same polynomial as Aave v3 `MathUtils.calculateCompoundedInterest`, applied to the checkpointed index
- **Share Conversions**: Asset-to-share and share-to-asset conversions use high-precision math
- **Accumulated Interest**: Unlike Aave v3, which rounds half up, every operation rounds down, so the index never exceeds the exact polynomial, which itself stays below `e^x`
