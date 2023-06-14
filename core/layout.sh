#!/bin/bash

function inspect_and_print {
    echo "forge inspect --pretty src/$1.sol:$1 storage-layout" >> .storage-layout.md
    forge inspect --pretty "src/$1.sol:$1" storage-layout >> .storage-layout.md
    echo "" >> .storage-layout.md
}

rm .storage-layout.md
inspect_and_print Lender
inspect_and_print Borrower
inspect_and_print Factory
