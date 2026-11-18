#!/bin/bash
# Run by rpm-check.sh as the user "stranger" in a container where the Ectoview RPM was just
# installed: a headless KWin session, then the installed Ectoview judged from outside.
set -u
if [ "${1:-}" != session ]; then
    export XDG_RUNTIME_DIR=/tmp/rt-stranger XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wl-stranger QT_QPA_PLATFORM=wayland
    mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
    cp "$(command -v kwin_wayland)" /tmp/kwin_wayland
    cd "$HOME"
    exec dbus-run-session -- bash "$0" session
fi

bad=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; bad=1; }
kga() { gdbus call --session --dest org.kde.kglobalaccel "$@" 2>/dev/null; }
keys() { local o; o=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', '$1', '', '']"); o=${o#(}; echo "${o%,)}"; }
component() { kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.getComponent kwin | sed -n "s/^(objectpath '\(.*\)',)$/\1/p"; }
press() { kga --object-path "$(component)" --method org.kde.kglobalaccel.Component.invokeShortcut "$1" default >/dev/null; }
effects() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method "org.kde.kwin.Effects.$1" "${@:2}" 2>/dev/null; }
active() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.freedesktop.DBus.Properties.Get org.kde.kwin.Effects activeEffects 2>/dev/null; }
loaded() { effects isEffectLoaded "$1" | grep -q true; }
wait_for() { local i; for i in $(seq 50); do eval "$1" && return 0; sleep 0.2; done; return 1; }
kwin_script() {
    local f=/tmp/script-$RANDOM.js id; printf '%s\n' "$1" > "$f"
    id=$(gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.loadScript "$f" "s$RANDOM" | tr -dc 0-9)
    gdbus call --session --dest org.kde.KWin --object-path "/Scripting/Script$id" --method org.kde.kwin.Script.run >/dev/null; sleep 0.5
}

# (scripts' print() and QML's messages in KWin's log, on stderr: the checks below read them there)
QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="js.debug=true;kwin_scripting.debug=true;qml.debug=true" \
    /tmp/kwin_wayland --virtual --no-lockscreen --width 1920 --height 1080 --socket "$WAYLAND_DISPLAY" >/tmp/kwin.log 2>&1 &
wait_for "kga --object-path \"\$(component)\" --method org.kde.kglobalaccel.Component.shortcutNames | grep -q Overview" || { fail "the test session never came up"; exit 1; }
before=$(keys Overview)
case "$before" in '@a(ai) []'|'[]'|'[([0, 0, 0, 0],)]'|'') fail "the test session: Overview has no Meta+W, so the shortcut checks would prove nothing"; exit 1;; esac

ectoview-setup on > /tmp/on.log 2>&1; rc=$?
[ "$rc" = 0 ] && wait_for "loaded ectoview" && ! loaded overview && pass "ectoview-setup on: KWin has the package's Ectoview loaded, and Overview off" \
    || { fail "ectoview-setup on (exit $rc)"; tail -15 /tmp/on.log; grep -i ectoview /tmp/kwin.log | tail -10 | sed 's/^/  kwin: /'; }
[ "$(keys Ectoview)" = "$before" ] && [ "$(keys Overview)" = '@a(ai) []' ] && pass "Overview's Meta+W is Ectoview's" || fail "keys: Ectoview $(keys Ectoview), Overview $(keys Overview)"
press Ectoview
if wait_for "active | grep -q ectoview"; then
    sleep 1.5; press Ectoview
    wait_for "! active | grep -q ectoview" && pass "Meta+W's action opens Ectoview and closes it again" || fail "Ectoview didn't close"
else
    fail "Meta+W's action didn't open Ectoview (active effects: $(active))"
fi
errs=$(grep -iE 'ectoview' /tmp/kwin.log | grep -E 'Error|error|is not defined|Cannot|Unable|failed|undefined|Invalid|unavailable|not a type|not installed|Unknown|Duplicate|couldn.t load|[Bb]inding loop' | sort -u | head -15)
[ -z "$errs" ] && pass "KWin's log has no error from Ectoview's QML (the package brings every QML module it imports)" || { fail "Ectoview's QML errors:"; echo "$errs" | sed 's/^/  /'; }

kcmshell6 kwin/effects/configs/kwin_ectoview_config >/tmp/kcm.log 2>&1 &
sleep 6
kwin_script 'for (const w of workspace.windowList()) if (w.desktopFileName === "kwin_ectoview_config") print("settings window " + w.caption);'
grep -q "js: settings window Ectoview" /tmp/kwin.log && pass "the settings page opens from the package, in a window named Ectoview" \
    || { fail "the settings page didn't open"; tail -5 /tmp/kcm.log | sed 's/^/  kcm: /'; }
pkill -u stranger -x kcmshell6; sleep 0.5

ectoview-setup off > /tmp/off.log 2>&1; rc=$?
[ "$rc" = 0 ] && wait_for "loaded overview" && ! loaded ectoview && [ "$(keys Overview)" = "$before" ] \
    && pass "ectoview-setup off: Overview back, with Meta+W" || { fail "ectoview-setup off (exit $rc)"; tail -10 /tmp/off.log; }
[ ! -e "$HOME/.local/state/ectoview-install" ] && pass "ectoview-setup leaves no records behind" || fail "records left: $(ls "$HOME/.local/state/ectoview-install")"
kill $(jobs -p) 2>/dev/null
# KWin's lines about Ectoview, for reading after a run
echo "KWin's log about Ectoview:"; grep -i ectoview /tmp/kwin.log | grep -v 'js: ' | sort -u | head -40 | sed 's/^/  kwin: /'
exit $bad
