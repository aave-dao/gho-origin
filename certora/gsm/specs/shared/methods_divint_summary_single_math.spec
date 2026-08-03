// mulDiv summary for confs where only one `Math` library is in scene (no conflict),
// so the rounding enum is referenced unqualified as `Math.Rounding`.
// (See methods_divint_summary.spec for the conflict variant.) Implementation lives in
// mulDiv_summaries.spec.
import "mulDiv_summaries.spec";

methods {
  function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
  function _.mulDiv(uint256 x, uint256 y, uint256 denominator, Math.Rounding rounding) internal =>
    mulDivRounding(x, y, denominator,
        rounding == Math.Rounding.Ceil ||
        rounding == Math.Rounding.Expand
    ) expect (uint256);
}
