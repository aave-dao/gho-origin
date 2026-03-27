# GhoRouter Failure Modes and Security Assumptions

This document captures trust assumptions and failure modes for the current
router implementation at:

- `src/contracts/misc/GhoRouter.sol`

It is intended for integrators, operators, and reviewers.

## Scope and trust boundary

`GhoRouter` orchestrates six flows:

- `swapToGho(gsm, token, amount, minGHOAmount[, recipient])` for GSM token -> GHO
- `swapFromGho(gsm, token, ghoAmount, minOutputAmount[, recipient])` for GHO -> GSM underlying token/static aToken
- `swapToSGho(gsm, token, amount, minSGHOAmount[, recipient])` for GSM token -> sGHO
- `depositForSGho(ghoAmount, minSGHOAmount[, recipient])` for direct GHO -> sGHO
- `swapFromSGho(gsm, token, sghoAmount, minOutputAmount[, recipient])` for sGHO -> GSM underlying token/static aToken
- `redeemSGho(sghoAmount, minOutputAmount[, recipient])` for direct sGHO -> GHO

Important shape of the current design:

- `GHO` and `sGHO` are immutable constructor params.
- `gsm` is caller-supplied on GSM paths.
- GSM paths are gated by on-chain allowlist state in `isGsmAllowed`.
- The router keeps no per-user accounting state.

## GSM allowlist and validation model

- Storage: `mapping(address => bool) public isGsmAllowed`.
- Update path: `setGsmAllowed(address gsm, bool allowed)` (`onlyOwner`).
- Update constraints:
  - `gsm != address(0)` always.
  - Enabling (`allowed = true`) runs `_validateGsm(gsm)`:
    - `gsm.code.length != 0`
    - `IGSM(gsm).GHO_TOKEN() == GHO`
    - `IGSM(gsm).UNDERLYING_ASSET() != address(0)`
    - `IStaticAToken(stataToken).asset() != address(0)`
- Swap enforcement:
  - All GSM swap overloads require `isGsmAllowed[gsm] == true`.
- Observability: `GsmAllowedUpdated(gsm, allowed)` is emitted on every update.

## Runtime route composition

For GSM paths, token resolution at execution time is dynamic:

- Router reads `IGSM(gsm).UNDERLYING_ASSET()` to get `stataToken`.
- Router reads `IStaticAToken(stataToken).asset()` to get the underlying token.

Important caveat:

- `_validateGsm` checks compatibility when allowlisting is enabled, not on every swap.
- Preview methods also do not enforce `isGsmAllowed`.

## Security assumptions

The current implementation assumes:

1. Owner securely manages `isGsmAllowed` and curates safe GSM addresses.
2. `IGSM`, `IStaticAToken`, and `sGHO` dependencies are interface-compatible and non-malicious.
3. External dependency return values are correct (router accounting uses returned values).
4. Underlying tokens involved in selected routes have ERC20 semantics compatible with `SafeERC20`.
5. Users/integrators set realistic slippage bounds.
6. Owner key management is trusted for `rescueToken`.

## Security properties in the current implementation

- Slippage checks are enforced on write flows via `SlippageExceeded`:
  - `minGHOAmount`, `minOutputAmount`, `minSGHOAmount`
- Recipient is validated as non-zero on all write flows.
- GSM write flows are gated by `isGsmAllowed`.
- SM write flows enforce output/input token compatibility (`underlying` or `static aToken`).
- `rescueToken` is `onlyOwner`.

Limitations of current implementation:

- No internal pause/circuit-breaker.
- No explicit reentrancy guard.
- No on-swap revalidation of GSM `GHO_TOKEN`.
- Preview methods can return quotes for non-allowlisted GSMs.
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

### 2) GSM allowlist misconfiguration or admin compromise

What can happen:

- Valid routes can be unintentionally disabled, or unsafe routes can be enabled.

Why:

- Allowlist updates are owner-controlled.

Impact:

- Route outage or exposure to undesired GSM risk.

Current mitigation:

- `onlyOwner` protection and `GsmAllowedUpdated` monitoring.

### 3) Route drift after allowlisting

What can happen:

- A previously accepted `gsm` can change behavior over time.

Why:

- Underlying route components are re-read at runtime, while `_validateGsm` is only checked on enable.

Impact:

- Route behavior can change without router redeploy.

Current mitigation:

- Monitor downstream upgrades/config and disable affected GSM entries quickly.

### 4) Preview/allowlist mismatch and quote staleness

What can happen:

- Preview calls can succeed but swap later reverts with `GsmNotAllowed`.
- Preview outputs can differ from write-call outcomes due to dynamic fees/rates/capacity.

Why:

- Preview methods do not enforce `isGsmAllowed`.
- External pricing state can change between quote and execution.

Impact:

- Quote UX mismatch, revert, or lower output.

Current mitigation:

- Execution-time minimum output checks.
- Conservative slippage buffers.
- Integrators should check `isGsmAllowed(gsm)` before submitting GSM swaps.

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

- `swapToSGho`/`swapFromsGHO` paths may revert or behave unexpectedly.

Why:

- Constructor checks only `sgho != address(0)` and checks underlying is GHO.

Impact:

- Broken path or fund-loss risk if deployed with an incompatible vault.

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

1. Monitor `GsmAllowedUpdated` and verify `isGsmAllowed(gsm)` before GSM swaps.
2. Quote immediately before execution and set conservative minimum outputs.
3. Monitor router token balances for residual/stuck funds.
4. Alert on downstream GSM/static aToken/sGHO upgrades, pauses, and parameter changes.
5. Treat fork tests as integration smoke tests, not full economic assurance.
