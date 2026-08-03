// mulDiv summary that computes Ceil as the single closed form `(x*y + d - 1)/d`; the
// optimality proofs reason about that form far better than about a floor + remainder-bump.
// Conflict variant: `Math.Rounding` is ambiguous (two `Math` libraries), so the enum is
// qualified by FixedFeeStrategyHarness (imports the OZ v5 Math), present in optimality.conf.
// Implementation lives in mulDiv_summaries.spec.
import "mulDiv_summaries.spec";

methods {
  function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
  function _.mulDiv(uint256 x, uint256 y, uint256 denominator, FixedFeeStrategyHarness.Rounding rounding) internal =>
    mulDivRoundingClosed(x, y, denominator,
        rounding == FixedFeeStrategyHarness.Rounding.Ceil ||
        rounding == FixedFeeStrategyHarness.Rounding.Expand
    ) expect (uint256);
}
