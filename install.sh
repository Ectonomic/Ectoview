#!/bin/bash
# Installs Ectoview for the current user, in place of KDE's Overview. No root needed.
#
#   ./install.sh [--prefix DIR] [--no-shortcuts]
#
# 1. Builds the settings page and installs it under the prefix (default ~/.local).
# 2. Installs the effect (package/) with kpackagetool6, into ~/.local/share/kwin/effects/ectoview.
# 3. Adds the prefix's Qt plugin folder to the Plasma session (~/.config/plasma-workspace/env/ectoview.sh),
#    so System Settings finds the settings page. It shows up there after you log out and in once.
# 4. Turns Overview off and Ectoview on, carrying Overview's settings (minimized windows, the grid,
#    search, screen edges) over the first time.
# 5. Moves Overview's shortcuts (Meta+W, Meta+G and the cycle keys) to Ectoview.
# Everything it changes is recorded in ~/.local/state/ectoview-install, and ./uninstall.sh puts it
# back. Running it again updates the install and keeps your settings and shortcuts.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
. "$SRC/tools/install/common.sh"

PREFIX=$HOME/.local SHORTCUTS=1
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX=$(realpath -m "$2"); shift;;
        --no-shortcuts) SHORTCUTS=0;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
        *) fail "unknown option $1 (try --help)";;
    esac
    shift
done

for tool in cmake kpackagetool6 kwriteconfig6 kreadconfig6 gdbus; do
    command -v "$tool" >/dev/null || fail "$tool is missing"
done
mkdir -p "$STATE"
[ -f "$STATE/prefix" ] && [ "$(cat "$STATE/prefix")" != "$PREFIX" ] && fail "Ectoview is installed under $(cat "$STATE/prefix"); run ./uninstall.sh first to move it"
echo "$PREFIX" > "$STATE/prefix"

# ---- 1. the settings page
step "Building the settings page"
# its own build folder, kept with the install records (the source tree's build/ is for development)
BUILD=$STATE/build
# a build folder made from another copy of the source starts over (CMake won't reuse it)
if [ -f "$BUILD/CMakeCache.txt" ] && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$SRC" "$BUILD/CMakeCache.txt"; then rm -rf "$BUILD"; fi
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="$PREFIX" > "$STATE/cmake.log" 2>&1 || { cat "$STATE/cmake.log"; fail "configuring the build failed"; }
cmake --build "$BUILD" >> "$STATE/cmake.log" 2>&1 || { tail -30 "$STATE/cmake.log"; fail "building the settings page failed"; }
cmake --install "$BUILD" >> "$STATE/cmake.log" 2>&1 || fail "installing the settings page failed"
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
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -r "$SRC/package/." "$STAGE/"
mv "$STAGE/contents/ui/impl" "$STAGE/contents/ui/$BUILD_ID"
mkdir -p "$EFFECTS_ROOT"
# (kpackagetool6 --show also finds the package in the old folder, so the folder itself says what's there)
rm -rf "$EFFECTS_ROOT/ectoview"
kpkg --install "$STAGE" > "$STATE/kpackage.log" 2>&1 || { cat "$STATE/kpackage.log"; fail "installing the effect failed"; }
# an install from before the move to kwin-wayland/effects goes
if [ -d "$OLD_EFFECTS_ROOT/ectoview" ]; then
    kpackagetool6 --type KWin/Effect --remove ectoview >/dev/null 2>&1 || rm -rf "$OLD_EFFECTS_ROOT/ectoview"
    say "Moved the effect from $OLD_EFFECTS_ROOT to $EFFECTS_ROOT."
fi
kwriteconfig6 --file kwinrc --group Effect-ectoview --key Build "$BUILD_ID"
say "Build: $BUILD_ID"
say "Effect: $EFFECTS_ROOT/ectoview"

# ---- 3. where System Settings looks for the settings page
step "Adding the settings page's folder to the Plasma session"
mkdir -p "$(dirname "$ENV_SCRIPT")"
cat > "$ENV_SCRIPT" <<EOF
# Added by Ectoview's install.sh, removed by its uninstall.sh: where System Settings finds
# Ectoview's settings page (Qt looks for plugins in QT_PLUGIN_PATH as well as its own folder).
export QT_PLUGIN_PATH="$PLUGINS\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
EOF
# for programs started from now on through systemd or D-Bus (the rest after the next login)
if session_env_ok; then
    current=$(systemctl --user show-environment | sed -n 's/^QT_PLUGIN_PATH=//p')
    case ":$current:" in *":$PLUGINS:"*) ;; *) systemctl --user set-environment "QT_PLUGIN_PATH=$PLUGINS${current:+:$current}" || true;; esac
fi

# ---- 4. Ectoview in, Overview out
step "Turning Overview off and Ectoview on"
if [ ! -f "$STATE/overview-enabled" ]; then
    # Overview's switch as it was (absent means KWin's default), for uninstall.sh
    kreadconfig6 --file kwinrc --group Plugins --key overviewEnabled --default __absent__ > "$STATE/overview-enabled"
    # Overview's settings become Ectoview's, the first time only
    for key in IgnoreMinimized FilterWindows OrganizedGrid BorderActivate GridBorderActivate TouchBorderActivate GridTouchBorderActivate; do
        v=$(kreadconfig6 --file kwinrc --group Effect-overview --key "$key" --default __absent__)
        [ "$v" = __absent__ ] && continue
        [ "$(kreadconfig6 --file kwinrc --group Effect-ectoview --key "$key" --default __absent__)" = __absent__ ] || continue
        kwriteconfig6 --file kwinrc --group Effect-ectoview --key "$key" "$v"
        say "Carried over Overview's $key ($v)"
    done
fi
kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key ectoviewEnabled true
if kwin_running; then
    kwin_effects unloadEffect overview >/dev/null
    kwin_effects unloadEffect ectoview >/dev/null   # so an update loads the new files
    kwin_effects loadEffect ectoview >/dev/null
    for _ in $(seq 50); do kwin_effects isEffectLoaded ectoview | grep -q true && break; sleep 0.1; done
    kwin_effects isEffectLoaded ectoview | grep -q true || fail "KWin didn't load Ectoview; see journalctl --user -b | grep -i ectoview"
    say "KWin has Ectoview loaded."
else
    say "KWin isn't running here; Ectoview starts with your next Plasma session."
fi

# ---- 5. shortcuts
if [ "$SHORTCUTS" = 1 ]; then
    take_shortcuts
fi

step "Done"
say "Meta+W opens Ectoview; the gear beside its search field opens its settings. They're also in"
say "System Settings > Window Management > Desktop Effects after you log out and in once."
say "./uninstall.sh puts Overview back."
