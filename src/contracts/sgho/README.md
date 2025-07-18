# sGHO - Savings GHO Vault

## About

sGHO is an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vault that allows users to earn yield on their GHO tokens. The vault automatically accrues and distributes yield to depositors through internal accounting, with all logic self-contained in the sGHO contract.

## Features

- **Full [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) compatibility.** sGHO implements all standard ERC-4626 functions for deposits, withdrawals, and share calculations.
- **Automatic yield accrual.** Yield is accrued and distributed internally during vault operations, compounding linearly between state updates (e.g., deposit, withdraw, mint, redeem).
- **Role-based access control.** Uses Aave's ACLManager for managing permissions:
  - `YIELD_MANAGER_ROLE`: Can set the target APR and supply cap
  - `FUNDS_ADMIN_ROLE`: Can rescue non-GHO tokens in emergencies
- **Permit support.** Users can approve sGHO to spend their GHO tokens using EIP-2612 permits, enabling gasless approvals.
- **No ETH acceptance.** The contract rejects direct ETH transfers.
- **Supply cap.** The vault enforces a maximum cap on total GHO that can be deposited.

## Architecture

The system consists of a single main contract:

**sGHO.sol**: The main vault contract that:
- Implements ERC4626 for standard vault operations
- Handles deposits and withdrawals with automatic yield accrual
- Manages internal asset accounting with a yield index
- Integrates with Aave's ACLManager for role management

## Inheritance and Dependencies

### sGHO.sol
- Inherits from:
  - `ERC4626Upgradeable` (OpenZeppelin) - For vault functionality
  - `ERC20PermitUpgradeable` (OpenZeppelin) - For permit functionality
  - `Initializable` (OpenZeppelin) - For initialization pattern
  - `IsGHO` (Custom interface) - Contract interface
- Uses OpenZeppelin interfaces:
  - `IERC20` - For token operations
  - `IAccessControl` - For role management
- Uses Aave libraries:
  - `WadRayMath` - For precise mathematical calculations

## Yield Accrual and Distribution

Yield is accrued and distributed automatically during vault operations. The yield compounds linearly between state updates (e.g., deposit, withdraw, mint, redeem) and is tracked via a `yieldIndex`.

### Key Components:
- **Target Rate**: Annual percentage rate in basis points (e.g., 1000 = 10%)
- **Yield Index**: Tracks the cumulative yield multiplier (in ray, 1e27 scale)
- **Last Update**: Timestamp of the last yield accrual
- **Supply Cap**: Maximum GHO that can be deposited in the vault

### Yield Accrual Process:
1. When a vault operation occurs (deposit, withdraw, mint, redeem), `_updateYieldIndex()` is called.
2. The yield index is updated based on the elapsed time and the current target rate.
3. Share/asset conversions use the up-to-date yield index for accurate accounting.

#### Example (from contract):
```solidity
function _getCurrentYieldIndex() internal view returns (uint256) {
  if (targetRate == 0) return yieldIndex;
  uint256 timeSinceLastUpdate = block.timestamp - lastUpdate;
  if (timeSinceLastUpdate == 0) return yieldIndex;
  uint256 annualRateRay = uint256(targetRate).rayDiv(10000);
  uint256 ratePerSecond = annualRateRay.rayDiv(365 days);
  uint256 accumulatedRate = ratePerSecond.rayMul(timeSinceLastUpdate);
  uint256 growthFactor = WadRayMath.RAY + accumulatedRate;
  return yieldIndex.rayMul(growthFactor);
}
```

## Security Considerations

- **Role-based access control** through Aave's ACLManager
- **Token rescue mechanism** for handling stuck non-GHO tokens (GHO cannot be rescued)
- **No ETH acceptance** to prevent accidental ETH deposits
- **Initialization pattern** prevents re-initialization attacks
- **Supply cap** to limit total GHO in the vault

## Limitations

- Target rate and supply cap can only be modified by accounts with the YIELD_MANAGER_ROLE
- The system requires GHO tokens to be properly configured and accessible
- Withdrawals and redemptions are limited by the contract's actual GHO balance (no explicit buffer logic)
- Yield is accrued automatically during vault operations, not on-demand
- **GHO Balance Dependency**: While yield accrues based on time and target rate, actual withdrawals are limited by the contract's GHO balance. Users can check available withdrawal capacity using `maxWithdraw()` and `maxRedeem()` functions, which return the minimum of the user's share value and the contract's actual GHO balance.

## Shortfall Risk and Capitalization

**Important**: sGHO operates on a first-come, first-served basis for withdrawals. If the contract's GHO balance falls below the total value of shares (totalAssets), some depositors may be unable to withdraw their full balance until additional GHO is provided to the contract.

This creates an expectation that the AAVE DAO will maintain sGHO sufficiently capitalized above the value of totalAssets to ensure all depositors can withdraw their funds when desired. The DAO should monitor the contract's GHO balance and replenish it as needed to maintain adequate liquidity for withdrawals.

Users should be aware that during periods of insufficient GHO balance, withdrawal requests may be partially filled or rejected entirely, depending on the available GHO in the contract at the time of the withdrawal attempt.

## Usage Examples

### Depositing GHO
```solidity
// Deposit GHO into the vault
sgho.deposit(amount, receiver);

// Deposit with permit (gasless approval)
sgho.permit(owner, spender, value, deadline, v, r, s);
sgho.deposit(amount, receiver);

// Mint shares for a specific amount of GHO
sgho.mint(shares, receiver);
```

### Withdrawing GHO
```solidity
// Withdraw GHO from the vault
sgho.withdraw(assets, receiver, owner);

// Redeem shares for GHO
sgho.redeem(shares, receiver, owner);
```

### Managing Yield and Configuration
```solidity
// Set target rate (YIELD_MANAGER_ROLE only)
sgho.setTargetRate(1000); // 10% APR

// Set supply cap (YIELD_MANAGER_ROLE only)
sgho.setSupplyCap(newCap);

// View current vault APR
uint256 apr = sgho.vaultAPR();

// Rescue non-GHO tokens in emergency (FUNDS_ADMIN_ROLE only)
sgho.rescueERC20(tokenAddress, recipient, amount);
```

### Permit Usage (Gasless Approvals)
```solidity
// Standard permit
sgho.permit(owner, spender, value, deadline, v, r, s);
```

## Important Notes

- **Supply Cap**: The vault enforces a maximum cap on total GHO that can be deposited, providing a mechanism to control the pool size.
- **Automatic Yield**: Yield is accrued and distributed automatically during deposit/withdrawal/mint/redeem operations.
- **No External Yield Management**: All yield logic is internal; there is no separate yield manager contract.
- **Self-contained Architecture**: The system is fully contained within the sGHO contract.
- **Composable Design**: sGHO implements the ERC4626 standard, making it composable with DeFi protocols that support this standard (lending protocols, yield aggregators, etc.).
- **Cross-chain Deployment**: The contract can be deployed on any EVM-compatible blockchain, enabling GHO yield opportunities across multiple networks.

---

This README is up-to-date with the current implementation of `sGHO.sol` as of this version. Please refer to the contract for the most precise technical details.
