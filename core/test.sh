#!/bin/bash

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
source ../.env
MAINNET_RPC_URL=$FOUNDRY_ETH_RPC_URL forge test -vv --gas-report

# Get coverage
MAINNET_RPC_URL=$FOUNDRY_ETH_RPC_URL forge coverage --report lcov --report summary
