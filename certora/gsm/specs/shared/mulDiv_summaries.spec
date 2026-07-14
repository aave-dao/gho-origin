// Shared (unverified) summaries for OpenZeppelin's `Math.mulDiv`. Use with care!
// Callers pass `roundUp` (true for Math.Rounding.Ceil) so the arithmetic can be reused
// across the different `Math.Rounding` enum qualifiers each conf must use.

function mulDivSummary(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    require denominator > 0;
    return require_uint256((x * y) / denominator);
}

// ceil/floor of x*y/denominator. Reuses the single floor division and bumps by 1 on a
// remainder for Ceil: floor(x*y/d) + (x*y mod d > 0 ? 1 : 0) == ceil(x*y/d). Reusing one
// division term (rather than a separate (x*y+d-1)/d) is far more tractable for the solver.
function mulDivRounding(uint256 x, uint256 y, uint256 denominator, bool roundUp) returns uint256 {
    uint256 base = mulDivSummary(x, y, denominator);
    if (roundUp && (x * y) % denominator > 0) {
        return require_uint256(base + 1);
    }
    return base;
}

// Same value as mulDivSummary/mulDivRounding, but encoded nondeterministically: the result
// is a fresh variable pinned only by its multiplicative floor/ceil bounds plus implied
// linear hints, so no div/mod terms over symbolic denominators reach the solver. floor and
// ceil are unique, so this is an encoding change, not a weakening. Rules composing several
// mulDivs over symbolic denominators (e.g. R4 in balances-sell-4626) time out on the exact
// div-based summaries — even with the bounds and hints added on top of the div term — and
// prove in minutes on this encoding.
function mulDivNondet(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    require denominator > 0;
    uint256 q;
    require q * denominator <= x * y;
    require x * y < (q + 1) * denominator;
    mulDivLinearHints(x, y, denominator, q);
    return q;
}

function mulDivNondetRounding(uint256 x, uint256 y, uint256 denominator, bool roundUp) returns uint256 {
    if (!roundUp) {
        return mulDivNondet(x, y, denominator);
    }
    require denominator > 0;
    uint256 q;
    require x * y <= q * denominator;
    require q * denominator < x * y + denominator;
    mulDivLinearHints(x, y, denominator, q);
    return q;
}

// Implied linear consequences of the multiplicative bounds on q (valid for both floor and
// ceil, for any x, y, d > 0). Semantically redundant, but product-free: they hand the LIA
// overapproximation magnitude facts about q that it otherwise only gets by reasoning about
// the nonlinear bounds, which is what made single splits run for hours.
function mulDivLinearHints(uint256 x, uint256 y, uint256 denominator, uint256 q) {
    require y <= denominator => q <= x;
    require y >= denominator => q >= x;
    require x <= denominator => q <= y;
    require x >= denominator => q >= y;
}

// Same value as mulDivRounding, written as the single closed form (x*y+d-1)/d for Ceil.
// The optimality proofs reason about this closed form far better than the reuse-floor form.
function mulDivRoundingClosed(uint256 x, uint256 y, uint256 denominator, bool roundUp) returns uint256 {
    require denominator > 0;
    if (roundUp) {
        return require_uint256((x * y + denominator - 1) / denominator);
    }
    return require_uint256((x * y) / denominator);
}
