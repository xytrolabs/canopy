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

# The compositor is part of the desktop, not an optional extra: build it when it
# is missing so a release never ships a session that falls back to labwc.
COMPOSITOR_BUILD="${CANOPY_COMPOSITOR_BUILD:-$PROJECT_DIR/build-compositor}"
if [ "${CANOPY_SKIP_COMPOSITOR:-0}" != "1" ] && [ ! -x "$COMPOSITOR_BUILD/canopywc" ]; then
    say ">> building the compositor (canopywc)"
    if [ -f "$COMPOSITOR_BUILD/build.ninja" ]; then
        meson compile -C "$COMPOSITOR_BUILD"
    else
        meson setup "$COMPOSITOR_BUILD" "$PROJECT_DIR/compositor" --buildtype=release >/dev/null
        meson compile -C "$COMPOSITOR_BUILD"
    fi
fi

# ---- Stage ---------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/assets" "$STAGE/config" "$STAGE/scripts" "$STAGE/share"

cp "$BUILD_DIR/canopy" "$STAGE/bin/canopy"
if [ -x "$COMPOSITOR_BUILD/canopywc" ]; then
    say ">> including canopywc"
    mkdir -p "$STAGE/compositor"
    cp "$COMPOSITOR_BUILD/canopywc" "$STAGE/compositor/canopywc"
else
    say "error: canopywc is required in every Canopy release but is missing" >&2
    exit 1
fi
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

# install.sh locates the binaries through CANOPY_BUILD_DIR and expects them at the root of
# that directory, while the payload stages them under bin/ and compositor/. Copy (not
# symlink) so the layout survives the system install's relocation to /usr/local/share.
if [ -x "$WORKDIR/bin/canopy" ]; then
    cp -f "$WORKDIR/bin/canopy" "$WORKDIR/canopy"
fi
if [ -x "$WORKDIR/compositor/canopywc" ] && [ ! -x "$WORKDIR/canopywc" ]; then
    cp -f "$WORKDIR/compositor/canopywc" "$WORKDIR/canopywc"
fi

# Fail loudly and specifically if the payload is malformed, rather than letting a
# generic error from a deeper script appear after a successful checksum.
if [ ! -x "$WORKDIR/canopy" ]; then
    echo "error: this payload has no canopy binary; it is not a complete Canopy release." >&2
    exit 1
fi

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

# Runtime dependencies come from the distribution's own package manager, so this
# is one command rather than a "now go install these 20 packages" list. It only
# runs when something is actually missing, and stops at the first failure rather
# than leaving a half-working desktop.
if [ "${CANOPY_SKIP_DEPS:-0}" != "1" ] && [ -x "$WORKDIR/scripts/deps.sh" ]; then
    echo ""
    echo ">> checking runtime dependencies"
    # deps.sh plan always exits 0 (it is a report), so look at what it says rather than
    # at the status. "missing      : nothing on this machine" is the satisfied case.
    _deps_report="$(sh "$WORKDIR/scripts/deps.sh" plan 2>/dev/null || true)"
    if printf '%s\n' "$_deps_report" | grep -q 'missing      : nothing on this machine'; then
        echo "   all runtime pieces present"
    else
        echo "   some runtime pieces are missing."
        _missing_list="$(printf '%s\n' "$_deps_report" | awk '/^missing      :/ { sub(/^[^:]*: */, ""); print }')"
        [ -n "$_missing_list" ] && echo "   missing:$_missing_list"
        if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
            printf '   install them now with the system package manager? [Y/n] '
            read -r _answer </dev/tty 2>/dev/null || _answer=y
            case "${_answer:-y}" in
                [Nn]*) echo "   skipped: run 'sh scripts/deps.sh install' yourself." ;;
                *)     sh "$WORKDIR/scripts/deps.sh" install || {
                           echo "error: dependency install failed; fix the packages above and re-run." >&2
                           exit 1
                       } ;;
            esac
        else
            echo "   install them with: sh scripts/deps.sh install"
        fi
    fi
fi

_missing_deps=""
command -v canopywc >/dev/null 2>&1 || _missing_deps="$_missing_deps canopywc"
command -v xdg-desktop-portal >/dev/null 2>&1 || _missing_deps="$_missing_deps xdg-desktop-portal"
if [ -n "$_missing_deps" ]; then
    echo ""
    echo "missing runtime pieces:$_missing_deps"
    echo "  sh scripts/deps.sh install   # install them now"
fi
echo ""
echo "Done."
exit 0
__CANOPY_PAYLOAD_BELOW__
HEADER

tar -czf - -C "$STAGE" . >> "$OUT"
chmod +x "$OUT"

say "built: $OUT ($(du -h "$OUT" | cut -f1))"