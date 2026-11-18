#!/bin/bash
# Installs Ectoview for the current user, in place of KDE's Overview. No root needed.
#
#   ./install.sh [--yes] [--prefix DIR] [--no-shortcuts] [--no-deps]
#
# 0. Checks this is KDE Plasma 6.7 or newer, and that what the build needs is installed: when
#    something is missing it shows your package manager's command and runs it only if you agree
#    (that one step uses sudo). --yes agrees in advance; --no-deps skips the check.
# 1. Builds the settings page and installs it under the prefix (default ~/.local).
# 2. Installs the effect (package/) with kpackagetool6, into ~/.local/share/kwin/effects/ectoview.
# 3. Adds the prefix's Qt plugin folder to the Plasma session (~/.config/plasma-workspace/env/ectoview.sh),
#    so System Settings finds the settings page. It shows up there after you log out and in once.
# 4. Turns Overview off and Ectoview on, carrying Overview's settings (minimized windows, the grid,
#    search, screen edges) over the first time.
# 5. Moves Overview's shortcuts (Meta+W, Meta+G and the cycle keys) to Ectoview.
# Everything it changes is recorded in ~/.local/state/ectoview-install, and ./uninstall.sh puts it
# back. Running it again updates the install and keeps your settings and shortcuts. If a step
# fails, Overview stays as it was.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
. "$SRC/tools/install/common.sh"

PREFIX=$HOME/.local SHORTCUTS=1 ASSUME_YES=0 DEPS=1
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) [ $# -ge 2 ] && [ -n "$2" ] || fail "--prefix needs a folder"; PREFIX=$(realpath -m "$2"); shift;;
        --no-shortcuts) SHORTCUTS=0;;
        --yes|-y) ASSUME_YES=1;;
        --no-deps) DEPS=0;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
        *) fail "unknown option $1 (try --help)";;
    esac
    shift
done

[ "$(id -u)" != 0 ] || fail "run this as yourself, not as root: Ectoview installs for one person"
[ -f "$SRC/CMakeLists.txt" ] && [ -d "$SRC/package" ] || fail "run this from the Ectoview source folder"

# ---- 0. this system: KDE Plasma's KWin, and what the build needs (nothing is changed before this passes)
step "Checking this system"
check_system
if [ "$DEPS" = 1 ]; then install_needs; fi
for tool in cmake kpackagetool6 kwriteconfig6 kreadconfig6 gdbus python3; do
    command -v "$tool" >/dev/null || fail "$tool is missing (see the README's Installing, or run without --no-deps)"
done
[ -f "$STATE/prefix" ] && [ "$(cat "$STATE/prefix")" != "$PREFIX" ] && fail "Ectoview is installed under $(cat "$STATE/prefix"); run ./uninstall.sh first to move it"
# the records' own folder first (its new folders are noted once it exists to hold the note)
STATE_DIRS=$(new_dirs "$STATE")
mkdir -p "$STATE"
printf '%s\n' "$STATE_DIRS" | while IFS= read -r d; do [ -z "$d" ] || note_new_dirs_known "$d"; done
echo "$PREFIX" > "$STATE/prefix"

# ---- 1. the settings page
step "Building the settings page"
# its own build folder, kept with the install records (the source tree's build/ is for development)
BUILD=$STATE/build
# a build folder made from another copy of the source starts over (CMake won't reuse it)
if [ -f "$BUILD/CMakeCache.txt" ] && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$SRC" "$BUILD/CMakeCache.txt"; then rm -rf "$BUILD"; fi
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX" > "$STATE/cmake.log" 2>&1 || { cat "$STATE/cmake.log"; fail "configuring the build failed"; }
cmake --build "$BUILD" >> "$STATE/cmake.log" 2>&1 || { tail -30 "$STATE/cmake.log"; fail "building the settings page failed"; }
# the folders the install will make, learned from a trial install into an empty folder
TRIAL=$(mktemp -d)
DESTDIR=$TRIAL cmake --install "$BUILD" >> "$STATE/cmake.log" 2>&1 || { rm -rf "$TRIAL"; fail "installing the settings page failed"; }
while IFS= read -r f; do note_new_dirs "$(dirname "${f#"$TRIAL"}")"; done < <(find "$TRIAL" -type f)
rm -rf "$TRIAL"
# KDE's icon install refreshes the icon cache; one it makes is Ectoview's to remove again
ICON_CACHE=$PREFIX/share/icons/hicolor/icon-theme.cache
[ -e "$ICON_CACHE" ] || [ -f "$STATE/icon-cache" ] || echo "$ICON_CACHE" > "$STATE/icon-cache.maybe"
cmake --install "$BUILD" >> "$STATE/cmake.log" 2>&1 || fail "installing the settings page failed"
if [ -f "$STATE/icon-cache.maybe" ]; then
    if [ -e "$ICON_CACHE" ]; then mv "$STATE/icon-cache.maybe" "$STATE/icon-cache"; else rm -f "$STATE/icon-cache.maybe"; fi
fi
cp "$BUILD/install_manifest.txt" "$STATE/installed-files"
# the plugin folder: the installed module's path less kwin/effects/configs/kwin_ectoview_config.so
SO=$(grep -m1 'kwin_ectoview_config.so$' "$STATE/installed-files" || true)
PLUGINS=${SO%/kwin/effects/configs/kwin_ectoview_config.so}
[ -n "$SO" ] && [ -f "$PLUGINS/kwin/effects/configs/kwin_ectoview_config.so" ] || fail "the settings page wasn't installed where expected"
echo "$PLUGINS" > "$STATE/plugins"
# the gear beside Ectoview's search field opens the page by this path
kwriteconfig6 --file kwinrc --group Effect-ectoview --key SettingsModule "$PLUGINS/kwin/effects/configs/kwin_ectoview_config.so"
say "Settings page: $PLUGINS/kwin/effects/configs/kwin_ectoview_config.so"

# ---- 2. the effect
step "Installing the effect"
# KWin compiles an effect's QML once per path and keeps it until it restarts, so each build goes
# into its own folder, named for its contents (package/contents/ui/main.qml loads it by name)
# (ECTOVIEW_TEST_BUILD_ID: the tests' planted fault, one folder name for every build)
BUILD_ID=${ECTOVIEW_TEST_BUILD_ID:-}
[ -n "$BUILD_ID" ] || BUILD_ID=b$(cd "$SRC/package/contents/ui/impl" && find . -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -c1-12)
STAGE=$(mktemp -d) NEWROOT=
trap 'rm -rf "$STAGE"; [ -z "$NEWROOT" ] || rm -rf "$NEWROOT"' EXIT
cp -r "$SRC/package/." "$STAGE/"
mv "$STAGE/contents/ui/impl" "$STAGE/contents/ui/$BUILD_ID"
note_new_dirs "$EFFECTS_ROOT"
mkdir -p "$EFFECTS_ROOT"
# installed beside the old one first, then put in its place, so a failed install leaves the old one
NEWROOT=$(mktemp -d "$EFFECTS_ROOT/.ectoview-new.XXXXXX")
kpackagetool6 --type KWin/Effect --packageroot "$NEWROOT" --install "$STAGE" > "$STATE/kpackage.log" 2>&1 || { cat "$STATE/kpackage.log"; fail "installing the effect failed; the installed one is as it was"; }
[ -f "$NEWROOT/ectoview/metadata.json" ] || fail "installing the effect failed (no metadata.json); the installed one is as it was"
rm -rf "$EFFECTS_ROOT/ectoview"
mv "$NEWROOT/ectoview" "$EFFECTS_ROOT/ectoview"
# a copy where KWin 6.7 looks first, left by an install from before 1.0, goes
if [ -d "$OTHER_EFFECTS_ROOT/ectoview" ]; then
    rm -rf "$OTHER_EFFECTS_ROOT/ectoview"
    say "Moved the effect from $OTHER_EFFECTS_ROOT to $EFFECTS_ROOT."
fi
kwriteconfig6 --file kwinrc --group Effect-ectoview --key Build "$BUILD_ID"
say "Build: $BUILD_ID"
say "Effect: $EFFECTS_ROOT/ectoview"

# ---- 3. where System Settings looks for the settings page
step "Adding the settings page's folder to the Plasma session"
note_new_dirs "$(dirname "$ENV_SCRIPT")"
mkdir -p "$(dirname "$ENV_SCRIPT")"
# (the paths go in single-quoted, so a folder name with $ or " in it stays as it is)
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
cat > "$ENV_SCRIPT" <<EOF
# Added by Ectoview's install.sh, removed by its uninstall.sh: where System Settings finds
# Ectoview's settings page (Qt looks for plugins in QT_PLUGIN_PATH as well as its own folder).
export QT_PLUGIN_PATH=$(q "$PLUGINS")"\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
EOF
# the settings window's icon and desktop entry are in the prefix's share folder: Plasma looks in the
# data home (~/.local/share, the default prefix's) and XDG_DATA_DIRS, so another prefix is added there
SHARE=$PREFIX/share
[ "$SHARE" = "$(realpath -m "${XDG_DATA_HOME:-$HOME/.local/share}")" ] && SHARE=
echo "$SHARE" > "$STATE/share"
if [ -n "$SHARE" ]; then echo "export XDG_DATA_DIRS=$(q "$SHARE")\":\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\"" >> "$ENV_SCRIPT"; fi
# for programs started from now on through systemd or D-Bus (the rest after the next login); what
# was added is recorded, so uninstall.sh takes away only that
if session_env_ok; then
    current=$(systemctl --user show-environment | sed -n 's/^QT_PLUGIN_PATH=//p')
    case ":$current:" in
        *":$PLUGINS:"*) ;;
        *) systemctl --user set-environment "QT_PLUGIN_PATH=$PLUGINS${current:+:$current}" && echo "$PLUGINS" > "$STATE/session-plugins" || true;;
    esac
    if [ -n "$SHARE" ]; then
        current=$(systemctl --user show-environment | sed -n 's/^XDG_DATA_DIRS=//p')
        case ":$current:" in
            *":$SHARE:"*) ;;
            *) [ -f "$STATE/session-data-dirs-before" ] || { if [ -n "$current" ]; then echo "$current"; else echo __unset__; fi; } > "$STATE/session-data-dirs-before"
               systemctl --user set-environment "XDG_DATA_DIRS=$SHARE:${current:-/usr/local/share:/usr/share}" && echo "$SHARE" > "$STATE/session-share" || true;;
        esac
    fi
fi

# ---- 4 and 5. Ectoview in, Overview out, and Overview's shortcuts to Ectoview (tools/install/common.sh)
turn_on

step "Done"
say "Meta+W opens Ectoview; the gear beside its search field opens its settings. They're also in"
say "System Settings > Window Management > Desktop Effects after you log out and in once."
say "./uninstall.sh puts Overview back."
if [ "$NEEDS_RELOGIN" = 1 ]; then
    say ""
    say "KWin was running when the QML modules Ectoview uses were installed: log out and in once,"
    say "and Meta+W opens Ectoview with everything in place."
fi
