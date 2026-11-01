#!/bin/sh
# reinstall.sh - clean reinstall of Canopy.
#
# Run as root (it replaces files under /usr/local):
#
#     sudo sh scripts/reinstall.sh
#
# It removes every previous copy of the desktop - the system-wide payload, the
# PATH launcher, the session entry and the per-user shell - then installs the
# current build from dist/ and refreshes the invoking user's configuration.
#
# Your personal settings (~/.config/canopy/settings.json) are kept.
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "reinstall.sh: run me with sudo (it replaces /usr/local/share/canopy)" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_USER="${SUDO_USER:-$(id -un)}"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[ -n "$USER_HOME" ] || USER_HOME="$HOME"

echo ">> project:     $PROJECT_DIR"
echo ">> target user: $TARGET_USER ($USER_HOME)"

echo ">> stopping any running Canopy shell"
pkill -f "quickshell -c canopy" 2>/dev/null || true
sleep 1

echo ">> removing old system copies"
rm -rf /usr/local/share/canopy
rm -f  /usr/local/bin/canopy
rm -f  /usr/local/share/wayland-sessions/canopy.desktop

echo ">> removing stale per-user shell"
rm -rf "$USER_HOME/.config/quickshell/canopy"
rm -rf "$USER_HOME/.themes/canopy"

RUN=$(ls -t "$PROJECT_DIR"/dist/canopy-*.run 2>/dev/null | head -1)
if [ -z "$RUN" ]; then
    echo "reinstall.sh: no dist/canopy-*.run found - run scripts/build-release.sh first" >&2
    exit 1
fi

echo ">> installing $RUN"
sh "$RUN"

echo
echo "Installed. To test from a TTY:"
echo "  1. switch to a free virtual terminal (Ctrl+Alt+F3, log in as $TARGET_USER)"
echo "  2. run:  canopy"
echo "  3. to return to the graphical session: Ctrl+Alt+F2 (or wherever it is)"
echo
echo "Without the system install you can always run it nested from a terminal:"
echo "  labwc -S 'quickshell -n -c canopy' -t Canopy"
