#!/usr/bin/env bash
# build.sh — build i3lock-color with the box indicator patch applied.
#
#   --keep    leave the build tree behind for inspection
#
# The patched binary goes to /usr/local/bin/i3lock, which precedes /usr/bin on
# PATH. The distro package stays exactly where it is, still owned by dpkg: this
# adds a binary, it does not replace one. `sudo rm /usr/local/bin/i3lock` is the
# whole of the uninstall, and betterlockscreen goes back to the stock locker on
# the next lock with nothing else to undo.
#
# That also means an i3lock-color upgrade from the archive does NOT rebuild
# this. Re-run the script after one. The version pinned below is the version
# the patch was written against; if apt has moved on, the checkout still
# matches the patch and the build stays reproducible -- at the cost of missing
# whatever upstream fixed, which is why UPSTREAM_TAG is worth revisiting rather
# than trusting forever.
set -euo pipefail

UPSTREAM_TAG="2.13.c.5"
UPSTREAM_URL="https://github.com/Raymo111/i3lock-color.git"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/box-indicator.patch"

KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

# Build deps. Listed here rather than in a README so that the failure mode is a
# printable command instead of a compiler error forty lines deep.
DEPS=(
    build-essential autoconf pkg-config
    libpam0g-dev libcairo2-dev libev-dev libjpeg-dev libgif-dev
    libfontconfig-dev
    libxcb1-dev libxcb-composite0-dev libxcb-xinerama0-dev libxcb-randr0-dev
    libxcb-xkb-dev libxcb-image0-dev libxcb-util-dev libxcb-xrm-dev
    libxkbcommon-dev libxkbcommon-x11-dev
)

missing=()
for d in "${DEPS[@]}"; do
    dpkg -s "$d" >/dev/null 2>&1 || missing+=("$d")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "build.sh: missing build dependencies. Run:" >&2
    echo >&2
    echo "    sudo apt-get install -y ${missing[*]}" >&2
    echo >&2
    exit 1
fi

[ -f "$PATCH" ] || { echo "build.sh: no patch at $PATCH" >&2; exit 1; }

BUILD="$(mktemp -d)"
cleanup() {
    if [ "$KEEP" -eq 1 ]; then
        echo "build tree kept at $BUILD"
    else
        rm -rf "$BUILD"
    fi
}
trap cleanup EXIT

echo "==> fetching i3lock-color $UPSTREAM_TAG"
git clone --quiet --branch "$UPSTREAM_TAG" --depth 1 "$UPSTREAM_URL" "$BUILD/src"

echo "==> applying box-indicator.patch"
git -C "$BUILD/src" apply --verbose "$PATCH"

echo "==> building"
cd "$BUILD/src"
autoreconf -fi >/dev/null
./configure --prefix=/usr/local >/dev/null

# `|| true`, and then check for the binary instead of trusting the exit status.
# Upstream's Makefile recurses into an arch-named subdirectory and then re-runs
# the `all-configured` target in it, where no such rule exists -- so a build
# that has already linked i3lock successfully still ends on:
#
#     make[1]: *** No rule to make target 'all-configured'.  Stop.
#     make: *** [Makefile:2210: all-configured] Error 2
#
# That is upstream's build system, not the patch, and it happens with a clean
# tree too. The binary on disk is the honest signal here.
make -j"$(nproc)" >/dev/null 2>&1 || true

BINARY="$(find . -type f -name i3lock -perm -u+x -print -quit)"
if [ -z "$BINARY" ]; then
    echo "build.sh: build produced no i3lock binary" >&2
    exit 1
fi

# The patch is only useful if the flags it adds actually parse. i3lock reads
# options left to right, so a patched binary takes --box-indicator and then
# exits 0 on --version without ever touching the screen; an unpatched one bails
# on the unknown option first. Cheap, and it runs before anything is installed.
if ! "$BINARY" --box-indicator --version >/dev/null 2>&1; then
    echo "build.sh: built binary does not understand --box-indicator" >&2
    echo "          (did the patch apply to the right tag?)" >&2
    exit 1
fi

# Install by hand rather than `make install`: upstream's install target also
# lays down a systemd unit and a pam.d file, and the distro package already
# owns working copies of both. Overwriting a working PAM config from a
# hand-built tree is exactly the way to end up locked out.
echo "==> installing /usr/local/bin/i3lock (needs sudo)"
sudo install -m 755 "$BINARY" /usr/local/bin/i3lock
sudo install -d -m 755 /usr/local/share/man/man1
sudo install -m 644 i3lock.1 /usr/local/share/man/man1/i3lock.1

# owl-lock goes in the same trip, because it is the thing that makes a failure
# here survivable: if the patched binary is missing or rejects a flag, this is
# what still gets the screen locked. Installing the rc without it would mean the
# one new failure mode this repo introduces has no net under it.
echo "==> installing /usr/local/bin/owl-lock"
sudo install -m 755 "$HERE/owl-lock" /usr/local/bin/owl-lock

echo
echo "done. /usr/local/bin/i3lock now shadows /usr/bin/i3lock:"
command -v i3lock
i3lock --version
