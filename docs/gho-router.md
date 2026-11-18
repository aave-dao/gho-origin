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
`GHO <-> GHO` and `sGHO <-> sGHO` paths revert with `InvalidToken` (or `GsmNotConfigured` if `gsm` is not allowed) rather than the above mentioned `InvalidTokenPair(tokenIn, tokenOut)`.

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
    - `IGsm(gsm).UNDERLYING_ASSET()` is not `address(0)`, `GHO` or `sGHO` (a GSM settling in GHO or sGHO would only enable `GHO -> GHO` / `sGHO -> sGHO` round trips)
- Constraints on `revokeGsm`:
  - `gsm` must currently be allowed, otherwise reverts `GsmNotSet()`.
- Constraints on `setTokenToStata`:
  - Both `token` and `stata` must be non-zero.
  - `token` must not be `GHO` or `sGHO` (reverts `InvalidToken()`); such a mapping would only enable `GHO -> GHO` / `sGHO -> sGHO` round trips through a GSM.
  - `token` must not already have a mapping (reverts `TokenToStataAlreadySet()`; remove it first).
  - `IERC4626(stata).asset() == token` — the stata must actually wrap the token (reverts `InvalidToken()`).
- Constraints on `removeTokenToStata`:
  - `token` must currently have a mapping, otherwise reverts `TokenToStataNotSet()`.
- Swap enforcement (`_validateGsmInput(token, gsm)`):
  - `allowedGsm[gsm]` must be set, otherwise reverts `GsmNotConfigured()`.
  - Let `gsmAsset = IGsm(gsm).UNDERLYING_ASSET()`. It is re-checked against `GHO` and `sGHO` (reverts `InvalidToken()`), so a GSM upgraded after being allowlisted cannot reopen those round trips. Then:
    - `token == gsmAsset` → route directly through the GSM (no wrapping).
    - `tokenToStata[token] == gsmAsset` → wrap/unwrap `token` through the stata around the GSM call.
    - otherwise reverts `InvalidToken()`.
- Observability: `GsmAdded(gsm)`, `GsmRemoved(gsm)`, `TokenToStataSet(token, stata)`, and `TokenToStataRemoved(token, stata)` are emitted on every update.

## Access control and pausing

`GhoRouter` inherits `Ownable2StepWithGuardian` (BGD `solidity-utils`), which combines OpenZeppelin `Ownable2Step` with a guardian role.

- Owner:
  - Set at construction (`initialOwner`, must be non-zero).
  - Ownership transfers are two-step: `transferOwnership(newOwner)` sets `pendingOwner`, which must call `acceptOwnership()`.
  - Controls `allowGsm`, `revokeGsm`, `setTokenToStata`, `removeTokenToStata`, `rescueToken`, `pause`, and `unpause`.
- Guardian:
  - Set at construction (`initialGuardian`); may be `address(0)`, meaning no guardian.
  - Can call `pause()` and `updateGuardian(newGuardian)`. All other admin functions, including `unpause()`, are owner-only.
  - `updateGuardian` is callable by the owner or the current guardian and may set the guardian to `address(0)`.
  - The guardian is unaffected by ownership transfers or `renounceOwnership()`.
- Pausing:
  - `pause()` (`onlyOwnerOrGuardian`) and `unpause()` (`onlyOwner`).
  - While paused, `swap` and `previewSwap` revert with `EnforcedPause()`. Admin functions remain callable.
- Observability: `OwnershipTransferStarted`, `OwnershipTransferred`, `GuardianUpdated(oldGuardian, newGuardian)`, `Paused(account)`, `Unpaused(account)`.

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
- `_validateGsm` checks full GSM compatibility (e.g. `GHO_TOKEN`) only when the GSM is allowlisted, not on every swap. The exception is the `GHO`/`sGHO` check on `UNDERLYING_ASSET()`, which `_validateGsmInput` repeats on every swap and preview.
- Preview methods do not re-validate the GSM's `GHO_TOKEN` on each call.

## Security assumptions

The current implementation assumes:

1. Owner (governance) securely manages the `allowedGsm` allowlist and the `tokenToStata` registry, curating safe GSMs and correct underlying → stata mappings.
2. `IGsm`, static aToken (`IERC4626`), and `sGHO` dependencies are interface-compatible and non-malicious.
3. `sGHO` is a valid ERC4626 vault over GHO (constructor enforces `IERC4626(sgho).asset() == gho`).
4. External dependency return values are correct (router accounting uses returned values).
5. Underlying tokens involved in selected routes have ERC20 semantics compatible with `SafeERC20`.
6. Users/integrators set realistic slippage bounds.
7. Owner key management is trusted for `rescueToken`.
8. Guardian (if set) is a trusted emergency address; it can halt all swaps but cannot unpause, move funds, or change routing configuration.

## Security properties in the current implementation

- Slippage checks are enforced on write flows via `SlippageExceeded`:
  - `minAmountOut` covers all six internal paths.
- Deadline is validated on every `swap()` call via `DeadlineExpired()`.
- Recipient is validated as non-zero and different from the router on all write flows (`ZeroAddress()` / `InvalidRecipient()`).
- GSM write flows are gated by `allowedGsm[gsm]` for the caller-supplied `gsm`.
- GSM write flows enforce input/output token compatibility against the GSM asset and `tokenToStata` registry (`InvalidToken()`).
- `rescueToken` is `onlyOwner`.
- Swaps can be halted by the owner or guardian via `pause()`; only the owner can resume.
- `swap()` is protected by `nonReentrant`.
- GSM allowances are reset to zero after each `sellAsset`/`buyAsset` call.

Limitations of current implementation:

- No on-swap revalidation of GSM `GHO_TOKEN`; only `UNDERLYING_ASSET()` is re-checked against `GHO` and `sGHO`.
- Allowances to static aTokens and sGHO are exact-amount (`forceApprove`) and are not explicitly reset, since they are expected to be fully consumed.

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
- Owner or guardian can pause the router.

### 2) GSM mapping misconfiguration or admin/guardian compromise

What can happen:

- Valid routes can be unintentionally removed, or unsafe GSMs / incorrect `tokenToStata` mappings can be added.
- A compromised guardian can pause the router (DoS) or rotate the guardian, but cannot unpause, move funds or alter routes; the owner can replace it via `updateGuardian`.

Why:

- Allowlist updates are owner-controlled and an already-allowed GSM cannot be re-added (must revoke then re-allow).

Impact:

- Route outage or exposure to undesired GSM risk.

Current mitigation:

- `onlyOwner` protection and `GsmAdded`/`GsmRemoved`/`TokenToStataSet`/`TokenToStataRemoved` event monitoring.
- `GuardianUpdated`/`Paused` event monitoring.

### 3) Route drift after mapping

What can happen:

- A previously accepted `gsm` can change behavior over time.

Why:

- Underlying route components are re-read at runtime, while `_validateGsm` is only checked on `allowGsm`. A GSM upgraded to settle in `GHO` or `sGHO` is still rejected at swap time; other drift is not caught.

Impact:

- Route behavior can change without router redeploy.

Current mitigation:

- Monitor downstream upgrades/config; pause the router (owner or guardian) and revoke affected GSMs.

### 4) Quote staleness and preview divergence

What can happen:

- Preview outputs can differ from write-call outcomes due to dynamic fees/rates/capacity.
- On the underlying → GHO/sGHO wrap path, `previewSwap` prices the static aToken shares before the router's deposit. Because the deposit rounds shares down, the actual output can exceed the preview by up to one share's worth of underlying. The preview never overestimates on this path.

Why:

- External pricing state can change between quote and execution.

Impact:

- Quote UX mismatch, revert, or lower output than expected.

Current mitigation:

- Execution-time minimum output checks via `minAmountOut`.
- Conservative slippage buffers.

### 5) Residual balances

What can happen:

- The router holds no tokens after a swap. Rounding can make the GSM take or spend slightly less than offered; the router returns the difference to the caller instead of keeping it.

Why:

- GSMs do not partially fill: `buyAsset`/`sellAsset` either execute in full for the quoted amount or revert.
- On buy paths the GSM quotes whole units of its asset, so the GHO actually spent (`ghoUsed`) can be slightly below the GHO available. For GHO → token the router pulls only `ghoUsed` from the caller. For sGHO → token the caller's sGHO is redeemed in full first, and the unspent `ghoAmount - ghoUsed` is returned to the caller (`msg.sender`), not to `recipient`. Integrations calling the router on behalf of users receive this GHO and must forward it themselves.
- On sell paths the GSM recomputes the asset amount it takes from the quoted GHO, which can be below the amount offered (e.g. 18-decimal assets or static aTokens with a sell fee, or a static aToken rate below 1). The unsold `amount - assetSold` of the GSM asset is returned to the caller (`msg.sender`), not to `recipient`. On the underlying → GHO/sGHO path it is returned as static aToken shares, not unwrapped.

Impact:

- None for the router balance. Integrations calling the router on behalf of users receive the refunded GSM asset or GHO and must forward it themselves.

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

- GSM approvals are reset to zero after each call; only the exact-amount `forceApprove` approvals to static aTokens and sGHO are not explicitly cleared.

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
6. Check `paused()` before routing; monitor `Paused`/`Unpaused` events.
