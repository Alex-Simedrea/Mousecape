#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -arch arm64 \
  -I Mousecape/mousecloak -I Mousecape/mousecloak/CGSInternal \
  -include Mousecape/mousecloak/mousecloak-Prefix.pch \
  -framework Cocoa -framework ApplicationServices \
  tests/cursor-compatibility.m Mousecape/mousecloak/apply.m \
  Mousecape/mousecloak/MCDefs.m Mousecape/mousecloak/NSBitmapImageRep+ColorSpace.m \
  -o build/test-cursor-compatibility
build/test-cursor-compatibility
