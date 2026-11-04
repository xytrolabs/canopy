#!/bin/sh
# Canopy — install the desktop environment.
#
#   sh scripts/install.sh              # user install (no root)
#   sudo sh scripts/install.sh         # system install (binary, assets, session)
#   sh scripts/install.sh --dry-run    # show what would happen
#
# A user install puts the shell in ~/.local/bin and keeps configuration in the
# home directory. A system install additionally registers the Wayland session,
# the desktop portal configuration and the session target.
#
# Existing user configuration is never overwritten: defaults are only written
# where nothing exists yet.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BUILD_DIR="${CANOPY_BUILD_DIR:-$PROJECT_DIR/build-release}"
VERSION="$(tr -d ' \t\r\n' < "$PROJECT_DIR/VERSION" 2>/dev/null || echo dev)"
DRY_RUN=0
REFRESH_CONFIG=0
for a in "$@"; do
    case "$a" in
        --dry-run|-n) DRY_RUN=1 ;;
        --refresh-config) REFRESH_CONFIG=1 ;;
    esac
done

say() { printf '%s\n' "$*"; }
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  would run: %s\n' "$*"
    else
        "$@"
    fi
}

is_system=0
[ "$(id -u)" -eq 0 ] && is_system=1

# ------------------------------------------------------------- dependencies --
# Canopy should not leave the user to discover that portals or the compositor
# are missing. Missing runtime pieces are installed through the distribution's
# package manager (scripts/lib-distro.sh knows the names).
ensure_dependencies() {
    [ "${CANOPY_SKIP_DEPS:-0}" = "1" ] && return 0

    _missing=""
    for b in labwc; do
        command -v "$b" >/dev/null 2>&1 || _missing="$_missing $b"
    done
    for p in xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr; do
        canopy_pkg_available "$p" >/dev/null 2>&1 || _missing="$_missing $p"
    done

    [ -n "$_missing" ] || return 0

    say "missing runtime pieces:$_missing"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "would install:"
        canopy_install_hint runtime | sed 's/^/  /'
        return 0
    fi

    _pkgs="$(canopy_pkgs runtime)"
    if [ "$is_system" -eq 1 ]; then
        _sudo=""
    else
        command -v sudo >/dev/null 2>&1 || { say "install these yourself: $_pkgs" >&2; return 0; }
        _sudo="sudo"
    fi

    say "installing them now:"
    case "$(canopy_family)" in
        arch)   $_sudo pacman -S --needed --noconfirm $_pkgs ;;
        fedora) $_sudo dnf install -y --skip-unavailable $_pkgs ;;
        debian) $_sudo apt-get update && $_sudo apt-get install -y $_pkgs ;;
        suse)   $_sudo zypper install -y $_pkgs ;;
        *) say "unknown distribution - install these yourself: $_pkgs" >&2 ;;
    esac
}

# ---------------------------------------------------------------- binary -----
install_binary() {
    if [ "$is_system" -eq 1 ]; then
        if [ -x "$BUILD_DIR/canopy" ]; then
            # meson lays out bin/canopy and share/canopy/assets; the assets tree
            # is required at runtime, the binary alone is not enough.
            run meson install --no-rebuild -C "$BUILD_DIR"
        elif [ -x /usr/local/bin/canopy ]; then
            say "using the already installed binary in /usr/local/bin"
        else
            say "error: no build found; run 'just build release' first" >&2
            exit 1
        fi
    else
        [ -x "$BUILD_DIR/canopy" ] || {
            say "error: $BUILD_DIR/canopy is missing; run 'just build release' first" >&2
            exit 1
        }
        run mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/canopy"
        run install -m755 "$BUILD_DIR/canopy" "$HOME/.local/bin/canopy"
        run rm -rf "$XDG_DATA_HOME/canopy/assets"
        run cp -a "$PROJECT_DIR/assets" "$XDG_DATA_HOME/canopy/assets"
    fi
}

# ------------------------------------------------------- session + portals ---
install_session() {
    if [ "$is_system" -eq 1 ]; then
        run install -Dm755 "$PROJECT_DIR/scripts/canopy-session" /usr/local/bin/canopy-session
        run install -Dm644 "$PROJECT_DIR/config/canopy-session.desktop" \
            /usr/local/share/wayland-sessions/canopy.desktop
        if [ -d /usr/share/xdg-desktop-portal ]; then
            run install -Dm644 "$PROJECT_DIR/config/xdg-desktop-portal/canopy-portals.conf" \
                /usr/share/xdg-desktop-portal/canopy-portals.conf
        fi
        run install -Dm644 "$PROJECT_DIR/config/xdg-desktop-portal/canopy-portals.conf" \
            /usr/local/share/xdg-desktop-portal/canopy-portals.conf

        # Defaults for accounts that have never run a session: labwc reads
        # /etc/xdg/labwc when ~/.config/labwc does not exist. Never clobber a
        # file the distribution already ships.
        for f in rc.xml menu.xml environment autostart; do
            if [ -f "$PROJECT_DIR/config/labwc/$f" ] && [ ! -f "/etc/xdg/labwc/$f" ]; then
                run install -Dm644 "$PROJECT_DIR/config/labwc/$f" "/etc/xdg/labwc/$f"
            fi
        done
        if [ -d "$PROJECT_DIR/config/labwc/themes/canopy" ] && [ ! -d /usr/share/themes/canopy ]; then
            run cp -a "$PROJECT_DIR/config/labwc/themes/canopy" /usr/share/themes/canopy
        fi
    else
        run mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/wayland-sessions"
        run install -m755 "$PROJECT_DIR/scripts/canopy-session" "$HOME/.local/bin/canopy-session"
        run install -m644 "$PROJECT_DIR/config/canopy-session.desktop" \
            "$XDG_DATA_HOME/wayland-sessions/canopy.desktop"
    fi
}

# --------------------------------------------------------------- user config -
seed_config() {
    run mkdir -p "$XDG_CONFIG_HOME/canopy"
    if [ -f "$XDG_CONFIG_HOME/canopy/config.toml" ]; then
        if [ "$REFRESH_CONFIG" -eq 1 ]; then
            _backup="$XDG_CONFIG_HOME/canopy/config.toml.bak-$(date +%Y%m%d-%H%M%S)"
            run cp "$XDG_CONFIG_HOME/canopy/config.toml" "$_backup"
            say "backed up existing config -> $_backup"
            run cp "$PROJECT_DIR/config/canopy/config.toml" "$XDG_CONFIG_HOME/canopy/config.toml"
            say "refreshed $XDG_CONFIG_HOME/canopy/config.toml from Canopy defaults"
        else
            say "keeping existing $XDG_CONFIG_HOME/canopy/config.toml (use --refresh-config to replace it)"
        fi
    else
        run cp "$PROJECT_DIR/config/canopy/config.toml" "$XDG_CONFIG_HOME/canopy/config.toml"
        say "installed Canopy defaults -> $XDG_CONFIG_HOME/canopy/config.toml"
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '%s\n' "$VERSION" > "$XDG_CONFIG_HOME/canopy/VERSION"
    fi
}

seed_labwc() {
    [ -d "$PROJECT_DIR/config/labwc" ] || return 0
    run mkdir -p "$XDG_CONFIG_HOME/labwc"
    for f in rc.xml menu.xml environment autostart; do
        [ -f "$PROJECT_DIR/config/labwc/$f" ] || continue
        if [ -f "$XDG_CONFIG_HOME/labwc/$f" ]; then
            say "keeping existing labwc/$f"
        else
            run cp "$PROJECT_DIR/config/labwc/$f" "$XDG_CONFIG_HOME/labwc/$f"
        fi
    done
    run chmod +x "$XDG_CONFIG_HOME/labwc/autostart"

    if [ -d "$PROJECT_DIR/config/labwc/themes/canopy" ]; then
        run mkdir -p "$XDG_DATA_HOME/themes"
        run rm -rf "$XDG_DATA_HOME/themes/canopy"
        run cp -a "$PROJECT_DIR/config/labwc/themes/canopy" "$XDG_DATA_HOME/themes/canopy"
    fi
}

# The toolkit layer: GTK, Qt, default applications, icon and cursor theme.
seed_toolkits() {
    ICON_THEME="$(canopy_icon_theme)"
    CURSOR_THEME="$(canopy_cursor_theme)"

    for v in 3.0 4.0; do
        run mkdir -p "$XDG_CONFIG_HOME/gtk-$v"
        if [ -f "$XDG_CONFIG_HOME/gtk-$v/settings.ini" ]; then
            say "keeping existing gtk-$v/settings.ini"
        elif [ "$DRY_RUN" -eq 1 ]; then
            say "would write gtk-$v/settings.ini (icons: $ICON_THEME, cursor: $CURSOR_THEME)"
        else
            sed -e "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$ICON_THEME/" \
                -e "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CURSOR_THEME/" \
                "$PROJECT_DIR/config/gtk-$v/settings.ini" \
                > "$XDG_CONFIG_HOME/gtk-$v/settings.ini"
        fi
    done

    run mkdir -p "$XDG_CONFIG_HOME/qt6ct"
    if [ -f "$PROJECT_DIR/config/qt6ct/qt6ct.conf" ] && [ "$DRY_RUN" -eq 0 ]; then
        sed "s/^icon_theme=.*/icon_theme=$ICON_THEME/" \
            "$PROJECT_DIR/config/qt6ct/qt6ct.conf" \
            > "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
    fi

    if [ -f "$XDG_CONFIG_HOME/mimeapps.list" ]; then
        say "keeping existing mimeapps.list"
    else
        run cp "$PROJECT_DIR/config/mimeapps.list" "$XDG_CONFIG_HOME/mimeapps.list"
    fi
}

seed_assets() {
    # Canopy ships its own typefaces so the desktop looks the same everywhere:
    # Space Grotesk (display), Inter (body), JetBrains Mono (numerals). The icon
    # font stays in the asset bundle - installing it as a text font would make
    # it selectable in every application's font picker.
    if [ -d "$PROJECT_DIR/assets/fonts" ]; then
        run mkdir -p "$XDG_DATA_HOME/fonts/canopy"
        for f in "$PROJECT_DIR"/assets/fonts/*.ttf; do
            case "$f" in
                *canopy-tabler.ttf) continue ;;
            esac
            run cp -f "$f" "$XDG_DATA_HOME/fonts/canopy/"
        done
        if [ "$DRY_RUN" -eq 0 ] && command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$XDG_DATA_HOME/fonts/canopy" >/dev/null 2>&1 || true
        fi
    fi

    if [ -d "$PROJECT_DIR/assets/wallpapers" ]; then
        run mkdir -p "$XDG_DATA_HOME/backgrounds"
        for w in "$PROJECT_DIR"/assets/wallpapers/*.png; do
            [ -f "$w" ] || continue
            run cp -n "$w" "$XDG_DATA_HOME/backgrounds/"
        done
    fi
    if [ -f "$PROJECT_DIR/assets/canopy-wallpaper.png" ]; then
        run mkdir -p "$XDG_DATA_HOME/backgrounds"
        run cp -n "$PROJECT_DIR/assets/canopy-wallpaper.png" \
            "$XDG_DATA_HOME/backgrounds/canopy-wallpaper.png"
    fi
    if [ -f "$PROJECT_DIR/assets/canopy-mark.svg" ]; then
        run mkdir -p "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
        run cp -f "$PROJECT_DIR/assets/canopy-mark.svg" \
            "$XDG_DATA_HOME/icons/hicolor/scalable/apps/canopy-mark.svg"
    fi
    if [ -f "$PROJECT_DIR/assets/canopy.svg" ]; then
        run mkdir -p "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
        run cp -f "$PROJECT_DIR/assets/canopy.svg" \
            "$XDG_DATA_HOME/icons/hicolor/scalable/apps/canopy.svg"
        if [ "$DRY_RUN" -eq 0 ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -q -t "$XDG_DATA_HOME/icons/hicolor" 2>/dev/null || true
        fi
    fi
    # A system install also seeds the desktop-wide defaults used by accounts
    # that have never logged into Canopy before.
    if [ "$is_system" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
        for f in mimeapps.list; do
            [ -f "$PROJECT_DIR/config/$f" ] && [ ! -f "/etc/xdg/$f" ] \
                && install -Dm644 "$PROJECT_DIR/config/$f" "/etc/xdg/$f"
        done
        for v in 3.0 4.0; do
            [ -f "/etc/xdg/gtk-$v/settings.ini" ] || \
                install -Dm644 "$PROJECT_DIR/config/gtk-$v/settings.ini" "/etc/xdg/gtk-$v/settings.ini"
        done
    fi
    if [ "$DRY_RUN" -eq 0 ] && command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$XDG_DATA_HOME/applications" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------- helpers ----
install_helpers() {
    run mkdir -p "$HOME/.local/bin"
    for helper in canopy-session canopy-screenshot canopy-update; do
        [ -f "$PROJECT_DIR/scripts/$helper" ] || continue
        run install -m755 "$PROJECT_DIR/scripts/$helper" "$HOME/.local/bin/$helper"
    done
    # Helper copies of the distribution knowledge, so `deps.sh` still works
    # after the release payload has been extracted to a temporary directory.
    run mkdir -p "$XDG_DATA_HOME/canopy/scripts"
    for f in lib-distro.sh deps.sh build-release.sh uninstall.sh; do
        [ -f "$PROJECT_DIR/scripts/$f" ] || continue
        run cp -f "$PROJECT_DIR/scripts/$f" "$XDG_DATA_HOME/canopy/scripts/$f"
    done
}

install_binary
install_session
install_helpers
seed_config
seed_labwc
seed_toolkits
seed_assets
ensure_dependencies

say ""
if [ "$is_system" -eq 1 ]; then
    say "Canopy $VERSION installed system-wide."
    say "Log out and choose \"Canopy\" in the display manager, or run: canopy-session"
else
    say "Canopy $VERSION installed for $(id -un)."
    say "Start it:  canopy-session"
    say "Nested:    canopy-session --nested   (inside a running Wayland session)"
    if [ -x /usr/local/bin/canopy ] && [ -x "$HOME/.local/bin/canopy" ] \
       && [ "/usr/local/bin/canopy" -nt "$HOME/.local/bin/canopy" ]; then
        say "note: /usr/local/bin/canopy shadows ~/.local/bin on PATH; run 'sudo sh scripts/install.sh' to refresh it"
    fi
fi