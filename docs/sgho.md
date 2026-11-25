# sGHO - Savings GHO Vault

## Overview

sGHO is an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vault that allows users to earn yield on their GHO tokens. The vault automatically accrues and distributes yield to depositors through internal accounting, with all logic self-contained in the sGHO contract.

## Key Features

- **Full EIP-4626 Compliance**: Complete implementation of the ERC-4626 standard for tokenized vaults
- **Fixed-Rate Yield**: Yield compounds every second at a fixed target rate, tracked via a yield index
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
2. **Per-Second Compounding**: The index grows to `index * (1 + targetRate / year) ^ timeElapsed` from its last checkpoint, so growth over a period depends only on its length. It is only checkpointed to storage when the rate changes, and user actions never checkpoint it. In between, conversions read the live accrued value
3. **Share Conversion**: Asset/share conversions use the current yield index

### Key Parameters

- **Target Rate**: Fixed annual rate in basis points, compounded every second (max 50% = 5000)
- **Yield Index**: Index used for share/asset conversions

## Role Management

- `PAUSE_GUARDIAN_ROLE` : This role has permissions to pause/unpause any action related to sGho shares including deposits, withdrawals and transfers.
- `TOKEN_RESCUER_ROLE` : This role has permissions to rescue tokens held on the contract
- `YIELD_MANAGER_ROLE` : This role has permissions to update the yield target rate and the supply cap.

## Security Considerations

### Built-in Protections

- **Supply Cap**: Limits maximum vault capacity
- **Rate Limits**: Maximum 50% annual rate, compounded every second, to prevent excessive yield.
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
3. `upgrade` to `sGhoInstance` with no calldata. Its `initialize` is locked because revision 2 is already used.
4. Revoke `YIELD_MANAGER_ROLE` from the executor.

The deployed `sGhoSteward` calls `setSupplyCap(uint160)`, a selector that no longer exists, so a new steward must be deployed in the same payload, granted `YIELD_MANAGER_ROLE`, and configured with the current rate config. Revoke `YIELD_MANAGER_ROLE` from the old steward in the same payload.

## Math

sGHO uses high-precision arithmetic to ensure accurate yield calculations and prevent precision loss during share/asset conversions.
The following are key considerations for arithmetic precision in math operations:

- **Yield Index**: Stored with RAY precision (1e27) to maintain accuracy over long periods
- **Rate Calculations**: The growth factor since the last checkpoint is `(RAY + rate / year) ^ timeElapsed`, computed by binary exponentiation and applied to the checkpointed index
- **Share Conversions**: Asset-to-share and share-to-asset conversions use high-precision math
- **Accumulated Interest**: Every operation rounds down, so the index never exceeds the exact growth
