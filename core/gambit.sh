#!/bin/bash

gambit mutate --json gambit.json

for OUTPUT in $(ls gambit_out/mutants)
do
    cp -r "gambit_out/mutants/$OUTPUT/" .

    (FOUNDRY_PROFILE='gambit' forge test -vv --match-contract "LenderInvariantsTest")
    passed=$?

    git restore test/invariants/LenderHarness.sol

    if [ "${passed}" == "0" ]; then
        gambit summary
        echo "❌ Invariant tests passed when they shouldn't have (mutation $OUTPUT)"
        exit 1
    fi
done
