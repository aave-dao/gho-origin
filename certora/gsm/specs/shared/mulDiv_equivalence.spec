// Guards the mulDiv summaries in mulDiv_summaries.spec against silent drift.
// The confs pick between an exact, a nondeterministic and a closed-form encoding purely for
// solver tractability, so all three must denote the same value. Nothing else enforces that:
// loosening one of the nondet bounds would weaken every proof routed through it while leaving
// CI green, so the equality is proven here instead of being assumed.
import "mulDiv_summaries.spec";

// @title The nondet encoding pins the same quotient as the exact floor division
rule mulDivNondetEqMulDivSummary(uint256 x, uint256 y, uint256 denominator) {
    assert mulDivNondet(x, y, denominator) == mulDivSummary(x, y, denominator);
}

// @title The nondet encoding pins the same quotient as the exact division, both roundings
rule mulDivNondetRoundingEqMulDivRounding(uint256 x, uint256 y, uint256 denominator, bool roundUp) {
    assert mulDivNondetRounding(x, y, denominator, roundUp) ==
        mulDivRounding(x, y, denominator, roundUp);
}

// @title The closed form (x*y+d-1)/d agrees with floor plus a remainder bump
rule mulDivRoundingClosedEqMulDivRounding(uint256 x, uint256 y, uint256 denominator, bool roundUp) {
    assert mulDivRoundingClosed(x, y, denominator, roundUp) ==
        mulDivRounding(x, y, denominator, roundUp);
}
