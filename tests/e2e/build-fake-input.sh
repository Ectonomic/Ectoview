#!/bin/bash
# Builds the tests' input helper (tests/e2e/fake-input.c) into build/bin/ectoview-fake-input, outside
# the product's CMake build, so installing Ectoview never needs Wayland's development tools.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd); OUT=$ROOT/build/bin; GEN=$ROOT/build/fake-input; mkdir -p "$OUT" "$GEN"
XML=$(pkg-config --variable=pkgdatadir plasma-wayland-protocols 2>/dev/null || true)/fake-input.xml
[ -f "$XML" ] || XML=/usr/share/plasma-wayland-protocols/fake-input.xml
wayland-scanner client-header "$XML" "$GEN/fake-input-client-protocol.h"
wayland-scanner private-code "$XML" "$GEN/fake-input-protocol.c"
cc -O2 -Wall -I"$GEN" "$ROOT/tests/e2e/fake-input.c" "$GEN/fake-input-protocol.c" -o "$OUT/ectoview-fake-input" $(pkg-config --cflags --libs wayland-client)
echo "$OUT/ectoview-fake-input"
