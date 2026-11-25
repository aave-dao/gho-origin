# Proves the unchecked loop in sGho._calculateCompoundedInterest cannot overflow.
# Run with: pip install z3-solver && python3 tests/misc/z3/sgho_compound_per_second.py
#
#   if ((rate * elapsed) / SECONDS_PER_YEAR > MAX_ACCRUAL_EXPONENT * RAY) revert YieldIndexOverflow();
#   result = RAY;
#   if (elapsed == 0) return result;
#   uint256 base = RAY + rate / SECONDS_PER_YEAR;
#   unchecked {
#     while (true) {
#       if (elapsed & 1 != 0) result = (result * base) / RAY;
#       elapsed >>= 1;
#       if (elapsed == 0) return result;
#       base = (base * base) / RAY;
#     }
#   }
#
# The loop is binary exponentiation: `base` covers 1, 2, 4, 8... seconds, and `result` multiplies
# in the bases for the bits of `elapsed`. With B = 2, no ray and elapsed = 13 (1101):
#
#   row | step | low | bit | base | result after
#     1 |    1 |   0 |   1 |    2 |      2
#     2 |    2 |   1 |   0 |    4 |      2
#     3 |    4 |   1 |   1 |   16 |     32
#     4 |    8 |   5 |   1 |  256 |   8192 = 2^13
#
# P(t) is the exact growth over t seconds, without rounding. Rounding down keeps
# result <= P(low) and base <= P(step). Both are at most P(elapsed), which the cap keeps below
# e^21 * RAY, since (1 + r)^n <= e^(r * n). So every product fits in uint256.
#
# z3 cannot compute B^t, so the P values are unknown reals constrained only by facts true for
# any rate: growth over a + b seconds is growth over a times growth over b, and more seconds
# never give less growth. z3 checks one generic iteration: if it starts within the bounds, its
# products fit and it ends within the bounds. The loop starts within them (result = P(0),
# base = P(1)), so every iteration does.
from z3 import *

RAY = 10**27
UINT256_MAX = 2**256 - 1
UINT120_MAX = 2**120 - 1
MAX_GROWTH = 1318816 * 10**30  # e^21 * RAY, rounded up


def proveValid(s, propertyDescription, property, assumptions=[]):
    propertyDescriptionOutput = f"-- VALID Property: {propertyDescription} --"
    print("=" * len(propertyDescriptionOutput))
    print(propertyDescriptionOutput)

    result = s.check(Not(property), *assumptions)
    if result == sat:
        print("❌ Property is not valid:")
        print(s.model())
    elif result == unsat:
        print(f"✅ Property is valid.")
    elif result == unknown:
        print("❓ Timed out or unknown.")

    print("=" * len(propertyDescriptionOutput))


s = Solver()

# `step` = 2^k is the bit being processed, `low` < step the seconds already processed, and
# `m` = elapsed >> k the bits still to go
elapsed, low, step, m = Ints("elapsed low step m")
s.add(0 <= low, low < step, m >= 1, elapsed == low + step * m)

# P(low), P(step), P(low + step), P(2 * step) and P(elapsed), in ray
pLow, pStep, pLowPlusStep, pTwoSteps, pElapsed = Reals(
    "pLow pStep pLowPlusStep pTwoSteps pElapsed"
)
s.add(pLow >= RAY, pStep >= RAY)
s.add(pLow * pStep == pLowPlusStep * RAY)
s.add(pStep * pStep == pTwoSteps * RAY)
s.add(pLow <= pElapsed)
s.add(Implies(low + step <= elapsed, pLowPlusStep <= pElapsed))
s.add(Implies(2 * step <= elapsed, pTwoSteps <= pElapsed))
s.add(pElapsed <= MAX_GROWTH)

# Loop state at the start of the iteration, within the bounds
result, base = Ints("result base")
s.add(RAY <= result, result <= pLow)
s.add(RAY <= base, base <= pStep)

bitSet = m % 2 == 1
loopContinues = m / 2 != 0
loopReturns = m / 2 == 0

proveValid(
    s,
    "result * base fits in uint256",
    result * base <= UINT256_MAX,
    assumptions=[bitSet],
)
proveValid(
    s,
    "base * base fits in uint256",
    base * base <= UINT256_MAX,
    assumptions=[loopContinues],
)

nextResult = If(bitSet, (result * base) / RAY, result)
proveValid(
    s,
    "next result stays within [RAY, P(seconds consumed)]",
    And(RAY <= nextResult, nextResult <= If(bitSet, pLowPlusStep, pLow)),
)
proveValid(s, "next result <= MAX_GROWTH", nextResult <= MAX_GROWTH)

nextBase = (base * base) / RAY
proveValid(
    s,
    "next base stays within [RAY, P(2 * step)]",
    And(RAY <= nextBase, nextBase <= pTwoSteps),
    assumptions=[loopContinues],
)
proveValid(
    s, "next base <= MAX_GROWTH", nextBase <= MAX_GROWTH, assumptions=[loopContinues]
)

# After the loop: `uint256(index).mulDiv(growth, RAY).toUint120()`. The cast is SafeCast and
# reverts above uint120, so only the inputs to it need bounds
proveValid(
    s,
    "returned growth fits in uint120",
    nextResult <= UINT120_MAX,
    assumptions=[loopReturns],
)
index = Int("index")
proveValid(
    s,
    "index * growth fits in uint256 for any uint120 index",
    index * nextResult <= UINT256_MAX,
    assumptions=[loopReturns, 0 <= index, index <= UINT120_MAX],
)
