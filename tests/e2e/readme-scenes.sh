# The README's pictures, filmed in run.sh's private KWin: sourced by inner.sh for SCENARIO=readme-NAME.
# Each scene is driven as a person would drive it, with the real pointer and keys (fake input), and
# filmed by film.py through KWin's own screenshots. tools/readme-pictures.sh runs every scene in
# SCENES and tools/readme-pictures.py cuts the films into docs/pictures/ (its CUTS name the pictures).
# Nothing private is on screen: the made-up desktops, groups and files below, KDE's wallpaper, and no
# app that lists this computer's drives (Dolphin's Places would). The main screen is 2560x1440 at
# scale 1.5 (1707x960), the dashboard screen left of it 2560x1440 at 1.75 (1463x823), bottoms lined up.

# the scenes, in the order the README shows them
SCENES="hero overview groups todesktop towindow reorder arrows beacons shortcut screens kdelook bartop barbottom barleft barright grid overflow"

README_SCENE=${SCENARIO#readme-}

# made-up desktops and groups, as someone might keep them: Work, Home and Play, and one hidden
readme_desktops() {
  local names=(Code Review Docs Mail Music Photos Games Chat Scratch) i
  [ "$README_SCENE" = overflow ] && names=(Code Review Docs Mail Specs Builds Design Tickets Notes Calls Plans Ideas Music Games)
  [ "$README_SCENE" = grid ] && names=(Code Review Docs Mail Specs Builds Design Tickets Notes Calls Music Photos Games Chat Scratch)
  printf '[Desktops]\nNumber=%d\nRows=1\n' ${#names[@]}
  for i in "${!names[@]}"; do printf 'Name_%d=%s\nId_%d=d%d\n' $((i + 1)) "${names[$i]}" $((i + 1)) $((i + 1)); done
}
readme_groups() {
  if [ "$README_SCENE" = grid ]; then
    # Work long enough to stack in Grid View (ten), Home and Play short, one Hidden
    printf 'Groups=w:Work,h:Home,p:Play\nDesktopGroups=%s\n' "$(for i in $(seq 15); do printf 'd%d=%s,' $i $( { [ $i -le 10 ] && echo w; } || { [ $i -le 12 ] && echo h; } || { [ $i -le 14 ] && echo p; } || echo hidden); done)"
  elif [ "$README_SCENE" = overflow ]; then
    printf 'Groups=w:Work,p:Play\nDesktopGroups=%s\n' "$(for i in $(seq 14); do printf 'd%d=%s,' $i $([ $i -le 12 ] && echo w || echo p); done)"
  else
    printf 'Groups=w:Work,h:Home,p:Play\nDesktopGroups=d1=w,d2=w,d3=w,d4=w,d5=h,d6=h,d7=p,d8=p,d9=hidden\n'
  fi
}

film() { echo "$*" > "$W/film.fifo"; }
film_wait() { for i in $(seq 200); do [ -e "$OUT/film/$1" ] && return 0; sleep 0.05; done; echo "film: $1 never came" >> "$OUT/readme.log"; }
film_end() { film stop; film_wait stopped; touch "$W/readme-done"; }
# a moment in the film, by the wall clock (film.py's start.txt says when the film began)
film_mark() { echo "$1 $(date +%s.%N)" >> "$OUT/film/marks-wall.txt"; }
R_PX=0; R_PY=0
# the pointer travels as a hand moves it: eased, on a slight curve, a step every 16 ms
glide() {
  local x1=$1 y1=$2 ms=${3:-500} n x y
  n=$((ms / 16)); [ "$n" -lt 2 ] && n=2
  while read -r x y; do feed "move $x $y"; feed "sleep 16"; done < <(awk -v x0="$R_PX" -v y0="$R_PY" -v x1="$x1" -v y1="$y1" -v n="$n" 'BEGIN {
    dx = x1 - x0; dy = y1 - y0; bend = 0.08
    for (i = 1; i <= n; i++) { t = i / n; s = t * t * (3 - 2 * t); b = sin(3.14159265 * t) * bend
      printf "%.1f %.1f\n", x0 + dx * s - dy * b, y0 + dy * s + dx * b } }')
  R_PX=$x1; R_PY=$y1
}
place() { R_PX=$1; R_PY=$2; feed "move $1 $2"; }
press() { feed "down"; feed "sleep 70"; feed "up"; }
hold() { sleep "$(python3 -c "print($1 / 1000)")"; }
# a drag: press here, travel, let go
drag_to() { feed "down"; feed "sleep 120"; glide "$1" "$2" "${3:-700}"; feed "sleep 120"; feed "up"; }
# a window asking for attention (KWin's demandsAttention, as a chat's ping or a terminal's bell sets it)
attention() { script "for (const w of workspace.windowList()) if (w.caption.indexOf(\"$1\") >= 0) w.demandsAttention = $2;"; }

# ---- where things are on the main screen (logical px): its origin and size from KWin's log
readme_geometry() {
  read MX MY MW MH < <(python3 -c "import re;t=open('$OUT/kwin.log').read();m=re.search(r'Virtual-1 \{\"x\":([0-9.]+),\"y\":([0-9.]+),\"width\":([0-9.]+),\"height\":([0-9.]+)',t);print(*(round(float(v)) for v in m.groups()))")
  CX=$((MX + MW / 2))
  # the toolbar row: the search field (360 wide, centered), the groups' pill ending 8 px left of it
  # with ^ and v as its last 61 px, the gear 8 px right of it
  ROW=$((MY + 153)); PR=$((CX - 188)); STEP_DOWN=$((CX - 208)); STEP_UP=$((CX - 230)); PILL_NAME=$((CX - 280))
  TW=$(python3 -c "print(round(90 * $MW / $MH))")
}
# the bar's tile I of N (the shown group's desktops and the add tile), centered on the main screen
tile() { python3 -c "w=90*$MW/$MH; x0=$MX+($MW-($2*w+($2-1)*8))/2; print(round(x0+$1*(w+8)+w/2), $MY+52)"; }

# ---- before Plasma starts: KDE's own Breeze Dark (not this computer's colors), Kate without its
# folder bar (it would show the sandbox's temporary path), and a plain web browser of the sandbox's
# own for the panel's browser button (this computer's default browser would show its brand)
readme_prepare() {
  cp /usr/share/color-schemes/BreezeDark.colors "$XDG_CONFIG_HOME/kdeglobals"
  printf '[General]\nShow Url Nav Bar=false\nShow welcome view for new window=false\n' > "$XDG_CONFIG_HOME/katerc"
  mkdir -p "$XDG_DATA_HOME/applications"
  printf '[Desktop Entry]\nType=Application\nName=Web Browser\nIcon=internet-web-browser\nExec=true %%u\nMimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;\n' \
    > "$XDG_DATA_HOME/applications/ectoview-readme-browser.desktop"
  printf '[Default Applications]\nx-scheme-handler/http=ectoview-readme-browser.desktop\nx-scheme-handler/https=ectoview-readme-browser.desktop\ntext/html=ectoview-readme-browser.desktop\n' > "$XDG_CONFIG_HOME/mimeapps.list"
  kwriteconfig6 --file "$XDG_CONFIG_HOME/kdeglobals" --group General --key BrowserApplication ectoview-readme-browser.desktop
}

# ---- the apps: windows with made-up words, nothing that lists this computer's drives
readme_apps() {
  mkdir -p "$HOME/Projects/launch" "$HOME/Documents"
  printf '%s\n' '# Launch notes' '' '## This week' '- Ship the new onboarding flow' '- Review the pricing page copy' \
    '- Record the walkthrough video' '' '## Open questions' '- Which plans get the trial?' '- Do we keep the waitlist?' > "$HOME/Projects/launch/notes.md"
  printf '%s\n' '# Today' '' '09:30  Standup' '11:00  Design review' '14:00  Pairing on search' '16:30  Release check' \
    '' 'Inbox zero by noon.' > "$HOME/Documents/today.md"
  printf '%s\n' 'diff --git a/src/search.ts b/src/search.ts' '@@ -12,7 +12,9 @@ export function rank(items) {' \
    '-  return items.sort(byScore);' '+  return items' '+    .filter(isVisible)' '+    .sort(byScore);' ' }' > "$HOME/Projects/launch/review.diff"
  konsole --separate --hide-menubar --hide-tabbar -p tabtitle=build -e bash -c \
    "printf '\033[1;32m\$\033[0m npm test\n\n  search\n    \033[32m✓\033[0m ranks visible items first\n    \033[32m✓\033[0m keeps the order stable\n  onboarding\n    \033[32m✓\033[0m saves progress\n\n  \033[32m3 passing\033[0m (41ms)\n\n\033[1;32m\$\033[0m '; exec cat" > /dev/null 2>&1 &
  sleep 1.5
  kate -n "$HOME/Projects/launch/notes.md" > /dev/null 2>&1 &
  sleep 1.5
  kate -n "$HOME/Projects/launch/review.diff" > /dev/null 2>&1 &
  sleep 1.5
  kcharselect > /dev/null 2>&1 &
  sleep 1.5
  konsole --separate --hide-menubar --hide-tabbar -p tabtitle=chat -e bash -c \
    "printf '\033[1;35mmaya\033[0m  are we still on for the walkthrough?\n\033[1;36msam\033[0m   yes, 4:30\n\033[1;35mmaya\033[0m  great, I will bring the slides\n'; exec cat" > /dev/null 2>&1 &
  sleep 1.5
  # the dashboard screen's still window: a day's notes, on every desktop
  kate -n "$HOME/Documents/today.md" > /dev/null 2>&1 &
  sleep 4
  script '
const outs = workspace.screens;
const left = outs.reduce((a, o) => o.geometry.x < a.geometry.x ? o : a); const main = outs.find(o => o !== left) || left;
const g = main.geometry, l = left.geometry, d = workspace.desktops;
print("screens " + outs.map(o => o.name + " " + JSON.stringify(o.geometry)).join(" | ") + " order " + workspace.screenOrder.map(o => o.name).join(","));
const at = (w, desk, x, y, wd, h) => { w.desktops = [d[desk]]; workspace.sendClientToScreen(w, main); w.frameGeometry = {x: g.x + x, y: g.y + y, width: wd, height: h}; };
for (const w of workspace.stackingOrder) {
  if (!w.normalWindow) continue;
  const c = w.caption;
  if (c.indexOf("today") >= 0) { w.onAllDesktops = true; workspace.sendClientToScreen(w, left); w.frameGeometry = {x: l.x + 40, y: l.y + 40, width: l.width - 80, height: l.height - 124}; }
  else if (c.indexOf("build") >= 0) at(w, 0, 60, 120, 760, 520);
  else if (c.indexOf("notes") >= 0) at(w, 0, 860, 150, 780, 560);
  else if (c.indexOf("review") >= 0) at(w, 1, 200, 110, 1200, 640);
  else if (w.resourceClass.indexOf("kcharselect") >= 0) at(w, 2, 260, 100, 1100, 680);
  else if (c.indexOf("chat") >= 0) at(w, 7, 300, 160, 900, 520);
  print("window " + w.resourceClass + " " + c + " " + JSON.stringify(w.frameGeometry) + " " + w.output.name);
}
workspace.currentDesktop = d[0];'
  sleep 1.5
  for w in build notes; do script "for (const w of workspace.stackingOrder) if (w.caption.indexOf(\"$w\") >= 0) workspace.activeWindow = w;"; done
}

# ---- filming
readme_start_film() {
  mkfifo "$W/film.fifo"
  printf '[Desktop Entry]\nType=Application\nName=Ectoview README film\nExec=%s\nNoDisplay=true\nX-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2\n' \
    "$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.executable))')" > "$XDG_DATA_HOME/applications/ectoview-readme-film.desktop"
  mkdir -p "$OUT/film"
  python3 -I "$HERE/film.py" "$W/film.fifo" "$OUT" 2>> "$OUT/film.err" &
  FILM_PID=$!
  sleep 1
  # what to film: the main screen (the screens scene films both)
  if [ "$README_SCENE" = screens ]; then film area 0 0 $((MX + MW)) $((MY + MH)); else film area "$MX" "$MY" "$MW" "$MH"; fi
}

# ---- the scenes
scene_hero() {
  # Meta+W on a desktop: Ectoview opens on Work's desktops, the groups' pill and its ^ and v; Chat
  # (in Play) asks for attention and the pill lights; v to Play, its desktops rise in; Chat's beacon;
  # ^ back to Work; Review chosen from the bar; Ectoview closes onto it
  place $((CX + 300)) $((MY + 700)); hold 300
  film start hero; film_wait hero
  hold 900; film_mark open; kglob "Ectoview"; hold 1400
  attention chat true; hold 900
  glide "$STEP_DOWN" "$ROW" 700; hold 300; film_mark down; press; hold 1500
  glide "$STEP_UP" "$ROW" 350; hold 250; press; hold 1300
  read -r X Y < <(tile 1 5); glide "$X" "$Y" 650; hold 300; press; hold 900
  kglob "Ectoview"; hold 1200
  film_end
}
scene_overview() {
  # KDE's own Overview (Ectoview off), on the same desktop: for the side by side
  place $((CX + 300)) $((MY + 700)); hold 300
  film start overview; film_wait overview
  hold 400; kglob "Overview"; hold 1600; film_mark open; hold 600
  kglob "Overview"; hold 900
  film_end
}
scene_groups() {
  # the pill's list: Work, Home and Play with their first desktops, Hidden, New desktop group
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start groups; film_wait groups
  glide "$PILL_NAME" "$ROW" 600; hold 250; press; hold 1100; film_mark list
  glide $((PR - 20)) $((MY + 176 + 4 + 30 + 44 + 22)) 600; hold 1200; film_mark hover
  film_end
}
scene_todesktop() {
  # Docs dragged from the bar onto the pill, then onto Home's row: it moves to Home
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start todesktop; film_wait todesktop
  read -r X Y < <(tile 2 5); glide "$X" "$Y" 600; hold 200
  feed "down"; feed "sleep 150"; glide "$PILL_NAME" "$ROW" 900; hold 900
  glide $((PR + 40)) $((MY + 176 + 4 + 30 + 44 + 22)) 600; hold 700; feed "up"; hold 1400
  film_end
}
scene_towindow() {
  # the build terminal dragged from the view onto the pill, then onto Play's row: it goes to Play's
  # desktop, and you with it
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start towindow; film_wait towindow
  glide $((CX - 400)) $((MY + 450)) 600; hold 200
  feed "down"; feed "sleep 150"; glide "$PILL_NAME" "$ROW" 900; hold 900
  glide $((PR + 40)) $((MY + 176 + 4 + 30 + 44 * 2 + 22)) 700; hold 700; feed "up"; hold 1600
  film_end
}
scene_reorder() {
  # Mail dragged from the end of Work's desktops to the front
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start reorder; film_wait reorder
  read -r X Y < <(tile 3 5); glide "$X" "$Y" 600; hold 200
  read -r X0 Y0 < <(tile 0 5); drag_to "$X0" "$Y0" 1200; hold 1400
  film_end
}
scene_arrows() {
  # the notes window carried to the next desktop: held on >, the view moves after a pause, and it's
  # let go there
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start arrows; film_wait arrows
  glide $((CX + 200)) $((MY + 480)) 600; hold 200
  # (the > sits 64 px right of the big view, halfway down it: on this screen 123 px in from the
  # right edge, 567 down)
  feed "down"; feed "sleep 150"; glide $((MX + MW - 123)) $((MY + 567)) 900; hold 1500
  glide $((CX + 100)) $((MY + 500)) 700; hold 200; feed "up"; hold 1400
  film_end
}
scene_beacons() {
  # a window on Review asks for attention: its desktop's beacon lights; then Chat, in Play: the pill
  # lights; going to Review takes the beacon away
  attention review false
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start beacons; film_wait beacons
  hold 600; attention review true; hold 1500; film_mark review
  attention chat true; hold 1600; film_mark chat
  glide "$PILL_NAME" "$ROW" 600; hold 200; press; hold 1000; film_mark list; hold 2500
  feed "key 1"; hold 600
  film_end
}
scene_shortcut() {
  # Ectoview closed: "Next Desktop Group" goes from Code to Home's Music, rising in over Code in
  # place, not sliding past every desktop between
  place $((CX + 300)) $((MY + 700)); hold 300
  film start shortcut; film_wait shortcut
  hold 700; film_mark press; kglob "Ectoview Next Desktop Group"; hold 1300
  film_mark back; kglob "Ectoview Previous Desktop Group"; hold 1300
  film_end
}
scene_screens() {
  # both screens: the dashboard screen on the left left as it is while Ectoview opens on the main one
  place $((CX + 300)) $((MY + 700)); hold 300
  film start screens; film_wait screens
  hold 600; kglob "Ectoview"; hold 1800; film_mark open
  kglob "Ectoview"; hold 900
  film_end
}
scene_kdelook() {
  # the same in your KDE colors and font (Breeze Dark here), with KDE's accent
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1800
  film still kdelook; film_wait kdelook.done
  kglob "Ectoview"; hold 600; touch "$W/readme-done"
}
# where the bar sits (the README's 2x2): along the top and the bottom with the toolbar, down the
# left and the right without it, so the groups' button and the gear sit at the bar's end
bar_still() {
  place $((CX + 300)) $((MY + 420))
  kglob "Ectoview"; hold 1800
  film still "$1"; film_wait "$1.done"
  kglob "Ectoview"; hold 600; touch "$W/readme-done"
}
scene_bartop() { bar_still bartop; }
scene_barbottom() { bar_still barbottom; }
scene_barleft() { bar_still barleft; }
scene_barright() { bar_still barright; }
scene_grid() {
  # Grid View: a row per desktop group; Work's ten stack onto more rows, lined up in columns, the grid centered
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview Grid View"; hold 2000
  film still grid; film_wait grid.done
  kglob "Ectoview Grid View"; hold 600; touch "$W/readme-done"
}
scene_overflow() {
  # a group of twelve desktops: the bar pages, its ends fading; > pages along
  place $((CX + 300)) $((MY + 700))
  kglob "Ectoview"; hold 1600
  film start overflow; film_wait overflow
  hold 600; glide $((MX + MW - 47)) $((MY + 52)) 800; hold 300; press; hold 1200; film_mark paged
  glide $((MX + 47)) $((MY + 52)) 900; hold 300; press; hold 1400
  film_end
}

readme_run() {
  readme_geometry
  readme_start_film
  echo "scene $README_SCENE main $MX $MY $MW $MH" >> "$OUT/readme.log"
  "scene_$README_SCENE"
  film quit; sleep 0.5
}
