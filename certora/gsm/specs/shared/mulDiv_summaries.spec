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

// Same value as mulDivRounding, written as the single closed form (x*y+d-1)/d for Ceil.
// The optimality proofs reason about this closed form far better than the reuse-floor form.
function mulDivRoundingClosed(uint256 x, uint256 y, uint256 denominator, bool roundUp) returns uint256 {
    require denominator > 0;
    if (roundUp) {
        return require_uint256((x * y + denominator - 1) / denominator);
    }
    return require_uint256((x * y) / denominator);
}
