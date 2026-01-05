#CMN="--compilation_steps_only"


echo
echo "******** 1. Running: conf/gsm4626/gho-gsm4626-1.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/gho-gsm4626-1.conf \
           --msg "1. gsm4626/gho-gsm4626.conf"

echo
echo "******** 2a. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/gho-gsm4626-2.conf --rule accruedFeesLEGhoBalanceOfThis \
           --msg "2a. "

echo
echo "******** 2b. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/gho-gsm4626-2.conf --rule accruedFeesNeverDecrease  \
           --msg "2b. "

# waiting for ticket CERT-9408
#echo
#echo "******** 2c. Running:    ****************"
#certoraRun $CMN certora/gsm/conf/gsm4626/gho-gsm4626-2.conf --rule systemBalanceStabilitySell \
#           --msg "2c. "


echo
echo "******** 3. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/gho-gsm4626-inverse.conf --rule buySellInverse27 buySellInverse26 buySellInverse25 buySellInverse24 buySellInverse23 buySellInverse22 buySellInverse21 buySellInverse20 buySellInverse19 \
           --msg "3. "



echo
echo "******** 4. Running: gsm4626/balances-buy-4626.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/balances-buy-4626.conf \
           --msg "4. gsm4626/balances-buy-4626.conf"


echo
echo "******** 5a. Running: conf/gsm4626/balances-sell-4626.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/balances-sell-4626.conf --rule R1_getAssetAmountForSellAsset_arg_vs_return R1a_buyGhoUpdatesGhoBalanceCorrectly1 R2_getAssetAmountForSellAsset_sellAsset_eq \
           --msg "5a. "


echo
echo "******** 5b. Running: conf/gsm4626/balances-sell-4626.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/balances-sell-4626.conf --rule R3a_sellAssetUpdatesAssetBalanceCorrectly \
           --msg "5b. "


echo
echo "******** 5c. Running: conf/gsm4626/balances-sell-4626.conf   ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/balances-sell-4626.conf --rule R4_buyGhoUpdatesGhoBalanceCorrectly R4a_buyGhoAmountGtGhoBalanceChange \
           --msg "5c. "


echo
echo "******** 6. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/fees-buy-4626.conf \
           --msg "6. "


echo
echo "******** 7. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/fees-sell-4626.conf --rule R3a_estimatedSellFeeCanBeLowerThanActualSellFee R2_getAssetAmountForSellAssetVsActualSellFee R4a_getSellFeeVsgetAssetAmountForSellAsset R4_getSellFeeVsgetAssetAmountForSellAsset R1a_getAssetAmountForSellAssetFeeNeGetSellFee R2a_getAssetAmountForSellAssetNeActualSellFee R4b_getSellFeeVsgetAssetAmountForSellAsset R1_getAssetAmountForSellAssetFeeGeGetSellFee R3b_estimatedSellFeeEqActualSellFee \
           --msg "7. "


echo
echo "******** 8a. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/optimality4626.conf --rule R5a_externalOptimalityOfSellAsset R6a_externalOptimalityOfBuyAsset \
           --msg "8a. "


echo
echo "******** 8b. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/optimality4626.conf --rule R1_optimalityOfBuyAsset_v1 \
           --msg "8b. "


echo
echo "******** 8c. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/optimality4626.conf --rule R3_optimalityOfSellAsset_v1 \
           --msg "8c. "


echo
echo "******** 9a. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/getAmount-properties-4626.conf --rule getAssetAmountForBuyAsset_correctness_bound1 getAssetAmountForBuyAsset_correctness_bound2 getGhoAmountForBuyAsset_correctness_bound1 getAssetAmountForSellAsset_correctness getAssetAmountForBuyAsset_optimality getAssetAmountForBuyAsset_correctness \
           --msg "9a. gsm4626/getAmount-properties-4626.conf"


echo
echo "******** 9b. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/getAmount-properties-4626.conf --rule getGhoAmountForBuyAsset_optimality \
           --msg "9b. "


echo
echo "******** 9c. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/getAmount-properties-4626.conf --rule getGhoAmountForBuyAsset_correctness \
           --msg "9c. "


echo
echo "******** 9d. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/getAmount-properties-4626.conf --rule getAssetAmountForSellAsset_optimality getAssetAmountForBuyAsset_funcProperty \
           --msg "9d. "


echo
echo "******** 10a. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/finishedRules-4626.conf --rule cantBuyOrSellWhenSeized cantBuyOrSellWhenFrozen sellAssetIncreasesExposure buyAssetDecreasesExposure rescuingAssetKeepsAccruedFees rescuingGhoKeepsAccruedFees giftingGhoDoesntAffectStorageSIMPLE correctnessOfBuyAsset giftingUnderlyingDoesntAffectStorageSIMPLE sellAssetSameAsGetGhoAmountForSellAsset correctnessOfSellAsset giftingGhoDoesntCreateExcessOrDearth backWithGhoDoesntCreateExcess getAssetAmountForSellAsset_correctness collectedSellFeeIsAtLeastAsRequired collectedBuyFeePlus2IsAtLeastAsRequired collectedBuyFeePlus1IsAtLeastAsRequired collectedBuyFeeIsAtLeastAsRequired sellingDoesntExceedExposureCap whoCanChangeAccruedFees whoCanChangeExposure \
           --msg "10a. "


echo
echo "******** 10b. Running:    ****************"
certoraRun $CMN certora/gsm/conf/gsm4626/finishedRules-4626.conf --rule giftingUnderlyingDoesntCreateExcessOrDearth \
           --msg "10b. "
