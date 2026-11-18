#!/bin/bash
# Inside run.sh's sandbox: a fresh home, Ectoview installed from the package as a stranger would,
# four desktops, two screens (a 1.75-scaled one on the left as the dashboard), real apps.
W=$1; OUT=$2; PKG=$3; HERE=$(cd "$(dirname "$0")" && pwd)
SCENARIO=${SCENARIO:-smoke}
export XDG_RUNTIME_DIR=$W/rt XDG_CONFIG_HOME=$W/xdg/config XDG_DATA_HOME=$W/home/.local/share XDG_CACHE_HOME=$W/xdg/cache XDG_STATE_HOME=$W/xdg/state HOME=$W/home
# (the data folder where a stranger's is, ~/.local/share: install.sh's default prefix puts the
# settings window's icon and desktop entry there, and Plasma looks there)
mkdir -p "$XDG_DATA_HOME"
unset WAYLAND_DISPLAY DISPLAY
# logs stay in the test output, never the real journal (run.sh hides its socket too)
export QT_FORCE_STDERR_LOGGING=1
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
log() { echo "$*" >> "$OUT/steps.log"; }

# ---- Ectoview, installed the way install.sh does it, before KWin starts
# the README's pictures (SCENARIO=readme-NAME, tools/readme-pictures.sh): their own screens, desktops,
# groups and apps (readme-scenes.sh)
README=; case "$SCENARIO" in readme-*) README=1; source "$HERE/readme-scenes.sh";; esac
INSTALLER=; case "$SCENARIO" in install|plant-update|migrate) INSTALLER=1;; esac   # install.sh does it all, against a running KWin
[ -n "$INSTALLER" ] || kpackagetool6 --type KWin/Effect --install "$PKG" >> "$OUT/install.log" 2>&1 || { log "FAIL kpackagetool6 install"; exit 1; }
# other screens: 0 all of Ectoview, 1 only their windows, 2 left as they are
OTHER=0; case "$SCENARIO" in primary|plant-primary|readme-screens) OTHER=2;; windows|plant-windows|crossscreen) OTHER=1;; esac
case "$SCENARIO" in groupshortcut|plant-groupshortcut) DESKTOPS_N=${DESKTOPS_N:-14};; esac
case "$SCENARIO" in gridstack|plant-gridstack) DESKTOPS_N=${DESKTOPS_N:-19};; esac
if [ -n "$README" ]; then
  DESKTOPS=$(readme_desktops)
elif [ "$SCENARIO" = overflow ] || [ -n "${DESKTOPS20:-}" ] || [ -n "${DESKTOPS_N:-}" ]; then
  # more desktops (D1 to D20, or DESKTOPS_N of them)
  N=${DESKTOPS_N:-20}
  DESKTOPS=$(printf '[Desktops]\nNumber=%d\nRows=1\n' $N; for i in $(seq $N); do printf 'Name_%d=D%d\nId_%d=d%d\n' $i $i $i $i; done)
else
  DESKTOPS=$(printf '[Desktops]\nNumber=4\nRows=1\nName_1=Work\nName_2=Code\nName_3=Design\nName_4=Music\nId_1=d1\nId_2=d2\nId_3=d3\nId_4=d4\n')
fi
cat > "$XDG_CONFIG_HOME/kwinrc" <<RC
$DESKTOPS

[Windows]
PerOutputVirtualDesktops=true

RC
[ -n "$INSTALLER" ] || cat >> "$XDG_CONFIG_HOME/kwinrc" <<RC

[Plugins]
overviewEnabled=$([ "$SCENARIO" = readme-overview ] && echo true || echo false)
ectoviewEnabled=$([ "$SCENARIO" = readme-overview ] && echo false || echo true)

[Effect-ectoview]
OtherScreens=$OTHER
$(printf '%b' "${EXTRA_EFFECT_CONFIG:-}")
$([ -n "$README" ] && readme_groups)
$([ "$SCENARIO" = readme-kdelook ] && printf 'Look=1\nAccent=1\n')
$(case "$SCENARIO" in readme-bartop) printf 'BarPosition=0\n';; readme-barbottom) printf 'BarPosition=1\n';; readme-barleft) printf 'BarPosition=2\nShowToolbar=false\n';; readme-barright) printf 'BarPosition=3\nShowToolbar=false\n';; esac)
$([ "$SCENARIO" = crossscreen ] && printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=g1\n')
$(case "$SCENARIO" in arrows|plant-arrows|arrowsback) printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=desktops,d4=g1\n';; esac)
$([ "$SCENARIO" = gridgroups ] && printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=hidden\n')
$(case "$SCENARIO" in transition|plant-transition) printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=g1\n';; esac)
$(case "$SCENARIO" in groupshortcut|plant-groupshortcut) printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=%s\n' "$(for i in $(seq 14); do printf 'd%d=%s,' $i $([ $i -le 7 ] && echo desktops || echo g1); done)";; esac)
$([ "$SCENARIO" = grouparrows ] && printf 'Groups=desktops:Desktops,g1:Weekend Games,g2:Media\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=g2\n')
$(case "$SCENARIO" in beacons|plant-beacons) printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=hidden\n';; esac)
$([ "$SCENARIO" = groupreorder ] && printf 'Groups=desktops:Desktops,g1:Games,g2:Media\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=g2\n')
$([ "$SCENARIO" = windrag ] && printf 'Groups=desktops:Desktops,g1:Games\nDesktopGroups=d1=desktops,d2=desktops,d3=g1,d4=g1\n')
$([ "$SCENARIO" = hide ] && printf 'HiddenDesktops=d2\nSearchAllDesktops=true\nPrimaryScreenOnly=true\n')
$(case "$SCENARIO" in gridstack|plant-gridstack) printf 'Groups=g1:Standard,g2:Personal,g3:Development,g4:Business\nDesktopGroups=%s\n' "$(for i in $(seq 19); do printf 'd%d=%s,' $i $( { [ $i -le 3 ] && echo g1; } || { [ $i -le 6 ] && echo g2; } || { [ $i -le 17 ] && echo g3; } || echo g4); done)";; esac)
RC
# planted faults, each a copy of the package with one boundary broken, to prove the checks catch it
if [ "$SCENARIO" = plant-reorder ]; then
  # letting go of a dragged desktop doesn't move it
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/DesktopBar.qml
  sed -i 's#^\( *\)bar.moveDesktop(me, place);#\1// planted: no move#' "$P"
  grep -q 'planted: no move' "$P" && log "planted: a drop doesn't move the desktop" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-gridstack ]; then
  # Grid View back to one line per group, as wide as the longest (no stacking)
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Main.qml
  sed -i 's#for (let c = 1; c <= longest; c++) {#for (let c = longest; c <= longest; c++) { // planted#' "$P"
  grep -q 'planted' "$P" && log "planted: one line per group" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-beacons ]; then
  # a desktop whose window asks for attention keeps its beacon grey
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/DesktopBar.qml
  sed -i 's#lit: bar.asksAttention(delegate.desktop)#lit: false // planted#' "$P"
  grep -q 'lit: false // planted' "$P" && log "planted: a desktop's beacon never lights" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-groupshortcut ]; then
  # the group shortcuts switch the desktop straight away with Ectoview closed (KWin's slide plays)
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Effect.qml
  sed -i 's#^        if (overviewState.status === Togglable.Status.Inactive \&\& !host.visible \&\& animationDuration > 0) {$#        if (false) { // planted#' "$P"
  grep -q 'if (false) { // planted' "$P" && log "planted: the shortcut switches the desktop itself" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-tokens ]; then
  # the groups pill drawn 6 px shorter than the search field and the gear
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/EctoGroupPill.qml
  sed -i 's#^    height: theme.rowHeight$#    height: theme.rowHeight - 6#' "$P"
  grep -q 'rowHeight - 6' "$P" && log "planted: the pill is 6 px shorter" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-arrows ]; then
  # a window still held on an arrow switches again almost at once (his report, November 12, 2026)
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/EctoStepArrow.qml
  sed -i 's#^\( *\)if (now - arrow.lastStep < arrow.holdMs - 50) {#\1if (false) {#; s#^\( *\)hold.interval = arrow.holdMs;#\1hold.interval = 150;#' "$P"
  grep -q 'hold.interval = 150;' "$P" && grep -q 'if (false) {' "$P" && log "planted: the next switch comes 150 ms after the last" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-transition ]; then
  # a group change jumps straight to the new group
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Main.qml
  sed -i 's#^        const animate = organized .*#        const animate = false;#' "$P"
  grep -q 'const animate = false;' "$P" && log "planted: no group transition" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-wheelbar ]; then
  # the wheel switches desktops anywhere in Ectoview again, as Overview's does
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Main.qml
  sed -i 's#^\( *\)if (desktopBar.opacity <= 0 || !desktopBar.contains(atBar)) {#\1if (false) {#' "$P"
  grep -q '            if (false) {' "$P" && log "planted: the wheel switches desktops anywhere" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-windows ]; then
  # "only their windows" draws all of Ectoview anyway
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Effect.qml
  sed -i 's#return otherScreens === 1 \&\& !!primaryScreen \&\& screen !== primaryScreen;#return false;#' "$P"
  grep -q '        return false;$' "$P" && log "planted: no screen shows only its windows" || log "FAIL plant not placed"
fi
if [ "$SCENARIO" = plant-primary ]; then
  # the untouched screen draws Overview anyway
  P=$XDG_DATA_HOME/kwin/effects/ectoview/contents/ui/impl/Effect.qml
  sed -i 's#source: effect.showsOn(screen) ? "Main.qml" : "Untouched.qml"#source: "Main.qml"#' "$P"
  grep -q 'source: "Main.qml"' "$P" && log "planted: every screen draws Overview" || log "FAIL plant not placed"
fi

if [ "$SCENARIO" = migrate ]; then
  # an install from before the loader, in the old folder, present when KWin starts (as on a desktop
  # that installed Ectoview earlier): KWin compiles it at that path and keeps it
  # the "old build": the package's metadata with a main.qml that is the effect itself and draws solid red
  OLD=$W/old-package; mkdir -p "$OLD/contents/ui" "$OLD/contents/config"; cp "$PKG/metadata.json" "$OLD/"; cp "$PKG/contents/config/main.xml" "$OLD/contents/config/"
  cat > "$OLD/contents/ui/main.qml" <<'QML'
import QtQuick
import org.kde.kwin as KWinComponents
KWinComponents.SceneEffect {
    id: old
    delegate: Rectangle { color: "#ff0000" }
    KWinComponents.ShortcutHandler { name: "Ectoview"; text: "Toggle Ectoview"; sequence: "Meta+W"; onActivated: old.visible = !old.visible }
}
QML
  kpackagetool6 --type KWin/Effect --install "$OLD" >> "$OUT/old-install.log" 2>&1
  printf '\n[Plugins]\noverviewEnabled=false\nectoviewEnabled=true\n' >> "$XDG_CONFIG_HOME/kwinrc"
fi
# the transition scenario: Plasma's animation speed slowed ten times, so pictures land mid-motion
case "$SCENARIO" in transition|plant-transition|groupshortcut|plant-groupshortcut|arrowsback|reorderstill) ;; *) false;; esac && printf '[KDE]\nAnimationDurationFactor=10\n' >> "$XDG_CONFIG_HOME/kdeglobals"
[ -n "$README" ] && readme_prepare
mkdir -p "$XDG_DATA_HOME/applications"
cat > "$XDG_DATA_HOME/applications/ectoview-fake-input.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Ectoview test input
Exec=$FAKE_INPUT
NoDisplay=true
X-KDE-Wayland-Interfaces=org_kde_kwin_fake_input
DESK

QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="js.debug=true;kwin_scripting.debug=true;qml.debug=true;${EXTRA_LOG_RULES:-}" \
  ${KWIN_BIN:-kwin_wayland} --virtual --width "$([ -n "$README" ] && echo 2560 || echo 3440)" --height 1440 --output-count 2 --socket ectoview --no-lockscreen > "$OUT/kwin.log" 2>&1 &
KW=$!
for i in $(seq 100); do [ -S "$W/rt/ectoview" ] && break; sleep 0.1; done
export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 WAYLAND_DISPLAY=ectoview QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=kde QT_QUICK_CONTROLS_STYLE=org.kde.desktop
# services D-Bus starts from now on get the session's display too, as a Plasma session passes it on at
# login (KDE's activity manager 6.8 aborts without one, and Plasma's shell then loads no desktop)
gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.UpdateActivationEnvironment \
  "{'WAYLAND_DISPLAY': '$WAYLAND_DISPLAY', 'QT_QPA_PLATFORM': 'wayland', 'XDG_CURRENT_DESKTOP': 'KDE', 'KDE_FULL_SESSION': 'true', 'KDE_SESSION_VERSION': '6'}" > /dev/null 2>&1 || true
sleep 1
# the main screen right and primary; the dashboard screen left, scaled 1.75, bottoms lined up
LS=${LEFT_SCALE:-1.75}; echo "$LS" > "$OUT/left-scale.txt"
if [ -n "$README" ]; then
  # a 16:9 main screen at 1.5 (1707x960), the dashboard at 1.75 (1463x823), bottoms lined up
  LW=$(python3 -c "print(round(2560/$LS))"); LH=$(python3 -c "print(round(1440/$LS))")
  kscreen-doctor output.Virtual-1.scale.1.5 output.Virtual-0.scale.$LS output.Virtual-0.position.0,$((960 - LH)) output.Virtual-1.position.$LW,0 output.Virtual-1.priority.1 output.Virtual-0.priority.2 >> "$OUT/layout.log" 2>&1
else
# MAIN_SCALE: the main screen at a scale of its own (1 when unset), bottoms still lined up
MS=${MAIN_SCALE:-1}; MH=$(python3 -c "print(round(1440/$MS))")
LW=$(python3 -c "print(round(3440/$LS))"); LH=$(python3 -c "print(round(1440/$LS))")
kscreen-doctor $([ "$MS" != 1 ] && echo output.Virtual-1.scale.$MS) output.Virtual-0.scale.$LS output.Virtual-0.position.0,$((MH - LH)) output.Virtual-1.position.$LW,0 output.Virtual-1.priority.1 output.Virtual-0.priority.2 >> "$OUT/layout.log" 2>&1
fi
kscreen-doctor -o >> "$OUT/layout.log" 2>&1
shot() { spectacle --background --nonotify --fullscreen --output "$1" >> "$OUT/shots.log" 2>&1; }
script() { # a KWin script given as text; its print() lands in kwin.log as "js: ..."
  local f="$W/s$RANDOM.js"; printf '%s\n' "$1" > "$f"
  local id; id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "s$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null; sleep 0.5
}
kglob() { qdbus org.kde.kglobalaccel /component/kwin invokeShortcut "$1" >> "$OUT/shortcuts.log" 2>&1; }
# until KWin says Ectoview has finished closing and the desktop switch's slide is over (a shortcut
# pressed while either runs doesn't open Ectoview; a slower machine, such as tests/e2e/container.sh's,
# finishes later)
wait_closed() { local i; for i in $(seq 50); do qdbus org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | grep -qxE 'ectoview|slide' || return 0; sleep 0.1; done; }

# KDE's activity manager first, as a Plasma session starts it (systemd's plasma-kactivitymanagerd)
# before the shell: the shell loads no desktop without it
for kamd in /usr/libexec/kactivitymanagerd /usr/lib/*/libexec/kactivitymanagerd /usr/lib/kactivitymanagerd; do
  [ -x "$kamd" ] || continue
  gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.kde.ActivityManager 2>/dev/null | grep -q true \
    || { "$kamd" > "$OUT/kactivitymanagerd.log" 2>&1 & }
  for i in $(seq 50); do gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.kde.ActivityManager 2>/dev/null | grep -q true && break; sleep 0.1; done
  break
done
plasmashell --no-respawn > "$OUT/plasmashell.log" 2>&1 &
sleep 6
mkdir -p "$HOME/Documents/Notes" "$HOME/Music" "$HOME/Pictures" "$HOME/Projects" "$HOME/Downloads"
printf '%s\n' '# Release notes' '' 'Overview keeps the dashboard screen as it is.' 'Desktops can be dragged into a new order.' > "$HOME/Documents/Notes/release-notes.md"
if [ -n "$README" ]; then readme_apps; else
konsole --hide-menubar --hide-tabbar -e bash -c "printf 'ectoview test\n'; exec cat" > /dev/null 2>&1 &
sleep 1.5
dolphin "$HOME" > /dev/null 2>&1 &
sleep 1.5
kate "$HOME/Documents/Notes/release-notes.md" > /dev/null 2>&1 &
sleep 1.5
# the dashboard: a still window (System Monitor's graphs move, which a pixel check can't tell from a fault)
dolphin --new-window "$HOME/Documents" > /dev/null 2>&1 &
sleep 4
script '
const outs = workspace.screens;
const left = outs.reduce((a, o) => o.geometry.x < a.geometry.x ? o : a); const main = outs.find(o => o !== left) || left;
const g = main.geometry, l = left.geometry; let dol = 0;
print("screens " + outs.map(o => o.name + " " + JSON.stringify(o.geometry)).join(" | ") + " order " + workspace.screenOrder.map(o => o.name).join(","));
for (const w of workspace.stackingOrder) {
  if (!w.normalWindow) continue;
  const c = w.resourceClass;
  if (c.indexOf("dolphin") >= 0 && w.caption.indexOf("Documents") >= 0) { w.onAllDesktops = true; workspace.sendClientToScreen(w, left); w.frameGeometry = {x: l.x, y: l.y, width: l.width, height: l.height - 44}; }
  else if (c.indexOf("konsole") >= 0) { w.desktops = [workspace.desktops[0]]; w.frameGeometry = {x: g.x + 80, y: g.y + 160, width: 1050, height: 700}; }
  else if (c.indexOf("dolphin") >= 0) { w.desktops = [workspace.desktops[0]]; w.frameGeometry = {x: g.x + 1195, y: g.y + 160, width: 1050, height: 700}; }
  else if (c.indexOf("kate") >= 0) { w.desktops = [workspace.desktops[0]]; w.frameGeometry = {x: g.x + 2310, y: g.y + 160, width: 1050, height: 700}; }
  print("window " + c + " " + w.caption + " " + JSON.stringify(w.frameGeometry) + " " + w.output.name);
}'
sleep 1.5
fi

coproc FI { exec "$FAKE_INPUT" 2>>"$OUT/fake-input.log"; }
feed() { echo "$1" >&"${FI[1]}"; read -t 10 -r _ <&"${FI[0]}"; }
# the groups' pill ends 188 px left of the main screen's center (8 px left of the search field);
# with two groups or more its last 61 px are ^ and v (design proposal 8), so the list opens from a
# click 91 px in (on the name half)
# a real wheel through KWin's EIS input (eis-wheel.py), started on first use: "move X Y", "wheel N"
wheel() {
  if [ -z "${EWI:-}" ]; then
    mkfifo "$W/ew.in" "$W/ew.out"
    python3 -I "$HERE/eis-wheel.py" < "$W/ew.in" > "$W/ew.out" 2>>"$OUT/eis-wheel.log" &
    exec {EWI}>"$W/ew.in"; exec {EWO}<"$W/ew.out"
    read -t 10 -r _ <&$EWO
  fi
  echo "$1" >&$EWI; read -t 10 -r _ <&$EWO
}
feed "move 3500 1300"   # the pointer on the main screen
sleep 0.5
effects_loaded() { qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects | tr '\n' ' '; }
log "loaded effects: $(effects_loaded)"
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames > "$OUT/shortcut-names.txt"

case "$SCENARIO" in
smoke)
  shot "$OUT/desktop.png"
  kglob "Ectoview"; sleep 2; shot "$OUT/overview.png"
  kglob "Ectoview"; sleep 1.5; shot "$OUT/closed.png"
  kglob "Ectoview Grid View"; sleep 2; shot "$OUT/grid.png"
  kglob "Ectoview Grid View"; sleep 1.5
  kglob "Ectoview"; sleep 2
  for k in 37 30 20; do feed "key $k"; sleep 0.15; done   # "kat"
  sleep 2; shot "$OUT/search.png"
  for k in 14 14 14; do feed "key $k"; sleep 0.1; done
  for k in 31 18 20 20 23 49 34 31; do feed "key $k"; sleep 0.15; done   # "settings"
  sleep 3; shot "$OUT/search-apps.png"
  feed "key 1"; sleep 0.8; feed "key 1"; sleep 1.5   # Esc: clear, then close
  shot "$OUT/after-esc.png"
  ;;
primary|plant-primary|every)
  # focus stays on the main screen (Kate), so the dashboard window is already inactive: opening
  # Ectoview takes the keyboard, and an active window would redraw itself as inactive
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("kate") >= 0) workspace.activeWindow = w;'
  sleep 1
  shot "$OUT/desktop.png"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/overview.png"
  # a click on the left (dashboard) screen: when it's left alone, the click does nothing and Ectoview stays open
  feed "move 900 1100"; sleep 0.3; feed "click"; sleep 1.5; shot "$OUT/after-click.png"
  ;;
windows|plant-windows)
  # the dashboard screen set to "only their windows": Ectoview lays them out there, with no bar or
  # toolbar; then the same screen with "all of Ectoview", for the bar's band to compare against
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("kate") >= 0) workspace.activeWindow = w;'
  sleep 1
  shot "$OUT/desktop.png"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/overview.png"; kglob "Ectoview"; sleep 1.5
  kwriteconfig6 --file kwinrc --group Effect-ectoview --key OtherScreens 0
  qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect ectoview; sleep 1
  kglob "Ectoview"; sleep 2.5; shot "$OUT/every.png"; kglob "Ectoview"; sleep 1.5
  ;;
windrag)
  # Desktops (Work, Code) and Games (Design, Music); Konsole, Dolphin and Kate on Work
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  rc() { kreadconfig6 --file kwinrc --group Effect-ectoview --key "$1"; }
  where() { script "for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf(\"$1\") >= 0 && w.output.name === \"Virtual-1\") print(\"where $1 \" + w.desktops.map(d => d.name).join(\",\"));"; grep "js: where $1" "$OUT/kwin.log" | tail -1 | sed "s/.*js: where $1 //"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  left() { python3 -c "w=90*$MW/1440; print(round($MX+($MW-(($1+1)*w+$1*8))/2+$2*(w+8)))"; }
  TW=$(python3 -c "print(round(90*$MW/1440))")
  PR=$(python3 -c "print(round($MX + $MW/2 - 188))"); CX=$(python3 -c "print(round($MX + $MW/2))")
  grouprow() { python3 -c "print(176 + 4 + 30 + 44*$1 + 22)"; }
  typeit() { for k in "$@"; do feed "key $k"; sleep 0.12; done; sleep 1.5; }
  clear() { for i in 1 2 3; do feed "key 14"; sleep 0.08; done; sleep 0.5; }
  # press the one window the search left, centered in the view, and carry it to the pill
  grab() { feed "move $CX 780"; sleep 0.4; feed "down"; sleep 0.2
    for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($CX+($PR-91-$CX)*$f), round(780+(150-780)*$f))")"; sleep 0.08; done; sleep 0.6; }
  # back on Work with Ectoview open (a drop into another group takes you there)
  # (KWin's desktop slide must end first: Ectoview won't start while another full-screen effect runs)
  home() { kglob "Ectoview"; sleep 1.5; script 'workspace.currentDesktop = workspace.desktops[0];'; sleep 1.5; kglob "Ectoview"; sleep 2.5; }
  kglob "Ectoview"; sleep 2.5
  # 1. Kate onto Games' row: it goes to Games' first desktop, and you go with it
  typeit 37 30 20; grab
  feed "move $((PR + 60)) $(grouprow 1)"; sleep 0.3; shot "$OUT/over-row.png"; feed "up"; sleep 1.2
  log "kate: $(where kate) $(order)"
  clear; home
  # 2. Dolphin held on Games' row: the bar shows Games (and Work, where you are), then onto Music (place
  # 2 of 3): it lands there and so do you
  typeit 32 24 38; grab
  feed "move $((PR + 60)) $(grouprow 1)"; sleep 1.4; shot "$OUT/peek.png"
  X=$(( $(left 3 2) + TW/2 ))
  for f in 0.25 0.5 0.75 1; do feed "move $(python3 -c "print(round($PR+60+($X-$PR-60)*$f), round($(grouprow 1)+(53-$(grouprow 1))*$f))")"; sleep 0.08; done
  sleep 0.4; shot "$OUT/over-music.png"; feed "up"; sleep 1.2
  log "dolphin: $(where dolphin) $(order)"
  clear; home
  # 3. Konsole held on Games' row until the bar shows Games, then brought back and let go on the view:
  # it stays on Work, you stay, and the bar shows your own group again
  typeit 37 24 49; grab
  feed "move $((PR + 60)) $(grouprow 1)"; sleep 1.4; shot "$OUT/peek-back.png"
  for f in 0.25 0.5 0.75 1; do feed "move $(python3 -c "print(round($PR+60+($CX-$PR-60)*$f), round($(grouprow 1)+(780-$(grouprow 1))*$f))")"; sleep 0.08; done
  sleep 0.4; feed "up"; sleep 1.5
  log "konsole back: $(where konsole) $(order)"
  shot "$OUT/after-peek.png"
  # 4. Konsole onto New desktop group (two groups, a line, then New desktop group): a new group and
  # desktop of its own, and you go with it
  grab
  feed "move $((PR + 60)) $(python3 -c "print(176 + 4 + 30 + 44*2 + 9 + 17)")"; sleep 0.3; feed "up"; sleep 1.2
  log "konsole: $(where konsole) groups=$(rc Groups) $(order)"
  clear
  shot "$OUT/end.png"
  ;;
transition|plant-transition)
  # Desktops (Work, Code) to Games (Design, Music) from the pill, at a tenth of the speed
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  PR=$(python3 -c "print(round($MX + $MW/2 - 188))")
  kglob "Ectoview"; sleep 6; shot "$OUT/before.png"
  feed "move $((PR - 91)) 150"; sleep 0.4; feed "click"; sleep 4
  feed "move $((PR + 60)) $(python3 -c "print(176 + 4 + 30 + 44 + 22)")"; sleep 0.4; feed "click"
  sleep 0.6; shot "$OUT/t1.png"; sleep 0.6; shot "$OUT/t2.png"; sleep 0.8; shot "$OUT/t3.png"
  sleep 6; shot "$OUT/after.png"
  ;;
groupshortcut|plant-groupshortcut)
  # 14 desktops, D1 to D7 in Desktops and D8 to D14 in Games; Konsole, Dolphin and Kate on D1. With
  # Ectoview closed, "Next Desktop Group" at a tenth of the speed: the group transition (D8 rising and
  # fading in over D1 where it stands), not KWin's slide sideways past D2 to D7 (the owner's ask,
  # November 17, 2026)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  shot "$OUT/before.png"
  log "pressed: $(date +%s%3N)"; kglob "Ectoview Next Desktop Group"
  sleep 0.6; shot "$OUT/t1.png"; log "t1: $(date +%s%3N)"; sleep 0.6; shot "$OUT/t2.png"; log "t2: $(date +%s%3N)"; sleep 0.8; shot "$OUT/t3.png"; log "t3: $(date +%s%3N)"
  sleep 8; shot "$OUT/after.png"
  log "after: $(order)"
  log "visible after: $(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | tr '\n' ' ')"
  ;;
kcmview|shortcuts)
  # the settings page, installed as a stranger would, opened tall enough to show its shortcuts editor.
  # shortcuts: its Shortcuts tab, a shortcut's key editor, Custom, Meta+K recorded, Apply (positions
  # for the window this places at 1000 px wide); kcmview: clicks given in KCMVIEW_* for looking around
  if [ "$SCENARIO" = shortcuts ]; then KCMVIEW_CLICKS="320,90 630,477 377,542"; KCMVIEW_COMBO=37; KCMVIEW_THEN="1062,1307"; fi
  REPO=$(dirname "$PKG")
  ECTOVIEW_NO_SESSION_ENV=1 "$REPO/install.sh" > "$OUT/install-run.log" 2>&1; log "install exit $?"
  ( . "$XDG_CONFIG_HOME/plasma-workspace/env/ectoview.sh"; kcmshell6 kwin/effects/configs/kwin_ectoview_config > "$OUT/kcmshell.log" 2>&1 & )
  sleep 5
  script 'for (const w of workspace.stackingOrder) if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) { const g = w.output.geometry; w.frameGeometry = {x: g.x + 200, y: g.y + 10, width: 1000, height: g.height - 120}; workspace.activeWindow = w; print("settings window " + JSON.stringify(w.frameGeometry)); print("settings named " + JSON.stringify({caption: w.caption, desktopFile: w.desktopFileName})); }'
  sleep 1.5
  log "$(grep 'js: settings window' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  log "$(grep 'js: settings named' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  # its icon and its desktop entry, where the install put them (the sandbox's own home)
  log "settings icon: $(ls "$HOME"/.local/share/icons/hicolor/*/apps/ectoview.svg 2>/dev/null | wc -l) sizes; entry: $(grep -h '^Icon=' "$HOME"/.local/share/applications/kwin_ectoview_config.desktop 2>/dev/null)"
  shot "$OUT/settings-top.png"
  # click a shortcut's Global cell (KCMVIEW_CLICKS: "x,y x,y ..." in the main screen's logical pixels)
  MXL=$(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+)',t);print(round(float(m.group(1))))")
  n=0; for xy in ${KCMVIEW_CLICKS:-}; do n=$((n+1)); X=${xy%,*}; Y=${xy#*,}; feed "move $((MXL + X)) $Y"; sleep 0.4; feed "click"; sleep 1.2; shot "$OUT/click$n.png"; done
  for k in ${KCMVIEW_KEYS:-}; do feed "key $k"; sleep 0.3; done; sleep 1; shot "$OUT/keys.png"
  # KCMVIEW_COMBO: a key pressed with Meta held (to record), KCMVIEW_THEN: clicks after it (Apply)
  if [ -n "${KCMVIEW_COMBO:-}" ]; then feed "press 125"; sleep 0.1; feed "key $KCMVIEW_COMBO"; sleep 0.1; feed "release 125"; sleep 1; shot "$OUT/recorded.png"; fi
  for xy in ${KCMVIEW_THEN:-}; do X=${xy%,*}; Y=${xy#*,}; feed "move $((MXL + X)) $Y"; sleep 0.4; feed "click"; sleep 1.5; done
  shot "$OUT/after.png"
  log "keys: $(gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', 'Ectoview Next Desktop in Desktop Group', '', '']" 2>&1)"
  ;;
gridstack|plant-gridstack)
  # design proposal 10: groups of 3, 3, 11 and 2 desktops (D1 to D19) on the 3440-wide main screen,
  # you on D11 (Development's fifth, no windows). Grid View stacks Development's eleven onto lines of
  # the column count that draws the desktops biggest, lined up, the grid centered. Down goes to the
  # desktop below on Development's next line; a click on its second line's first desktop goes there.
  order() { script 'print("order current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  cell() { python3 -I - "$OUT/kwin.log" "$MX" "$MW" "$1" "$2" <<'PY'
import sys, re, json
log, mx, mw, g, i = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
l = json.loads(re.findall(r'Ectoview: grid layout Virtual-1 (\{.*\})', open(log, errors='replace').read())[-1])
print(round(mx + l['x0'] + l['head'] + (i % l['cols']) * l['cellW'] + l['s'] * mw / 2), round(l['tops'][g] + (i // l['cols']) * l['cellH'] + l['s'] * 1440 / 2))
PY
}
  script 'workspace.currentDesktop = workspace.desktops[10];'; sleep 1; wait_closed
  kglob "Ectoview Grid View"; sleep 2.5; shot "$OUT/grid.png"
  log "places: mx=$MX mw=$MW"
  feed "key 108"; sleep 1; log "down: $(order)"
  read X Y < <(cell 2 "$(python3 -I -c "import re,json;print(json.loads(re.findall(r'Ectoview: grid layout Virtual-1 (\{.*\})',open('$OUT/kwin.log',errors='replace').read())[-1])['cols'])")")
  feed "move $X $Y"; sleep 0.4; feed "click"; sleep 1.5; log "clicked: $(order)"
  ;;
gridgroups)
  # Desktops (Work, Code), Games (Design), Hidden (Music); Grid View lays them out a row per group (few
  # desktops: one line each, the grid centered)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  rc() { kreadconfig6 --file kwinrc --group Effect-ectoview --key "$1"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  # a cell's middle: 300 px of headings, then columns; rows share the height above a 64 px foot
  # the middle of desktop I of group G (in Grid View's order of groups), from the layout Ectoview logs
  # for the main screen when it changes ("Ectoview: grid layout Virtual-1 {...}"), the latest one
  cell() { python3 -I - "$OUT/kwin.log" "$MX" "$MW" "$1" "$2" <<'PY'
import sys, re, json
log, mx, mw, g, i = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
l = json.loads(re.findall(r'Ectoview: grid layout Virtual-1 (\{.*\})', open(log, errors='replace').read())[-1])
x = mx + l['x0'] + l['head'] + (i % l['cols']) * l['cellW'] + l['s'] * mw / 2
y = l['tops'][g] + (i // l['cols']) * l['cellH'] + l['s'] * 1440 / 2
print(round(x), round(y))
PY
}
  kglob "Ectoview Grid View"; sleep 2.5; shot "$OUT/grid.png"
  # Design, in the second row (2 rows, 2 columns): a click goes there
  read X Y < <(cell 1 0); feed "move $X $Y"; sleep 0.4; feed "click"; sleep 1.5
  log "clicked design: $(order)"
  # "1 hidden" brings the Hidden row in (3 rows); a click on Music goes there
  kglob "Ectoview Grid View"; sleep 2.5
  feed "move $(python3 -c "print(round($MX + 40 + 50))") $((1440 - 32))"; sleep 0.4; feed "click"; sleep 1.5; shot "$OUT/grid-hidden.png"
  read X Y < <(cell 2 0); feed "move $X $Y"; sleep 0.4; feed "click"; sleep 1.5
  log "clicked music: $(order) groups=$(rc DesktopGroups)"
  # back on Work; drag Code (row 0, column 1) into Games' row (onto Design): Code joins Games, after Design
  script 'workspace.currentDesktop = workspace.desktops[0];'; sleep 0.6; wait_closed
  log "before grid: active=$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | tr '\n' ' ') $(order)"
  kglob "Ectoview Grid View"; sleep 2.5
  log "after grid: active=$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | tr '\n' ' ')"
  read X1 Y1 < <(cell 0 1); read X2 Y2 < <(cell 1 0)
  feed "move $X1 $Y1"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($X1+($X2-$X1)*$f), round($Y1+($Y2-$Y1)*$f))")"; sleep 0.1; done
  sleep 0.5; shot "$OUT/grid-drag.png"; feed "up"; sleep 1.5
  log "dragged code: $(order) groups=$(rc DesktopGroups)"
  shot "$OUT/grid-after.png"
  # arrow keys: from Work, the first Down selects a window on it (as Overview does); the next, with
  # nothing below that window, goes to the Games row
  feed "key 108"; sleep 0.6; feed "key 108"; sleep 1; log "down: $(order)"
  ;;
arrows|plant-arrows)
  # Desktops (Work, Code, Design) and Games (Music); the windows on Work. The desktop view spans about
  # 256 to 3190 px of the main screen and 194 to 1422 down; its arrows sit 64 px off its sides, halfway down.
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  where() { script "for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf(\"$1\") >= 0 && w.output.name === \"Virtual-1\") print(\"where $1 \" + w.desktops.map(d => d.name).join(\",\"));"; grep "js: where $1" "$OUT/kwin.log" | tail -1 | sed "s/.*js: where $1 //"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))"); RX=$(python3 -c "print(round($MX + 3190 + 64))"); LX=$(python3 -c "print(round($MX + 256 - 64))"); AY=808
  typeit() { for k in "$@"; do feed "key $k"; sleep 0.12; done; sleep 1.5; }
  clear() { for i in 1 2 3; do feed "key 14"; sleep 0.08; done; sleep 0.5; }
  # a window picked up mid-view and carried to x, y
  # (or from x = $3: with Kate gone, Work's two windows leave the middle empty)
  carry() { local SX=${3:-$CX}; feed "move $SX 780"; sleep 0.4; feed "down"; sleep 0.2
    for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($SX+($1-$SX)*$f), round(780+($2-780)*$f))")"; sleep 0.08; done; }
  back() { for f in 0.25 0.5 0.75 1; do feed "move $(python3 -c "print(round($1+($CX-$1)*$f), round($AY+(780-$AY)*$f))")"; sleep 0.08; done; }
  click() { feed "move $1 $2"; sleep 0.3; feed "down"; sleep 0.05; feed "up"; sleep 1; }
  script 'workspace.currentDesktopChanged.connect(() => print("switched " + workspace.currentDesktop.name + " " + Date.now()));'
  kglob "Ectoview"; sleep 2.5
  shot "$OUT/rest.png"
  # 0. the pointer on the right arrow: it lights and names where it leads
  feed "move $RX $AY"; sleep 0.6; shot "$OUT/pointed.png"
  # 1. the arrows clicked: > to Code, < back to Work
  click $RX $AY; log "clicked next: $(order)"
  click $LX $AY; log "clicked previous: $(order)"
  # 2. Kate dropped on the right arrow at once: it goes to Code; you stay on Work
  typeit 37 30 20; carry $RX $AY; sleep 0.2; feed "up"; sleep 1.2
  log "kate: $(where kate) $(order)"
  clear
  # 3. on Work, the first desktop, there's no < : Dolphin (no search needed) held where it
  # would be switches nothing
  carry $LX $AY $(python3 -c "print(round($MX + 2412))"); sleep 1.5; log "held previous on first: $(order)"
  # 4. then held on > for 3 s: Code after the pause, Design after another as long, then nothing (Design
  # is the group's last); dropped back on the view, it lands on Design
  for f in 0.2 0.4 0.6 0.8 1; do feed "move $(python3 -c "print(round($LX+($RX-$LX)*$f))") $AY"; sleep 0.08; done
  log "arrived: $(date +%s%3N)"; sleep 1.5; shot "$OUT/held.png"; sleep 1.5
  back $RX; sleep 0.3; feed "up"; sleep 1.2
  log "switches: $(grep -o 'js: switched .*' "$OUT/kwin.log" | sed 's/js: switched //' | tr '\n' ';')"
  log "dolphin: $(where dolphin) $(order)"
  shot "$OUT/after.png"
  ;;
arrowsback)
  # with Plasma's animations ten times slower: Dolphin carried from Work to Code on >, then back on <;
  # Work must slide in as any desktop does (it stood still, already in place, November 12, 2026). A
  # picture a moment into the slide back and one once it's settled, the window still held
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))"); RX=$(python3 -c "print(round($MX + 3190 + 64))"); LX=$(python3 -c "print(round($MX + 256 - 64))"); AY=808
  script 'workspace.currentDesktopChanged.connect(() => print("switched " + workspace.currentDesktop.name + " " + Date.now()));'
  kglob "Ectoview"; sleep 5
  shot "$OUT/start.png"
  feed "move $CX 780"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($CX+($RX-$CX)*$f), round(780+($AY-780)*$f))")"; sleep 0.08; done
  # one switch (1 s), then off the arrow onto the view while Code slides in, then over to <
  sleep 1.3; feed "move $CX $AY"; sleep 4
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($CX+($LX-$CX)*$f))") $AY"; sleep 0.08; done
  # the switch back comes 1 s after arriving; a picture 0.6 s into its 3 s slide, and one settled
  sleep 1.6; shot "$OUT/mid.png"; sleep 4.5; shot "$OUT/settled.png"
  feed "move $CX 780"; sleep 0.5; feed "up"; sleep 4
  log "switches: $(grep -o 'js: switched .*' "$OUT/kwin.log" | sed 's/js: switched //' | tr '\n' ';')"
  ;;
grouparrows)
  # Desktops (Work, Code), Games (Design), Media (Music); you on Work. ^ and v are the groups' pill's
  # right end (design proposal 8): the pill ends 8 px left of the search field (360 wide, centered on
  # the main screen), v's chevron 20 px in from that end and ^'s 22 px further. They stay put whatever
  # the group's name, checked in three groups; at either end of the list one dims and does nothing.
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  where() { script "for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf(\"$1\") >= 0 && w.output.name === \"Virtual-1\") print(\"where $1 \" + w.desktops.map(d => d.name).join(\",\"));"; grep "js: where $1" "$OUT/kwin.log" | tail -1 | sed "s/.*js: where $1 //"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))")
  ROW=153
  down() { echo $(( CX - 180 - 8 - 20 )); }
  up() { echo $(( CX - 180 - 8 - 20 - 22 )); }
  click() { feed "move $1 $ROW"; sleep 0.3; feed "down"; sleep 0.05; feed "up"; sleep 1.5; }
  script 'workspace.currentDesktopChanged.connect(() => print("switched " + workspace.currentDesktop.name + " " + Date.now()));'
  kglob "Ectoview"; sleep 2.5
  shot "$OUT/rest.png"
  # the dimmed ^ in the first group: a click does nothing
  click $(up); log "dimmed: $(order)"
  # (the next group's name, under the pill, ending at its right end)
  feed "move $(down) $ROW"; sleep 0.6; shot "$OUT/pointed.png"
  # v to Games, v to Media (a picture: no v there, the last group); ^ back to Games and to Desktops
  # (its last desktop, Work)
  click $(down); log "down: $(order)"
  feed "move $CX 780"; sleep 0.6; shot "$OUT/middle.png"
  click $(down); log "down again: $(order)"
  feed "move $CX 780"; sleep 0.6; shot "$OUT/last.png"
  log "places: up3=$(( $(up) - MX )) down3=$(( $(down) - MX )) up2=$(( $(up) - MX )) down2=$(( $(down) - MX )) row=$ROW"
  click $(up); log "up: $(order)"
  click $(up); log "up again: $(order)"
  # 3. Dolphin (mid-view) held on v: after the pause the view goes to Games, carrying it; let go on
  # the view, it lands on Design
  V=$(down)
  feed "move $CX 780"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($CX+($V-$CX)*$f), round(780+($ROW-780)*$f))")"; sleep 0.08; done
  # (off it again soon after the first step: v stays where it is, so a window left on it steps once
  # more after another pause, as it should)
  log "arrived: $(date +%s%3N)"; sleep 1.3
  for f in 0.25 0.5 0.75 1; do feed "move $(python3 -c "print(round($V+($CX-$V)*$f), round($ROW+(780-$ROW)*$f))")"; sleep 0.08; done
  shot "$OUT/held.png"
  sleep 0.4; feed "up"; sleep 1.5
  log "dolphin: $(where dolphin) $(order)"
  log "switches: $(grep -o 'js: switched .*' "$OUT/kwin.log" | sed 's/js: switched //' | tr '\n' ';')"
  shot "$OUT/after.png"
  ;;
beacons|plant-beacons)
  # Desktops (Work, Code), Games (Design), Hidden (Music); you on Work. Kate sent to Code and Konsole
  # to Design, each asking for attention (KWin's demandsAttention, as a terminal's bell or a chat's
  # ping sets it): beacons on Code's thumbnail, on the groups' pill (Games isn't shown) and on Games's
  # row in its list; none on Work. Then Konsole stops asking: the pill's beacon goes, Code's stays.
  # Then Kate stops too: none at all.
  attention() { script "for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf(\"$1\") >= 0) { w.desktops = [workspace.desktops[$2]]; w.demandsAttention = $3; print(\"attention $1 \" + w.demandsAttention); }"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))"); PR=$(( CX - 188 ))
  attention kate 1 true; attention konsole 2 true
  log "asking: $(grep -o 'js: attention .*' "$OUT/kwin.log" | sed 's/js: attention //' | tr '\n' ';')"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/asking.png"
  feed "move $((PR - 101)) 153"; sleep 0.3; feed "click"; sleep 1; shot "$OUT/list.png"
  feed "move $((PR - 101)) 153"; sleep 0.3; feed "click"; sleep 0.8
  attention konsole 2 false; sleep 0.8; shot "$OUT/one.png"
  attention kate 1 false; sleep 0.8; shot "$OUT/none.png"
  kglob "Ectoview"; sleep 1.5
  # a window on a Hidden desktop (Music) asks: nothing lights, not the groups' pill nor the Hidden
  # row in its list (the owner's ruling, November 17, 2026: Hidden desktops stay quiet)
  attention kate 3 true
  kglob "Ectoview"; sleep 2.5; shot "$OUT/hidden.png"
  feed "move $((PR - 101)) 153"; sleep 0.3; feed "click"; sleep 1; shot "$OUT/hidden-list.png"
  feed "key 1"; sleep 0.5
  attention kate 3 false
  log "places: mx=$MX mw=$MW cx=$CX pr=$PR"
  kglob "Ectoview"; sleep 1.5
  ;;
terminalbeacon)
  # A helper run inside a terminal asks for attention for its window, the way an agent's
  # notification hook does when it waits on you: HOOK names it (run with a hook's JSON on its
  # input); without one the scenario is skipped. A second Konsole (its own process) is sent to Code
  # and left inactive; the helper runs in it after a pause; Ectoview shows a beacon on Code
  if [ -z "${HOOK:-}" ]; then log "skipped: no HOOK given"; else
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  konsole --separate --hide-menubar --hide-tabbar -p tabtitle=beacon-test -e bash -c "sleep 6; printf '%s' '{\"hook_event_name\":\"Stop\"}' | python3 -I '$HOOK'; exec cat" > /dev/null 2>&1 &
  sleep 2.5
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("konsole") >= 0 && w.caption.indexOf("beacon-test") >= 0) { w.desktops = [workspace.desktops[1]]; print("helper window " + w.caption + " on " + w.desktops.map(d => d.name)); }
for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("kate") >= 0) workspace.activeWindow = w;'
  sleep 6
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("konsole") >= 0) print("asks " + w.caption + " " + w.demandsAttention);'
  log "helper: $(grep -o 'js: helper window .*' "$OUT/kwin.log" | tail -1 | sed 's/js: //')"
  log "asks: $(grep -o 'js: asks .*' "$OUT/kwin.log" | sed 's/js: asks //' | tr '\n' ';')"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/asking.png"
  log "places: mx=$MX mw=$MW"
  kglob "Ectoview"; sleep 1.5
  fi
  ;;
groupreorder)
  # Desktops, Games and Media in the pill's list; Media dragged by its row to the top, then one place
  # back down; the order read back from kwinrc
  rc() { kreadconfig6 --file kwinrc --group Effect-ectoview --key "$1"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  PR=$(python3 -c "print(round($MX + $MW/2 - 188))")
  grouprow() { python3 -c "print(176 + 4 + 30 + 44*$1 + 22)"; }
  # a row pressed (beside its desktops, on its name) and carried to another row's place
  carryrow() { feed "move $((PR + 130)) $(grouprow $1)"; sleep 0.4; feed "down"; sleep 0.2
    for f in 0.1 0.2 0.35 0.5 0.65 0.8 0.9 1; do feed "move $((PR + 130)) $(python3 -c "print(round($(grouprow $1)+($(grouprow $2)-$(grouprow $1))*$f))")"; sleep 0.06; done
    sleep 0.3; shot "$OUT/carry-$1-$2.png"; feed "up"; sleep 1; }
  kglob "Ectoview"; sleep 2.5
  feed "move $((PR - 101)) 153"; sleep 0.3; feed "click"; sleep 1; shot "$OUT/open.png"
  log "before: $(rc Groups)"
  carryrow 2 0
  log "media up: $(rc Groups)"
  shot "$OUT/after-1.png"
  carryrow 0 1
  log "media down: $(rc Groups)"
  ;;
reorderstill)
  # with Plasma's animations ten times slower: Music dragged in the bar from the end to the front while
  # you're on Work. Only the bar moves; the big view stays put (a moved desktop swept across it,
  # November 13, 2026). Pictures a moment after the drop and once settled
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  at() { python3 -c "w=90*$MW/1440; s=w+8; x0=$MX+($MW-(5*w+4*8))/2; print(round(x0+$1*s+w/2), 52)"; }
  kglob "Ectoview"; sleep 5
  read X3 Y3 < <(at 3); read X0 Y0 < <(at 0)
  feed "move $X3 $Y3"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($X3+($X0-$X3-20)*$f), $Y3)")"; sleep 0.12; done
  sleep 1.5; shot "$OUT/before-drop.png"
  feed "up"; sleep 1.2; shot "$OUT/mid.png"; sleep 6; shot "$OUT/settled.png"
  log "after drag: $(order)"
  ;;
wheelclose)
  # a wheel turn just after Ectoview starts closing must not switch desktops (over the bar, where
  # the wheel switches desktops while Ectoview is open)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  at() { python3 -c "w=90*$MW/1440; s=w+8; x0=$MX+($MW-(5*w+4*8))/2; print(round(x0+$1*s+w/2), 52)"; }
  read X0 Y0 < <(at 0)
  wheel "move $X0 $Y0"; sleep 0.3
  kglob "Ectoview"; sleep 2.5
  # (open, the wheel switches desktops: the check that the wheel reaches it at all)
  wheel "wheel 1"; sleep 1; log "open wheel: $(order)"
  wheel "wheel -1"; sleep 1
  kglob "Ectoview"; sleep 0.05; wheel "wheel 1"; sleep 0.05; wheel "wheel 1"; sleep 1.5
  log "closing wheel: $(order)"
  ;;
wheelbar|plant-wheelbar)
  # the wheel switches desktops only over the desktop bar
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))")
  kglob "Ectoview"; sleep 2.5
  log "start: $(order)"
  # over the big desktop view, over a window in it, and over the empty space beside the bar's
  # thumbnails: nothing switches
  wheel "move $CX 700"; sleep 0.3; wheel "wheel 1"; sleep 0.8; wheel "wheel 1"; sleep 0.8
  log "view wheel: $(order)"
  wheel "move $CX 1300"; sleep 0.3; wheel "wheel -1"; sleep 0.8
  log "low wheel: $(order)"
  # over the bar's thumbnails: one detent toward you is the next desktop, one away the one before
  wheel "move $(python3 -c "print(round($MX + $MW*0.42))") 52"; sleep 0.3; wheel "wheel 1"; sleep 1
  log "bar wheel: $(order)"
  wheel "wheel -1"; sleep 1
  log "bar wheel back: $(order)"
  shot "$OUT/wheelbar.png"
  ;;
crossscreen)
  # the dashboard screen shows only its windows (OtherScreens=1); Kate dragged from the main screen's
  # desktop view onto it must land there, on that screen's desktop, not vanish
  where() { script "for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf(\"$1\") >= 0) print(\"where $1 \" + w.desktops.map(d => d.name).join(\",\") + \" on \" + w.output.name + \" left \" + workspace.currentDesktopForScreen(workspace.screens.find(o => o.name === \"Virtual-0\")).name);"; grep "js: where $1" "$OUT/kwin.log" | tail -1 | sed "s/.*js: where $1 //"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  CX=$(python3 -c "print(round($MX + $MW/2))")
  log "before: $(where kate)"
  kglob "Ectoview"; sleep 2.5
  for k in 37 30 20; do feed "key $k"; sleep 0.12; done; sleep 1.5
  feed "move $CX 780"; sleep 0.4; feed "down"; sleep 0.2
  LX=$(python3 -c "print(round($MX * 0.5))"); LY=1100
  for f in 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1; do feed "move $(python3 -c "print(round($CX+($LX-$CX)*$f), round(780+($LY-780)*$f))")"; sleep 0.1; done
  sleep 0.6; shot "$OUT/over-left.png"; feed "up"; sleep 1.5
  log "after: $(where kate)"
  shot "$OUT/after.png"
  ;;
install)
  # a stranger's Plasma with Overview on Meta+W: install.sh, the real key, the settings page, uninstall.sh
  REPO=$(dirname "$PKG")
  meta_w() { feed "press 125"; sleep 0.1; feed "key 17"; sleep 0.1; feed "release 125"; }
  keysof() { gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "['kwin', '$1', '', '']" 2>/dev/null; }
  log "before: loaded=$(effects_loaded | tr ' ' '\n' | grep -xE 'overview|ectoview' | paste -sd, -) Overview=$(keysof Overview)"
  shot "$OUT/desktop.png"
  meta_w; sleep 2; shot "$OUT/stock-open.png"; meta_w; sleep 1.5
  ECTOVIEW_NO_SESSION_ENV=1 "$REPO/install.sh" > "$OUT/install-run.log" 2>&1; log "install exit $?"
  log "after install: loaded=$(effects_loaded | tr ' ' '\n' | grep -xE 'overview|ectoview' | paste -sd, -) Overview=$(keysof Overview) Ectoview=$(keysof Ectoview) GridView=$(keysof 'Grid View') EctoviewGrid=$(keysof 'Ectoview Grid View')"
  log "plugins: $(grep -A3 '^\[Plugins\]' "$XDG_CONFIG_HOME/kwinrc" | tr '\n' ' ')"
  meta_w; sleep 2.5; shot "$OUT/ectoview-open.png"
  # the gear beside search: 8 px right of the 360 px field centered on the main screen, 36 px round
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  feed "move $(python3 -c "print(round($MX + $MW/2 + 180 + 8 + 18))") 154"; sleep 0.6; shot "$OUT/gear-hover.png"; feed "click"; sleep 5
  script 'for (const w of workspace.stackingOrder) if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) print("gear window " + w.caption + " " + JSON.stringify(w.frameGeometry));'
  log "$(grep 'js: gear window' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  shot "$OUT/after-gear.png"
  script 'for (const w of workspace.stackingOrder) if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) w.closeWindow();'
  sleep 1.5
  # an update, installed over a running Ectoview, must run at once (KWin keeps compiled QML per path)
  REPO2=$W/repo2; mkdir -p "$REPO2"
  (cd "$REPO" && tar --exclude=./build --exclude=./.git -cf - .) | (cd "$REPO2" && tar -xf -)
  sed -i 's/"Search windows and apps"/"Search windows and apps (updated)"/' "$REPO2/package/contents/ui/impl/EctoSearchField.qml"
  grep -q 'apps (updated)' "$REPO2/package/contents/ui/impl/EctoSearchField.qml" && log "update made" || log "FAIL update not made"
  ECTOVIEW_NO_SESSION_ENV=1 "$REPO2/install.sh" > "$OUT/update-run.log" 2>&1; log "update exit $?"
  log "builds loaded: $(grep -o 'Ectoview: loaded build [a-z0-9]*' "$OUT/kwin.log" | awk '{print $4}' | paste -sd, -)"
  meta_w; sleep 2.5; shot "$OUT/ectoview-updated.png"; meta_w; sleep 1.5
  # the settings page, found the way System Settings finds it: by its plugin path, with the session script's QT_PLUGIN_PATH
  ( . "$XDG_CONFIG_HOME/plasma-workspace/env/ectoview.sh"; echo "QT_PLUGIN_PATH=$QT_PLUGIN_PATH" >> "$OUT/steps.log"; kcmshell6 kwin/effects/configs/kwin_ectoview_config > "$OUT/kcmshell.log" 2>&1 & )
  sleep 5
  script 'for (const w of workspace.stackingOrder) { print("win " + w.resourceClass + " | " + w.resourceName + " | " + w.caption); if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) { print("settings window " + w.caption + " " + JSON.stringify(w.frameGeometry)); workspace.activeWindow = w; } }'
  log "$(grep 'js: settings window' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  shot "$OUT/settings.png"
  script 'for (const w of workspace.stackingOrder) if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) w.closeWindow();'
  sleep 1
  ECTOVIEW_NO_SESSION_ENV=1 "$REPO/uninstall.sh" > "$OUT/uninstall-run.log" 2>&1; log "uninstall exit $?"
  sleep 1
  log "after uninstall: loaded=$(effects_loaded | tr ' ' '\n' | grep -xE 'overview|ectoview' | paste -sd, -) Overview=$(keysof Overview) GridView=$(keysof 'Grid View')"
  log "leftovers: $(ls -d "$XDG_DATA_HOME/kwin/effects/ectoview" "$XDG_DATA_HOME/kwin-wayland/effects/ectoview" "$XDG_CONFIG_HOME/plasma-workspace/env/ectoview.sh" "$XDG_STATE_HOME/ectoview-install" 2>/dev/null; find "$HOME/.local" -name 'kwin_ectoview_config*' 2>/dev/null; grep -c 'Effect-ectoview\|ectoviewEnabled' "$XDG_CONFIG_HOME/kwinrc")"
  meta_w; sleep 2; shot "$OUT/stock-again.png"; meta_w; sleep 1
  ;;
overflow)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  log "before: $(order)"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/open.png"
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  # the bar doesn't fit, so it starts at the screen's left edge
  place() { python3 -c "w=90*$MW/1440; s=w+8; print(round($MX+$1*s+w/2))"; }
  Y=52
  feed "move $(place 1) $Y"; sleep 0.4; feed "down"; sleep 0.2
  END=$(python3 -c "print(round($MX+$MW-12))")
  for f in 0.1 0.3 0.5 0.7 0.9 1; do feed "move $(python3 -c "print(round($(place 1)+($END-$(place 1))*$f))") $Y"; sleep 0.08; done
  sleep 2.5; shot "$OUT/scrolled.png"   # held at the right end: the bar scrolls
  feed "up"; sleep 1.2; shot "$OUT/dropped.png"
  log "after drag: $(order)"
  ;;
kcmpath)
  # does kcmshell6 open the settings page by its full path, with no QT_PLUGIN_PATH?
  cmake --install "$(dirname "$PKG")/build" --prefix "$HOME/.local" > "$OUT/kcm-install.log" 2>&1
  SO=$(find "$HOME/.local" -name kwin_ectoview_config.so | head -1); log "so: $SO"
  env -u QT_PLUGIN_PATH kcmshell6 "$SO" > "$OUT/kcmshell.log" 2>&1 &
  sleep 5
  script 'for (const w of workspace.stackingOrder) if ((w.resourceClass + w.resourceName + w.caption).indexOf("kcmshell") >= 0) print("settings window " + w.resourceClass + " " + w.caption + " " + JSON.stringify(w.frameGeometry));'
  log "$(grep 'js: settings window' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  shot "$OUT/settings.png"
  ;;
plant-update)
  # every build in one folder (the old installer's way): the update can't run until KWin restarts
  REPO=$(dirname "$PKG")
  meta_w() { feed "press 125"; sleep 0.1; feed "key 17"; sleep 0.1; feed "release 125"; }
  ECTOVIEW_TEST_BUILD_ID=bfixed ECTOVIEW_NO_SESSION_ENV=1 "$REPO/install.sh" > "$OUT/install-run.log" 2>&1; log "install exit $?"
  meta_w; sleep 2.5; shot "$OUT/ectoview-open.png"; meta_w; sleep 1.5
  REPO2=$W/repo2; mkdir -p "$REPO2"
  (cd "$REPO" && tar --exclude=./build --exclude=./.git -cf - .) | (cd "$REPO2" && tar -xf -)
  sed -i 's/"Search windows and apps"/"Search windows and apps (updated)"/' "$REPO2/package/contents/ui/impl/EctoSearchField.qml"
  ECTOVIEW_TEST_BUILD_ID=bfixed ECTOVIEW_NO_SESSION_ENV=1 "$REPO2/install.sh" > "$OUT/update-run.log" 2>&1; log "update exit $?"
  log "builds loaded: $(grep -o 'Ectoview: loaded build [a-z0-9]*' "$OUT/kwin.log" | awk '{print $4}' | paste -sd, -)"
  meta_w; sleep 2.5; shot "$OUT/ectoview-updated.png"; meta_w; sleep 1.5
  ;;
layout|gutter)
  shot "$OUT/desktop.png"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/overview.png"
  kglob "Ectoview"; sleep 1.5; shot "$OUT/closed.png"
  kglob "Ectoview Grid View"; sleep 2.5; shot "$OUT/grid.png"; kglob "Ectoview Grid View"; sleep 1.5
  ;;
rename)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  kglob "Ectoview"; sleep 2.5
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  X=$(python3 -c "w=90*$MW/1440; s=w+8; x0=$MX+($MW-(5*w+4*8))/2; print(round(x0+1*s+w/2))")
  feed "move $X 111"; sleep 0.3; feed "click"; sleep 1; shot "$OUT/editing.png"
  for k in 49 24 20 18 31; do feed "key $k"; sleep 0.1; done   # "notes" replaces the selected name
  sleep 0.5; shot "$OUT/typed.png"
  feed "key 28"; sleep 1   # Enter
  log "after rename: $(order)"
  ;;
migrate)
  # an install from before the loader, in the old folder, already compiled by KWin, then the new
  # install.sh over it while KWin keeps running: the new build must run without a restart
  REPO=$(dirname "$PKG")
  meta_w() { feed "press 125"; sleep 0.1; feed "key 17"; sleep 0.1; feed "release 125"; }
  log "old loaded: $(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded ectoview)"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/old-open.png"; kglob "Ectoview"; sleep 1.5
  ECTOVIEW_NO_SESSION_ENV=1 "$REPO/install.sh" --no-shortcuts > "$OUT/install-run.log" 2>&1; log "install exit $?"
  log "folders: old=$(ls "$XDG_DATA_HOME/kwin/effects/" 2>/dev/null | paste -sd, -) new=$(ls "$XDG_DATA_HOME/kwin-wayland/effects/" 2>/dev/null | paste -sd, -)"
  log "builds loaded: $(grep -o 'Ectoview: loaded build [a-z0-9]*' "$OUT/kwin.log" | awk '{print $4}' | paste -sd, -)"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/new-open.png"; kglob "Ectoview"; sleep 1
  ;;
hide)
  # starts from a kwinrc of the build before groups: Code hidden (HiddenDesktops=d2) and search set to all desktops
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  rc() { kreadconfig6 --file kwinrc --group Effect-ectoview --key "$1"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  # the bar with N desktops shown: thumbnails 90 px tall, 8 apart, centered; place P's left edge
  left() { python3 -c "w=90*$MW/1440; print(round($MX+($MW-(($1+1)*w+$1*8))/2+$2*(w+8)))"; }
  TW=$(python3 -c "print(round(90*$MW/1440))")
  # a desktop's Move to desktop group button (left of delete, top right of its thumbnail), and a row in its list
  movemenu() { local L=$(left $1 $2); feed "move $((L + TW/2)) 53"; sleep 0.6; feed "move $((L + TW - 52)) 28"; sleep 0.6; feed "click"; sleep 1; MENU_X=$((L + TW - 66 + 60)); }
  # the list: a 30 px heading, then 34 px rows: the groups, a line, Hidden, a line, New desktop group…
  menurow() { python3 -c "print(round(48 + 4 + 30 + 34*$1 + 9*$2 + 17))"; }
  PR=$(python3 -c "print(round($MX + $MW/2 - 188))")
  kglob "Ectoview"; sleep 2.5
  log "migrated: groups=$(rc DesktopGroups) hidden=$(rc HiddenDesktops) scope=$(rc SearchScope) all=$(rc SearchAllDesktops) others=$(rc OtherScreens) primaryonly=$(rc PrimaryScreenOnly)"
  shot "$OUT/migrated.png"
  # the pill's list: a 30 px heading, a 44 px row per group, a line, then Hidden
  feed "move $((PR - 30)) 150"; sleep 0.4; feed "click"; sleep 1.2; shot "$OUT/menu.png"
  feed "move $((PR + 60)) $(python3 -c "print(176 + 4 + 30 + 44 + 9 + 22)")"; sleep 0.4; shot "$OUT/menu-hover.png"; feed "click"; sleep 1.5
  shot "$OUT/onhidden.png"
  log "on hidden: groups=$(rc DesktopGroups) $(order)"
  # the view shows the Hidden group now: Code alone in the bar. Move to desktop group > Desktops brings it back
  # (it stays in this view, dimmed, until you leave it)
  movemenu 1 0; shot "$OUT/move-menu.png"; feed "move $MENU_X $(menurow 0 0)"; sleep 0.4; feed "click"; sleep 1.2
  log "after show: groups=$(rc DesktopGroups) $(order)"
  # with nothing hidden and one group, the pill goes and the bar shows all four again
  shot "$OUT/shown.png"
  # Code (place 1 of 4): Move to desktop group > Hidden; it stays, dimmed, while you're on it
  movemenu 4 1; feed "move $MENU_X $(menurow 1 1)"; sleep 0.4; feed "click"; sleep 1.2
  log "after hide: groups=$(rc DesktopGroups) $(order)"
  # Work (place 0 of 4): the bar closes up
  feed "move $(( $(left 4 0) + TW/2 )) 53"; sleep 0.3; feed "click"; sleep 1.2
  log "back to Work: $(order)"
  shot "$OUT/hidden.png"
  # drag Music onto Design's place (Code keeps its place in KWin's order)
  X2=$(( $(left 3 2) + TW/2 )); X1=$(( $(left 3 1) + TW/2 ))
  feed "move $X2 53"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.2 0.4 0.6 0.8 1; do feed "move $(python3 -c "print(round($X2+($X1-$X2)*$f))") 53"; sleep 0.08; done
  sleep 0.4; feed "up"; sleep 1.2
  log "after drag: groups=$(rc DesktopGroups) $(order)"
  # Grid View leaves the hidden desktop out
  kglob "Ectoview"; sleep 1.5; kglob "Ectoview Grid View"; sleep 2.5; shot "$OUT/grid-hidden.png"; kglob "Ectoview Grid View"; sleep 1.5
  ;;
groups|plant-tokens)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  rc() { kreadconfig6 --file kwinrc --group Effect-ectoview --key "$1"; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  left() { python3 -c "w=90*$MW/1440; print(round($MX+($MW-(($1+1)*w+$1*8))/2+$2*(w+8)))"; }
  TW=$(python3 -c "print(round(90*$MW/1440))")
  movemenu() { local L=$(left $1 $2); feed "move $((L + TW/2)) 53"; sleep 0.6; feed "move $((L + TW - 52)) 28"; sleep 0.6; feed "click"; sleep 1; MENU_X=$((L + TW - 66 + 60)); }
  menurow() { python3 -c "print(round(48 + 4 + 30 + 34*$1 + 9*$2 + 17))"; }
  # the pill's list: a 30 px heading, then 44 px rows
  grouprow() { python3 -c "print(176 + 4 + 30 + 44*$1 + 22)"; }
  PR=$(python3 -c "print(round($MX + $MW/2 - 188))")
  kglob "Ectoview"; sleep 2.5; shot "$OUT/nopill.png"
  # 1. Design: Move to desktop group > New desktop group…, named "games"
  movemenu 4 2; shot "$OUT/move-menu.png"
  feed "move $MENU_X $(menurow 2 2)"; sleep 0.4; feed "click"; sleep 0.8
  for k in 34 30 50 18 31; do feed "key $k"; sleep 0.1; done; sleep 0.3; shot "$OUT/naming.png"; feed "key 28"; sleep 1.2
  log "new group: groups=$(rc Groups) members=$(rc DesktopGroups)"
  shot "$OUT/after-new.png"
  # 2. drag Music (place 2 of 3) onto the pill, then onto games' row (the second)
  X=$(( $(left 3 2) + TW/2 ))
  feed "move $X 53"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.2 0.4 0.6 0.8 1; do feed "move $(python3 -c "print(round($X+($PR-91-$X)*$f), round(53+(150-53)*$f))")"; sleep 0.1; done
  sleep 0.8
  for f in 0.25 0.5 0.75 1; do feed "move $(python3 -c "print(round($PR-91+151*$f), round(150+($(grouprow 1)-150)*$f))")"; sleep 0.1; done
  sleep 0.6; shot "$OUT/drag-over.png"; feed "up"; sleep 1.2
  log "after drop: members=$(rc DesktopGroups) $(order)"
  # 3. the pill's list: games' row takes you to its first desktop
  feed "move $((PR - 91)) 150"; sleep 0.4; feed "click"; sleep 1.2; shot "$OUT/menu.png"
  feed "move $((PR + 60)) $(grouprow 1)"; sleep 0.4; feed "click"; sleep 1.5
  shot "$OUT/games.png"
  log "chose games: $(order)"
  log "heights: $(python3 "$HERE/measure.py" "$OUT" games.png heights)"
  # 4. rename (pencil) to "play", from the pill's list
  PL=$(python3 "$HERE/measure.py" "$OUT" games.png pill-left); log "pill left: $PL"
  feed "move $((PR - 91)) 150"; sleep 0.4; feed "click"; sleep 1.2
  feed "move $((PL + 200)) $(grouprow 1)"; sleep 0.6; feed "move $((PL + 325)) $(grouprow 1)"; sleep 0.6; shot "$OUT/row-hover.png"; feed "click"; sleep 0.8
  for k in 25 38 30 21; do feed "key $k"; sleep 0.1; done; feed "key 28"; sleep 1
  log "renamed: groups=$(rc Groups)"
  feed "key 1"; sleep 0.6
  # 5. the shortcuts, with Ectoview closed: next desktop in the group, then the next group
  kglob "Ectoview"; sleep 1.5
  kglob "Ectoview Next Desktop in Desktop Group"; sleep 0.8; log "next in group: $(order)"
  kglob "Ectoview Previous Desktop in Desktop Group"; sleep 0.8; log "previous in group: $(order)"
  kglob "Ectoview Next Desktop Group"; sleep 0.8; log "next group: $(order)"
  kglob "Ectoview Previous Desktop Group"; sleep 0.8; log "previous group: $(order)"
  # 6. "This desktop group": Konsole on Music; from Design, search finds it, and a click takes you there
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("konsole") >= 0) w.desktops = [workspace.desktops[3]]; workspace.currentDesktop = workspace.desktops[2];'
  sleep 0.8
  kglob "Ectoview"; sleep 2.5
  FR=$(python3 -c "print(round($MX + $MW/2 + 180))")
  feed "move $((FR - 18)) 151"; sleep 0.3; feed "click"; sleep 0.8; shot "$OUT/scope-menu.png"
  feed "move $((FR - 150)) $((176 + 4 + 46 + 23))"; sleep 0.3; feed "click"; sleep 0.8
  log "scope: $(rc SearchScope)"
  for k in 18 46 20 24 47 23 18 17; do feed "key $k"; sleep 0.12; done; sleep 2; shot "$OUT/group-search.png"
  feed "move $(python3 -c "print(round($MX + $MW/2))") 780"; sleep 0.3; feed "click"; sleep 1.5
  log "after search click: $(order)"
  # 7. New desktop group from the pill's list (two groups, no Hidden: its row follows a line): a new desktop in
  # a new group, you're on it, and its name ready to type
  kglob "Ectoview"; sleep 2.5
  feed "move $((PR - 91)) 150"; sleep 0.4; feed "click"; sleep 1.2
  feed "move $((PR + 60)) $(python3 -c "print(176 + 4 + 30 + 44*2 + 9 + 17)")"; sleep 0.4; feed "click"; sleep 1.5
  for k in 50 23 31 46; do feed "key $k"; sleep 0.1; done; feed "key 28"; sleep 1
  log "new from pill: groups=$(rc Groups) members=$(rc DesktopGroups) $(order)"
  # Esc after naming closes the list (and only the list)
  feed "key 1"; sleep 0.6
  # 8. remove "play" (its ✕ on hover): Design and Music go back to the first group
  shot "$OUT/before-remove.png"; PL=$(python3 "$HERE/measure.py" "$OUT" before-remove.png pill-left); log "pill left: $PL"
  feed "move $((PR - 91)) 150"; sleep 0.4; feed "click"; sleep 1.2
  feed "move $((PL + 200)) $(grouprow 1)"; sleep 0.6; feed "move $((PL + 355)) $(grouprow 1)"; sleep 0.6; feed "click"; sleep 1.2
  log "removed: groups=$(rc Groups) members=$(rc DesktopGroups)"
  shot "$OUT/removed.png"
  ;;
deadclicks)
  # 20 desktops (DESKTOPS20=1), so the bar overflows and its back arrow starts faded
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  shot "$OUT/desktop.png"
  kglob "Ectoview"; sleep 2.5
  feed "move $(python3 -c "print(round($MX + 60))") 900"; sleep 0.3; feed "click"; sleep 1.2; shot "$OUT/after-backdrop.png"
  feed "move $(python3 -c "print(round($MX + 8 + 18))") 53"; sleep 0.3; feed "click"; sleep 1.2; shot "$OUT/after-arrow.png"
  # the desktop itself: inside the desktop view, above the windows
  feed "move $(python3 -c "print(round($MX + $MW/2))") 330"; sleep 0.3; feed "click"; sleep 1.5; shot "$OUT/after-desktop.png"
  ;;
searchall)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  # Konsole goes to Code; Ectoview opens on Work
  script 'for (const w of workspace.stackingOrder) if (w.resourceClass.indexOf("konsole") >= 0) w.desktops = [workspace.desktops[1]];'
  sleep 0.5
  script 'print("captions " + workspace.stackingOrder.filter(w => w.normalWindow).map(w => w.caption + " @" + w.desktops.map(d => d.name)).join(" | "));'
  log "$(grep -o 'js: captions .*' "$OUT/kwin.log" | tail -1 | sed 's/js: //')"
  kglob "Ectoview"; sleep 2.5
  typeit() { for k in 18 46 20 24 47 23 18 17; do feed "key $k"; sleep 0.12; done; }   # "ectoview"
  typeit; sleep 2; shot "$OUT/this.png"
  for i in 1 2 3 4 5 6 7 8; do feed "key 14"; sleep 0.08; done
  FR=$(python3 -c "print(round($MX + $MW/2 + 180))")
  feed "move $((FR - 18)) 151"; sleep 0.3; feed "click"; sleep 0.8; shot "$OUT/scope-menu.png"
  feed "move $((FR - 200)) 250"; sleep 0.3; feed "click"; sleep 0.8
  log "scope: $(kreadconfig6 --file kwinrc --group Effect-ectoview --key SearchScope)"
  typeit; sleep 2; shot "$OUT/all.png"
  feed "move $(python3 -c "print(round($MX + $MW/2))") 780"; sleep 0.3; shot "$OUT/before-click.png"; feed "click"; sleep 1.5
  shot "$OUT/after-click.png"
  script 'print("screens now " + workspace.screens.map(o => o.name + "=" + workspace.currentDesktopForScreen(o).name).join(" ") + " active " + (workspace.activeWindow ? workspace.activeWindow.caption : "none"));'
  log "$(grep 'js: screens now' "$OUT/kwin.log" | tail -1 | sed 's/.*js: //')"
  log "after click: $(order)"
  ;;
readme-*)
  readme_run
  ;;
reorder|plant-reorder)
  order() { script 'print("order " + workspace.desktops.map(d => d.name).join(",") + " current " + workspace.currentDesktop.name);'; grep "js: order" "$OUT/kwin.log" | tail -1 | sed 's/.*js: order //'; }
  log "before: $(order)"
  kglob "Ectoview"; sleep 2.5; shot "$OUT/open.png"
  # the bar's places, from KWin's own sizes: thumbnails 5 grid units tall (18 px each), as wide as the
  # screen's shape, 8 px apart, centered on the main screen
  read MX MW < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":[0-9.]+,\"width\":([0-9.]+)',t);print(m.group(1),m.group(2))")
  if [ "${BAR:-top}" = left ]; then
    # a vertical list on the left, centered top to bottom: 108 px per desktop (90 + its name), 8 apart, then the add tile
    at() { python3 -c "h=90; s=108+8; total=4*108+90+4*8; y0=(1440-total)/2; print($MX+8+round(h*$MW/1440)/2, round(y0+$1*s+h/2))"; }
  else
    at() { python3 -c "w=90*$MW/1440; s=w+8; x0=$MX+($MW-(5*w+4*8))/2; print(round(x0+$1*s+w/2), 52)"; }
  fi
  read X3 Y3 < <(at 3); read X1 Y1 < <(at 1); read X2 Y2 < <(at 2)
  feed "move $X3 $Y3"; sleep 0.4; feed "down"; sleep 0.2
  for f in 0.1 0.25 0.4 0.55 0.7 0.85 1; do feed "move $(python3 -c "print(round($X3+($X1-$X3)*$f), round($Y3+($Y1-$Y3)*$f))")"; sleep 0.08; done
  sleep 0.4; shot "$OUT/dragging.png"
  feed "up"; sleep 1.2; shot "$OUT/dropped.png"
  log "after drag: $(order)"
  # a plain click on a desktop still switches to it (and the overview stays: Overview's own behavior)
  feed "move $X2 $Y2"; sleep 0.3; feed "click"; sleep 1.2
  log "after click: $(order)"
  ;;
esac
kill $KW 2>/dev/null; wait $KW 2>/dev/null
exit 0
