#!/bin/sh
# build-quickshell.sh — build the shell runtime where no package provides it.
#
# Needed on Debian (trixie backports has 0.3.0, forky has 0.3.2) and on Fedora
# releases before quickshell was packaged. Arch/CachyOS users should not need
# this: quickshell 0.3.2 is in `extra`.
#
#   sh scripts/build-quickshell.sh                 # build + install (sudo)
#   sh scripts/build-quickshell.sh --prefix OKAY   # build only, install later
#   TAG=v0.3.2 sh scripts/build-quickshell.sh      # pin a different tag
#
# Canopy needs the 0.3.x API (Networking, PipeWire, Pam, Bluetooth services).
# The script refuses older tags rather than building something that will fail
# at runtime with a wall of "module not installed".
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

TAG="${TAG:-v0.3.2}"
SRC_DIR="${SRC_DIR:-${TMPDIR:-/tmp}/quickshell-build}"
PREFIX="${PREFIX:-/usr/local}"
BUILD_ONLY=0

for a in "$@"; do
    case "$a" in
        --build-only) BUILD_ONLY=1 ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) printf 'unknown option: %s\n' "$a" >&2; exit 2 ;;
    esac
done

say() { printf '>> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "$TAG" in
    v0.3.*|0.3.*) ;;
    *) die "Canopy needs quickshell 0.3.x; refusing to build $TAG" ;;
esac

say "distribution : $(canopy_distro_name) ($(canopy_family))"
say "target       : $TAG -> $PREFIX"

for c in git cmake ninja; do
    command -v "$c" >/dev/null 2>&1 || {
        say "missing build tool: $c"
        say "install: $(canopy_pkgs build)"
        die "cannot continue"
    }
done

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

if [ -d "$SRC_DIR/.git" ]; then
    say "updating existing checkout"
    git -C "$SRC_DIR" fetch --tags --depth 1 origin "$TAG" || true
    git -C "$SRC_DIR" checkout -q "$TAG"
else
    say "cloning"
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "$TAG" \
        https://github.com/quickshell-mirror/quickshell.git "$SRC_DIR"
fi

say "configuring"
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DDISTRIBUTOR=Canopy

say "building (this takes a few minutes)"
cmake --build "$SRC_DIR/build"

if [ "$BUILD_ONLY" -eq 1 ]; then
    say "build complete: $SRC_DIR/build"
    say "install later with: sudo cmake --install $SRC_DIR/build"
    exit 0
fi

say "installing"
$SUDO cmake --install "$SRC_DIR/build"

if command -v quickshell >/dev/null 2>&1; then
    say "installed: $(command -v quickshell)"
    quickshell --version 2>/dev/null | head -1 || true
else
    die "install finished but quickshell is not on PATH (check $PREFIX/bin)"
fi
