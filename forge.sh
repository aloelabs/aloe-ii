#!/bin/bash

if [ "$CI" != "true" ]; then
  line=$(grep -E 'ALCHEMY_KEY' .env)
  line=(${line//=/ })
  key=${line[1]}
  FOUNDRY_ETH_RPC_URL='https://eth-mainnet.alchemyapi.io/v2/'$key

  line=$(grep -E 'ETHERSCAN_API_KEY' .env)
  line=(${line//=/ })
  FOUNDRY_ETHERSCAN_API_KEY=${line[1]}
fi

export FOUNDRY_ETH_RPC_URL
export FOUNDRY_ETHERSCAN_API_KEY

forge "$@"
