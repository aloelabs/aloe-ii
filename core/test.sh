#!/bin/bash

# Ensure each constant in `Constants.sol` is only defined once
echo "Verifying that each constant is defined only once..."
constants=$(grep -oh '[_A-Z]* =' ./src/libraries/constants/Constants.sol)
while read constant; do 
#   echo "  $constant"
  n=$(grep -rnw --include=\*.sol '.' -e "$constant" | wc -l)
  if (( n > 1)); then
    echo "Failure"
    exit 1
  fi
done <<< "$constants"
echo "Success!"

# Ensure that `Ledger` and `Lender` have the same storage layouts
A=$(mktemp)
B=$(mktemp)

forge inspect --pretty "src/Ledger.sol:Ledger" storage-layout >> ${A}
forge inspect --pretty "src/Lender.sol:Lender" storage-layout >> ${B}

sed -i '' 's/Lender/Ledger/g' ${B}
(cmp -s ${A} ${B})
are_equivalent=$?
rm ${A}
rm ${B}

if [ "${are_equivalent}" != "0" ]; then
    printf 'ERROR: Ledger and Lender have different storage layouts.\n'
    exit 1
fi

# Ensure that `Ledger` has only view & pure functions
forge build
(node 'test/Ledger.js')
modifies_state=$?
if [ "${modifies_state}" != "0" ]; then
    exit 1
fi

# Run forge tests
forge test -vv --no-match-contract ".*Gas"

# Get coverage
forge coverage --report lcov --report summary --no-match-contract ".*Gas"
