#!/bin/bash
# install.sh and uninstall.sh on other people's computers: for each distribution, a clean
# container with KDE Plasma's KWin, a new user ("stranger") who has never run Ectoview, and
# this source folder as a fresh copy (only the files git tracks, as a clone has them).
# The stranger runs ./install.sh --yes inside a headless KWin session; inside.sh judges what
# it did, then uninstalls and judges that too. Too-old distributions must be refused with
# nothing changed. (Ectolens's tests/install/stranger-check.sh, adapted.)
#
#   tests/install/stranger-check.sh [DISTRO ...]     (default: all of them)
#   OUT=dir  keeps the logs there (default build/stranger-check)
#   PLANT="a.patch b.patch"  applies planted faults to the copy first (tests/install/plants/),
#                     to prove a check catches each: the run must then fail where each patch says
#
# Needs rootless podman and network access for the packages. Nothing runs on this desktop,
# and nothing of this computer's user goes in.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../.." && pwd)
OUT=$(realpath -m "${OUT:-$SRC/build/stranger-check}")
mkdir -p "$OUT"

# name | image | how to install the desktop (KWin and the QML modules a Plasma desktop has, under the
# names install.sh asks for, so a wrong name fails here; its D-Bus and GLib's gdbus, Mesa) and sudo |
# expect. The Plasma each has (November 17, 2026): Fedora 44 and 45, Arch, Tumbleweed and KDE
# neon 6.8, Debian testing 6.7, Ubuntu 26.04 6.6 and Debian 13 6.3 (too old).
DISTROS=(
  "fedora-44|registry.fedoraproject.org/fedora:44|dnf -y install kwin plasma-milou libplasma kf6-kirigami kf6-ksvg kf6-kcmutils qt6-qt5compat qt6-qtdeclarative sudo procps-ng glib2 dbus-daemon findutils mesa-dri-drivers diffutils|installs"
  "fedora-45|registry.fedoraproject.org/fedora:45|dnf -y install kwin plasma-milou libplasma kf6-kirigami kf6-ksvg kf6-kcmutils qt6-qt5compat qt6-qtdeclarative sudo procps-ng glib2 dbus-daemon findutils mesa-dri-drivers diffutils|installs"
  "tumbleweed|registry.opensuse.org/opensuse/tumbleweed:latest|zypper -n refresh && zypper -n install --force-resolution kwin6 milou6 libplasma6-components kf6-kirigami-imports kf6-ksvg-imports kf6-kcmutils-imports kf6-kcmutils qt6-qt5compat-imports qt6-declarative-imports sudo procps glib2-tools dbus-1-daemon findutils Mesa-dri diffutils|installs"
  "arch|docker.io/library/archlinux:latest|pacman -Syu --noconfirm kwin milou libplasma kirigami ksvg kcmutils qt6-5compat qt6-declarative sudo procps-ng glib2 dbus mesa diffutils|installs"
  "debian-testing|docker.io/library/debian:testing|apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y kwin-wayland qml6-module-org-kde-milou plasma-desktoptheme qml6-module-org-kde-kirigami qml6-module-org-kde-ksvg qml6-module-org-kde-kcmutils qml6-module-qt5compat-graphicaleffects qml6-module-qtquick qml6-module-qtquick-templates qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-controls sudo procps libglib2.0-bin dbus-daemon libgl1-mesa-dri libegl-mesa0|installs"
  "neon|invent-registry.kde.org/neon/docker-images/plasma:user|apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y sudo procps libglib2.0-bin libgl1-mesa-dri libegl-mesa0|installs"
  "ubuntu-26.04|docker.io/library/ubuntu:26.04|apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y kwin-wayland sudo procps libglib2.0-bin dbus-daemon|refused"
  "debian-13|docker.io/library/debian:trixie|apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y kwin-wayland sudo procps libglib2.0-bin dbus-daemon|refused"
)
want=("$@")
for w in "${want[@]}"; do
    printf '%s\n' "${DISTROS[@]}" | cut -d'|' -f1 | grep -qxF "$w" \
        || { echo "no distribution called $w; the names: $(printf '%s\n' "${DISTROS[@]}" | cut -d'|' -f1 | tr '\n' ' ')" >&2; exit 1; }
done

# a share of this computer, at low priority, so a build that runs out fails in the container
CPUS=$(nproc); [ "$CPUS" -gt 16 ] && CPUS=16
MEM_GB=$(awk '/^MemTotal:/ { g = int($2 * 0.4 / 1048576); print (g > 24 ? 24 : (g < 4 ? 4 : g)) }' /proc/meminfo)

# KWin draws on a render node that isn't NVIDIA's (its card stays out of every test)
GPU=()
for n in /sys/class/drm/renderD*; do
    [ "$(cat "$n/device/vendor" 2>/dev/null)" = 0x10de ] && continue
    GPU=(--device "/dev/dri/${n##*/}"); break
done
[ ${#GPU[@]} -gt 0 ] || { echo "no render node other than NVIDIA's; KWin can't draw in the containers" >&2; exit 1; }

# the source as a stranger would clone it: the files git tracks (and new ones not ignored), no build
COPY=$(mktemp -d "${TMPDIR:-/tmp}/ectoview-stranger.XXXXXX"); trap 'rm -rf "$COPY"' EXIT
( cd "$SRC" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
    | tar -cf - --null --no-recursion -T - ) | tar -xf - -C "$COPY"
# what GitHub's copy leaves out (the mockups and their capture tool) is left out here too
rm -rf "$COPY/design" "$COPY/tests/capture"
for plant in ${PLANT:-}; do
    patch -s -p1 -d "$COPY" < "$(realpath "$plant")" || { echo "the plant $plant doesn't apply" >&2; exit 1; }
    echo "planted: $plant"
done
chmod -R a+rX "$COPY"   # the container's stranger is another user id
[ -f "$COPY/install.sh" ] && [ -f "$COPY/package/metadata.json" ] || { echo "copy is incomplete" >&2; exit 1; }

overall=0 ran=0
for row in "${DISTROS[@]}"; do
    IFS='|' read -r name image desktop expect <<<"$row"
    if [ ${#want[@]} -gt 0 ] && ! printf '%s\n' "${want[@]}" | grep -qxF "$name"; then continue; fi
    log=$OUT/$name.log
    ran=$((ran + 1))
    echo "== $name ($image), expected: $expect"
    # a desktop image per distribution, kept so a second run starts quicker (named by its recipe);
    # the build's own packages are never in it: install.sh has to find and install them every time
    # (sudo without PAM's account check: a rootless container can't run the helper that reads /etc/shadow)
    containerfile="FROM $image
USER root
RUN $desktop
RUN (id stranger >/dev/null 2>&1 || useradd -m -s /bin/bash stranger) && printf 'Defaults:stranger !pam_acct_mgmt\\nstranger ALL=(ALL) NOPASSWD: ALL\\n' > /etc/sudoers.d/stranger && chmod 440 /etc/sudoers.d/stranger"
    tag=localhost/ectoview-stranger-$name:$(printf '%s' "$containerfile" | sha1sum | cut -c1-12)
    if ! podman image exists "$tag"; then
        printf '%s\n' "$containerfile" | podman build -t "$tag" -f - "$HERE" >"$OUT/$name.image.log" 2>&1 \
            || { echo "FAIL  $name: the desktop image didn't build ($OUT/$name.image.log)"; overall=1; continue; }
    fi
    rc=0
    podman run --rm --memory=${MEM_GB}g --memory-swap=${MEM_GB}g --cpus="$CPUS" --cpu-shares=128 "${GPU[@]}" \
        --user stranger --workdir /home/stranger -v "$COPY:/src:ro,Z" -v "$HERE/inside.sh:/inside.sh:ro,Z" "$tag" \
        bash -c 'cp -r /src /home/stranger/Ectoview &&
                 exec env -i HOME=/home/stranger USER=stranger LOGNAME=stranger LANG=C.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin CMAKE_BUILD_PARALLEL_LEVEL='"$CPUS"' \
                     bash /inside.sh '"$expect" >"$log" 2>&1 || rc=$?
    grep -E '^(PASS|FAIL|NOTE) ' "$log" | sed "s/^/  /" || true
    if [ "$rc" != 0 ] || grep -q '^FAIL ' "$log" || ! grep -q '^PASS ' "$log"; then
        echo "FAIL  $name (exit $rc, log $log)"; overall=1
    else
        echo "PASS  $name"
    fi
done
[ "$ran" -gt 0 ] || { echo "nothing was checked" >&2; exit 1; }
exit $overall
