#!/bin/bash
forge doc --build

rm -r ../docs/src/core
mv ../docs/src/src ../docs/src/core
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Darwin) sed command
    sed -i '' 's|# src|# core contracts|g' ../docs/src/SUMMARY.md
    sed -i '' 's|src|core|g' ../docs/src/SUMMARY.md
else
    # Linux (including Ubuntu) sed command
    sed -i 's|# src|# core contracts|g' ../docs/src/SUMMARY.md
    sed -i 's|src|core|g' ../docs/src/SUMMARY.md
fi
