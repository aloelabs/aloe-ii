#!/bin/bash

mv lib/core lib/core_link

mkdir lib/core
cp -R ../core/src lib/core/src
cp -R ../core/lib lib/core/lib
cp ../core/foundry.toml lib/core/

source .env
# forge clean
forge build
forge script script/Deploy.s.sol:DeployScript --multi --broadcast

rm -rf lib/core
mv lib/core_link lib/core
