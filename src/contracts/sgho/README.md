# sGHO - Savings GHO Vault

## Overview

sGHO is an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vault that allows users to earn yield on their GHO tokens. The vault automatically accrues and distributes yield to depositors through internal accounting, with all logic self-contained in the sGHO contract.

## Key Features

- **Full EIP-4626 Compliance**: Complete implementation of the ERC-4626 standard for tokenized vaults
- **Automatic Yield Accrual**: Yield compounds linearly between operations and is tracked via a yield index
- **Gas-Efficient Design**: Optimized storage layout and cached rate calculations
- **Role-Based Access Control**: Granular permissions for yield management and emergency operations
- **Permit Support**: Gasless deposits using EIP-2612 permits
- **Supply Cap Management**: Configurable maximum vault capacity
- **Emergency Token Rescue**: Ability to recover accidentally sent non-GHO tokens

## Architecture

### Core Components

**sGHO.sol**: The main vault contract implementing:

- ERC-4626 vault functionality (deposit, withdraw, mint, redeem)
- ERC-20 token standard with permit support
- Automatic yield accrual via yield index mechanism
- Role-based access control using OpenZeppelin's AccessControl
- Emergency token rescue functionality

### Storage Layout

The contract uses a custom storage layout for gas optimization:

```solidity
struct sGHOStorage {
  uint176 yieldIndex; // Current yield index for share/asset conversion
  uint64 lastUpdate; // Timestamp of last yield index update
  uint16 targetRate; // Target annual yield rate in basis points
  uint160 supplyCap; // Maximum total assets allowed in vault
  uint96 ratePerSecond; // Cached rate per second for gas efficiency
}
```

## Yield Mechanism

### How It Works

1. **Yield Index**: Tracks cumulative yield multiplier (in RAY precision, 1e27)
2. **Linear Accrual**: Yield compounds linearly between operations
3. **Automatic Updates**: Yield index updates on every vault operation
4. **Share Conversion**: Asset/share conversions use current yield index

### Key Parameters

- **Target Rate**: Annual percentage rate in basis points (max 50% = 5000)
- **Rate Per Second**: Cached calculation for gas efficiency
- **Yield Index**: Current multiplier for share/asset conversions

### Yield Calculation

```solidity
// Linear interest calculation within update periods
uint256 accumulatedRate = ratePerSecond * timeSinceLastUpdate;
uint256 growthFactor = RAY + accumulatedRate;
newYieldIndex = oldYieldIndex * growthFactor / RAY;
```

## Access Control

### Roles

- **DEFAULT_ADMIN_ROLE**: Can grant/revoke other roles
- **YIELD_MANAGER_ROLE**: Can set target rate and supply cap
- **FUNDS_ADMIN_ROLE**: Can rescue non-GHO tokens in emergencies

### Role Management

```solidity
// Set target rate (YIELD_MANAGER_ROLE only)
sgho.setTargetRate(1000); // 10% APR

// Set supply cap (YIELD_MANAGER_ROLE only)
sgho.setSupplyCap(1000000e18); // 1M GHO

// Rescue tokens (FUNDS_ADMIN_ROLE only)
sgho.emergencyTokenTransfer(tokenAddress, recipient, amount);
```

## Usage Examples

### Basic Vault Operations

```solidity
// Deposit GHO and receive sGHO shares
uint256 shares = sgho.deposit(1000e18, receiver);

// Mint specific number of shares
uint256 assets = sgho.mint(1000e18, receiver);

// Withdraw GHO using assets amount
uint256 shares = sgho.withdraw(1000e18, receiver, owner);

// Redeem shares for GHO
uint256 assets = sgho.redeem(1000e18, receiver, owner);
```

### Gasless Deposits with Permit

```solidity
// Deposit with permit (no separate approval needed)
sgho.depositWithPermit(
    1000e18,           // assets
    receiver,          // receiver
    deadline,          // deadline
    signatureParams    // v, r, s signature components
);
```

### Preview Functions

```solidity
// Check conversion rates before operations
uint256 shares = sgho.previewDeposit(1000e18);
uint256 assets = sgho.previewRedeem(1000e18);

// Check maximum limits
uint256 maxDeposit = sgho.maxDeposit(address(0));
uint256 maxWithdraw = sgho.maxWithdraw(user);
```

## Security Considerations

### Built-in Protections

- **No ETH Acceptance**: Contract rejects direct ETH transfers
- **Supply Cap**: Limits maximum vault capacity
- **Rate Limits**: Maximum 50% annual rate to prevent excessive yield
- **Balance Checks**: Withdrawals limited by actual GHO balance
- **Safe Math**: Overflow protection with SafeCast

### Important Limitations

- **First-Come-First-Served**: Withdrawals depend on available GHO balance
- **No Yield Buffer**: No explicit buffer for yield payments
- **DAO Dependency**: Relies on DAO to maintain adequate GHO balance

### Shortfall Risk

The vault operates on a first-come, first-served basis. If the contract's GHO balance falls below the theoretical total assets, some users may be unable to withdraw their full balance until additional GHO is provided.

## Integration Guide

### For DeFi Protocols

sGHO implements the ERC-4626 standard, making it compatible with:

- Lending protocols
- Yield aggregators
- Decentralized Exchanges
- Portfolio management tools

### For Developers

```solidity
// Check if contract is ERC-4626 compatible
bool isVault = IERC165(address(sgho)).supportsInterface(type(IERC4626).interfaceId);

// Get vault information
address asset = sgho.asset();
uint256 totalAssets = sgho.totalAssets();
uint256 totalSupply = sgho.totalSupply();

// Convert between assets and shares
uint256 shares = sgho.convertToShares(assets);
uint256 assets = sgho.convertToAssets(shares);
```

## Deployment

### Initialization Parameters

```solidity
sgho.initialize(
    ghoAddress,        // GHO token address
    supplyCap,         // Maximum vault capacity
    executor          // DEFAULT_ADMIN_ROLE
);
```

### Upgradeable Design

The contract uses OpenZeppelin's upgradeable pattern with:

- Transparent proxy deployment
- Storage collision protection via ERC-7201
- Initialization pattern to prevent re-initialization

## Testing

The contract includes comprehensive test coverage for:

- ERC-4626 compliance
- Yield accrual mechanisms
- Access control
- Edge cases and precision
- Emergency functions

Run tests with:

```bash
forge test --match-contract sGhoTest
```

## Technical Specifications

- **Solidity Version**: ^0.8.19
- **Precision**: RAY (1e27) for yield calculations
- **Maximum Rate**: 50% annual (5000 basis points)
- **Token Decimals**: 18 (same as GHO)
- **Storage**: ERC-7201 namespaced storage

## Support

For technical questions or issues:

- Check the test files for usage examples
- Review the contract comments for implementation details
- Refer to the EIP-4626 specification for vault standards

---

_This README reflects the current implementation as of the latest version. For the most precise technical details, refer to the contract source code and tests._
