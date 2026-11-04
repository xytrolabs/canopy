#!/bin/sh
# Canopy — install the desktop for the current user.
#
#   sh scripts/install.sh            # after `just build release`
#   sudo sh scripts/install.sh       # system install (binary + assets + session)
#
# A user install never needs root: it copies the built binary into
# ~/.local/bin, seeds the Canopy configuration and Labwc integration, and
# installs the helper assets. Nothing here overwrites an existing user
# configuration — Canopy only writes defaults that are missing.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BUILD_DIR="${CANOPY_BUILD_DIR:-$PROJECT_DIR/build-release}"
VERSION="$(tr -d ' \t\r\n' < "$PROJECT_DIR/VERSION" 2>/dev/null || echo dev)"

say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------- binary ----
install_payload() {
    if [ "$(id -u)" -eq 0 ]; then
        # System install: meson lays out bin/ + share/canopy/assets. The assets
        # tree is required at runtime; the binary alone is not enough.
        if [ -x "$BUILD_DIR/canopy" ]; then
            meson install --no-rebuild -C "$BUILD_DIR"
        fi
        install -Dm644 "$PROJECT_DIR/config/canopy-session.desktop" \
            /usr/local/share/wayland-sessions/canopy.desktop
        # meson installs the real binary as <bindir>/canopy. The TTY helper is a
        # separate name so it can never shadow or exec-loop onto the shell.
        install -Dm755 /dev/stdin /usr/local/bin/canopy-session <<'LAUNCH'
#!/bin/sh
# Start a Canopy session from a TTY: compositor first, shell via autostart.
exec labwc -S 'canopy' -t Canopy "$@"
LAUNCH
        return 0
    fi

    [ -x "$BUILD_DIR/canopy" ] || {
        say "error: $BUILD_DIR/canopy is missing; run 'just build release' first" >&2
        exit 1
    }
    mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/canopy"
    install -m755 "$BUILD_DIR/canopy" "$HOME/.local/bin/canopy"
    # A stale system-wide install shadows ~/.local/bin when /usr/local/bin comes
    # first on PATH; say so instead of silently running the older build.
    if [ -x /usr/local/bin/canopy ] && [ "/usr/local/bin/canopy" -nt "$HOME/.local/bin/canopy" ]; then
        say "note: /usr/local/bin/canopy is newer on PATH; run 'sudo sh scripts/install.sh' to refresh it"
    fi
    # Assets are looked up next to the binary first, then in the installed
    # share directory; keep the bundle beside the binary for a user install.
    rm -rf "$XDG_DATA_HOME/canopy/assets"
    cp -a "$PROJECT_DIR/assets" "$XDG_DATA_HOME/canopy/assets"
    install -Dm644 "$PROJECT_DIR/config/canopy-session.desktop" \
        "$XDG_DATA_HOME/wayland-sessions/canopy.desktop"
}

# ------------------------------------------------------------ user config ----
seed_config() {
    mkdir -p "$XDG_CONFIG_HOME/canopy"
    if [ -f "$XDG_CONFIG_HOME/canopy/config.toml" ]; then
        say "keeping existing $XDG_CONFIG_HOME/canopy/config.toml"
    else
        cp "$PROJECT_DIR/config/canopy/config.toml" "$XDG_CONFIG_HOME/canopy/config.toml"
        say "installed Canopy defaults -> $XDG_CONFIG_HOME/canopy/config.toml"
    fi
    printf '%s\n' "$VERSION" > "$XDG_CONFIG_HOME/canopy/VERSION"
}

# ------------------------------------------------------------------ labwc ----
seed_labwc() {
    [ -d "$PROJECT_DIR/config/labwc" ] || return 0
    mkdir -p "$XDG_CONFIG_HOME/labwc"
    for f in rc.xml environment autostart; do
        if [ -f "$XDG_CONFIG_HOME/labwc/$f" ]; then
            say "keeping existing labwc/$f"
        else
            cp "$PROJECT_DIR/config/labwc/$f" "$XDG_CONFIG_HOME/labwc/$f"
        fi
    done
    chmod +x "$XDG_CONFIG_HOME/labwc/autostart" 2>/dev/null || true

    if [ -d "$PROJECT_DIR/config/labwc/themes/canopy" ]; then
        mkdir -p "$XDG_DATA_HOME/themes"
        rm -rf "$XDG_DATA_HOME/themes/canopy"
        cp -a "$PROJECT_DIR/config/labwc/themes/canopy" "$XDG_DATA_HOME/themes/canopy"
    fi
}

# -------------------------------------------------------------- wallpaper ----
seed_wallpaper() {
    if [ -f "$PROJECT_DIR/assets/canopy-wallpaper.png" ]; then
        mkdir -p "$XDG_DATA_HOME/backgrounds"
        cp -n "$PROJECT_DIR/assets/canopy-wallpaper.png" \
            "$XDG_DATA_HOME/backgrounds/canopy-wallpaper.png" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------ icons ----
seed_icon() {
    if [ -f "$PROJECT_DIR/assets/canopy.svg" ]; then
        for d in "$XDG_DATA_HOME/icons/hicolor/scalable/apps" \
                 "$HOME/.local/share/icons/hicolor/scalable/apps"; do
            mkdir -p "$d"
            cp -f "$PROJECT_DIR/assets/canopy.svg" "$d/canopy.svg"
            break
        done
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$HOME/.local/share/icons/hicolor" ]; then
        gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi
}

install_payload
seed_config
seed_labwc
seed_wallpaper
seed_icon

say ""
say "Canopy $VERSION installed."
if [ "$(id -u)" -eq 0 ]; then
    say "Log out and choose \"Canopy\" in the display manager, or start it from a TTY with: labwc"
else
    say "Start it now:  labwc -S 'canopy' -t Canopy"
    say "Or log out and pick \"Canopy\" from the display manager (system install)."
fi