#!/bin/bash
# Removes Ectoview and puts KDE's Overview back as it was before install.sh: Overview on (or as you
# had it), its shortcuts back, the session script gone, the settings page and effect removed.
#
#   ./uninstall.sh [--keep-settings]
#
# Ectoview's own settings (kwinrc [Effect-ectoview]) go too unless --keep-settings. KWin's
# "Switch desktops independently for each screen" is KWin's and stays as you set it.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
. "$SRC/tools/install/common.sh"

KEEP=0
[ "${1:-}" = --keep-settings ] && KEEP=1
[ -d "$STATE" ] || fail "Ectoview isn't installed for this user (no $STATE)"

step "Giving Overview its shortcuts back"
give_back_shortcuts

step "Turning Ectoview off and Overview back on"
kwriteconfig6 --file kwinrc --group Plugins --key ectoviewEnabled --delete
was=$(cat "$STATE/overview-enabled" 2>/dev/null || echo __absent__)
if [ "$was" = __absent__ ]; then
    kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled --delete
else
    kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled "$was"
fi
if kwin_running; then
    kwin_effects unloadEffect ectoview >/dev/null
    [ "$was" = false ] || kwin_effects loadEffect overview >/dev/null
fi
# the shortcut service forgets Ectoview's actions
if shortcut_service_up; then
    while IFS='|' read -r from to; do
        kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.unregister "kwin" "$to" >/dev/null || true
    done <<< "$PAIRS"
fi
if [ "$KEEP" = 0 ]; then
    # the whole group, written by Ectoview's settings page and install.sh
    python3 -I - "${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc" <<'PY'
import sys, re
p = sys.argv[1]
try:
    s = open(p).read()
except FileNotFoundError:
    sys.exit(0)
s = re.sub(r'\n?\[Effect-ectoview\]\n(?:(?!\[)[^\n]*\n?)*', '\n', s)
open(p, 'w').write(s.lstrip('\n'))
PY
fi

step "Removing the effect and the settings page"
kpkg --remove ectoview >/dev/null 2>&1 || rm -rf "$EFFECTS_ROOT/ectoview"
kpackagetool6 --type KWin/Effect --remove ectoview >/dev/null 2>&1 || true   # an install from before 2026-11-12
rm -rf "$OLD_EFFECTS_ROOT/ectoview"
if [ -f "$STATE/installed-files" ]; then
    # (the list has no newline after its last line)
    while read -r f || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        rm -f "$f"
        rmdir -p --ignore-fail-on-non-empty "$(dirname "$f")" 2>/dev/null || true
    done < "$STATE/installed-files"
fi
rm -f "$ENV_SCRIPT"
if session_env_ok; then
    PLUGINS=$(cat "$STATE/plugins" 2>/dev/null || true)
    current=$(systemctl --user show-environment | sed -n 's/^QT_PLUGIN_PATH=//p')
    rest=$(printf '%s' "$current" | tr ':' '\n' | grep -vxF "$PLUGINS" | paste -sd: - || true)
    if [ -n "$rest" ]; then systemctl --user set-environment "QT_PLUGIN_PATH=$rest" || true
    elif [ -n "$current" ]; then systemctl --user unset-environment QT_PLUGIN_PATH || true; fi
    SHARE=$(cat "$STATE/share" 2>/dev/null || true)
    if [ -n "$SHARE" ]; then
        current=$(systemctl --user show-environment | sed -n 's/^XDG_DATA_DIRS=//p')
        rest=$(printf '%s' "$current" | tr ':' '\n' | grep -vxF "$SHARE" | paste -sd: - || true)
        [ -n "$rest" ] && systemctl --user set-environment "XDG_DATA_DIRS=$rest" || true
    fi
fi
rm -rf "$STATE"

step "Done"
say "Overview is back. Ectoview's files are gone$([ "$KEEP" = 1 ] && echo "; its settings stay in kwinrc")."
