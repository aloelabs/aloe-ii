#!/bin/bash

cd core
forge doc
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Darwin) sed command
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i.bak -E 's|github.com\/aloelabs\/aloe-ii\/blob\/([0-9a-fA-F]+)\/|github.com/aloelabs/aloe-ii/blob/\1/core/|g'
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i.bak -E 's|\/src\/(.*)\.md|/core/\1.md|g'
else
    # Linux (including Ubuntu) sed command
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i -E 's|github.com\/aloelabs\/aloe-ii\/blob\/([0-9a-fA-F]+)\/|github.com/aloelabs/aloe-ii/blob/\1/core/|g'
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i -E 's|\/src\/(.*)\.md|/core/\1.md|g'
fi
cd ..

cp -rf core/docs/src/src/. docs/src/core
rm -rf core/docs

cd periphery
forge doc
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Darwin) sed command
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i.bak -E 's|github.com\/aloelabs\/aloe-ii\/blob\/([0-9a-fA-F]+)\/|github.com/aloelabs/aloe-ii/blob/\1/periphery/|g'
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i.bak -E 's|\/src\/(.*)\.md|/periphery/\1.md|g'
else
    # Linux (including Ubuntu) sed command
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i -E 's|github.com\/aloelabs\/aloe-ii\/blob\/([0-9a-fA-F]+)\/|github.com/aloelabs/aloe-ii/blob/\1/periphery/|g'
    find docs -type f -name '*.md' -print0 | xargs -0 sed -i -E 's|\/src\/(.*)\.md|/periphery/\1.md|g'
fi
cd ..

cp -rf periphery/docs/src/src/. docs/src/periphery
rm -rf periphery/docs
