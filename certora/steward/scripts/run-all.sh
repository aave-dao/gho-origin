#CMN="--compilation_steps_only"

echo
echo "******** 1. Running: GhoAaveSteward.conf   ****************"
certoraRun $CMN certora/steward/conf/GhoAaveSteward.conf \
           --msg "1. GhoAaveSteward.conf "

echo
echo "******** 2. Running: GhoBucketSteward.conf   ****************"
certoraRun $CMN certora/steward/conf/GhoBucketSteward.conf \
           --msg "2. GhoBucketSteward.conf"

echo
echo "******** 3. Running: GhoCcipSteward.conf   ****************"
certoraRun $CMN certora/steward/conf/GhoCcipSteward.conf \
           --msg "3. GhoCcipSteward.conf"

echo
echo "******** 4. Running: GhoGsmSteward.conf   ****************"
certoraRun $CMN certora/steward/conf/GhoGsmSteward.conf \
           --msg "4. GhoGsmSteward.conf"
