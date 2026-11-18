# Shared by install.sh, uninstall.sh and ectoview-setup. Sourced, never run.
# The shortcut moving is Ectolens's proven route (Ectolens tools/install/shortcuts.sh): KDE's
# shortcut service over D-Bus, Overview's keys saved before anything changes.

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/ectoview-install
ENV_SCRIPT=${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/ectoview.sh

# Where the effect goes: kwin/effects, the folder KWin 6.8 looks in (it dropped kwin-wayland/effects;
# effectloader.cpp, KWin 6.8.3) and KWin 6.7 looks in too (after kwin-wayland/effects; KWin 6.7.5),
# so an install made on 6.7 still loads after the system moves to 6.8. A copy left in
# kwin-wayland/effects by an install from before 1.0 is removed: on 6.7 it would win.
EFFECTS_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/kwin/effects
OTHER_EFFECTS_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/kwin-wayland/effects
kpkg() { kpackagetool6 --type KWin/Effect --packageroot "$EFFECTS_ROOT" "$@"; }
# (ECTOVIEW_TEST_EFFECT_ID: the install check's way to make KWin's load fail, for the rollback)
EFFECT_ID=${ECTOVIEW_TEST_EFFECT_ID:-ectoview}

step() { printf '\n== %s\n' "$*"; }
say() { printf '   %s\n' "$*"; }
fail() { printf '\nEctoview: %s\n' "$*" >&2; exit 1; }

# a library's version from its file name (libkwin.so.6.7.5), as the system has it
lib_version() {
    local f= d
    for d in /usr/lib64 /usr/lib/"$(uname -m)"-linux-gnu /usr/lib /lib64; do
        [ -e "$d/$1" ] && { f=$d/$1; break; }
    done
    [ -n "$f" ] || f=$(ldconfig -p 2>/dev/null | awk -v n="$1" '$1 == n {print $NF; exit}')
    [ -n "$f" ] || return 0
    f=$(readlink -f "$f"); f=${f##*/}
    echo "${f#"${1%%.so*}".so.}" | sed -n 's/^\(6\(\.[0-9]\+\)*\)$/\1/p'
}
at_least() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# the folders install.sh makes (each one that didn't exist before it), so uninstall.sh removes those
# and never a folder of the person's own that happens to be empty
# a folder known to be new (made just now), noted as install.sh's
note_new_dirs_known() { grep -qxF "$1" "$STATE/dirs-made" 2>/dev/null || echo "$1" >> "$STATE/dirs-made"; }
# (new_dirs prints each folder of the paths given, up to the first that exists, that isn't there yet)
new_dirs() {
    local d
    for d in "$@"; do
        while [ -n "$d" ] && [ "$d" != / ] && [ ! -e "$d" ]; do echo "$d"; d=$(dirname "$d"); done
    done
}
note_new_dirs() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -qxF "$d" "$STATE/dirs-made" 2>/dev/null || echo "$d" >> "$STATE/dirs-made"
    done < <(new_dirs "$@")
}

# the user's systemd session environment (tests set ECTOVIEW_NO_SESSION_ENV so a sandbox never reaches a real session)
session_env_ok() { [ -z "${ECTOVIEW_NO_SESSION_ENV:-}" ] && command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; }
kwin_running() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; }
kwin_effects() { gdbus call --session --dest org.kde.KWin --object-path /Effects --method "org.kde.kwin.Effects.$1" "${@:2}" 2>/dev/null || true; }

kga() { gdbus call --session --dest org.kde.kglobalaccel "$@" 2>/dev/null; }
shortcut_service_up() { kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.allMainComponents >/dev/null; }
component_actions() {
    local path
    path=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.getComponent "$1" | sed -n "s/^(objectpath '\(.*\)',)$/\1/p")
    [ -n "$path" ] || return 0
    kga --object-path "$path" --method org.kde.kglobalaccel.Component.shortcutNames \
        | sed "s/^(@as \[\],)$//; s/^(\[//; s/\],)$//" | sed "s/', '/\n/g" | tr -d "'" | sed '/^$/d'
}
# keys ACTION: an action of KWin's (component "kwin") in GVariant text, as setForeignShortcutKeys takes it;
# nothing when the shortcut service doesn't answer
keys() {
    local out
    out=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', '$1', '', '']") || return 1
    out=${out#(}; out=${out%,)}
    printf '%s\n' "$out"
}
set_keys() { kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.setForeignShortcutKeys "['kwin', '$1', '', '']" "$2" >/dev/null; }
# no keys, as the shortcut service says it: an empty list, or (Debian's KWin) one empty key sequence
no_keys() { [ "$1" = '@a(ai) []' ] || [ "$1" = '[]' ] || [ "$1" = '[([0, 0, 0, 0],)]' ]; }
saved_keys() { grep -P "^\Q$1\E\t" "$2" | cut -f2; }

# Overview's actions and the Ectoview actions that take their keys
PAIRS="Overview|Ectoview
Grid View|Ectoview Grid View
Cycle Overview|Ectoview Cycle
Cycle Overview Opposite|Ectoview Cycle Opposite"

# Overview's keys saved, in a record that's "moving" until every key is Ectoview's and checked; a
# move cut short (a crash, a closed terminal) is put back by the next run before it moves again.
# Returns non-zero, with TAKE_ERROR, when the keys couldn't be moved; Overview then has them.
take_shortcuts() {
    TAKE_ERROR=
    step "Moving Overview's shortcuts to Ectoview"
    if ! shortcut_service_up; then
        say "KDE's shortcut service isn't running (this isn't a Plasma session); run this again in Plasma."
        return 0
    fi
    # Ectoview's actions exist once KWin has loaded it
    local _ from to k bad=0
    for _ in $(seq 50); do component_actions kwin | grep -qx 'Ectoview' && break; sleep 0.2; done
    if ! component_actions kwin | grep -qx 'Ectoview'; then
        TAKE_ERROR="KDE's shortcut service hasn't picked up Ectoview's shortcuts; log out and in, then run this again"
        return 1
    fi
    if [ -f "$STATE/overview-shortcuts.moving" ]; then
        give_back_from "$STATE/overview-shortcuts.moving"
        say "Put back a move an earlier run didn't finish."
    fi
    if [ -f "$STATE/overview-shortcuts" ]; then
        say "Already moved by an earlier run; left as they are."
        return 0
    fi
    : > "$STATE/overview-shortcuts.new"
    while IFS='|' read -r from to; do
        k=$(keys "$from") || k=
        if [ -z "$k" ]; then
            rm -f "$STATE/overview-shortcuts.new"
            TAKE_ERROR="KDE's shortcut service didn't say what Overview's $from keys are; nothing was moved"
            return 1
        fi
        printf '%s\t%s\n' "$from" "$k" >> "$STATE/overview-shortcuts.new"
    done <<< "$PAIRS"
    mv "$STATE/overview-shortcuts.new" "$STATE/overview-shortcuts.moving"
    # one key, one owner: Overview lets go first, then Ectoview takes the keys
    while IFS='|' read -r from to; do
        k=$(saved_keys "$from" "$STATE/overview-shortcuts.moving")
        no_keys "$k" && continue
        set_keys "$from" '@a(ai) []' || true
        set_keys "$to" "$k" || true
    done <<< "$PAIRS"
    while IFS='|' read -r from to; do
        k=$(saved_keys "$from" "$STATE/overview-shortcuts.moving")
        no_keys "$k" && continue
        [ "$(keys "$to" || true)" = "$k" ] || bad=1
        no_keys "$(keys "$from" || true)" || bad=1
    done <<< "$PAIRS"
    if [ "$bad" = 1 ]; then
        give_back_from "$STATE/overview-shortcuts.moving"
        TAKE_ERROR="KDE's shortcut service didn't give Ectoview Overview's keys, so Overview keeps them; run this again to retry"
        return 1
    fi
    mv "$STATE/overview-shortcuts.moving" "$STATE/overview-shortcuts"
    say "Moved: $(cut -f1,2 "$STATE/overview-shortcuts" | grep -v "@a(ai) \[\]" | cut -f1 | paste -sd, - | sed 's/,/, /g')."
}

# Overview gets back the keys a record saved, and Ectoview's actions let go of them; the record goes.
# (Callers make sure the shortcut service is up first: see need_shortcut_service.)
give_back_from() {
    local from to k
    while IFS='|' read -r from to; do set_keys "$to" '@a(ai) []' || true; done <<< "$PAIRS"
    while IFS='|' read -r from to; do
        k=$(saved_keys "$from" "$1")
        no_keys "$k" || set_keys "$from" "$k" || true
    done <<< "$PAIRS"
    rm -f "$1"
}
give_back_shortcuts() {
    local f
    for f in "$STATE/overview-shortcuts.moving" "$STATE/overview-shortcuts"; do
        [ -f "$f" ] && give_back_from "$f"
    done
    say "Overview has its shortcuts back."
}
# saved shortcuts need the shortcut service to go back: without it (not a Plasma session) stop
# before anything changes, so the record isn't lost
need_shortcut_service() {
    if { [ -f "$STATE/overview-shortcuts" ] || [ -f "$STATE/overview-shortcuts.moving" ]; } && ! shortcut_service_up; then
        fail "KDE's shortcut service isn't running, so Overview's shortcuts can't go back now. Run this again in your Plasma session. Nothing was changed."
    fi
}

# ---- the system check and the build's packages (Ectolens's install.sh is the model: its
# stranger-check proves the same lists on Fedora, openSUSE, Arch, Debian and KDE neon)

# the minimum Plasma: Ectoview's views are KWin 6.7's Overview, and use what KWin 6.7 gives QML
PLASMA_MIN=6.7
ASSUME_YES=${ASSUME_YES:-0}
# the Plasmas Ectoview is made and tested on (tests/e2e on 6.7, tests/e2e/container.sh and
# tests/install on 6.8); a newer one is let through with a word of warning
PLASMA_MADE_FOR="6.7 6.8"

ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    local a; read -r -p "   $1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]
}

check_system() {
    . /etc/os-release 2>/dev/null || true
    DISTRO=${PRETTY_NAME:-this system}
    PLASMA=$(lib_version libkwin.so.6)
    say "$DISTRO: Plasma ${PLASMA:-not found}"
    [ -n "$PLASMA" ] || fail "KDE Plasma's KWin isn't installed here. Ectoview runs on KDE Plasma 6.7 or newer, on Wayland."
    at_least "$PLASMA" "$PLASMA_MIN" || fail "$DISTRO has Plasma $PLASMA, too old for Ectoview: it needs Plasma $PLASMA_MIN or newer. Nothing was changed."
    local v made=0
    for v in $PLASMA_MADE_FOR; do case "$PLASMA" in "$v"|"$v".*) made=1;; esac; done
    if [ "$made" = 0 ]; then
        say "Ectoview is made for Plasma ${PLASMA_MADE_FOR// / and } and hasn't been tried on Plasma $PLASMA yet."
        say "If it misbehaves, ./uninstall.sh puts Overview back."
    fi
}

# what the build and install.sh need, by package manager (Fedora and openSUSE name what CMake looks for),
# and the QML modules Ectoview's views import (Qt Quick's, Milou, Plasma's components, Kirigami, KSvg,
# KCMUtils, Qt5Compat): a full Plasma desktop has them, and without one the view doesn't load. The
# names are each distribution's package for the module's qmldir (looked up November 17, 2026).
install_needs() {
    local FAMILY= id
    for id in ${ID:-} ${ID_LIKE:-}; do
        case "$id" in
            fedora|rhel) FAMILY=rpm-dnf;;
            suse|opensuse|opensuse-tumbleweed|opensuse-leap|opensuse-slowroll) FAMILY=rpm-zypper;;
            arch) FAMILY=pacman;;
            debian|ubuntu) FAMILY=apt;;
            *) continue;;
        esac
        break
    done
    local RPM_NEEDS=(cmake gcc-c++ make python3
        'cmake(Qt6Core)' 'cmake(Qt6Gui)' 'cmake(Qt6Widgets)' 'cmake(Qt6DBus)'
        'cmake(KF6Config)' 'cmake(KF6ConfigWidgets)' 'cmake(KF6CoreAddons)' 'cmake(KF6GlobalAccel)'
        'cmake(KF6I18n)' 'cmake(KF6KCMUtils)' 'cmake(KF6WidgetsAddons)' 'cmake(KF6XmlGui)'
        /usr/bin/kpackagetool6 /usr/bin/kwriteconfig6 /usr/bin/kreadconfig6 /usr/bin/gdbus)
    local NEEDS=() INSTALL=()
    case "$FAMILY" in
        rpm-dnf)    NEEDS=("${RPM_NEEDS[@]}" extra-cmake-modules qt6-qtdeclarative
                        plasma-milou libplasma kf6-kirigami kf6-ksvg kf6-kcmutils qt6-qt5compat)
                    missing() { local p; for p in "$@"; do rpm -q --whatprovides "$p" >/dev/null 2>&1 || echo "$p"; done; }
                    INSTALL=(sudo dnf install -y);;
        rpm-zypper) NEEDS=("${RPM_NEEDS[@]}" kf6-extra-cmake-modules qt6-declarative-imports
                        milou6 libplasma6-components kf6-kirigami-imports kf6-ksvg-imports kf6-kcmutils-imports kf6-kcmutils qt6-qt5compat-imports)
                    missing() { local p; for p in "$@"; do rpm -q --whatprovides "$p" >/dev/null 2>&1 || echo "$p"; done; }
                    INSTALL=(sudo zypper --non-interactive install);;
        pacman)     NEEDS=(base-devel cmake extra-cmake-modules python qt6-base qt6-declarative kconfig kconfigwidgets kcoreaddons
                        kglobalaccel ki18n kcmutils kwidgetsaddons kxmlgui kpackage glib2
                        milou libplasma kirigami ksvg qt6-5compat)
                    missing() { pacman -T "$@" || true; }
                    INSTALL=(sudo pacman -S --needed --noconfirm);;
        apt)        NEEDS=(build-essential cmake extra-cmake-modules python3 qt6-base-dev
                        libkf6config-dev libkf6configwidgets-dev libkf6coreaddons-dev libkf6globalaccel-dev
                        libkf6i18n-dev libkf6kcmutils-dev libkf6widgetsaddons-dev libkf6xmlgui-dev
                        'kpackagetool6|libkf6package-bin' 'libkf6config-bin|kf6-kconfig-bin' libglib2.0-bin
                        qml6-module-qtquick qml6-module-qtquick-templates qml6-module-qtquick-layouts
                        qml6-module-qtquick-window qml6-module-qtquick-controls
                        'qml6-module-org-kde-milou|milou' 'plasma-desktoptheme|libplasma6' 'qml6-module-org-kde-kirigami|kf6-kirigami'
                        'qml6-module-org-kde-ksvg|kf6-ksvg' 'qml6-module-org-kde-kcmutils|kf6-kcmutils' qml6-module-qt5compat-graphicaleffects)
                    # a|b: names differ between Debian, Ubuntu and KDE neon; the first the package lists know is asked for
                    missing() { local p a c alts; for p in "$@"; do
                        IFS='|' read -ra alts <<<"$p"
                        for a in "${alts[@]}"; do [ "$(dpkg-query -W -f='${db:Status-Status}' "$a" 2>/dev/null)" = installed ] && continue 2; done
                        for a in "${alts[@]}"; do
                            c=$(apt-cache policy "$a" 2>/dev/null | sed -n 's/ *Candidate: //p')
                            [ -n "$c" ] && [ "$c" != "(none)" ] && { echo "$a"; continue 2; }
                        done
                        echo "${alts[0]}"
                    done; }
                    INSTALL=(sudo apt-get install -y);;
    esac
    step "Checking what the build needs"
    if [ -z "$FAMILY" ]; then
        say "This script doesn't know $DISTRO's package names. Install CMake, KDE's Extra CMake Modules, a C++"
        say "compiler, Python 3, and the development files for Qt 6 (Core, Gui, Widgets, DBus) and KDE"
        say "Frameworks 6 (Config, ConfigWidgets, CoreAddons, GlobalAccel, I18n, KCMUtils, WidgetsAddons,"
        say "XmlGui), with kpackagetool6, kwriteconfig6, gdbus and the QML modules of Milou, Plasma,"
        say "Kirigami, KSvg, KCMUtils and Qt5Compat; then run ./install.sh --no-deps."
        exit 1
    fi
    local MISSING STILL
    mapfile -t MISSING < <(missing "${NEEDS[@]}")
    if [ ${#MISSING[@]} -eq 0 ]; then
        say "Everything is installed."
        return 0
    fi
    # an image-based Fedora (Kinoite) installs packages with rpm-ostree, not dnf
    if [ "$FAMILY" = rpm-dnf ] && [ -e /run/ostree-booted ]; then
        say "This is an image-based system, where dnf can't install packages. The build needs:"
        say ""; say "  ${MISSING[*]}"; say ""
        fail "install them with rpm-ostree (or build in a toolbox), then run ./install.sh --no-deps. Nothing was changed."
    fi
    if [ "$FAMILY" = apt ]; then
        say "The build needs ${#MISSING[@]} packages from $DISTRO. The commands are:"
        say ""; say "  sudo apt-get update"; say "  ${INSTALL[*]} ${MISSING[*]}"; say ""
        ask "Run them now?" || fail "run those commands, then ./install.sh again. Nothing was changed."
        sudo apt-get update
        # the names the refreshed lists know; asked again when they differ from the ones shown
        local SHOWN=("${MISSING[@]}")
        mapfile -t MISSING < <(missing "${NEEDS[@]}")
        if [ "${MISSING[*]}" != "${SHOWN[*]}" ] && [ ${#MISSING[@]} -gt 0 ]; then
            say "With the refreshed lists, the command is:"; say ""; say "  ${INSTALL[*]} ${MISSING[*]}"; say ""
            ask "Run it now?" || fail "run that command, then ./install.sh again."
        fi
    else
        say "The build needs ${#MISSING[@]} packages from $DISTRO. The command is:"
        say ""; say "  ${INSTALL[*]} ${MISSING[*]}"; say ""
        ask "Run it now?" || fail "run that command, then ./install.sh again. Nothing was changed."
    fi
    [ ${#MISSING[@]} -eq 0 ] || "${INSTALL[@]}" "${MISSING[@]}"
    mapfile -t STILL < <(missing "${NEEDS[@]}")
    [ ${#STILL[@]} -eq 0 ] || fail "still missing after the install: ${STILL[*]}"
    # a QML module installed while KWin runs isn't seen by it until it starts again (Qt's QML engine
    # keeps the folder listings it read); the last step says so
    local p
    for p in "${MISSING[@]}"; do
        case "$p" in *milou*|*plasma*|*kirigami*|*ksvg*|*kcmutils*|*5compat*|*declarative*|qml6-module-*) NEEDS_RELOGIN=1;; esac
    done
}
NEEDS_RELOGIN=0

# ---- Ectoview on in place of Overview, and back: install.sh and uninstall.sh run these, and so does
# ectoview-setup for Ectoview installed from a package (which can't change anyone's settings or keys)

# Overview's switch as the record has it, or (no record: Ectoview never switched it) as it is now
overview_was() {
    if [ -f "$STATE/overview-enabled" ]; then cat "$STATE/overview-enabled"
    else kreadconfig6 --file kwinrc --group Plugins --key overviewEnabled --default __absent__; fi
}
# Overview back as it was, Ectoview off: what turn_off does, and what a failed turn_on undoes
overview_back() {
    local was
    was=$(overview_was)
    kwriteconfig6 --file kwinrc --group Plugins --key ectoviewEnabled --delete
    if [ -f "$STATE/overview-enabled" ]; then
        if [ "$was" = __absent__ ]; then
            kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled --delete
        else
            kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled "$was"
        fi
    fi
    if kwin_running; then
        kwin_effects unloadEffect "$EFFECT_ID" >/dev/null
        [ "$was" = false ] || kwin_effects loadEffect overview >/dev/null
    fi
}
# a turn_on that can't finish leaves Overview as it was, with its keys, and says why
turn_on_failed() {
    say "Putting Overview back as it was."
    shortcut_service_up && give_back_shortcuts
    overview_back
    rm -f "$STATE/overview-enabled"
    fail "$1"
}
turn_on() {
    step "Turning Overview off and Ectoview on"
    if [ ! -f "$STATE/overview-enabled" ]; then
        # Overview's switch as it was (absent means KWin's default), for uninstall.sh
        kreadconfig6 --file kwinrc --group Plugins --key overviewEnabled --default __absent__ > "$STATE/overview-enabled"
        # Overview's settings become Ectoview's, the first time only
        local key v
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
        kwin_effects unloadEffect "$EFFECT_ID" >/dev/null   # so an update loads the new files
        # KPackage keeps its list of effects for 20 s after KWin first reads it (PackageLoader's
        # startup cache, maxCacheAge 20), so just after login a new effect isn't found yet: ask
        # again each second until KWin has it (half a minute at most)
        local _
        for _ in $(seq 30); do
            kwin_effects loadEffect "$EFFECT_ID" >/dev/null
            kwin_effects isEffectLoaded "$EFFECT_ID" | grep -q true && break
            sleep 1
        done
        kwin_effects isEffectLoaded "$EFFECT_ID" | grep -q true \
            || turn_on_failed "KWin didn't load Ectoview, so Overview stays; see journalctl --user -b | grep -i ectoview"
        say "KWin has Ectoview loaded."
    else
        say "KWin isn't running here; Ectoview starts with your next Plasma session."
    fi

    if [ "$SHORTCUTS" = 1 ]; then
        take_shortcuts || turn_on_failed "$TAKE_ERROR"
    fi
}
turn_off() {
    need_shortcut_service
    step "Giving Overview its shortcuts back"
    if shortcut_service_up; then give_back_shortcuts; fi

    step "Turning Ectoview off and Overview back on"
    overview_back
    # the shortcut service forgets Ectoview's actions
    if shortcut_service_up; then
        local from to
        while IFS='|' read -r from to; do
            kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.unregister "kwin" "$to" >/dev/null || true
        done <<< "$PAIRS"
    fi
}
