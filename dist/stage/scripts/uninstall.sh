#!/bin/sh
# Canopy — uninstall the desktop environment.
#
#   sh scripts/uninstall.sh             # remove the installed desktop, keep config
#   sh scripts/uninstall.sh --purge     # also remove ~/.config/canopy and state
#   sudo sh scripts/uninstall.sh        # system install: binary, assets, session
#
# Configuration is kept by default: uninstalling should not destroy the user's
# settings, wallpaper choice or pinned applications.
set -eu

PURGE=0
for a in "$@"; do
    case "$a" in
        --purge) PURGE=1 ;;
    esac
done

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

say() { printf '%s\n' "$*"; }

pkill -x canopy 2>/dev/null || true

if [ "$(id -u)" -eq 0 ]; then
    say "removing the system install"
    rm -f /usr/local/bin/canopy /usr/local/bin/canopy-session
    rm -rf /usr/local/share/canopy
    rm -f /usr/local/share/wayland-sessions/canopy.desktop
    rm -f /usr/share/xdg-desktop-portal/canopy-portals.conf
    rm -f /usr/local/share/xdg-desktop-portal/canopy-portals.conf
    rm -f /usr/share/applications/dev.canopy.Canopy.desktop
    rm -f /usr/share/applications/dev.canopy.Canopy.Annotator.desktop
    rm -f /usr/share/icons/hicolor/scalable/apps/canopy.svg
    command -v gtk-update-icon-cache >/dev/null 2>&1 \
        && gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database /usr/share/applications 2>/dev/null || true
    say "system install removed (user configuration untouched)"
    exit 0
fi

say "removing the user install"
rm -f "$HOME/.local/bin/canopy" "$HOME/.local/bin/canopy-session" "$HOME/.local/bin/canopy-session"
rm -f "$HOME/.local/bin/canopy-screenshot" "$HOME/.local/bin/canopy-update"
rm -rf "$XDG_DATA_HOME/canopy"
rm -f "$XDG_DATA_HOME/wayland-sessions/canopy.desktop"
rm -f "$XDG_DATA_HOME/icons/hicolor/scalable/apps/canopy.svg"
rm -rf "$XDG_DATA_HOME/themes/canopy"

# Labwc files this DE installed.
rm -f "$XDG_CONFIG_HOME/labwc/menu.xml"
if [ -f "$XDG_CONFIG_HOME/labwc/autostart" ] && grep -q "canopy" "$XDG_CONFIG_HOME/labwc/autostart" 2>/dev/null; then
    rm -f "$XDG_CONFIG_HOME/labwc/autostart"
fi

if [ "$PURGE" -eq 1 ]; then
    say "purging configuration and state"
    rm -rf "$XDG_CONFIG_HOME/canopy" "$XDG_STATE_HOME/canopy"
    rm -f "$XDG_DATA_HOME/backgrounds/canopy-wallpaper.png"
else
    say "kept $XDG_CONFIG_HOME/canopy (use --purge to remove it)"
fi

say "done"