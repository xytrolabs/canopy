#!/bin/sh
# build-labwc.sh — build labwc where the packaged version is too old.
#
# Canopy is developed against labwc 0.20.x. Arch and Fedora 45 carry it; Debian
# trixie ships 0.8.3, which is a different era of the compositor, so Core builds
# it from source until forky lands.
#
#   sh scripts/build-labwc.sh
#   TAG=0.20.2 PREFIX=/usr/local sh scripts/build-labwc.sh
#
# labwc needs wlroots of the same generation. The script checks pkg-config and
# stops with a clear message instead of producing a binary that segfaults.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

TAG="${TAG:-0.20.2}"
SRC_DIR="${SRC_DIR:-${TMPDIR:-/tmp}/labwc-build}"
PREFIX="${PREFIX:-/usr/local}"
BUILD_ONLY=0

for a in "$@"; do
    case "$a" in
        --build-only) BUILD_ONLY=1 ;;
        --help|-h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown option: %s\n' "$a" >&2; exit 2 ;;
    esac
done

say() { printf '>> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

WANT_WLROOTS="${WANT_WLROOTS:-0.20}"
say "distribution : $(canopy_distro_name) ($(canopy_family))"
say "target       : labwc $TAG -> $PREFIX"

for c in git meson ninja pkg-config; do
    command -v "$c" >/dev/null 2>&1 || {
        say "missing build tool: $c"
        say "install: $(canopy_pkgs build)"
        die "cannot continue"
    }
done

HAVE_WLROOTS="$(pkg-config --modversion wlroots 2>/dev/null || true)"
if [ -z "$HAVE_WLROOTS" ]; then
    die "wlroots development files not found - install $(canopy_pkgs build)"
fi
case "$HAVE_WLROOTS" in
    "$WANT_WLROOTS"*) say "wlroots $HAVE_WLROOTS (matches)" ;;
    *)
        die "labwc $TAG needs wlroots $WANT_WLROOTS.x, this machine has $HAVE_WLROOTS.
       Build wlroots $WANT_WLROOTS first, or use the packaged labwc." ;;
esac

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

if [ -d "$SRC_DIR/.git" ]; then
    git -C "$SRC_DIR" fetch --tags --depth 1 origin "$TAG" || true
    git -C "$SRC_DIR" checkout -q "$TAG"
else
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "$TAG" https://github.com/labwc/labwc.git "$SRC_DIR"
fi

say "configuring"
meson setup --prefix="$PREFIX" --buildtype=release "$SRC_DIR/build" "$SRC_DIR"

say "building"
ninja -C "$SRC_DIR/build"

if [ "$BUILD_ONLY" -eq 1 ]; then
    say "build complete: $SRC_DIR/build"
    exit 0
fi

say "installing"
$SUDO ninja -C "$SRC_DIR/build" install
if command -v labwc >/dev/null 2>&1; then
    say "installed: $(command -v labwc)"
else
    die "install finished but labwc is not on PATH (check $PREFIX/bin)"
fi
