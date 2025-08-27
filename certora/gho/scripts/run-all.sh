#CMN="--compilation_steps_only"

echo
echo "******** 1. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyUpgradeableGhoToken.conf \
           --msg "1.  "

echo
echo "******** 2. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoToken.conf \
           --msg "2.  "

echo
echo "******** 3. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoAToken.conf --rule noMint noBurn noTransfer transferUnderlyingToCantExceedCapacity totalSupplyAlwaysZero userBalanceAlwaysZero level_does_not_decrease_after_transferUnderlyingTo_followed_by_handleRepayment \
           --msg "3.  "

echo
echo "******** 4. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoDiscountRateStrategy.conf --rule equivalenceOfWadMulCVLAndWadMulSol maxDiscountForHighDiscountTokenBalance zeroDiscountForSmallDiscountTokenBalance partialDiscountForIntermediateTokenBalance limitOnDiscountRate \
           --msg "4.  "

echo
echo "******** 5. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyFlashMinter.conf --rule balanceOfFlashMinterGrows integrityOfTreasurySet integrityOfFeeSet availableLiquidityDoesntChange integrityOfDistributeFeesToTreasury feeSimulationEqualsActualFee \
           --msg "5.  "

echo
echo "******** 6. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule user_index_after_mint user_index_ge_one_ray nonzeroNewDiscountToken \
           --msg "6.  "

echo
echo "******** 7. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule accumulated_interest_increase_after_mint \
           --msg "7.  "

echo
echo "******** 8. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule userCantNullifyItsDebt \
           --msg "8.  "

echo
echo "******** 9. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule discountCantExceedDiscountRate \
           --msg "9.  "

echo
echo "******** 10. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule onlyMintForUserCanIncreaseUsersBalance \
           --msg "10.  "

echo
echo "******** 11. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule discountCantExceed100Percent \
           --msg "11.  "

echo
echo "******** 12. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken.conf --rule disallowedFunctionalities nonMintFunctionCantIncreaseBalance nonMintFunctionCantIncreaseScaledBalance debtTokenIsNotTransferable onlyCertainFunctionsCanModifyScaledBalance userAccumulatedDebtInterestWontDecrease integrityOfMint_updateDiscountRate integrityOfMint_updateIndex integrityOfMint_updateScaledBalance_fixedIndex integrityOfMint_userIsolation integrityMint_atoken integrityOfBurn_updateDiscountRate integrityOfBurn_updateIndex burnZeroDoesntChangeBalance integrityOfBurn_fullRepay_concrete integrityOfBurn_userIsolation integrityOfUpdateDiscountDistribution_updateIndex integrityOfUpdateDiscountDistribution_userIsolation integrityOfRebalanceUserDiscountPercent_updateDiscountRate integrityOfRebalanceUserDiscountPercent_updateIndex integrityOfRebalanceUserDiscountPercent_userIsolation integrityOfBalanceOf_fullDiscount integrityOfBalanceOf_noDiscount integrityOfBalanceOf_zeroScaledBalance burnAllDebtReturnsZeroDebt integrityOfUpdateDiscountRateStrategy user_index_up_to_date \
           --msg "12.  "


echo
echo "******** 13. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken_summarized.conf --rule accrueAlwaysCalleldBeforeRefresh \
           --msg "13.  "

echo
echo "******** 14. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtTokenInternal.conf \
           --msg "14.  "

echo
echo "******** 15. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken-rayMulDiv-summarization.conf \
           --msg "15.  "


echo
echo "******** 16. Running:    ****************"
certoraRun $CMN certora/gho/conf/verifyGhoVariableDebtToken_specialBranch.conf --rule sendersDiscountPercentCannotIncrease \
           --msg "16.  "


