#!/usr/bin/env bash
# build.sh — install the lock screen: owl-lock, then i3lock-color patched with
# the box indicator.
#
#   --keep          leave the build tree behind for inspection
#   --wrapper-only  install owl-lock and stop; no compiler, no network
#   --yes, -y       install missing build dependencies without asking
#
# This is the only thing that installs any part of the lock screen.
# kali-deploy-physical used to write owl-lock and betterlockscreenrc itself and
# no longer does: it calls this instead, so there is one place that owns the
# lock screen rather than two that can disagree about it.
#
# Order matters here and is not incidental. owl-lock goes in FIRST, before the
# dependency check and before anything is compiled, because it is five lines
# with no build requirements and it is the piece that decides whether a failed
# lock leaves the screen open. The patched binary is the cosmetic half. So a
# machine where the build fails -- no network, no compiler, an upstream tag that
# moved -- still ends up locking correctly, falling back to the stock i3lock
# with its circle. Ugly and safe beats pretty and open.
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
WRAPPER_ONLY=0
ASSUME_YES=0
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        --wrapper-only) WRAPPER_ONLY=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "build.sh: unknown option '$a'" >&2; exit 1 ;;
    esac
done

# The deploy script runs as root and has no sudo in its environment worth
# relying on; a user running this by hand does. Resolve it once rather than
# sprinkling `sudo` through the install steps.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    echo "build.sh: need root or sudo to install into /usr/local" >&2
    exit 1
fi

# --- owl-lock, first and unconditionally -----------------------------------
#
# Before the dep check, before the clone, before the compiler. See the header:
# this is the piece that must be present for the screen to lock at all, and it
# costs nothing to install.
[ -f "$HERE/owl-lock" ] || { echo "build.sh: no owl-lock at $HERE" >&2; exit 1; }
$SUDO install -m 755 "$HERE/owl-lock" /usr/local/bin/owl-lock
echo "==> installed /usr/local/bin/owl-lock"

if [ "$WRAPPER_ONLY" -eq 1 ]; then
    echo "done (--wrapper-only: patched i3lock not built)"
    exit 0
fi

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
    if [ "$ASSUME_YES" -eq 1 ]; then
        # Non-interactive path, used by kali-deploy-physical. The deps live here
        # rather than in the deploy script's package list so that the lock
        # screen stays one self-contained thing: whatever building it needs is
        # this script's business, and a deploy does not carry eighteen -dev
        # packages it would otherwise never mention.
        echo "==> installing build dependencies: ${missing[*]}"
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${missing[@]}" \
            || { echo "build.sh: could not install build dependencies" >&2; exit 1; }
    else
        echo "build.sh: missing build dependencies. Run:" >&2
        echo >&2
        echo "    sudo apt-get install -y ${missing[*]}" >&2
        echo >&2
        echo "or re-run this script with --yes to install them automatically." >&2
        exit 1
    fi
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
echo "==> installing /usr/local/bin/i3lock"
$SUDO install -m 755 "$BINARY" /usr/local/bin/i3lock
$SUDO install -d -m 755 /usr/local/share/man/man1
$SUDO install -m 644 i3lock.1 /usr/local/share/man/man1/i3lock.1

echo
echo "done. /usr/local/bin/i3lock now shadows /usr/bin/i3lock:"
command -v i3lock
i3lock --version
