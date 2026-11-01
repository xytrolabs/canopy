#!/bin/sh
# build-release.sh - package Canopy into a single self-extracting installer.
#
# Produces: dist/canopy-<version>.run
# The .run file contains the whole tree and installs with:
#     sh canopy-<version>.run            (user install: config + shell)
#     sudo sh canopy-<version>.run       (system install: also the DE session entry)
#
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Release identity. CI passes the tag (v2026.11.01 -> 2026.11.01) so the payload
# name, the installed VERSION file and the update check all agree.
VERSION="${CANOPY_VERSION:-$(date -u +%Y.%m.%d)}"
VERSION="$(printf '%s' "$VERSION" | sed 's/^v//')"
DIST="$PROJECT_DIR/dist"
STAGE="$DIST/stage"
OUT="$DIST/canopy-$VERSION.run"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

# ---- Collect the payload -------------------------------------------------
mkdir -p "$STAGE/shell" "$STAGE/config" "$STAGE/scripts"

cp -a "$PROJECT_DIR"/shell/. "$STAGE/shell/"
cp -a "$PROJECT_DIR"/config/. "$STAGE/config/"
# Assets ship with the payload: wallpapers, icons and the fonts used by the
# shell. Without this the installer's asset steps silently did nothing.
if [ -d "$PROJECT_DIR/assets" ]; then
    cp -a "$PROJECT_DIR"/assets "$STAGE/assets"
fi
cp -a "$PROJECT_DIR"/scripts/install.sh "$STAGE/scripts/install.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/gen-icon-map.py "$STAGE/scripts/gen-icon-map.py" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/canopy-screenshot.sh "$STAGE/scripts/canopy-screenshot.sh" 2>/dev/null || true
# Distribution knowledge travels with the payload: `deps.sh` and the source
# builders are how a user on Debian or an older Fedora gets a runtime.
cp -a "$PROJECT_DIR"/scripts/lib-distro.sh "$STAGE/scripts/lib-distro.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/deps.sh "$STAGE/scripts/deps.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/build-quickshell.sh "$STAGE/scripts/build-quickshell.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/build-wlroots.sh "$STAGE/scripts/build-wlroots.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/build-labwc.sh "$STAGE/scripts/build-labwc.sh" 2>/dev/null || true
cp -a "$PROJECT_DIR"/scripts/canopy-update.sh "$STAGE/scripts/canopy-update.sh" 2>/dev/null || true
# The version this payload is. install.sh copies it into the installed tree; the
# updater reads it to answer "what am I running?" without guessing from dates.
printf '%s\n' "$VERSION" > "$STAGE/VERSION"
cp -a "$PROJECT_DIR"/README.md "$STAGE/README.md" 2>/dev/null || true
cp -a "$PROJECT_DIR"/LICENSE "$STAGE/LICENSE" 2>/dev/null || true

# Drop anything that only makes sense in a dev tree
rm -f "$STAGE"/shell/_probe.qml

# ---- Self-extracting header ---------------------------------------------
cat > "$OUT" <<'HEADER'
#!/bin/sh
# =====================================================================
#  Canopy - a lightweight, modular Linux desktop environment
#  Xytro Labs
#
#  This single file contains the complete Canopy desktop: the Quickshell
#  shell, the Labwc compositor configuration, the icon index and the
#  installer.
#
#    sh canopy-*.run            install for the current user
#    sudo sh canopy-*.run       install system-wide + register the DE session
#
#  After installing, log out and pick "Canopy" at the display manager, or
#  start it from a TTY with:  labwc
# =====================================================================
set -e

SUDO=""
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

PAYLOAD_LINE=$(awk '/^__CANOPY_PAYLOAD_BELOW__$/ { print NR + 1; exit 0; }' "$0")
WORKDIR="${TMPDIR:-/tmp}/canopy-install-$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

echo ">> extracting Canopy..."
tail -n +"$PAYLOAD_LINE" "$0" | tar -xzf - -C "$WORKDIR"

if [ "$(id -u)" -eq 0 ]; then
    DEST=/usr/local/share/canopy
    mkdir -p "$DEST"
    cp -a "$WORKDIR"/. "$DEST"/
    SH_INSTALL="$DEST/scripts/install.sh"
    sh "$SH_INSTALL"
    # The shell actually runs from the user's own config directory (labwc
    # autostart starts `quickshell -c canopy`), so a system install must also
    # refresh the invoking user's copy - otherwise `sudo sh canopy.run` would
    # leave them running the previous build.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
            echo ">> refreshing $SUDO_USER's shell in $USER_HOME/.config/quickshell/canopy"
            su "$SUDO_USER" -s /bin/sh -c \
                "HOME='$USER_HOME' XDG_CONFIG_HOME='$USER_HOME/.config' sh '$SH_INSTALL'" || true
        fi
    fi
    # System integration: session entry + PATH launcher
    echo ">> registering the Canopy desktop session..."
    install -Dm644 "$DEST/config/canopy-session.desktop" \
        /usr/local/share/wayland-sessions/canopy.desktop
    cat > /usr/local/bin/canopy <<'LAUNCH'
#!/bin/sh
# Start the Canopy desktop environment.
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
    exec labwc
fi
exec quickshell -n -c canopy
LAUNCH
    chmod 755 /usr/local/bin/canopy
    echo ">> installed system-wide in $DEST"
else
    cp -a "$WORKDIR"/. "$(dirname "$WORKDIR")/canopy-src-$$" 2>/dev/null || true
    sh "$WORKDIR/scripts/install.sh"
    echo
    echo ">> Canopy installed for user $(id -un)."
    echo "   Start it with:  labwc -S 'quickshell -n -c canopy' -t Canopy"
    echo "   For a real desktop session run:  sudo sh $0"
fi

echo
echo "## helper scripts (kept next to the installed shell)"
echo "  sh ~/.config/quickshell/canopy/scripts/deps.sh plan     # what is missing"
echo "  sh ~/.config/quickshell/canopy/scripts/build-quickshell.sh  # if it is unpackaged"
echo ""
echo "Canopy supports Arch/CachyOS, Fedora and Debian/Ubuntu; other"
echo "distributions work if labwc, quickshell and Qt 6 QML are present."
echo ""
echo "Done."
exit 0

__CANOPY_PAYLOAD_BELOW__
HEADER

# ---- Payload ------------------------------------------------------------
tar -czf - -C "$STAGE" . >> "$OUT"
chmod +x "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
echo "built: $OUT ($SIZE)"
