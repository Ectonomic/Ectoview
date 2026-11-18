#!/bin/bash
# Run by stranger-check.sh inside each container, as the user "stranger": a headless KWin
# session, then install.sh and uninstall.sh run the way the README tells a person to, each
# judged from outside (KWin's effects and shortcut services over D-Bus, KWin's own log, the
# files). (Ectolens's tests/install/inside.sh, adapted.)
#   inside.sh installs|refused
set -u
expect=$1
if [ "${2:-}" != session ]; then
    export XDG_RUNTIME_DIR=/tmp/rt-stranger XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wl-stranger QT_QPA_PLATFORM=wayland
    mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
    # a copy of KWin: the installed one carries file capabilities, which a rootless container can't grant
    cp "$(command -v kwin_wayland)" /tmp/kwin_wayland
    exec dbus-run-session -- bash "$0" "$expect" session
fi

bad=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; bad=1; }
note() { echo "NOTE  $*"; }
kga() { gdbus call --session --dest org.kde.kglobalaccel "$@" 2>/dev/null; }
keys() { local o; o=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', '$1', '', '']"); o=${o#(}; echo "${o%,)}"; }
actions() {
    local p; p=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.getComponent kwin | sed -n "s/^(objectpath '\(.*\)',)$/\1/p")
    [ -n "$p" ] && kga --object-path "$p" --method org.kde.kglobalaccel.Component.shortcutNames \
        | sed "s/^(@as \[\],)$//; s/^(\[//; s/\],)$//" | sed "s/', '/\n/g" | tr -d "'" | sed '/^$/d'
}
press() {   # an action of KWin's, pressed through the shortcut service
    local p; p=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.getComponent kwin | sed -n "s/^(objectpath '\(.*\)',)$/\1/p")
    kga --object-path "$p" --method org.kde.kglobalaccel.Component.invokeShortcut "$1" default >/dev/null
}
effects() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method "org.kde.kwin.Effects.$1" "${@:2}" 2>/dev/null; }
active() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.freedesktop.DBus.Properties.Get org.kde.kwin.Effects activeEffects 2>/dev/null; }
loaded() { effects isEffectLoaded "$1" | grep -q true; }
wait_for() { local i; for i in $(seq 50); do eval "$1" && return 0; sleep 0.2; done; return 1; }
kwin_script() {   # run JavaScript in KWin; its print() lines land in /tmp/kwin.log as "js: ..."
    local f=/tmp/script-$RANDOM.js id; printf '%s\n' "$1" > "$f"
    id=$(gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.loadScript "$f" "s$RANDOM" | tr -dc 0-9)
    gdbus call --session --dest org.kde.KWin --object-path "/Scripting/Script$id" --method org.kde.kwin.Script.run >/dev/null; sleep 0.5
}
STATE=$HOME/.local/state/ectoview-install
cd "$HOME/Ectoview"

# (scripts' print() and QML's messages in KWin's log, on stderr: the checks below read them there)
QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="js.debug=true;kwin_scripting.debug=true;qml.debug=true" \
    /tmp/kwin_wayland --virtual --no-lockscreen --width 1920 --height 1080 --socket "$WAYLAND_DISPLAY" >/tmp/kwin.log 2>&1 &
wait_for "actions | grep -qx Overview" || { fail "the test session: KWin's shortcut service with Overview's shortcuts never came up"; tail -20 /tmp/kwin.log; exit 1; }
. /etc/os-release; echo "system: $PRETTY_NAME, KWin $(ls /usr/lib64/libkwin.so.6.* /usr/lib/libkwin.so.6.* /usr/lib/*/libkwin.so.6.* 2>/dev/null | head -1 | sed 's/.*\.so\.//')"
for a in Overview "Grid View" "Cycle Overview" "Cycle Overview Opposite"; do printf '%s\t%s\n' "$a" "$(keys "$a")"; done > /tmp/before
echo "Overview's shortcuts before:"; sed 's/^/  /' /tmp/before
empty() { case "$1" in '@a(ai) []'|'[]'|'[([0, 0, 0, 0],)]'|'') return 0;; esac; return 1; }
if empty "$(cut -f2 /tmp/before | head -1)"; then fail "the test session: Overview has no Meta+W to move, so the shortcut checks would prove nothing"; exit 1; fi
snapshot() { find "$HOME" -path "$HOME/Ectoview" -prune -o -path "$HOME/.cache" -prune -o -print 2>/dev/null | sort; }
snapshot > /tmp/home-before

if [ "$expect" = refused ]; then
    ./install.sh --yes > /tmp/install.log 2>&1; rc=$?
    cat /tmp/install.log
    [ "$rc" != 0 ] && grep -q "too old for Ectoview" /tmp/install.log \
        && pass "install.sh refuses this system: $(grep -m1 'too old' /tmp/install.log)" \
        || fail "install.sh did not refuse a Plasma older than 6.7 (exit $rc)"
    snapshot > /tmp/home-after
    diff -q /tmp/home-before /tmp/home-after >/dev/null && pass "the home folder is as it was" \
        || { fail "the home folder changed:"; diff /tmp/home-before /tmp/home-after | head; }
    loaded overview && pass "Overview is still on" || fail "Overview was turned off"
    # KWin's lines about Ectoview, for reading after a run
echo "KWin's log about Ectoview:"; grep -i ectoview /tmp/kwin.log | grep -v 'js: ' | sort -u | head -40 | sed 's/^/  kwin: /'
exit $bad
fi

# ---- an install whose load fails (KWin asked for an effect that isn't there) leaves Overview as it was
ECTOVIEW_TEST_EFFECT_ID=ectoview-not-there ./install.sh --yes > /tmp/install0.log 2>&1; rc=$?
ok=1
while IFS=$'\t' read -r a k; do [ "$(keys "$a")" = "$k" ] || { ok=0; echo "  Overview's $a is $(keys "$a"), was $k"; }; done < /tmp/before
[ "$rc" != 0 ] && grep -q "Overview stays" /tmp/install0.log && wait_for "loaded overview" && [ "$ok" = 1 ] \
    && [ "$(kreadconfig6 --file kwinrc --group Plugins --key overviewEnabled --default absent)" != false ] \
    && pass "an install that can't load Ectoview stops and leaves Overview on, with its shortcuts" \
    || { fail "a failed install (exit $rc) left: overview $(effects isEffectLoaded overview), overviewEnabled $(kreadconfig6 --file kwinrc --group Plugins --key overviewEnabled --default absent)"; tail -8 /tmp/install0.log; }

# ---- install, as the README says
start=$(date +%s)
./install.sh --yes > /tmp/install.log 2>&1; rc=$?
sed -n '/^== /p;/: Plasma [0-9]/p;/packages from/,+2p;/hasn.t been tried/,+1p;/Moved:/p' /tmp/install.log
[ "$rc" = 0 ] && pass "install.sh --yes finished ($(( $(date +%s) - start )) s, packages and build)" \
    || { fail "install.sh --yes failed (exit $rc)"; grep -nE "error:|Error|Ectoview: |Could NOT find|Problem" /tmp/install.log | head -30
         echo "  ..."; tail -25 /tmp/install.log; echo "  KWin's log about Ectoview:"; grep -i ectoview /tmp/kwin.log | tail -20 | sed 's/^/  kwin: /'; exit 1; }

loaded ectoview && ! loaded overview && pass "KWin has Ectoview loaded, and Overview off" || fail "effects: ectoview $(effects isEffectLoaded ectoview), overview $(effects isEffectLoaded overview)"
ok=1
while IFS=$'\t' read -r a k; do
    to=$(case "$a" in Overview) echo Ectoview;; "Grid View") echo "Ectoview Grid View";; "Cycle Overview") echo "Ectoview Cycle";; *) echo "Ectoview Cycle Opposite";; esac)
    empty "$k" && continue
    [ "$(keys "$to")" = "$k" ] || { ok=0; echo "  $to is $(keys "$to"), wanted $k"; }
    empty "$(keys "$a")" || { ok=0; echo "  Overview still has $a: $(keys "$a")"; }
done < /tmp/before
[ "$ok" = 1 ] && pass "Overview's keys ($(cut -f2 /tmp/before | head -1)) are Ectoview's now, none left on Overview" || fail "the shortcuts didn't move"

# Meta+W's action opens Ectoview, and pressed again closes it; the same for Grid View
for pair in "Ectoview|Ectoview" "Ectoview Grid View|Grid View"; do
    act=${pair%|*} what=${pair#*|}
    press "$act"
    if wait_for "active | grep -q ectoview"; then
        sleep 1.5; press "$act"
        wait_for "! active | grep -q ectoview" && pass "$what's shortcut opens Ectoview, and closes it again" || fail "$what: Ectoview didn't close"
    else
        fail "$what's shortcut didn't open Ectoview (active effects: $(active))"
    fi
done
errs=$(grep -iE 'ectoview' /tmp/kwin.log | grep -E 'Error|error|is not defined|Cannot|Unable|failed|undefined|Invalid|unavailable|not a type|not installed|Unknown|Duplicate|couldn.t load|[Bb]inding loop' | sort -u | head -15)
[ -z "$errs" ] && pass "KWin's log has no error from Ectoview's QML" || { fail "Ectoview's QML errors in KWin's log:"; echo "$errs" | sed 's/^/  /'; }

# the settings page, as Ectoview's gear opens it (kcmshell6, with the session's plugin path)
if command -v kcmshell6 >/dev/null; then
    ( . "$HOME/.config/plasma-workspace/env/ectoview.sh"; kcmshell6 kwin/effects/configs/kwin_ectoview_config >/tmp/kcm.log 2>&1 & )
    sleep 6
    kwin_script 'for (const w of workspace.windowList()) if (w.desktopFileName === "kwin_ectoview_config") print("settings window " + w.caption);'
    grep -q "js: settings window Ectoview" /tmp/kwin.log && pass "the settings page opens, in a window named Ectoview" \
        || { fail "the settings page didn't open"; tail -5 /tmp/kcm.log | sed 's/^/  kcm: /'
             echo "  kcmshell6 running: $(pgrep -u stranger -x kcmshell6 || echo no)"
             kwin_script 'for (const w of workspace.windowList()) print("window " + JSON.stringify({c: w.caption, d: w.desktopFileName, r: w.resourceClass}));'
             grep "js: window" /tmp/kwin.log | sed 's/^/  /'; }
    pkill -u stranger -x kcmshell6; sleep 0.5
else
    note "kcmshell6 isn't installed here (it comes with System Settings), so the settings page wasn't opened"
fi

# a second run updates in place and leaves the shortcuts as they are
./install.sh --yes > /tmp/install2.log 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "left as they are" /tmp/install2.log && loaded ectoview && [ "$(keys Ectoview)" = "$(cut -f2 /tmp/before | head -1)" ] \
    && pass "a second install.sh updates in place and leaves the shortcuts as they are" || { fail "second install.sh (exit $rc)"; tail -15 /tmp/install2.log; }

# ---- uninstall outside a Plasma session (no shortcut service): refused, nothing changed
DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent ./uninstall.sh > /tmp/uninstall0.log 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "Nothing was changed" /tmp/uninstall0.log && [ -f "$STATE/overview-shortcuts" ] && loaded ectoview \
    && [ "$(keys Ectoview)" = "$(cut -f2 /tmp/before | head -1)" ] \
    && pass "uninstall.sh outside a Plasma session refuses and changes nothing (Overview's saved shortcuts are kept)" \
    || { fail "uninstall.sh without the shortcut service (exit $rc)"; tail -5 /tmp/uninstall0.log; }
./uninstall.sh --help > /dev/null 2>&1 && [ -d "$STATE" ] && loaded ectoview && pass "uninstall.sh --help only shows the help" || fail "uninstall.sh --help changed something"

# ---- uninstall
./uninstall.sh > /tmp/uninstall.log 2>&1; rc=$?
sed 's/^/  | /' /tmp/uninstall.log
[ "$rc" = 0 ] && pass "uninstall.sh finished" || fail "uninstall.sh failed (exit $rc)"
wait_for "loaded overview" && ! loaded ectoview && pass "Overview is back on, Ectoview off" || fail "after uninstall: overview $(effects isEffectLoaded overview), ectoview $(effects isEffectLoaded ectoview)"
ok=1
while IFS=$'\t' read -r a k; do [ "$(keys "$a")" = "$k" ] || { ok=0; echo "  Overview's $a is $(keys "$a"), was $k"; }; done < /tmp/before
[ "$ok" = 1 ] && pass "Overview has every shortcut it had before the install" || fail "Overview's shortcuts aren't back"
left=$(find "$HOME" -path "$HOME/Ectoview" -prune -o -path "$HOME/.cache" -prune -o -iname '*ectoview*' -print 2>/dev/null)
[ -z "$left" ] && pass "no file named Ectoview is left in the home folder" || { fail "left behind:"; echo "$left" | sed 's/^/  /'; }
grep -q "^\[Effect-ectoview\]" "$HOME/.config/kwinrc" 2>/dev/null && fail "kwinrc still holds Ectoview's settings" || pass "kwinrc no longer holds Ectoview's settings"
# every file and folder the install made is gone (the icon cache, the folders it made); what KDE's
# own programs wrote while running (their settings and data) isn't Ectoview's
snapshot > /tmp/home-after
extra=$(comm -13 /tmp/home-before /tmp/home-after | while IFS= read -r f; do
    # a folder that holds something is judged by what it holds; an empty one is reported
    if [ -d "$f" ]; then [ -z "$(ls -A "$f" 2>/dev/null)" ] && echo "$f/ (empty folder)"; continue; fi
    case "${f#"$HOME"/}" in
        .config/kwinrc|.config/kwinrulesrc|.config/kglobalshortcutsrc|.config/kdeglobals|.config/kcmshell6rc|.config/kded6rc|.config/kconf_updaterc|.config/session/*|.config/kscreen*|.config/systemsettingsrc|.config/user-dirs.*|.config/trashrc) ;;
        .local/state/kglobalshortcutsstaterc|.local/state/kcmshell6statesrc|.local/share/kscreen/*|.local/share/kwin/*|.local/share/user-places.xbel*|.local/share/recently-used.xbel) ;;
        *) echo "$f";;
    esac
done)
[ -z "$extra" ] && pass "the home folder holds nothing the install made" || { fail "left in the home folder:"; echo "$extra" | head -20 | sed 's/^/  /'; }
# KWin's lines about Ectoview, for reading after a run
echo "KWin's log about Ectoview:"; grep -i ectoview /tmp/kwin.log | grep -v 'js: ' | sort -u | head -40 | sed 's/^/  kwin: /'
exit $bad
