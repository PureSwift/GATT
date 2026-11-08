#!/bin/sh
# Compiles GATT and the Bluetooth target it depends on for a bare-metal
# Embedded Swift triple.
#
# SwiftPM can't target these triples without a Swift SDK, so this runs swiftc
# directly, using the sources Bluetooth's build-tool plugin generates.
#
# `canImport(_Concurrency)` can't detect a triple without the module, because
# it exists for other triples, so the code checks EMBEDDED_NO_CONCURRENCY.
#
# Usage: .github/scripts/embedded-bare-metal.sh <triple>
set -eu

TRIPLE="$1"
OUT=".build/bare-metal/$TRIPLE"
mkdir -p "$OUT"

DEFINES=""
case "$TRIPLE" in
    aarch64-none-none-elf) DEFINES="-D EMBEDDED_NO_CONCURRENCY" ;;
esac

# Resolve Bluetooth and run its build-tool plugin.
SWIFTPM_ENABLE_MACROS=0 swift build --target Bluetooth

compile() {
    MODULE="$1"
    PACKAGE="$2"
    shift 2
    echo "Compiling $MODULE for $TRIPLE"
    # shellcheck disable=SC2086
    find "$@" -name '*.swift' | sort | xargs swiftc \
        -target "$TRIPLE" \
        -enable-experimental-feature Embedded \
        -wmo -parse-as-library -Osize -swift-version 6 \
        -package-name "$PACKAGE" \
        $DEFINES \
        -I "$OUT" \
        -module-name "$MODULE" \
        -emit-module -emit-module-path "$OUT/$MODULE.swiftmodule" \
        -c -o "$OUT/$MODULE.o"
}

compile Bluetooth bluetooth \
    .build/checkouts/Bluetooth/Sources/Bluetooth \
    .build/plugins/outputs/bluetooth/Bluetooth/destination
compile GATT gatt Sources/GATT
