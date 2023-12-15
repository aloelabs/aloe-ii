#!/bin/bash

mv lib/core lib/core_link

mkdir lib/core
cp -R ../core/src lib/core/src
cp -R ../core/lib lib/core/lib
cp ../core/foundry.toml lib/core/

source .env
# forge clean
forge build
forge script script/Deploy.s.sol:DeployScript --chain mainnet --rpc-url mainnet --broadcast --verify --slow --delay 10 --etherscan-api-key $ETHERSCAN_API_KEY
forge script script/Deploy.s.sol:DeployScript --chain optimism --rpc-url optimism --broadcast --verify --slow --delay 10 --etherscan-api-key $ETHERSCAN_API_KEY_OPTIMISM
forge script script/Deploy.s.sol:DeployScript --chain arbitrum --rpc-url arbitrum --broadcast --verify --slow --delay 10 --etherscan-api-key $ETHERSCAN_API_KEY_ARBITRUM
forge script script/Deploy.s.sol:DeployScript --chain base --rpc-url base --broadcast --verify --slow --delay 10 --etherscan-api-key $ETHERSCAN_API_KEY_BASE

rm -rf lib/core
mv lib/core_link lib/core
