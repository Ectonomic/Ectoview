#!/bin/bash
# Ectoview off-screen test: a headless KWin 6.7 (virtual screens, private D-Bus, plasmashell,
# config in a throwaway folder, any NVIDIA card hidden so Mesa draws it on another graphics chip) with
# Ectoview installed from package/ into the sandbox's fresh home, as a stranger would have it.
# Nothing opens on the real desktop and the real screen is never captured.
# usage: [SCENARIO=smoke|primary|every|reorder|plant-*] tests/e2e/run.sh OUT_DIR
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "$1"); mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/*.log "$OUT"/*.json
# the input helper: Ectoview's own (tests/e2e/fake-input.c), built on first use
FI=$HERE/../../build/bin/ectoview-fake-input
[ -x "$FI" ] || "$HERE/build-fake-input.sh" > /dev/null
export FAKE_INPUT=${FAKE_INPUT:-$(realpath "$FI")}
export PKG=$(realpath "$HERE/../../package")
W=$(mktemp -d /tmp/ectoview-e2e.XXXXXX); chmod 700 "$W"; mkdir -p "$W/rt" "$W/services" "$W/home" "$W/xdg"/{config,data,cache,state}; chmod 700 "$W/rt"
trap 'rm -rf "$W"' EXIT
# KDE's own session services (activities, kded, system stats) start on demand; nothing for sound, Bluetooth or hardware
for f in /usr/share/dbus-1/services/org.kde.*.service; do cp "$f" "$W/services/"; done
cat > "$W/session.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:dir=$W/rt</listen><auth>EXTERNAL</auth>
<servicedir>$W/services</servicedir><policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
DRI=(); for n in /sys/class/drm/renderD* /sys/class/drm/card[0-9]; do [ "$(cat $n/device/vendor 2>/dev/null)" = 0x10de ] || DRI+=(--dev-bind /dev/dri/$(basename $n) /dev/dri/$(basename $n)); done
if [ -n "${E2E_IN_CONTAINER:-}" ]; then
    # inside tests/e2e/container.sh's container, which already keeps the test apart (its own
    # processes, devices and journal) and where bwrap can't make namespaces of its own
    timeout ${TIMEOUT:-240} dbus-run-session --config-file="$W/session.conf" -- "$HERE/inner.sh" "$W" "$OUT" "$PKG"
else
    timeout ${TIMEOUT:-240} bwrap --dev-bind / / --unshare-pid --proc /proc --die-with-parent --tmpfs /dev/dri "${DRI[@]}" --tmpfs /run/systemd/journal -- dbus-run-session --config-file="$W/session.conf" -- "$HERE/inner.sh" "$W" "$OUT" "$PKG"
fi
python3 -I "$HERE/check.py" "$OUT" "${SCENARIO:-smoke}"
