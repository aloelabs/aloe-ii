#!/bin/bash

source ../.env
MAINNET_RPC_URL=$FOUNDRY_ETH_RPC_URL forge snapshot -vv --match-contract ".*Gas"
