#!/bin/bash
# Makes the README's pictures again: films every scene in tests/e2e/readme-scenes.sh in the
# off-screen KWin (nothing opens on your desktop, your screen is never captured), then cuts the films
# into docs/pictures/ with tools/readme-pictures.py. Run it whenever a part the pictures show changes.
# usage: tools/readme-pictures.sh [SCENE ...]      (the films stay in build/readme-films/)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FILMS=$ROOT/build/readme-films
SCENES=${*:-$(sed -n 's/^SCENES="\(.*\)"$/\1/p' tests/e2e/readme-scenes.sh)}
mkdir -p "$FILMS"
for scene in $SCENES; do
  echo "== $scene"
  rm -rf "${FILMS:?}/$scene"
  SCENARIO=readme-$scene timeout 400 tests/e2e/run.sh "$FILMS/$scene" > "$FILMS/$scene.log" 2>&1 || true
  if [ ! -e "$FILMS/$scene/film/stopped" ] && ! ls "$FILMS/$scene/film/"*.done > /dev/null 2>&1; then
    echo "$scene: nothing filmed (build/readme-films/$scene.log)" >&2; exit 1
  fi
  if grep -q "never came" "$FILMS/$scene/readme.log" 2>/dev/null; then
    echo "$scene: $(grep -m1 "never came" "$FILMS/$scene/readme.log")" >&2; exit 1
  fi
done
python3 -I tools/readme-pictures.py "$FILMS" docs/pictures --scenes $SCENES
