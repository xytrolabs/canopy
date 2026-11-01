#!/bin/sh
# Install Canopy configuration into the current user's XDG config.
#
# Distribution-agnostic: nothing here assumes Arch, Fedora or Debian. Package
# names and availability live in scripts/lib-distro.sh; this script only copies
# files and writes one generated config file.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

# Regenerate the system icon index (name -> file path) used by CanopyIcon.
if command -v python3 >/dev/null 2>&1 && [ -f "$PROJECT_DIR/scripts/gen-icon-map.py" ]; then
    python3 "$PROJECT_DIR/scripts/gen-icon-map.py" "$PROJECT_DIR/shell/icon-map.js" >/dev/null 2>&1 || true
fi
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Ensure Qt icon theme (qt6ct)
#
# The icon theme is picked from what this machine actually has instead of being
# hardcoded to Kora (an Arch/CachyOS favourite). A stale theme name makes every
# icon fall back to the 16px hicolor set, which is what "my icons are tiny and
# ugly" usually means. An existing install keeps its own choice if the theme is
# still installed.
mkdir -p "$XDG_CONFIG_HOME/qt6ct"
if [ -f "$PROJECT_DIR/config/qt6ct/qt6ct.conf" ]; then
    THEME="$(canopy_icon_theme)"
    if [ -f "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" ]; then
        OLD_THEME="$(sed -n 's/^icon_theme=//p' "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" | head -1)"
        if [ -n "$OLD_THEME" ] && [ -d "${XDG_DATA_HOME}/icons/$OLD_THEME" ]; then
            THEME="$OLD_THEME"
        elif [ -n "$OLD_THEME" ] && [ -d "/usr/share/icons/$OLD_THEME" ]; then
            THEME="$OLD_THEME"
        fi
    fi
    sed "s/^icon_theme=.*/icon_theme=$THEME/" \
        "$PROJECT_DIR/config/qt6ct/qt6ct.conf" \
        > "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
fi

# Default wallpapers
if [ -d "$PROJECT_DIR/assets/wallpapers" ]; then
    mkdir -p "$XDG_DATA_HOME/wallpapers"
    cp -n "$PROJECT_DIR"/assets/wallpapers/* "$XDG_DATA_HOME/wallpapers/" 2>/dev/null || true
fi

# Window-decoration theme (generated openbox theme)
# labwc reads themes from $XDG_DATA_HOME/themes and the legacy ~/.themes.
if [ -d "$PROJECT_DIR/config/labwc/themes/canopy" ]; then
    mkdir -p "$XDG_DATA_HOME/themes"
    rm -rf "$XDG_DATA_HOME/themes/canopy"
    cp -a "$PROJECT_DIR/config/labwc/themes/canopy" "$XDG_DATA_HOME/themes/canopy"
fi

# Labwc
mkdir -p "$XDG_CONFIG_HOME/labwc"
cp "$PROJECT_DIR/config/labwc/rc.xml" "$XDG_CONFIG_HOME/labwc/rc.xml"
cp "$PROJECT_DIR/config/labwc/environment" "$XDG_CONFIG_HOME/labwc/environment"
cp "$PROJECT_DIR/config/labwc/autostart" "$XDG_CONFIG_HOME/labwc/autostart"
chmod +x "$XDG_CONFIG_HOME/labwc/autostart"

# Quickshell (Canopy config)
mkdir -p "$XDG_CONFIG_HOME/quickshell/canopy"
cp -a "$PROJECT_DIR"/shell/. "$XDG_CONFIG_HOME/quickshell/canopy/"

# Distribution helpers, installed next to the shell so they survive the release
# payload (which extracts to a temp directory) and stay usable later:
#   sh ~/.config/quickshell/canopy/scripts/deps.sh plan
mkdir -p "$XDG_CONFIG_HOME/quickshell/canopy/scripts"
for f in lib-distro.sh deps.sh build-quickshell.sh build-wlroots.sh build-labwc.sh canopy-update.sh; do
    if [ -f "$PROJECT_DIR/scripts/$f" ]; then
        cp "$PROJECT_DIR/scripts/$f" "$XDG_CONFIG_HOME/quickshell/canopy/scripts/$f"
    fi
done

# Which release is installed. Read by the update checker and shown in Settings.
if [ -f "$PROJECT_DIR/VERSION" ]; then
    cp "$PROJECT_DIR/VERSION" "$XDG_CONFIG_HOME/quickshell/canopy/VERSION"
fi

# Bundled typefaces (Space Grotesk / Inter / JetBrains Mono). The shell loads
# them itself via FontLoader, but installing them system-side means Qt apps,
# terminals and the font picker also see the Canopy families.
if [ -d "$PROJECT_DIR/shell/fonts" ]; then
    FONT_DIR="$XDG_DATA_HOME/fonts/canopy"
    mkdir -p "$FONT_DIR"
    cp -f "$PROJECT_DIR"/shell/fonts/*.ttf "$FONT_DIR/" 2>/dev/null || true
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
fi

# Command-line helpers (screenshot tool used by the Print key and the menus)
mkdir -p "$HOME/.local/bin"
if [ -f "$PROJECT_DIR/scripts/canopy-screenshot.sh" ]; then
    cp "$PROJECT_DIR/scripts/canopy-screenshot.sh" "$HOME/.local/bin/canopy-screenshot"
    chmod 755 "$HOME/.local/bin/canopy-screenshot"
fi
if [ -f "$PROJECT_DIR/scripts/canopy-update.sh" ]; then
    cp "$PROJECT_DIR/scripts/canopy-update.sh" "$HOME/.local/bin/canopy-update"
    chmod 755 "$HOME/.local/bin/canopy-update"
fi

echo "Canopy installed."
if command -v labwc >/dev/null 2>&1 && command -v quickshell >/dev/null 2>&1; then
    echo "Start with: labwc (nested: labwc -S 'quickshell -c canopy')"
else
    echo "Runtime missing - run: sh scripts/deps.sh plan"
fi
