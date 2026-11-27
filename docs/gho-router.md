# GhoRouter

## Overview

`GhoRouter` swaps between GHO, sGHO and GSM-supported tokens in one call. It routes through an allowlisted GSM, wraps or unwraps static aTokens when the caller uses the underlying, and deposits into or redeems from sGHO. It holds no funds between calls and keeps no per-user state.

## Routes

`swap(tokenIn, tokenOut, gsm, exactAmountIn, minAmountOut, recipient, deadline)` supports six routes:

- GHO -> sGHO and sGHO -> GHO, which ignore `gsm`
- GHO -> token and sGHO -> token, which buy the GSM asset
- token -> GHO and token -> sGHO, which sell the GSM asset

`token` is either the GSM asset itself or an underlying registered in `tokenToStata` whose static aToken is the GSM asset. In the second case the router wraps on the way in and unwraps on the way out. Any other pair reverts.

`previewSwap` takes the same route arguments and returns the expected output.

## Configuration

The owner manages two registries:

- `allowGsm` / `revokeGsm`: the GSMs the router may use. Allowing a GSM checks it has code, uses this GHO, and does not settle in GHO or sGHO.
- `setTokenToStata` / `removeTokenToStata`: the underlying -> static aToken mapping used for wrapping. The static aToken must report the underlying as its `asset()`.

On every swap the router re-checks that the GSM is allowed and that its asset is not GHO or sGHO. Other GSM properties are checked only when the GSM is allowed.

## Access control

`GhoRouter` uses `Ownable2StepWithGuardian`.

- The owner manages both registries, pauses and unpauses, and can rescue any token held by the router.
- The guardian can pause and rotate itself. It cannot unpause, move funds or change routes.
- While paused, `swap` and `previewSwap` revert.

## Integrator notes

- **Slippage and deadline**: every swap checks `minAmountOut` and `deadline`. `recipient` cannot be zero or the router.
- **Refunds go to `msg.sender`, not `recipient`**:

  - GHO -> token: the router pulls only the GHO the GSM charges.
  - sGHO -> token: the router redeems all shares and returns the GHO the GSM does not spend.
  - token -> GHO/sGHO: the router returns the GSM asset the GSM does not take. On the underlying route this comes back as static aToken shares.

  Contracts swapping on behalf of users must forward these refunds.

- **Tokens**: routes assume standard ERC20 behaviour. Fee-on-transfer and rebasing tokens are not supported.
- **Allowances**: GSM allowances are reset after each call. Allowances to static aTokens and sGHO are exact-amount and fully consumed.
