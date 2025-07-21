# Precision, Rounding, and Edge Case Handling in sGHO

## Overview

This document details how precision, rounding, and edge cases are handled in the `sGHO` contract, with a focus on:
- Mathematical operations (deposits, withdrawals, yield accrual)
- The use of WadRayMath (Aave's math library)
- Rounding modes and their implications
- Edge cases related to time, rates, and conversions

---

## Units and Math Libraries

- **Wad**: 18 decimal places (1e18), used for standard ERC20 math.
- **Ray**: 27 decimal places (1e27), used for high-precision interest/yield math.
- **WadRayMath**: Aave's math library for safe, high-precision arithmetic. All core math in sGHO uses this library.

### WadRayMath Rounding
- All multiplication and division operations round **half up** (i.e., values >= 0.5 round up, otherwise down).
- See [WadRayMath.sol](../../lib/aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol) for implementation details.

---

## Yield Accrual and Indexing

- Yield is accrued linearly between state updates (deposit, withdraw, mint, redeem), but compounds across multiple updates.
- The yield index (`yieldIndex`) is always stored and updated in **ray** (1e27).
- The target rate (`targetRate`) is set in **basis points** (1e4 = 100%).

> **Note:** Even if the target rate is set to the maximum (50% APR) and the yield is compounded daily due to user actions for 100 years, the `yieldIndex` will not exceed approximately `5e29`. This demonstrates that the system is robust against overflow and extreme long-term compounding scenarios.
>
> **See:** `test_yieldIndex_10YearsDailyCompounding_MaxRate` in `sGhoPrecision.t.sol` for a contract-vs-theoretical comparison, and the theoretical 100-year value.

### Yield Index Update Formula

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

- **Rounding**: All intermediate steps use WadRayMath, so rounding is always half-up.
- **Time**: If no time has passed, or the rate is zero, the index is unchanged.
- **Compounding**: Compounding only occurs across multiple updates, not within a single update period.

---

## Asset/Share Conversion

- All conversions between GHO (assets) and sGHO (shares) use the current yield index and WadRayMath's `mulDiv` with explicit rounding direction.
- The contract uses OpenZeppelin's `Math.mulDiv` for conversions, which allows specifying rounding direction (typically `Math.Rounding.Floor`).

### Conversion Functions

```solidity
function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
  uint256 currentYieldIndex = _getCurrentYieldIndex();
  if (currentYieldIndex == 0) return 0;
  return assets.mulDiv(WadRayMath.RAY, currentYieldIndex, rounding);
}

function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
  uint256 currentYieldIndex = _getCurrentYieldIndex();
  return shares.mulDiv(currentYieldIndex, WadRayMath.RAY, rounding);
}
```

- **Rounding**: The rounding mode is explicitly passed (usually `Floor` for user-facing queries).
- **Zero Index**: If the yield index is zero (should not occur in practice), conversions return zero.

---

## Share Value, Precision, and Minimum Recommended Amounts

The value of each share (in GHO) increases as the yield index grows. At very high yield index values (e.g., after many years of compounding at high rates), the smallest possible share (1 wei) can be worth a significant amount of GHO, and attempting to deposit or withdraw very small amounts can result in substantial precision loss due to integer division rounding.

**Relationship:**
- The minimum asset amount that can be converted to at least 1 share is:
  
  `minAssets = yieldIndex / 1e27`

- The minimum share amount that can be converted to at least 1 asset is:
  
  `minShares = 1e27 / yieldIndex`

**Warning:**
> To avoid significant precision loss, it is recommended to avoid depositing or withdrawing less than **1e4 wei** (0.00001 GHO) at any time. At high yield index values, smaller amounts may be rounded down to zero or may burn more shares than expected, resulting in a loss of value for the user.

- **See:** `test_precisionLossExtremeYieldIndex` and `test_precisionLossThreshold_convertToShares` in `sGhoPrecision.t.sol` for demonstrations of this effect at high yield index values and for the smallest possible share.

This is a fundamental limitation of fixed-point math in Solidity and is common to all protocols using integer math for share/asset conversions.

---

## Edge Cases and Limitations

### 1. **Zero Rate or Zero Time**
- If `targetRate == 0` or `block.timestamp == lastUpdate`, no yield accrues; the index remains unchanged.
- **See:** `test_yield_zeroTargetRate` and `test_yield_zeroTimeSinceLastUpdate` in `sGhoPrecision.t.sol`.

### 2. **Rounding Losses**
- Small deposits/withdrawals may be rounded down to zero if below the minimum precision (1e-27 for rays).
- Over time, repeated rounding may cause very small discrepancies, but these are minimized by high precision.
- **See:** `test_precisionLossThreshold_convertToShares`, `test_precisionLossThreshold_convertToAssets_largeYieldIndex`, and `test_precisionLossExtremeYieldIndex` in `sGhoPrecision.t.sol`.

### 3. **Max Withdraw/Max Redeem**
- Withdrawals and redemptions are limited by both the user's share balance and the contract's actual GHO balance.
- If the contract is under-collateralized, users may not be able to withdraw their full share value.
- **See:** `test_gho_shortfall_detection` and related shortfall tests in `sGhoPrecision.t.sol`.

### 4. **Overflow Protection**
- WadRayMath includes explicit overflow checks; operations revert on overflow or division by zero.
- **See:** `test_edgecase_overflowProtection` in `sGhoPrecision.t.sol`.

### 5. **Supply Cap**
- Deposits/mints are capped by the `supplyCap` (in GHO units). If the cap is reached, further deposits/mints revert.
- **See:** `test_edgecase_supplyCap` and related supply cap tests in `sGhoPrecision.t.sol`.

### 6. **Extreme Rates or Long Time Gaps**
- Very high rates or long periods between updates can cause the yield index to grow rapidly. However, the contract enforces a `MAX_SAFE_RATE` (50% APR) to prevent extreme compounding.
- If the time gap is extremely large, the linear approximation may diverge from true compounding, but this is mitigated by the compounding-on-update design.
- **See:** `test_overflow_timeGapIsAstronomical` and `test_yieldIndex_10YearsDailyCompounding_MaxRate` in `sGhoPrecision.t.sol`.

---

## Summary Table

| Operation                | Precision | Rounding      | Edge Case Handling                |
|--------------------------|-----------|---------------|-----------------------------------|
| Yield accrual            | Ray (1e27)| Half-up       | Zero rate/time, overflow checks   |
| Asset/share conversion   | Ray (1e27)| Floor/half-up | Zero index returns zero           |
| Deposit/mint/withdraw    | Wad/Ray   | Floor/half-up | Capped by supplyCap, GHO balance  |
| Permit/approval          | Wad       | N/A           | Standard ERC20/EIP-2612           |

---

## References
- [WadRayMath.sol](../../lib/aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol)
- [OpenZeppelin Math.sol](https://docs.openzeppelin.com/contracts/4.x/api/utils#Math)
- [sGHO.sol](./sGHO.sol)

---

*This document is intended for developers, auditors, and integrators seeking to understand the precision and edge case handling in sGHO.* 