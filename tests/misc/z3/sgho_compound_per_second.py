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
# The proof has two parts.
#
# Part 1: the cap bounds P(elapsed) (checked numerically below)
#
# Per second the index is multiplied by B = 1 + x, with x = floor(rate / Y) / RAY. This is the
# code's `base` without the ray scaling (base = B * RAY).
# P(t) = B^t * RAY is what the loop would return over t seconds if it did not round its products.
#
#   1. 1 + x <= e^x for x >= 0, since e^x = 1 + x + x^2/2! + ... and the dropped terms are >= 0.
#   2. Both sides are >= 0, so raising them to t keeps the order: B^t <= e^(x * t).
#   3. floor(rate / Y) <= rate / Y, so x * t <= rate * t / (Y * RAY). e^ is increasing, so
#      B^t <= e^(rate * t / (Y * RAY)).
#   4. Let v = rate * elapsed / Y, unrounded. The cap passes only if floor(v) <= 21 * RAY.
#      Any v is below floor(v) + 1, so v < 21 * RAY + 1 and v / RAY < 21 + 1 / RAY.
#   5. Steps 3 and 4 with t = elapsed give B^elapsed < e^(21 + 1 / RAY). Multiplying by RAY,
#      P(elapsed) < e^(21 + 1 / RAY) * RAY.
#   6. MAX_GROWTH must be at least e^(21 + 1 / RAY) * RAY. The code under "# Part 1" computes
#      that value with 80-digit decimals and asserts it.
#
# So P(elapsed) < MAX_GROWTH.
#
# Part 2: the loop, which rounds down, never exceeds P (proved by z3)
#
# The loop is binary exponentiation. Each row reads one bit of `elapsed`, lowest first, worth
# `step` = 1, 2, 4, 8... seconds, and `base` covers those `step` seconds. When the bit is 1,
# `result` is multiplied by `base`. `processed` counts the seconds of the bits read so far.
# A toy example: x = 1 (100% per second), so B = 1 + x = 2. With no ray, P(t) = 2^t.
# For elapsed = 13 (1101), after each row:
#
#   row | step | bit | base | processed | result
#     0 |      |     |      |         0 |    1 = 2^0
#     1 |    1 |   1 |    2 |         1 |    2 = 2^1
#     2 |    2 |   0 |    4 |         1 |    2 = 2^1
#     3 |    4 |   1 |   16 |         5 |   32 = 2^5
#     4 |    8 |   1 |  256 |        13 | 8192 = 2^13
#
# The real loop divides each product by RAY and rounds down, so result <= P(processed) and
# base <= P(step). Both are at most P(elapsed), which Part 1 keeps below MAX_GROWTH. So every
# product fits in uint256.
#
# z3 cannot compute B^t, so the P values are unknown reals constrained only by facts true for
# any rate: growth over a + b seconds is growth over a times growth over b, and more seconds
# never give less growth. z3 checks one generic iteration: if it starts within the bounds, its
# products fit and it ends within the bounds. The loop starts within them (result = P(0),
# base = P(1)), so every iteration does.
from decimal import Decimal, getcontext

from z3 import *

RAY = 10**27
UINT256_MAX = 2**256 - 1
UINT120_MAX = 2**120 - 1
MAX_ACCRUAL_EXPONENT = 21
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


# Part 1
getcontext().prec = 80
capDescription = "-- VALID Property: e^(MAX_ACCRUAL_EXPONENT + 1 / RAY) * RAY <= MAX_GROWTH --"
capBound = (Decimal(MAX_ACCRUAL_EXPONENT) + Decimal(1) / RAY).exp() * RAY
print("=" * len(capDescription))
print(capDescription)
print("✅ Property is valid." if capBound <= MAX_GROWTH else f"❌ Property is not valid: {capBound}")
print("=" * len(capDescription))

# Part 2
s = Solver()

# Loop state at the start of an iteration: `step` = 2^k is the bit being read, `processed` < step
# the seconds of the bits already read, and `m` = elapsed >> k the bits still to read
elapsed, processed, step, m = Ints("elapsed processed step m")
s.add(0 <= processed, processed < step, m >= 1, elapsed == processed + step * m)

# P(processed), P(step), P(processed + step), P(2 * step) and P(elapsed), in ray
pProcessed, pStep, pProcessedPlusStep, pTwoSteps, pElapsed = Reals(
    "pProcessed pStep pProcessedPlusStep pTwoSteps pElapsed"
)
s.add(pProcessed >= RAY, pStep >= RAY)
s.add(pProcessed * pStep == pProcessedPlusStep * RAY)
s.add(pStep * pStep == pTwoSteps * RAY)
s.add(pProcessed <= pElapsed)
s.add(Implies(processed + step <= elapsed, pProcessedPlusStep <= pElapsed))
s.add(Implies(2 * step <= elapsed, pTwoSteps <= pElapsed))
s.add(pElapsed <= MAX_GROWTH)

# Loop state at the start of the iteration, within the bounds
result, base = Ints("result base")
s.add(RAY <= result, result <= pProcessed)
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
    "next result stays within [RAY, P(seconds processed)]",
    And(RAY <= nextResult, nextResult <= If(bitSet, pProcessedPlusStep, pProcessed)),
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

# After the loop: `uint256(index).mulDiv(growth, RAY).toUint120()`
proveValid(
    s,
    "returned growth fits in uint120",
    nextResult <= UINT120_MAX,
    assumptions=[loopReturns],
)
