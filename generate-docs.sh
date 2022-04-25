#!/bin/bash
set -eu
mkdir -p "./docs"
echo "Build"
swift build
echo "Generate HTML"
swift package --allow-writing-to-directory ./docs \
    generate-documentation --target GATT \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path GATT \
    --output-path ./docs