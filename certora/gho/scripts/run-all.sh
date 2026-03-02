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
certoraRun $CMN certora/gho/conf/verifyFlashMinter.conf --rule balanceOfFlashMinterGrows integrityOfTreasurySet integrityOfFeeSet availableLiquidityDoesntChange integrityOfDistributeFeesToTreasury feeSimulationEqualsActualFee \
           --msg "3.  "

