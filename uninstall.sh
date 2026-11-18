#!/bin/bash
# Removes Ectoview and puts KDE's Overview back as it was before install.sh: Overview on (or as you
# had it), its shortcuts back, the session as it was, the settings page and effect removed, and
# only the folders install.sh made.
#
#   ./uninstall.sh [--keep-settings]
#
# Ectoview's own settings (kwinrc [Effect-ectoview]) go too unless --keep-settings. KWin's
# "Switch desktops independently for each screen" is KWin's and stays as you set it.
# Run it in your Plasma session: Overview's shortcuts go back through KDE's shortcut service.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
. "$SRC/tools/install/common.sh"

KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-settings) KEEP=1;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
        *) fail "unknown option $1 (try --help); nothing was changed";;
    esac
    shift
done
[ -d "$STATE" ] || fail "Ectoview isn't installed for this user (no $STATE)"
command -v python3 >/dev/null || [ "$KEEP" = 1 ] || fail "python3 is missing (it removes Ectoview's settings from kwinrc); install it, or use --keep-settings. Nothing was changed."
# without the shortcut service, saved shortcuts couldn't go back: stop before anything changes
need_shortcut_service

turn_off
rm -f "$STATE/overview-enabled"
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
kpkg --remove ectoview >/dev/null 2>&1 || true
rm -rf "$EFFECTS_ROOT/ectoview" "$OTHER_EFFECTS_ROOT/ectoview"
if [ -f "$STATE/installed-files" ]; then
    # (the list has no newline after its last line)
    while read -r f || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        rm -f "$f"
    done < "$STATE/installed-files"
fi
# an icon cache the install made goes; one that was there already is made again without Ectoview's icon
if [ -f "$STATE/icon-cache" ]; then
    rm -f "$(cat "$STATE/icon-cache")"
else
    PREFIX=$(cat "$STATE/prefix" 2>/dev/null || echo "$HOME/.local")
    if [ -e "$PREFIX/share/icons/hicolor/icon-theme.cache" ] && command -v gtk-update-icon-cache >/dev/null; then
        gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" 2>/dev/null || true
    fi
fi
rm -f "$ENV_SCRIPT"
if session_env_ok; then
    # only what install.sh added: its plugin folder, its share folder, and XDG_DATA_DIRS as it was
    if [ -f "$STATE/session-plugins" ]; then
        PLUGINS=$(cat "$STATE/session-plugins")
        current=$(systemctl --user show-environment | sed -n 's/^QT_PLUGIN_PATH=//p')
        rest=$(printf '%s' "$current" | tr ':' '\n' | grep -vxF "$PLUGINS" | paste -sd: - || true)
        if [ -n "$rest" ]; then systemctl --user set-environment "QT_PLUGIN_PATH=$rest" || true
        elif [ -n "$current" ]; then systemctl --user unset-environment QT_PLUGIN_PATH || true; fi
    fi
    if [ -f "$STATE/session-share" ]; then
        SHARE=$(cat "$STATE/session-share")
        current=$(systemctl --user show-environment | sed -n 's/^XDG_DATA_DIRS=//p')
        rest=$(printf '%s' "$current" | tr ':' '\n' | grep -vxF "$SHARE" | paste -sd: - || true)
        before=$(cat "$STATE/session-data-dirs-before" 2>/dev/null || echo __unset__)
        if [ "$before" = __unset__ ] && [ "$rest" = /usr/local/share:/usr/share ]; then systemctl --user unset-environment XDG_DATA_DIRS || true
        elif [ -n "$rest" ]; then systemctl --user set-environment "XDG_DATA_DIRS=$rest" || true; fi
    fi
fi
# the folders install.sh made, deepest first, each only if it's empty now
DIRS=$(cat "$STATE/dirs-made" 2>/dev/null || true)
rm -rf "$STATE"
printf '%s\n' "$DIRS" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- | while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && rmdir "$d" 2>/dev/null || true
done

step "Done"
say "Overview is back. Ectoview's files are gone$([ "$KEEP" = 1 ] && echo "; its settings stay in kwinrc")."
