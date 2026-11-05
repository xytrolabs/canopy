#!/bin/sh
# build-compositor.sh — build the vendored compositor fork.
#
#   sh scripts/build-compositor.sh              # build (debug, fast)
#   sh scripts/build-compositor.sh release      # optimised
#   sh scripts/build-compositor.sh clean        # wipe the build directory
#
# The compositor lives in compositor/ as a squashed subtree of upstream
# Umbriel. It is not the default session yet; docs/COMPOSITOR_FORK.md has the
# plan and the rebrand surface.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${CANOPY_COMPOSITOR_SRC:-$PROJECT_DIR/compositor}"
BUILD_DIR="${CANOPY_COMPOSITOR_BUILD:-$PROJECT_DIR/build-compositor}"
TARGET="${1:-debug}"

say() { printf '%s\n' "$*"; }

[ -f "$SRC/meson.build" ] || {
    say "error: $SRC/meson.build is missing — is the subtree present?" >&2
    exit 1
}

if [ "$TARGET" = "clean" ]; then
    rm -rf "$BUILD_DIR"
    say ">> removed $BUILD_DIR"
    exit 0
fi

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
    case "$TARGET" in
        release) BUILD_TYPE=release ;;
        debug) BUILD_TYPE=debugoptimized ;;
        *) say "error: unknown target '$TARGET' (debug|release|clean)" >&2; exit 1 ;;
    esac
    say ">> configuring compositor ($BUILD_TYPE)"
    meson setup "$BUILD_DIR" "$SRC" --buildtype="$BUILD_TYPE"
fi

say ">> building compositor"
meson compile -C "$BUILD_DIR"

BIN="$BUILD_DIR/umbriel"
[ -x "$BIN" ] || { say "error: $BIN was not produced" >&2; exit 1; }
say ">> built $BIN"

# Name resolution for the fork's IPC, as the shell expects it:
#   $XDG_RUNTIME_DIR/<binary>-<WAYLAND_DISPLAY>.sock, exported as UMBRIEL_SOCKET
say ""
say "Run it under the shell with:"
say "  CANOPY_COMPOSITOR_BUILD=$BIN sh scripts/canopy-session --compositor umbriel"