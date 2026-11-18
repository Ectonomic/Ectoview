#!/bin/bash
# The e2e scenarios on another Plasma: run.sh inside a clean container of a distribution, with
# that distribution's KWin, Plasma shell, Spectacle and apps, on this computer's graphics (never
# NVIDIA's card). Made to prove Ectoview on Plasma 6.8 while this desktop runs 6.7.
#
#   tests/e2e/container.sh OUT SCENARIO [SCENARIO ...]      (fedora:44, Plasma 6.8, by default)
#   IMAGE=registry.fedoraproject.org/fedora:45 tests/e2e/container.sh OUT smoke
# Each scenario's pictures and logs land in OUT/SCENARIO; the summary line of each is printed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../.." && pwd)
OUT=$(realpath -m "$1"); shift
[ $# -gt 0 ] || { echo "usage: $0 OUT SCENARIO [SCENARIO ...]" >&2; exit 2; }
mkdir -p "$OUT"
IMAGE=${IMAGE:-registry.fedoraproject.org/fedora:44}
GPU=()
for n in /sys/class/drm/renderD* /sys/class/drm/card[0-9]; do
    [ "$(cat "$n/device/vendor" 2>/dev/null)" = 0x10de ] && continue
    GPU+=(--device "/dev/dri/${n##*/}")
done
# the desktop the scenarios use, kept as an image named by its recipe
recipe="FROM $IMAGE
RUN dnf -y install kwin plasma-workspace plasma-desktop spectacle kscreen libkscreen konsole dolphin kate kcharselect \\
    plasma-milou libplasma kf6-kirigami kf6-ksvg kf6-kcmutils qt6-qt5compat kf6-kpackage kf6-kconfig \\
    qt6-qttools python3 python3-pillow python3-numpy python3-dbus libei glib2 dbus-daemon mesa-dri-drivers \\
    gcc pkgconf-pkg-config wayland-devel plasma-wayland-protocols-devel procps-ng findutils diffutils \\
    breeze-icon-theme google-noto-sans-fonts f44-backgrounds-kde && dnf clean all
RUN useradd -m -s /bin/bash tester"
tag=localhost/ectoview-e2e-$(printf '%s' "$IMAGE" | tr -c 'a-z0-9' '-' | sed 's/-*$//'):$(printf '%s' "$recipe" | sha1sum | cut -c1-12)
if ! podman image exists "$tag"; then
    printf '%s\n' "$recipe" | podman build -t "$tag" -f - "$HERE" > "$OUT/image.log" 2>&1 \
        || { echo "the desktop image didn't build ($OUT/image.log)"; tail -20 "$OUT/image.log"; exit 1; }
fi
# the source as git has it, in a folder named ectoview as a clone is (Konsole titles its window
# after its folder, and the search scenarios look for "ectoview"); the scenarios fake-input helper is built inside, for that system)
COPY=$(mktemp -d "${TMPDIR:-/tmp}/ectoview-e2e-src.XXXXXX"); trap 'rm -rf "$COPY"' EXIT
( cd "$SRC" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
    | tar -cf - --null --no-recursion -T - ) | tar -xf - -C "$COPY"
chmod -R a+rwX "$COPY" "$OUT"
podman run --rm "${GPU[@]}" --user tester --userns=keep-id:uid=1000,gid=1000 -v "$COPY:/work/ectoview:Z" -v "$OUT:/out:Z" "$tag" bash -c '
    cd /work/ectoview && echo "KWin $(rpm -q --qf %{VERSION} kwin)"
    # a copy of KWin: the installed one carries file capabilities, which a rootless container cannot grant
    cp "$(command -v kwin_wayland)" /tmp/kwin_wayland; export KWIN_BIN=/tmp/kwin_wayland
    # the harness calls the Qt tool qdbus by that name; Fedora calls it qdbus-qt6
    mkdir -p /tmp/bin; for q in qdbus-qt6 qdbus6; do command -v $q >/dev/null && { ln -sf "$(command -v $q)" /tmp/bin/qdbus; break; }; done; export PATH=/tmp/bin:$PATH
    for sc in '"$*"'; do
        E2E_IN_CONTAINER=1 SCENARIO=$sc tests/e2e/run.sh /out/$sc > /out/$sc.txt 2>&1
        grep -E "[0-9]+ of [0-9]+ passed" /out/$sc.txt | tail -1 || echo "$sc: no result (see $sc.txt)"
        grep -E "^\s+FAIL" /out/$sc.txt | head -5
    done'
