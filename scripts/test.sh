#!/usr/bin/env bash
# Run cPerch's swift-testing suite. XCTest ships only with full Xcode; under the
# Command Line Tools, Testing.framework + lib_TestingInterop.dylib live outside the
# default search/runtime paths, so we point swiftc + the linker at them. Both paths
# derive from `xcode-select -p`, so this works on CLT-only and full-Xcode machines.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"          # Testing.framework
LIB="$DEV/Library/Developer/usr/lib"            # lib_TestingInterop.dylib

ARGS=()
if [ -d "$FW/Testing.framework" ]; then
  ARGS+=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW")
fi
if [ -f "$LIB/lib_TestingInterop.dylib" ]; then
  ARGS+=(-Xlinker -rpath -Xlinker "$LIB")
fi

exec swift test "${ARGS[@]}" "$@"
