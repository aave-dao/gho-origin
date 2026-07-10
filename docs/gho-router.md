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

On `GHO <-> sGHO` paths, the GSM address is ignored.
Any `tokenIn`/`tokenOut` pair that does not match these six paths reverts with `InvalidTokenPair(tokenIn, tokenOut)`.
A `GHO <-> GHO` path will revert with `InvalidToken` rather than the above mentioned `InvalidTokenPair(tokenIn, tokenOut)`.

Important shape of the current design:

- `GHO` and `sGHO` are immutable constructor params.
- The GSM to use is supplied by the caller as the `gsm` argument; the router validates it against the `allowedGsm` allowlist before use.
- The same GSM can be reached with either its static aToken or that aToken's underlying; the caller picks the token and the router derives whether wrapping is needed.
- GSM paths are gated by on-chain allowlist state in `allowedGsm`.
- The router keeps no per-user accounting state.

## GSM mapping and validation model

The configuration is split into two independent concerns: which GSMs are trusted, and which underlying tokens have a known static aToken (stata) wrapper.

- Storage:
  - `mapping(address gsm => bool allowed) public allowedGsm` — the GSM allowlist.
  - `mapping(address token => address stata) public tokenToStata` — underlying token → its static aToken (ERC4626).
- Update path:
  - `allowGsm(address gsm)` (`onlyOwner`) — allowlists a GSM.
  - `revokeGsm(address gsm)` (`onlyOwner`) — removes a GSM from the allowlist.
  - `setTokenToStata(address token, address stata)` (`onlyOwner`) — registers the underlying → stata mapping used by wrap/unwrap routes.
  - `removeTokenToStata(address token)` (`onlyOwner`) — removes an existing underlying → stata mapping.
- Constraints on `allowGsm`:
  - `gsm` must be non-zero and not already allowed (reverts `GsmAlreadySet()`; revoke first).
  - `_validateGsm(gsm)` is run:
    - `gsm.code.length != 0`
    - `IGsm(gsm).GHO_TOKEN() == GHO`
    - `IGsm(gsm).UNDERLYING_ASSET() != address(0)`
- Constraints on `revokeGsm`:
  - `gsm` must currently be allowed, otherwise reverts `GsmNotSet()`.
- Constraints on `setTokenToStata`:
  - Both `token` and `stata` must be non-zero.
  - `token` must not already have a mapping (reverts `TokenToStataAlreadySet()`; remove it first).
  - `IERC4626(stata).asset() == token` — the stata must actually wrap the token (reverts `InvalidToken()`).
- Constraints on `removeTokenToStata`:
  - `token` must currently have a mapping, otherwise reverts `TokenToStataNotSet()`.
- Swap enforcement (`_validateGsmInput(token, gsm)`):
  - `allowedGsm[gsm]` must be set, otherwise reverts `GsmNotConfigured()`.
  - Let `gsmAsset = IGsm(gsm).UNDERLYING_ASSET()`. Then:
    - `token == gsmAsset` → route directly through the GSM (no wrapping).
    - `tokenToStata[token] == gsmAsset` → wrap/unwrap `token` through the stata around the GSM call.
    - otherwise reverts `InvalidToken()`.
- Observability: `GsmAdded(gsm)`, `GsmRemoved(gsm)`, `TokenToStataSet(token, stata)`, and `TokenToStataRemoved(token, stata)` are emitted on every update.

## Runtime route composition

For GSM paths, the caller supplies the `gsm` and the router composes the route from it at execution time via `_validateGsmInput`:

- Router checks `allowedGsm[gsm]`, reverting `GsmNotConfigured()` if not allowed.
- Router reads `IGsm(gsm).UNDERLYING_ASSET()` to get the GSM asset (`gsmAsset`).
- Router classifies the supplied `token`:
  - `token == gsmAsset` → settle directly in `gsmAsset` (covers both plain GSMs and stata GSMs entered with the static aToken).
  - `tokenToStata[token] == gsmAsset` → wrap on the way in / unwrap on the way out via the stata.
  - otherwise revert `InvalidToken()`.

Important properties:

- Token classification never calls `IERC4626(gsmAsset).asset()` at swap time. It relies on the curated `tokenToStata` registry, so a plain (non-stata) GSM paired with an incompatible token reverts cleanly with `InvalidToken()` rather than a low-level revert.
- `_validateGsm` checks full GSM compatibility (e.g. `GHO_TOKEN`) only when the GSM is allowlisted, not on every swap.
- Preview methods do not re-validate the GSM's `GHO_TOKEN` on each call.

## Security assumptions

The current implementation assumes:

1. Owner securely manages the `allowedGsm` allowlist and the `tokenToStata` registry, curating safe GSMs and correct underlying → stata mappings.
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
- GSM write flows are gated by `allowedGsm[gsm]` for the caller-supplied `gsm`.
- GSM write flows enforce input/output token compatibility against the GSM asset and `tokenToStata` registry (`InvalidToken()`).
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

- Valid routes can be unintentionally removed, or unsafe GSMs / incorrect `tokenToStata` mappings can be added.

Why:

- Allowlist updates are owner-controlled and an already-allowed GSM cannot be re-added (must revoke then re-allow).

Impact:

- Route outage or exposure to undesired GSM risk.

Current mitigation:

- `onlyOwner` protection and `GsmAdded`/`GsmRemoved`/`TokenToStataSet`/`TokenToStataRemoved` event monitoring.

### 3) Route drift after mapping

What can happen:

- A previously accepted `gsm` can change behavior over time.

Why:

- Underlying route components are re-read at runtime, while `_validateGsm` is only checked on `allowGsm`.

Impact:

- Route behavior can change without router redeploy.

Current mitigation:

- Monitor downstream upgrades/config and revoke affected GSMs quickly.

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

1. Monitor `GsmAdded`, `GsmRemoved`, `TokenToStataSet`, and `TokenToStataRemoved` events; verify `allowedGsm(gsm)` returns `true` for the `gsm` you intend to route through (and that your token is the GSM asset or registered in `tokenToStata`) before submitting GSM swaps.
2. Quote via `previewSwap` immediately before execution and set conservative `minAmountOut`.
3. Monitor router token balances for residual/stuck funds.
4. Alert on downstream GSM/static aToken/sGHO upgrades, pauses, and parameter changes.
5. Treat fork tests as integration smoke tests, not full economic assurance.
