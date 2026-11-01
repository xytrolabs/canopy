#!/bin/sh
# build-wlroots.sh — build the compositor library labwc 0.20 needs.
#
# Debian trixie ships wlroots 0.18.2, which labwc 0.20.x cannot build against.
# Arch and Fedora 45 already have 0.20.x, so this is only for the Debian family
# (Willow Core and anyone running Canopy on a stable Debian/Ubuntu base).
#
#   sh scripts/build-wlroots.sh
#   TAG=0.20.2 PREFIX=/usr/local sh scripts/build-wlroots.sh
#
# Build wlroots before scripts/build-labwc.sh, and keep the prefix identical so
# pkg-config finds the new library.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

TAG="${TAG:-0.20.2}"
SRC_DIR="${SRC_DIR:-${TMPDIR:-/tmp}/wlroots-build}"
PREFIX="${PREFIX:-/usr/local}"
BUILD_ONLY=0

for a in "$@"; do
    case "$a" in
        --build-only) BUILD_ONLY=1 ;;
        --help|-h) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown option: %s\n' "$a" >&2; exit 2 ;;
    esac
done

say() { printf '>> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

say "distribution : $(canopy_distro_name) ($(canopy_family))"
say "target       : wlroots $TAG -> $PREFIX"

for c in git meson ninja; do
    command -v "$c" >/dev/null 2>&1 || {
        say "missing build tool: $c"
        say "install: $(canopy_pkgs build)"
        die "cannot continue"
    }
done

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

if [ -d "$SRC_DIR/.git" ]; then
    git -C "$SRC_DIR" fetch --tags --depth 1 origin "$TAG" || true
    git -C "$SRC_DIR" checkout -q "$TAG"
else
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "$TAG" https://gitlab.freedesktop.org/wlroots/wlroots.git "$SRC_DIR"
fi

say "configuring"
meson setup --prefix="$PREFIX" --buildtype=release "$SRC_DIR/build" "$SRC_DIR" \
    -Dexamples=false -Dtests=false

say "building"
ninja -C "$SRC_DIR/build"

if [ "$BUILD_ONLY" -eq 1 ]; then
    say "build complete: $SRC_DIR/build"
    exit 0
fi

say "installing"
$SUDO ninja -C "$SRC_DIR/build" install
$SUDO ldconfig 2>/dev/null || true

say "installed: $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" pkg-config --modversion wlroots 2>/dev/null || echo 'not visible to pkg-config')"
say "next: sh scripts/build-labwc.sh"
