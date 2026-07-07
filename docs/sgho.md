# sGHO - Savings GHO Vault

## Overview

sGHO is an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vault that allows users to earn yield on their GHO tokens. The vault automatically accrues and distributes yield to depositors through internal accounting, with all logic self-contained in the sGHO contract.

## Key Features

- **Full EIP-4626 Compliance**: Complete implementation of the ERC-4626 standard for tokenized vaults
- **Linear Yield Accrual**: Yield accrues at a fixed APR (simple interest, no compounding), tracked via a yield index
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
2. **Linear Accrual**: The index grows by `targetRate * timeElapsed` (simple interest at a fixed APR — it does not compound). It is only checkpointed to storage when the rate changes; in between, conversions read the live accrued value
3. **Share Conversion**: Asset/share conversions use the current yield index

### Key Parameters

- **Target Rate**: Fixed annual percentage rate (APR) in basis points (max 50% = 5000)
- **Yield Index**: Index used for share/asset conversions

## Multi-Chain Synchronization

sGHO can be deployed on multiple chains with the yield index kept identical everywhere, at all times.

### Scheduled Rate Updates

`setTargetRate(newRate, effectiveAt)` schedules a rate change at an absolute future timestamp instead of applying it immediately. A multi-chain AIP passes the same `effectiveAt` (e.g. expected execution plus a 24-hour margin) on every chain: even though the payload executes at a different moment on each chain, the rate switches at the exact same instant everywhere.

The scheduled update is applied lazily. Views resolve it as soon as it is due, and the next rate update, deposit/mint or withdrawal/redemption persists it (plain transfers are exempt, to keep them free of a storage read they otherwise never need) — checkpointing the index exactly at `effectiveAt`, never at the (chain-specific) execution or interaction time, so the commit timing on each chain does not affect the resulting state. Since the accrual division is floored, checkpoints at chain-specific times would drift by a wei; anchoring every checkpoint to the shared `effectiveAt` keeps the index bit-identical across chains. For the same reason, every scheduled update (even a same-rate one) must be mirrored on all chains, and passing the current timestamp as `effectiveAt` (which applies the update immediately, checkpointing at the chain-local execution time) is only suitable for single-chain deployments.

### Cold Start & Reconciliation

`syncYieldIndex(newYieldIndex, newLastUpdate, newTargetRate)` (DEFAULT_ADMIN only) overwrites the yield index checkpoint with values read from an in-sync deployment (`yieldIndex()`, `lastUpdate()`, `targetRate()` — the getters already fold in a due scheduled update). The checkpoint timestamp may be in the past, so both deployments accrue identically from that point on. It covers:

- **Cold start**: `initialize` takes the same checkpoint values, so a deployment on a new chain starts in sync directly from a live deployment's checkpoint (a genesis deployment starts at `(RAY, now, 0)`); `syncYieldIndex` covers the same need post-initialization
- **Reconciliation**: if a multi-chain rate update fails on one chain, sync that chain from a healthy one (any scheduled update is discarded and must be re-scheduled afterwards)

Note that syncing rewrites the index directly and can decrease the asset value of existing shares, which is why it is restricted to the DEFAULT_ADMIN role (governance).

## Role Management

- `PAUSE_GUARDIAN_ROLE` : This role has permissions to pause/unpause any action related to sGho shares including deposits, withdrawals and transfers.
- `TOKEN_RESCUER_ROLE` : This role has permissions to rescue tokens held on the contract
- `YIELD_MANAGER_ROLE` : This role has permissions to update the yield target rate (immediately or scheduled) and the supply cap.
- `DEFAULT_ADMIN_ROLE` : Besides managing roles, this role has permissions to overwrite the yield index checkpoint via `syncYieldIndex`.

## Security Considerations

### Built-in Protections

- **Supply Cap**: Limits maximum vault capacity
- **Rate Limits**: Maximum 50% annual rate to prevent excessive yield.
- **Balance Checks**: Withdrawals limited by actual GHO balance

### Important Limitations

- **First-Come-First-Served**: Withdrawals depend on available GHO balance of the contract
- **No Yield Buffer**: No explicit buffer for yield payments, so available yield is not guaranteed at any given time
- **DAO Dependency**: Relies on DAO to maintain adequate GHO balance based on the yield index

### Shortfall Risk

The vault operates on a first-come, first-served basis. If the contract's GHO balance falls below the theoretical total assets, some users may be unable to withdraw their full balance until additional GHO is provided.

## Math

sGHO uses high-precision arithmetic to ensure accurate yield calculations and prevent precision loss during share/asset conversions.
The following are key considerations for arithmetic precision in math operations:

- **Yield Index**: Stored with RAY precision (1e27) to maintain accuracy over long periods
- **Rate Calculations**: The annual rate is applied linearly, dividing by seconds-per-year last so a full APR period is exact
- **Share Conversions**: Asset-to-share and share-to-asset conversions use high-precision math
- **Accumulated Interest**: Linear interest accumulation calculated with RAY precision
