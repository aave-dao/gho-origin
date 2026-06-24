# GhoRouter Failure Modes and Security Assumptions

This document captures trust assumptions and failure modes for the current
router implementation at:

- `src/contracts/misc/GhoRouter.sol`

It is intended for integrators, operators, and reviewers.

## Scope and trust boundary

`GhoRouter` exposes a single public entry point:

```
swap(tokenIn, tokenOut, gsm, exactAmountIn, minAmountOut, recipient, deadline)
```

Internally, the router dispatches to one of six flows based on the `tokenIn`/`tokenOut` pair:

- `tokenIn == GHO, tokenOut == sGHO` — direct GHO → sGHO deposit
- `tokenIn == GHO, tokenOut == other` — GHO → GSM underlying token or static aToken
- `tokenIn == sGHO, tokenOut == GHO` — direct sGHO → GHO redemption
- `tokenIn == sGHO, tokenOut == other` — sGHO → GSM underlying token or static aToken
- `tokenIn == other, tokenOut == GHO` — GSM token → GHO
- `tokenIn == other, tokenOut == sGHO` — GSM token → sGHO

Any `tokenIn`/`tokenOut` pair that does not match these six paths reverts with `InvalidTokenPair(tokenIn, tokenOut)`.

Important shape of the current design:

- `GHO` and `sGHO` are immutable constructor params.
- The GSM to use is supplied by the caller as the `gsm` argument; the router validates it against the `allowedGsm` allowlist before use.
- A token may have more than one allowed GSM; the caller selects which one to route through on each swap.
- GSM paths are gated by on-chain allowlist state in `allowedGsm`.
- The router keeps no per-user accounting state.

## GSM mapping and validation model

- Storage: `mapping(address token => mapping(address gsm => bool allowed)) public allowedGsm`.
- Update path:
  - `allowTokenGsm(address token, address gsm)` (`onlyOwner`) — allows a token-to-GSM pairing.
  - `revokeTokenGsm(address token, address gsm)` (`onlyOwner`) — revokes an existing pairing.
- Constraints on `allowTokenGsm`:
  - Both `token` and `gsm` must be non-zero.
  - `allowedGsm[token][gsm]` must be unset — an already-allowed pairing cannot be re-added (reverts `TokenToGsmAlreadySet()`); revoke first.
  - `_validateGsm(gsm, token)` is run:
    - `gsm.code.length != 0`
    - `IGsm(gsm).GHO_TOKEN() == GHO`
    - `IGsm(gsm).UNDERLYING_ASSET() != address(0)`
    - `token` must be either the static aToken or its underlying asset
- Constraints on `revokeTokenGsm`:
  - `allowedGsm[token][gsm]` must be set, otherwise reverts `TokenToGsmNotSet()`.
- Swap enforcement:
  - All GSM swap paths require `allowedGsm[token][gsm]` for the caller-supplied `gsm`, reverting with `GsmNotConfigured()`.
- Observability: `TokenToGsmAdded(token, gsm)` and `TokenToGsmRemoved(token, gsm)` are emitted on every update.

## Runtime route composition

For GSM paths, the caller supplies the `gsm` and the router composes the route from it at execution time:

- Router checks `allowedGsm[token][gsm]` for the caller-supplied `gsm`, reverting `GsmNotConfigured()` if not allowed.
- Router reads `IGsm(gsm).UNDERLYING_ASSET()` to get `stataToken`.
- Router reads `IERC4626(stataToken).asset()` to get the underlying token.
- Router re-checks token compatibility against the route via `_validateTokens` on each swap and preview.

Important caveat:

- `_validateGsm` checks full GSM compatibility (e.g. `GHO_TOKEN`) only when a token-to-GSM pairing is allowed, not on every swap.
- Preview methods do not re-validate the GSM's `GHO_TOKEN` on each call.

## Security assumptions

The current implementation assumes:

1. Owner securely manages the `allowedGsm` allowlist and curates safe token-to-GSM pairings.
2. `IGsm`, static aToken (`IERC4626`), and `sGHO` dependencies are interface-compatible and non-malicious.
3. `sGHO` is a valid ERC4626 vault over GHO (constructor enforces `IERC4626(sgho).asset() == gho`).
4. External dependency return values are correct (router accounting uses returned values).
5. Underlying tokens involved in selected routes have ERC20 semantics compatible with `SafeERC20`.
6. Users/integrators set realistic slippage bounds.
7. Owner key management is trusted for `rescueToken`.

## Security properties in the current implementation

- Slippage checks are enforced on write flows via `SlippageExceeded`:
  - `minAmountOut` covers all six internal paths.
- Deadline is validated on every `swap()` call via `DeadlineExpired()`.
- Recipient is validated as non-zero on all write flows.
- GSM write flows are gated by `allowedGsm[token][gsm]` for the caller-supplied `gsm`.
- GSM write flows enforce output/input token compatibility (`underlying` or `static aToken`).
- `rescueToken` is `onlyOwner`.

Limitations of current implementation:

- No internal pause/circuit-breaker.
- No explicit reentrancy guard.
- No on-swap revalidation of GSM `GHO_TOKEN`.
- The router does not explicitly reset allowances to zero after each operation.

## Documented failure modes

### 1) Dependency outage, pause, or insolvency

What can happen:

- Swaps revert or settle unexpectedly if GSM/static aToken/sGHO/token dependencies fail.

Why:

- Router delegates pricing and settlement to external contracts.

Impact:

- Route unavailable or economically unsafe.

Current mitigation:

- Fail-fast reverts.
- External monitoring and route-level disabling by operators.

### 2) GSM mapping misconfiguration or admin compromise

What can happen:

- Valid routes can be unintentionally removed, or unsafe token-to-GSM mappings can be added.

Why:

- Allowlist updates are owner-controlled and an already-allowed pairing cannot be re-added (must revoke then re-allow).

Impact:

- Route outage or exposure to undesired GSM risk.

Current mitigation:

- `onlyOwner` protection and `TokenToGsmAdded`/`TokenToGsmRemoved` event monitoring.

### 3) Route drift after mapping

What can happen:

- A previously accepted `gsm` can change behavior over time.

Why:

- Underlying route components are re-read at runtime, while `_validateGsm` is only checked on `allowTokenGsm`.

Impact:

- Route behavior can change without router redeploy.

Current mitigation:

- Monitor downstream upgrades/config and remove affected token-to-GSM entries quickly.

### 4) Quote staleness and preview divergence

What can happen:

- Preview outputs can differ from write-call outcomes due to dynamic fees/rates/capacity.

Why:

- External pricing state can change between quote and execution.

Impact:

- Quote UX mismatch, revert, or lower output than expected.

Current mitigation:

- Execution-time minimum output checks via `minAmountOut`.
- Conservative slippage buffers.

### 5) Partial consumption and residual balances

What can happen:

- Requested amounts are not fully consumed by downstream contracts.

Why:

- GSM buy/sell paths can partially fill based on external conditions (rounding error).

Impact:

- A tiny portion could be lost but the gas used to return funds would be more expensive than the funds (rounding error).

Current mitigation:

- Slippage checks on outputs.
- Owner-operated `rescueToken` for recovery.
- Balance monitoring by operators.

### 6) sGHO compatibility or misconfiguration

What can happen:

- sGHO paths may revert or behave unexpectedly.

Why:

- Constructor checks `asset() == GHO` but cannot anticipate future vault behavior changes.

Impact:

- Broken path or fund-loss risk if vault semantics change post-deployment.

Current mitigation:

- Deployment hygiene and post-deploy validation.

### 7) Non-standard token behavior

What can happen:

- Fee-on-transfer/rebasing/non-standard approval semantics can break path assumptions.

Why:

- Router assumes compatible ERC20 behavior on selected routes.

Impact:

- Reverts or unexpected settlement.

Current mitigation:

- `SafeERC20` and known-asset route curation.

### 8) Residual allowance risk

What can happen:

- If funds are stranded in the router, approved spenders may retain pull capability.

Why:

- Allowances set via `forceApprove` are not explicitly cleared after calls.

Impact:

- Recovery complexity and increased dependency trust surface.

Current mitigation:

- Keep router balances near zero operationally.
- Monitor allowances and balances.
- Use `rescueToken` under controlled governance.

### 9) Owner rescue authority

What can happen:

- Owner can withdraw any ERC20 held by router.

Why:

- `rescueToken` is intentionally broad for recovery.

Impact:

- Centralization and key-management risk.

Current mitigation:

- Multisig/governance ownership and event monitoring.

## Integrator guidance

1. Monitor `TokenToGsmAdded` and `TokenToGsmRemoved` events; verify `allowedGsm(token, gsm)` returns `true` for the `gsm` you intend to route through before submitting GSM swaps.
2. Quote via `previewSwap` immediately before execution and set conservative `minAmountOut`.
3. Monitor router token balances for residual/stuck funds.
4. Alert on downstream GSM/static aToken/sGHO upgrades, pauses, and parameter changes.
5. Treat fork tests as integration smoke tests, not full economic assurance.
