#!/bin/bash

cd core
forge doc
cd ..

rm -r docs/src/core
mv docs/src/src docs/src/core

cd periphery
forge doc
cd ..

rm -r docs/src/periphery
mv docs/src/src docs/src/periphery
