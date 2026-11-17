# Shared by install.sh and uninstall.sh. Sourced, never run.
# The shortcut moving is Ectolens's proven route (Ectolens tools/install/shortcuts.sh): KDE's
# shortcut service over D-Bus, Overview's keys saved before anything changes.

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/ectoview-install
ENV_SCRIPT=${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/ectoview.sh

# Where the effect goes: KWin looks in kwin-wayland/effects before kwin/effects for an effect and
# its main.qml (ScriptedEffectLoader, KWin 6.7.5). Installs before 2026-11-12 used kwin/effects,
# where a running KWin may hold the old build compiled; the new folder is a path it never compiled.
EFFECTS_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/kwin-wayland/effects
OLD_EFFECTS_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/kwin/effects
kpkg() { kpackagetool6 --type KWin/Effect --packageroot "$EFFECTS_ROOT" "$@"; }

step() { printf '\n== %s\n' "$*"; }
say() { printf '   %s\n' "$*"; }
fail() { printf '\nEctoview: %s\n' "$*" >&2; exit 1; }

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
# keys ACTION: an action of KWin's (component "kwin") in GVariant text, as setForeignShortcutKeys takes it
keys() {
    local out
    out=$(kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', '$1', '', '']") || return 1
    out=${out#(}; out=${out%,)}
    printf '%s\n' "$out"
}
set_keys() { kga --object-path /kglobalaccel --method org.kde.KGlobalAccel.setForeignShortcutKeys "['kwin', '$1', '', '']" "$2" >/dev/null; }
no_keys() { [ "$1" = '@a(ai) []' ] || [ "$1" = '[]' ]; }

# Overview's actions and the Ectoview actions that take their keys
PAIRS="Overview|Ectoview
Grid View|Ectoview Grid View
Cycle Overview|Ectoview Cycle
Cycle Overview Opposite|Ectoview Cycle Opposite"

take_shortcuts() {
    step "Moving Overview's shortcuts to Ectoview"
    if ! shortcut_service_up; then
        say "KDE's shortcut service isn't running (this isn't a Plasma session); run this again in Plasma."
        return 0
    fi
    # Ectoview's actions exist once KWin has loaded it
    for _ in $(seq 50); do component_actions kwin | grep -qx 'Ectoview' && break; sleep 0.2; done
    component_actions kwin | grep -qx 'Ectoview' || fail "KDE's shortcut service hasn't picked up Ectoview's shortcuts; log out and in, then run this again"
    if [ -f "$STATE/overview-shortcuts" ]; then
        say "Already moved by an earlier run; left as they are."
        return 0
    fi
    : > "$STATE/overview-shortcuts.new"
    while IFS='|' read -r from to; do
        printf '%s\t%s\n' "$from" "$(keys "$from")" >> "$STATE/overview-shortcuts.new"
    done <<< "$PAIRS"
    mv "$STATE/overview-shortcuts.new" "$STATE/overview-shortcuts"
    # one key, one owner: Overview lets go first, then Ectoview takes the keys
    while IFS='|' read -r from to; do
        k=$(grep -P "^\Q$from\E\t" "$STATE/overview-shortcuts" | cut -f2)
        no_keys "$k" && continue
        set_keys "$from" '@a(ai) []'
        set_keys "$to" "$k"
    done <<< "$PAIRS"
    bad=0
    while IFS='|' read -r from to; do
        k=$(grep -P "^\Q$from\E\t" "$STATE/overview-shortcuts" | cut -f2)
        no_keys "$k" && continue
        [ "$(keys "$to")" = "$k" ] || bad=1
        no_keys "$(keys "$from")" || bad=1
    done <<< "$PAIRS"
    if [ "$bad" = 1 ]; then
        give_back_shortcuts
        fail "KDE's shortcut service didn't give Ectoview Overview's keys, so Overview keeps them; run this again to retry"
    fi
    say "Moved: $(cut -f1,2 "$STATE/overview-shortcuts" | grep -v "@a(ai) \[\]" | cut -f1 | paste -sd, - | sed 's/,/, /g')."
}

give_back_shortcuts() {
    [ -f "$STATE/overview-shortcuts" ] || return 0
    shortcut_service_up || { say "KDE's shortcut service isn't running; Overview's keys stay saved in $STATE."; return 0; }
    while IFS='|' read -r from to; do set_keys "$to" '@a(ai) []'; done <<< "$PAIRS"
    while IFS='|' read -r from to; do
        k=$(grep -P "^\Q$from\E\t" "$STATE/overview-shortcuts" | cut -f2)
        no_keys "$k" || set_keys "$from" "$k"
    done <<< "$PAIRS"
    rm -f "$STATE/overview-shortcuts"
    say "Overview has its shortcuts back."
}
