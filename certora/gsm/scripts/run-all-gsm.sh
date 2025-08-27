#CMN="--compilation_steps_only"

echo
echo "******** 1. Running: gsm/gho-gsm-1.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-gsm-1.conf \
           --msg "1. gsm/gho-gsm-1.conf"

echo
echo "******** 2. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-gsm-2.conf \
           --msg "2. gsm/gho-gsm-2.conf"

echo
echo "******** 3. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-gsm-inverse.conf \
           --msg "3. gsm/gho-gsm-inverse.conf"

echo
echo "******** 4. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/balances-buy.conf \
           --msg "4. "

echo
echo "******** 5. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/balances-sell.conf \
           --exclude_rule R3_sellAssetUpdatesAssetBalanceCorrectly R4_buyGhoUpdatesGhoBalanceCorrectly \
           --msg "5. conf/gsm/balances-sell.conf:: All except R3,R4"

# waiting for ticket CERT-9408
#echo
#echo "******** 5a. Running:    ****************"
#certoraRun $CMN certora/gsm/conf/gsm/balances-sell.conf --rule R3_sellAssetUpdatesAssetBalanceCorrectly \
#           --msg "5a. conf/gsm/balances-sell.conf:: R3"


# waiting for ticket CERT-9408
#echo
#echo "******** 5b. Running:    ****************"
#certoraRun $CMN certora/gsm/conf/gsm/balances-sell.conf --rule R4_buyGhoUpdatesGhoBalanceCorrectly\
#           --msg "5b. conf/gsm/balances-sell.conf:: R4"

echo
echo "******** 6. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/fees-buy.conf \
           --msg "6. "

echo
echo "******** 7a. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/fees-sell.conf --exclude_rule R3_estimatedSellFeeCanBeHigherThanActualSellFee \
           --msg "7a. fees-sell.conf:: exclude_rule R3"

echo
echo "******** 7b. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/fees-sell.conf --rule R3_estimatedSellFeeCanBeHigherThanActualSellFee \
           --msg "7b. fees-sell.conf:: rule R3"

echo
echo "******** 8. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-assetToGhoInvertibility.conf --rule basicProperty_getAssetAmountForBuyAsset sellAssetInverse_all buyAssetInverse_all basicProperty_getGhoAmountForSellAsset basicProperty_getAssetAmountForSellAsset basicProperty_getGhoAmountForBuyAsset \
           --msg "8. "

echo
echo "******** 9. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-assetToGhoInvertibility.conf --rule basicProperty2_getAssetAmountForBuyAsset \
           --msg "9. "

echo
echo "******** 10. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/optimality.conf --rule R3_optimalityOfSellAsset_v1 R1_optimalityOfBuyAsset_v1 R6a_externalOptimalityOfBuyAsset R5a_externalOptimalityOfSellAsset R2_optimalityOfBuyAsset_v2 \
           --msg "10. "

echo
echo "******** 11. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/getAmount_properties.conf --rule getAssetAmountForBuyAsset_funcProperty_LR getAssetAmountForBuyAsset_funcProperty_RL \
           --msg "11. "

echo
echo "******** 12. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/finishedRules.conf --rule whoCanChangeExposure whoCanChangeAccruedFees sellingDoesntExceedExposureCap cantBuyOrSellWhenSeized giftingGhoDoesntAffectStorageSIMPLE giftingUnderlyingDoesntAffectStorageSIMPLE collectedBuyFeePlus1IsAtLeastAsRequired sellAssetSameAsGetGhoAmountForSellAsset collectedSellFeeIsAtLeastAsRequired collectedBuyFeeIsAtLeastAsRequired correctnessOfBuyAsset collectedBuyFeePlus2IsAtLeastAsRequired getAssetAmountForSellAsset_correctness cantBuyOrSellWhenFrozen whoCanChangeExposureCap cantSellIfExposureTooHigh sellAssetIncreasesExposure buyAssetDecreasesExposure rescuingGhoKeepsAccruedFees rescuingAssetKeepsAccruedFees \
           --msg "12. "


echo
echo "******** 13. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/gho-fixedPriceStrategy.conf \
           --msg "13. gsm/gho-fixedPriceStrategy.conf"

echo
echo "******** 14. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/FixedFeeStrategy.conf \
           --msg "14. gsm/FixedFeeStrategy.conf"

echo
echo "******** 15. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm/OracleSwapFreezer.conf \
           --msg "15. "

