## Overview

The following section explains how remote facilitators for GHO operate and outlines the contracts involved in the setup.

### [GhoDirectFacilitator](/src/contracts/facilitators/gsm/GhoDirectFacilitator.sol)

A minimal facilitator contract with minting and burning capabilities, controlled by a single entity. It must be granted the `Facilitator` role on the GHO token with a defined bucket capacity.

This contract can represent a remote minting strategy: it can mint any amount of GHO liquidity on Ethereum, which is then bridged to a remote chain for future use.

### [GhoReserve](/src/contracts/facilitators/gsm/GhoReserve.sol)

It holds GHO liquidity and allows authorized entities to use it up to a defined limit. It is intended for use on remote chains, where GHO is bridged from Ethereum, locked in this reserve, and later distributed by authorized entities through various strategies.

Instead of granting facilitator rights directly on the GHO token to remote facilitators, they are registered as entities in the `GhoReserve`. This indirection is necessary because GHO can only be minted on Ethereum.

A single `GhoReserve` instance can be shared across multiple remote faciltiators, or each remote facilitator can have a dedicated one. Both setups are functionally equivalent, though the shared approach is simpler.

### Remote Facilitators

Remote facilitators function similarly to those on Ethereum, but the way GHO is brought into circulation differs (since GHO can only be minted on Ethereum). Existing minting strategies such as `GhoDirectMinter` (for distribution via Aave V3 Pools) and GSM (for swapping GHO with exogenous assets) can be adapted as remote facilitators using the following setup:

[On Ethereum]

1. A `GhoDirectFacilitator` contract is deployed to represent the minting strategy on the remote chain. It is granted the `Facilitator` role on the Ethereum `GhoToken` contract, with a defined bucket capacity of X.
2. An amount X of GHO is minted via the `GhoDirectFacilitator` and bridged to the remote chain (typically via `CCIP`).

[On the Remote Chain]

1. A `GhoReserve` contract is deployed to hold the X GHO bridged from Ethereum. The remote minting strategy is registered as an entity in the `GhoReserve`, granting it permission to use and restore GHO liquidity.
2. The strategy operates using GHO from the `GhoReserve`, following its internal logic and collateralization rules.
3. Unused GHO remains in the `GhoReserve`. If the strategy is deprecated or idle for an extended period, the GHO can be transferred out and bridged back to Ethereum for burning.

Note: A `GhoReserve` can support multiple minting strategies concurrently. It's up to the configuration whether to deploy a dedicated `GhoReserve` per strategy or share a single instance among several.
