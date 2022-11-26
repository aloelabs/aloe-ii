#!/bin/bash

source ../.env
forge snapshot -vv --gas-report --fork-url $FOUNDRY_ETH_RPC_URL --fork-block-number 15348451 --match-contract ".*Gas"
