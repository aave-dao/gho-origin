// Same routing as methods_divint_summary.spec, but to the nondeterministic (multiplicative)
// mulDiv encodings — for confs whose rules compose several mulDivs with symbolic
// denominators (price ratio, asset units, PF - fee) and time out on the div/mod encoding.
// Semantically identical to the exact summaries; see mulDiv_summaries.spec.
import "mulDiv_summaries.spec";

methods {
  function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivNondet(x, y, denominator);
  function _.mulDiv(uint256 x, uint256 y, uint256 denominator, FixedFeeStrategyHarness.Rounding rounding) internal =>
    mulDivNondetRounding(x, y, denominator, rounding == FixedFeeStrategyHarness.Rounding.Ceil) expect (uint256);
}
