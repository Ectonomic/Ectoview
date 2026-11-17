#!/bin/bash
# Builds and runs the settings page test on a private D-Bus, so its "reconfigure" calls reach no real KWin.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cmake -S "$ROOT" -B "$ROOT/build" > /dev/null
cmake --build "$ROOT/build" --target settings_test > /dev/null
QT_QPA_PLATFORM=offscreen dbus-run-session -- "$ROOT/build/bin/settings_test" "$@"
