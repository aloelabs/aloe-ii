#!/bin/bash

source ../.env
forge test -vv --gas-report --fork-url $FOUNDRY_ETH_RPC_URL --fork-block-number 15348451
forge test -vv --fork-url $FOUNDRY_ETH_RPC_URL --fork-block-number 15348451 --match-contract Borrower
