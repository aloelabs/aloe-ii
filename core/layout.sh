#!/bin/bash

rm .storage-layout

function inspect_and_print {
    echo "forge inspect --pretty src/$1.sol:$1 storage-layout" >> .storage-layout
    forge inspect --pretty "src/$1.sol:$1" storage-layout >> .storage-layout
    echo "" >> .storage-layout
}

inspect_and_print Lender
inspect_and_print LenderERC20
