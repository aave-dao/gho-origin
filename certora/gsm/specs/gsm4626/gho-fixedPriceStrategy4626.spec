import "erc4626.spec";
import "../shared/mulDiv_summaries.spec";

methods {
    function getAssetPriceInGho(uint256, bool) external returns (uint256) envfree;
    function getGhoPriceInAsset(uint256, bool) external returns (uint256) envfree;
    function _.mulDiv(uint256 x, uint256 y, uint256 denominator) internal => mulDivSummary(x, y, denominator) expect (uint256);
    // Single `Math` in scene here, so the rounding enum is referenced unqualified as `Math.Rounding`.
    function _.mulDiv(uint256 x, uint256 y, uint256 denominator, Math.Rounding rounding) internal =>
        mulDivRounding(x, y, denominator,
            rounding == Math.Rounding.Ceil ||
            rounding == Math.Rounding.Expand
        ) expect (uint256);
}

// https://prover.certora.com/output/17512/4273175adeae4a289be8401c82ab9e14?anonymousKey=3dd87914a5a95f469b25a2666ffa484f4b734c34


rule assetToGhoAndBackAllErrorBounds() {
    env e;
    uint256 originalAssetAmount;

    mathint underlyingAssetUnits = getUnderlyingAssetUnits(e);
    require underlyingAssetUnits > 0; // safe as this number should be equal to 10 ** underlyingAssetDecimals
    uint256 priceRatio = getPriceRatio(e);
    require priceRatio > 0;

    mathint maxError =  (3*underlyingAssetUnits)/(5*priceRatio) + 2;

    assert to_mathint(getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, false), false)) >= originalAssetAmount - (maxError)
        && originalAssetAmount >= getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, false), false)
        , "rounding down then down";
    assert to_mathint(getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, false), true)) >= originalAssetAmount - (maxError - 1)
        && originalAssetAmount >= getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, false), true)
        , "rounding down then up";
    assert to_mathint(getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, true), false)) <= originalAssetAmount + (maxError - 1)
        && originalAssetAmount <= getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, true), false)
        , "rounding up then down";
    assert to_mathint(getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, true), true)) <= originalAssetAmount + maxError
        && originalAssetAmount <= getGhoPriceInAsset(getAssetPriceInGho(originalAssetAmount, true), true)
        , "rounding up then up";
}

rule ghoToAssetAndBackAllErrorBounds() {
    env e;
    uint256 originalAmountOfGho;

    mathint underlyingAssetUnits = getUnderlyingAssetUnits(e);
    require underlyingAssetUnits > 0; // safe as this number should be equal to 10 ** underlyingAssetDecimals
    uint256 priceRatio = getPriceRatio(e);
    require priceRatio > 0;

    mathint maxError = 11*priceRatio/(3*underlyingAssetUnits) + 1;

    // Notice that even when we round down, we can increase the amount of gho due to rounding in preview withdraw.
    assert to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, false), false)) >= originalAmountOfGho - maxError
        && originalAmountOfGho + priceRatio/underlyingAssetUnits >= to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, false), false))
        , "rounding down then down";
    assert to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, false), true)) >= originalAmountOfGho - maxError
        && originalAmountOfGho + priceRatio/underlyingAssetUnits + 1 >= to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, false), true))
        , "rounding down then up";
    assert to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, true), false)) <= originalAmountOfGho + maxError
        && originalAmountOfGho <= getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, true), false)
        , "rounding up then down";
    assert to_mathint(getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, true), true)) <= originalAmountOfGho + maxError
        && originalAmountOfGho <= getAssetPriceInGho(getGhoPriceInAsset(originalAmountOfGho, true), true)
        , "rounding up then up";
}

rule getAssetPriceIsMonotone() {
    env e;
    uint256 amount1;
    uint256 amount2;

    assert amount1 > amount2 => getAssetPriceInGho(amount1, false) >= getAssetPriceInGho(amount2, false);
    assert amount1 > amount2 => getAssetPriceInGho(amount1, true) >= getAssetPriceInGho(amount2, true);
}

rule getGhoPriceIsMonotone() {
    env e;
    uint256 amount1;
    uint256 amount2;

    assert amount1 > amount2 => getGhoPriceInAsset(amount1, false) >= getGhoPriceInAsset(amount2, false);
    assert amount1 > amount2 => getGhoPriceInAsset(amount1, true) >= getGhoPriceInAsset(amount2, true);
}
