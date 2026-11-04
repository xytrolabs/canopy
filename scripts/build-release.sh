#!/bin/sh
# build-release.sh — package Canopy into a single self-extracting installer.
#
# Produces: dist/canopy-<version>.run
#
#   sh scripts/build-release.sh                 # build + package
#   CANOPY_VERSION=2026.11.04 sh scripts/build-release.sh
#   CANOPY_SKIP_BUILD=1 sh scripts/build-release.sh   # package an existing build
#
# The payload contains the binary, the asset bundle, the session entry, the
# desktop portal config and every script needed to install, update or uninstall
# Canopy offline:
#
#   sh canopy-<version>.run          user install
#   sudo sh canopy-<version>.run     system install + Wayland session
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${CANOPY_VERSION:-$(tr -d ' \t\r\n' < "$PROJECT_DIR/VERSION" 2>/dev/null || date -u +%Y.%m.%d)}"
VERSION="$(printf '%s' "$VERSION" | sed 's/^v//')"
DIST="$PROJECT_DIR/dist"
STAGE="$DIST/stage"
OUT="$DIST/canopy-$VERSION.run"
BUILD_DIR="${CANOPY_BUILD_DIR:-$PROJECT_DIR/build-release}"

say() { printf '%s\n' "$*"; }

# ---- Build ---------------------------------------------------------------
if [ "${CANOPY_SKIP_BUILD:-0}" != "1" ]; then
    say ">> building Canopy $VERSION"
    if command -v just >/dev/null 2>&1; then
        just configure release >/dev/null
        just build release
    else
        meson setup "$BUILD_DIR" --buildtype=release -Dcpp_std=c++23 -Db_lto=true --prefix=/usr/local >/dev/null
        meson compile -C "$BUILD_DIR"
    fi
fi

[ -x "$BUILD_DIR/canopy" ] || { say "error: $BUILD_DIR/canopy is missing" >&2; exit 1; }

# ---- Stage ---------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/assets" "$STAGE/config" "$STAGE/scripts" "$STAGE/share"

cp "$BUILD_DIR/canopy" "$STAGE/bin/canopy"
cp -a "$PROJECT_DIR"/assets/. "$STAGE/assets/"
cp -a "$PROJECT_DIR"/config/. "$STAGE/config/"
cp -a "$PROJECT_DIR"/scripts/. "$STAGE/scripts/"
cp "$PROJECT_DIR/README.md" "$STAGE/share/README.md" 2>/dev/null || true
cp "$PROJECT_DIR/LICENSE" "$STAGE/share/LICENSE" 2>/dev/null || true
cp "$PROJECT_DIR/docs/CANOPY_DESIGN.md" "$STAGE/share/CANOPY_DESIGN.md" 2>/dev/null || true
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

# The login greeter is part of the desktop, so it ships in the same payload when
# it has been built. `install.sh --with-greeter` picks it up from greeter/build.
GREETER_BUILD="${CANOPY_GREETER_BUILD:-$PROJECT_DIR/greeter/build}"
if [ -x "$GREETER_BUILD/canopy-greeter" ]; then
    say ">> including Canopy Greeter"
    mkdir -p "$STAGE/greeter/build"
    for b in canopy-greeter canopy-greeter-compositor canopy-greeter-apply-appearance; do
        [ -x "$GREETER_BUILD/$b" ] && cp "$GREETER_BUILD/$b" "$STAGE/greeter/build/$b"
    done
    mkdir -p "$STAGE/greeter/scripts" "$STAGE/greeter/assets"
    cp "$PROJECT_DIR/greeter/scripts/canopy-greeter-session" "$STAGE/greeter/scripts/" 2>/dev/null || true
    cp -a "$PROJECT_DIR"/greeter/assets/. "$STAGE/greeter/assets/" 2>/dev/null || true
fi

# The payload's installer expects the layout of a source tree.
mv "$STAGE/bin/canopy" "$STAGE/canopy"
rmdir "$STAGE/bin"

# ---- Header --------------------------------------------------------------
cat > "$OUT" <<'HEADER'
#!/bin/sh
# =====================================================================
#  Canopy - the Xytro Labs desktop environment
#
#  One file containing the whole desktop: the shell, its assets, the
#  Labwc session configuration, the desktop portal setup and the
#  install / update / uninstall scripts.
#
#    sh canopy-*.run           install for the current user
#    sudo sh canopy-*.run      install system-wide, register the session
# =====================================================================
set -e

PAYLOAD_LINE=$(awk '/^__CANOPY_PAYLOAD_BELOW__$/ { print NR + 1; exit 0; }' "$0")
WORKDIR="${TMPDIR:-/tmp}/canopy-install-$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

echo ">> extracting Canopy..."
tail -n +"$PAYLOAD_LINE" "$0" | tar -xzf - -C "$WORKDIR"

# The payload is laid out like a source tree, which is what install.sh expects.
if [ "$(id -u)" -eq 0 ]; then
    DEST=/usr/local/share/canopy-src
    mkdir -p "$DEST"
    cp -a "$WORKDIR"/. "$DEST"/
    CANOPY_BUILD_DIR="$DEST" sh "$DEST/scripts/install.sh"
    # The shell runs from the user's own session, so a system install also
    # refreshes that user's copy of the configuration and helpers.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
            echo ">> refreshing $SUDO_USER's Canopy configuration"
            su "$SUDO_USER" -s /bin/sh -c \
                "HOME='$USER_HOME' CANOPY_BUILD_DIR='$DEST' sh '$DEST/scripts/install.sh'" || true
        fi
    fi
    rm -rf "$DEST"
    echo
    echo ">> Canopy installed system-wide."
    echo "   Log out and pick \"Canopy\" in your display manager,"
    echo "   or start it from a TTY with:  canopy-session"
else
    CANOPY_BUILD_DIR="$WORKDIR" sh "$WORKDIR/scripts/install.sh"
    echo
    echo ">> Canopy installed for $(id -un)."
fi

echo
echo "## helpers"
echo "  canopy-update check          # is there a newer release?"
echo "  canopy-session               # start the desktop"
echo "  sh scripts/uninstall.sh      # remove it again"

# Only mention dependencies when something is actually missing: printing a
# warning on a machine that already has them reads like the install failed.
_missing_deps=""
command -v labwc >/dev/null 2>&1 || _missing_deps="$_missing_deps labwc"
command -v xdg-desktop-portal >/dev/null 2>&1 || _missing_deps="$_missing_deps xdg-desktop-portal"
if [ -n "$_missing_deps" ]; then
    echo ""
    echo "missing runtime pieces:$_missing_deps"
    echo "  sh scripts/deps.sh plan     # what is missing, and how to install it"
fi
echo ""
echo "Done."
exit 0

__CANOPY_PAYLOAD_BELOW__
HEADER

tar -czf - -C "$STAGE" . >> "$OUT"
chmod +x "$OUT"

say "built: $OUT ($(du -h "$OUT" | cut -f1))"