// mulDiv summary for confs where two `Math` libraries make `Math.Rounding` ambiguous:
// qualify the enum by FixedFeeStrategyHarness (imports the OZ v5 Math), present in every
// conflicting conf that imports this spec. Implementation lives in mulDiv_summaries.spec.
import "mulDiv_summaries.spec";

methods {
  function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
  // The `FixedFeeStrategyHarness.Rounding` type binds this summary to the OZ v5 `Math.Rounding`
  // (via disambiguation by originating contract). Matching is type-exact: the vendored OZ v4
  // `Math.mulDiv(...,{Down,Up,Zero})` is a different type and never matches this summary.
  function _.mulDiv(uint256 x, uint256 y, uint256 denominator, FixedFeeStrategyHarness.Rounding rounding) internal =>
    mulDivRounding(x, y, denominator, rounding == FixedFeeStrategyHarness.Rounding.Ceil) expect (uint256);
}
