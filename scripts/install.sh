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
WITH_GREETER=0
WITH_MANGOWC=0
for a in "$@"; do
    case "$a" in
        --dry-run|-n) DRY_RUN=1 ;;
        --refresh-config) REFRESH_CONFIG=1 ;;
        --with-greeter) WITH_GREETER=1 ;;
        --with-mangowc) WITH_MANGOWC=1 ;;
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

# ------------------------------------------------------------ compositor -----
# Canopy's own compositor, built from compositor/ into build-compositor/. The
# session falls back to labwc when it is missing, so a checkout that has never
# been built still gives you a desktop instead of a black screen.
install_compositor() {
    _bin="${CANOPY_COMPOSITOR_BIN:-}"
    if [ -z "$_bin" ]; then
        # A source tree, a release payload (compositor/canopywc) or a build dir.
        for _candidate in "$PROJECT_DIR/compositor/canopywc" \
                          "$PROJECT_DIR/build-compositor/canopywc"; do
            [ -x "$_candidate" ] && { _bin="$_candidate"; break; }
        done
    fi
    if [ -z "$_bin" ] || [ ! -x "$_bin" ]; then
        say "note: canopywc is not built or packaged; the Canopy session will fall back to labwc"
        say "      build it with: sh scripts/build-compositor.sh"
        return 0
    fi
    if [ "$is_system" -eq 1 ]; then
        run install -Dm755 "$_bin" /usr/local/bin/canopywc
        run install -Dm644 "$PROJECT_DIR/config/compositor.toml" \
            /usr/local/share/canopy/compositor.toml
    else
        run mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/canopy"
        run install -m755 "$_bin" "$HOME/.local/bin/canopywc"
        run install -m644 "$PROJECT_DIR/config/compositor.toml" \
            "$XDG_DATA_HOME/canopy/compositor.toml"
    fi
    say "installed canopywc (Canopy compositor)"
}

# ------------------------------------------------------- session + portals ---
install_session() {
    if [ "$is_system" -eq 1 ]; then
        run install -Dm755 "$PROJECT_DIR/scripts/canopy-session" /usr/local/bin/canopy-session
        run install -Dm644 "$PROJECT_DIR/config/canopy-session.desktop" \
            /usr/local/share/wayland-sessions/canopy.desktop
        # Second, beta session: the same shell on MangoWC. Installed alongside
        # the labwc entry, never instead of it.
        if [ "$WITH_MANGOWC" -eq 1 ]; then
            run install -Dm644 "$PROJECT_DIR/config/canopy-session-mangowc.desktop" \
                /usr/local/share/wayland-sessions/canopy-mangowc.desktop
            run install -Dm644 "$PROJECT_DIR/config/mangowc/config.conf" \
                /usr/local/share/canopy/mangowc/config.conf
        fi
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

        # The shell only reads config.toml from the user's config directory, so
        # a system install must ship the Canopy defaults somewhere a *new*
        # account can find them. canopy-session seeds the user copy from here
        # on first login; /etc/xdg/canopy is the conventional place for it and
        # is what image builders/greeters look at.
        if [ -f "$PROJECT_DIR/config/canopy/config.toml" ]; then
            run install -Dm644 "$PROJECT_DIR/config/canopy/config.toml" \
                /usr/local/share/canopy/config.toml
            if [ ! -f /etc/xdg/canopy/config.toml ]; then
                run install -Dm644 "$PROJECT_DIR/config/canopy/config.toml" \
                    /etc/xdg/canopy/config.toml
            fi
        fi

        # Wallpapers and the mark, for accounts that never ran the user path.
        if [ -d "$PROJECT_DIR/assets/wallpapers" ]; then
            for w in "$PROJECT_DIR"/assets/wallpapers/*.png; do
                [ -f "$w" ] || continue
                run install -Dm644 "$w" "/usr/local/share/backgrounds/$(basename "$w")"
            done
        fi
        [ -f "$PROJECT_DIR/assets/canopy-wallpaper.png" ] && \
            run install -Dm644 "$PROJECT_DIR/assets/canopy-wallpaper.png" \
                /usr/local/share/backgrounds/canopy-wallpaper.png
        [ -f "$PROJECT_DIR/assets/canopy-mark.svg" ] && \
            run install -Dm644 "$PROJECT_DIR/assets/canopy-mark.svg" \
                /usr/local/share/icons/hicolor/scalable/apps/canopy-mark.svg
        [ -f "$PROJECT_DIR/assets/canopy.png" ] && \
            run install -Dm644 "$PROJECT_DIR/assets/canopy.png" \
                /usr/local/share/icons/hicolor/scalable/apps/canopy.png
        if [ "$DRY_RUN" -eq 0 ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -q -t /usr/local/share/icons/hicolor 2>/dev/null || true
        fi
        if [ "$DRY_RUN" -eq 0 ] && command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database /usr/local/share/applications 2>/dev/null || true
        fi
        if [ "$DRY_RUN" -eq 0 ] && command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f /usr/local/share/fonts/canopy >/dev/null 2>&1 || true
        fi
    else
        run mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/wayland-sessions"
        run install -m755 "$PROJECT_DIR/scripts/canopy-session" "$HOME/.local/bin/canopy-session"
        run install -m644 "$PROJECT_DIR/config/canopy-session.desktop" \
            "$XDG_DATA_HOME/wayland-sessions/canopy.desktop"
        if [ "$WITH_MANGOWC" -eq 1 ]; then
            run install -m644 "$PROJECT_DIR/config/canopy-session-mangowc.desktop" \
                "$XDG_DATA_HOME/wayland-sessions/canopy-mangowc.desktop"
        fi
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
            # ...but keep it current: shipped design changes only reach a user
            # whose config still holds the old value for a key. Anything edited
            # by hand is left alone.
            if [ "$DRY_RUN" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
                python3 "$PROJECT_DIR/scripts/migrate-config.py" \
                    "$XDG_CONFIG_HOME/canopy/config.toml" || \
                    say "warning: could not update defaults in the existing config"
            fi
        fi
    else
        run cp "$PROJECT_DIR/config/canopy/config.toml" "$XDG_CONFIG_HOME/canopy/config.toml"
        say "installed Canopy defaults -> $XDG_CONFIG_HOME/canopy/config.toml"
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '%s\n' "$VERSION" > "$XDG_CONFIG_HOME/canopy/VERSION"
    fi

    # A colour scheme picked in the UI is stored in the app overlay, which wins
    # over config.toml. Say so instead of leaving a "why is it not Canopy?" mystery.
    _overlay="${XDG_STATE_HOME:-$HOME/.local/state}/canopy/settings.toml"
    if [ -f "$_overlay" ] && grep -q '^builtin = "Canopy"' "$_overlay" 2>/dev/null; then
        :
    elif [ -f "$_overlay" ] && grep -q '^builtin = ' "$_overlay" 2>/dev/null; then
        say "note: $_overlay overrides the palette; reset with:"
        say "        canopy msg config-set theme.builtin Canopy"
    fi
}

seed_labwc() {
    [ -d "$PROJECT_DIR/config/labwc" ] || return 0
    run mkdir -p "$XDG_CONFIG_HOME/labwc"
    for f in rc.xml menu.xml environment autostart; do
        [ -f "$PROJECT_DIR/config/labwc/$f" ] || continue
        if [ -f "$XDG_CONFIG_HOME/labwc/$f" ]; then
            if [ "$REFRESH_CONFIG" -eq 1 ]; then
                # The window decorations (titlebar layout, corner radius) live in
                # rc.xml, so a refreshed install has to take the new file or the
                # decorations keep looking like the previous release.
                _backup="$XDG_CONFIG_HOME/labwc/$f.bak-$(date +%Y%m%d-%H%M%S)"
                run cp "$XDG_CONFIG_HOME/labwc/$f" "$_backup"
                run cp "$PROJECT_DIR/config/labwc/$f" "$XDG_CONFIG_HOME/labwc/$f"
                say "refreshed labwc/$f (backup: $_backup)"
            else
                say "keeping existing labwc/$f (use --refresh-config to update)"
            fi
        else
            run cp "$PROJECT_DIR/config/labwc/$f" "$XDG_CONFIG_HOME/labwc/$f"
        fi
    done
    run chmod +x "$XDG_CONFIG_HOME/labwc/autostart"

    if [ -d "$PROJECT_DIR/config/labwc/themes/canopy" ]; then
        run mkdir -p "$XDG_DATA_HOME/themes"
        run rm -rf "$XDG_DATA_HOME/themes/canopy"
        run cp -a "$PROJECT_DIR/config/labwc/themes/canopy" "$XDG_DATA_HOME/themes/canopy"
        # Older Canopy installs wrote the theme to ~/.themes. labwc reads that
        # location when the XDG data copy is missing, and a leftover copy keeps
        # the old, never-loaded button images alive, which is why decorations
        # could look unchanged after an upgrade.
        if [ -d "$HOME/.themes/canopy" ]; then
            run rm -rf "$HOME/.themes/canopy"
            run cp -a "$PROJECT_DIR/config/labwc/themes/canopy" "$HOME/.themes/canopy"
            say "refreshed the legacy theme copy in ~/.themes/canopy"
        fi
    fi
}

# The toolkit layer: GTK, Qt, default applications, icon and cursor theme.
seed_toolkits() {
    ICON_THEME="$(canopy_icon_theme)"
    CURSOR_THEME="$(canopy_cursor_theme)"

    for v in 3.0 4.0; do
        run mkdir -p "$XDG_CONFIG_HOME/gtk-$v"
        if [ -f "$XDG_CONFIG_HOME/gtk-$v/settings.ini" ] && [ "$REFRESH_CONFIG" -eq 0 ]; then
            say "keeping existing gtk-$v/settings.ini (use --refresh-config to update)"
        elif [ "$DRY_RUN" -eq 1 ]; then
            say "would write gtk-$v/settings.ini (icons: $ICON_THEME, cursor: $CURSOR_THEME)"
        else
            # Keep anything the user set that we do not own; only the icon and
            # cursor theme are Canopy's to choose.
            _existing="$XDG_CONFIG_HOME/gtk-$v/settings.ini"
            _base="$PROJECT_DIR/config/gtk-$v/settings.ini"
            if [ -f "$_existing" ] && [ "$REFRESH_CONFIG" -eq 1 ]; then
                sed -e "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$ICON_THEME/" \
                    -e "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CURSOR_THEME/" \
                    "$_existing" > "$_existing.canopy-new"
                mv "$_existing.canopy-new" "$_existing"
            else
                sed -e "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$ICON_THEME/" \
                    -e "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CURSOR_THEME/" \
                    "$_base" > "$_existing"
            fi
            say "icon theme -> $ICON_THEME (gtk-$v)"
        fi
    done

    run mkdir -p "$XDG_CONFIG_HOME/qt6ct"
    if [ -f "$PROJECT_DIR/config/qt6ct/qt6ct.conf" ] && [ "$DRY_RUN" -eq 0 ]; then
        sed "s/^icon_theme=.*/icon_theme=$ICON_THEME/" \
            "$PROJECT_DIR/config/qt6ct/qt6ct.conf" \
            > "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
    fi

    # Applications that draw their own decorations do not use the openbox
    # theme, so their headerbar is styled here. Without this the windows of
    # libadwaita/GTK apps keep the stock titlebar and the desktop looks like
    # two different systems.
    for v in 3.0 4.0; do
        if [ -f "$PROJECT_DIR/config/gtk-$v/gtk.css" ]; then
            run mkdir -p "$XDG_CONFIG_HOME/gtk-$v"
            if [ -f "$XDG_CONFIG_HOME/gtk-$v/gtk.css" ] && [ "$REFRESH_CONFIG" -eq 0 ]; then
                say "keeping existing gtk-$v/gtk.css (use --refresh-config to update)"
            else
                run cp -f "$PROJECT_DIR/config/gtk-$v/gtk.css" "$XDG_CONFIG_HOME/gtk-$v/gtk.css"
                say "headerbar style -> gtk-$v/gtk.css"
            fi
        fi
    done

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
    # The launcher widget points at the PNG mark; the vector stays for the menu
    # entry and window icons.
    if [ -f "$PROJECT_DIR/assets/canopy.png" ]; then
        run mkdir -p "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
        run cp -f "$PROJECT_DIR/assets/canopy.png" \
            "$XDG_DATA_HOME/icons/hicolor/scalable/apps/canopy.png"
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

# ---------------------------------------------------------------- mangowc ----
# MangoWC is Canopy's second, beta compositor: a tiling dwl derivative. It is
# installed *next to* labwc - its own session entry, its own config, its own
# package - so testing it can never change or break the default session.
install_mangowc() {
    [ "$WITH_MANGOWC" -eq 1 ] || return 0

    # Files first. They need no root and must land even when the package cannot
    # be installed (not packaged for this distribution, no sudo password, no
    # network) - otherwise --with-mangowc looks like it did nothing.
    if [ "$is_system" -eq 1 ]; then
        run install -Dm644 "$PROJECT_DIR/config/canopy-session-mangowc.desktop" \
            /usr/local/share/wayland-sessions/canopy-mangowc.desktop
        run install -Dm644 "$PROJECT_DIR/config/mangowc/config.conf" \
            /usr/local/share/canopy/mangowc/config.conf
    else
        run mkdir -p "$XDG_DATA_HOME/wayland-sessions" "$XDG_DATA_HOME/canopy/mangowc"
        run install -m644 "$PROJECT_DIR/config/canopy-session-mangowc.desktop" \
            "$XDG_DATA_HOME/wayland-sessions/canopy-mangowc.desktop"
        run cp -f "$PROJECT_DIR/config/mangowc/config.conf" \
            "$XDG_DATA_HOME/canopy/mangowc/config.conf"
    fi

    # The config MangoWC itself reads, seeded once and never overwritten.
    _mango_cfg="$XDG_CONFIG_HOME/mango/config.conf"
    if [ -f "$_mango_cfg" ]; then
        say "mangowc: keeping existing $_mango_cfg"
    else
        run mkdir -p "$XDG_CONFIG_HOME/mango"
        run cp "$PROJECT_DIR/config/mangowc/config.conf" "$_mango_cfg"
        say "mangowc: wrote $_mango_cfg"
    fi

    say "mangowc: session entry installed (Canopy (MangoWC, beta) at login)"

    # Package last, and never fatal: a missing package must not abort the rest
    # of the install or leave the session entry half-registered.
    if command -v mangowc >/dev/null 2>&1; then
        say "mangowc: mangowc already installed"
        return 0
    fi

    _pkgs="$(canopy_pkgs mangowc)"
    if [ -z "$_pkgs" ]; then
        say "mangowc: no package for $(canopy_family); build it from https://github.com/mangowm/mango"
        say "         the session entry and config are installed and will work once it is on PATH"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        say "mangowc: would install $_pkgs"
        return 0
    fi

    _sudo=""
    if [ "$is_system" -eq 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            say "mangowc: run 'pacman -S $_pkgs' (or your package manager) to finish the beta session"
            return 0
        fi
        # Only install the package when sudo would not have to ask for a
        # password: an installer must never leave a session half-done because a
        # prompt nobody can answer appeared halfway through.
        if ! sudo -n true 2>/dev/null; then
            say "mangowc: the session and config are installed; to add the compositor run:"
            say "         sudo $(canopy_install_cmd) $_pkgs"
            return 0
        fi
        _sudo="sudo"
    fi

    say "mangowc: installing $_pkgs"
    if ! case "$(canopy_family)" in
        arch)   $_sudo pacman -S --needed --noconfirm $_pkgs ;;
        fedora) $_sudo dnf install -y --skip-unavailable $_pkgs ;;
        debian) $_sudo apt-get update && $_sudo apt-get install -y $_pkgs ;;
        suse)   $_sudo zypper install -y $_pkgs ;;
    esac; then
        say "mangowc: installing $_pkgs failed; the session is installed but needs the compositor"
    fi
}

# ---------------------------------------------------------------- greeter ----
# The login screen is Canopy Greeter (the vendored fork in greeter/). It needs
# greetd and its own compositor, so it is opt-in per install and never replaces
# a display manager silently.
install_greeter() {
    [ "$WITH_GREETER" -eq 1 ] || return 0

    GREETER_BUILD="${CANOPY_GREETER_BUILD:-$PROJECT_DIR/greeter/build}"
    [ -x "$GREETER_BUILD/canopy-greeter" ] || {
        say "greeter: $GREETER_BUILD/canopy-greeter is missing; build it with:"
        say "  meson setup greeter/build --buildtype=release && meson compile -C greeter/build"
        return 0
    }

    if [ "$is_system" -eq 1 ]; then
        for b in canopy-greeter canopy-greeter-compositor canopy-greeter-apply-appearance; do
            run install -Dm755 "$GREETER_BUILD/$b" "/usr/local/bin/$b"
        done
        run install -Dm755 "$PROJECT_DIR/greeter/scripts/canopy-greeter-session" \
            /usr/local/bin/canopy-greeter-session
        run mkdir -p /usr/local/share/canopy-greeter
        run cp -a "$PROJECT_DIR/greeter/assets" /usr/local/share/canopy-greeter/assets

        if [ -d /etc/greetd ]; then
            if [ -f /etc/greetd/config.toml ]; then
                say "greeter: /etc/greetd/config.toml exists; leaving it alone"
                say "         point its [default_session] command at /usr/local/bin/canopy-greeter-session"
            else
                run install -Dm644 "$PROJECT_DIR/config/greetd-config.toml" /etc/greetd/config.toml
                say "greeter: configured /etc/greetd/config.toml"
            fi
        else
            say "greeter: greetd is not installed; install it and point it at canopy-greeter-session"
        fi
    else
        say "greeter: a login screen must be installed system-wide; run 'sudo sh scripts/install.sh --with-greeter'"
    fi
}

seed_icon_theme() {
    # The session advertises XDG_CURRENT_DESKTOP=Canopy, so libsfdo looks for an
    # icon theme literally named "canopy". Without a theme by that name Labwc
    # logs "Failed to initialize icon loader" and every window icon is blank.
    #
    # The alias is a *symlink* to the real theme, not a stub with its own
    # index.theme: a stub that declares a directory shadows that theme for
    # lookups, so applications whose icons live in an inherited theme (Apollo's
    # `apollo` icon sits in hicolor, Kora only ships `apollo-studio`) render
    # blank. A symlink resolves every lookup through the real theme, inherits
    # included, and costs no generated file to keep in sync.
    _parent="$(canopy_icon_theme)"
    _parent_dir=""
    for _dir in "$XDG_DATA_HOME/icons" /usr/local/share/icons /usr/share/icons; do
        if [ -d "$_dir/$_parent" ]; then
            _parent_dir="$_dir/$_parent"
            break
        fi
    done

    for _dir in "$XDG_DATA_HOME/icons" /usr/local/share/icons /usr/share/icons; do
        [ -w "$_dir" ] || [ "$is_system" -eq 1 ] || continue
        _target="$_dir/canopy"
        if [ -n "$_parent_dir" ]; then
            if [ "$DRY_RUN" -eq 0 ]; then
                # Replace a stub written by an older Canopy, but never a real
                # theme directory the user put there themselves.
                if [ -d "$_target" ] && [ ! -L "$_target" ] \
                   && grep -qx 'Name=Canopy' "$_target/index.theme" 2>/dev/null; then
                    rm -rf "$_target"
                fi
                [ -e "$_target" ] || ln -s "$_parent_dir" "$_target"
            fi
            say "icon theme -> $_target (symlink to $_parent)"
            return 0
        fi
        # No real theme to point at: fall back to a valid stub, which at least
        # keeps libsfdo's loader working.
        run mkdir -p "$_target/scalable/apps"
        if [ "$DRY_RUN" -eq 0 ]; then
            cat > "$_target/index.theme" <<EOF
[Icon Theme]
Name=Canopy
Comment=Canopy desktop icon theme (inherits the installed theme)
Inherits=$_parent
Directories=scalable/apps

[scalable/apps]
Size=64
MinSize=8
MaxSize=512
Type=Scalable
EOF
        fi
        say "icon theme -> $_target (stub inheriting $_parent)"
        return 0
    done
    return 0
}

# A malformed index.theme breaks libsfdo for *every* theme that inherits it, and
# hicolor is inherited by nearly everything. The common breakage is a wrapped
# `Directories=` value (the list ends up on the next line, which libsfdo rejects
# with "Invalid key character"), leaving the whole icon loader dead.
repair_icon_theme_index() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    for _f in "$XDG_DATA_HOME/icons/hicolor/index.theme" \
              /usr/local/share/icons/hicolor/index.theme; do
        [ -f "$_f" ] || continue
        _tmp="$_f.canopy-tmp"
        if awk '
            /^[[:space:]]*Directories=[[:space:]]*$/ {
                if ((getline nxt) > 0) {
                    if (nxt ~ /^[0-9]+x[0-9]+\//) { print "Directories=" nxt; fixed = 1; next }
                    print; print nxt; next
                }
            }
            { print }
            END { exit fixed ? 0 : 1 }
        ' "$_f" > "$_tmp"; then
            cp "$_f" "$_f.bak-$(date +%Y%m%d-%H%M%S)"
            mv "$_tmp" "$_f"
            say "repaired malformed $_f (Directories value was wrapped onto its own line)"
        else
            rm -f "$_tmp"
        fi
    done

    # A user-level hicolor theme shadows the system one, so every directory its
    # index forgets is invisible to every application. Complete the index from
    # the system theme: that is what makes tray icons in status/ resolve.
    if command -v python3 >/dev/null 2>&1; then
        python3 "$PROJECT_DIR/scripts/repair-icon-index.py" || \
            say "warning: could not complete the hicolor index"
    fi
}

# ---------------------------------------------------------------- helpers ----
install_helpers() {
    run mkdir -p "$HOME/.local/bin"
    for helper in canopy-session canopy-screenshot canopy-update; do
        [ -f "$PROJECT_DIR/scripts/$helper" ] || continue
        # canopy-update lives in /usr/local/bin for image installs; symlinking a
        # copy into ~/.local/bin is what lets the timer and the menu entry call
        # it without depending on PATH order.
        run install -m755 "$PROJECT_DIR/scripts/$helper" "$HOME/.local/bin/$helper"
    done

    # Daily update check (systemd user timer), plus a launcher entry so the
    # check is discoverable from the application menu.
    if [ -d "$PROJECT_DIR/config/systemd/user" ] && \
       [ "${XDG_DATA_HOME:-$HOME/.local/share}/systemd/user" != "/" ]; then
        run mkdir -p "$XDG_CONFIG_HOME/systemd/user"
        for u in canopy-update.service canopy-update.timer; do
            run cp -f "$PROJECT_DIR/config/systemd/user/$u" "$XDG_CONFIG_HOME/systemd/user/$u"
        done
        # Copying a timer without enabling it is how update checks silently
        # never run. As root there is no user session to load it into, so the
        # command is only attempted for a user install.
        if [ "$is_system" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            systemctl --user enable --now canopy-update.timer >/dev/null 2>&1 \
                && say "update timer enabled (canopy-update.timer)" \
                || say "note: enable the update check with: systemctl --user enable --now canopy-update.timer"
        fi
    fi
    if [ -f "$PROJECT_DIR/assets/canopy-update.desktop" ]; then
        run mkdir -p "$XDG_DATA_HOME/applications"
        run cp -f "$PROJECT_DIR/assets/canopy-update.desktop" \
            "$XDG_DATA_HOME/applications/canopy-update.desktop"
    fi
    # Helper copies of the distribution knowledge, so `deps.sh` still works
    # after the release payload has been extracted to a temporary directory.
    run mkdir -p "$XDG_DATA_HOME/canopy/scripts"
    for f in lib-distro.sh deps.sh build-release.sh uninstall.sh; do
        [ -f "$PROJECT_DIR/scripts/$f" ] || continue
        run cp -f "$PROJECT_DIR/scripts/$f" "$XDG_DATA_HOME/canopy/scripts/$f"
    done
}

# ----------------------------------------------------------------- verify ----
# "Installed" should be checkable, not assumed. Every component the shell needs
# at runtime is listed here, so a half-install (missing icon theme, missing
# config seed, missing greeter assets) shows up here instead of as a blank
# panel or a stock palette later.
verify_install() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    _fail=0
    _check() {
        if [ -e "$2" ]; then
            say "  ok    $1"
        else
            say "  MISS  $1 ($2)"
            _fail=$((_fail + 1))
        fi
    }

    say ""
    say "verifying the install:"
    if [ "$is_system" -eq 1 ]; then
        _check "shell binary" /usr/local/bin/canopy
        _check "runtime assets" /usr/local/share/canopy/assets
        _check "session entry" /usr/local/share/wayland-sessions/canopy.desktop
        _check "session launcher" /usr/local/bin/canopy-session
        _check "default config" /usr/local/share/canopy/config.toml
        _check "desktop entry" /usr/local/share/applications/dev.canopy.Canopy.desktop
        _check "portal config" /usr/local/share/xdg-desktop-portal/canopy-portals.conf
        _check "window theme" /usr/share/themes/canopy
        _check "icon font" /usr/local/share/canopy/assets/fonts/canopy-tabler.ttf
        _check "wallpaper" /usr/local/share/backgrounds/canopy-wallpaper.png
        [ "$WITH_GREETER" -eq 1 ] && _check "greeter" /usr/local/bin/canopy-greeter-session
        if [ "$WITH_MANGOWC" -eq 1 ]; then
            _check "mangowc session" /usr/local/share/wayland-sessions/canopy-mangowc.desktop
            _check "mangowc config" /usr/local/share/canopy/mangowc/config.conf
        fi
    else
        _check "shell binary" "$HOME/.local/bin/canopy"
        _check "runtime assets" "$XDG_DATA_HOME/canopy/assets"
        _check "session launcher" "$HOME/.local/bin/canopy-session"
        _check "user config" "$XDG_CONFIG_HOME/canopy/config.toml"
        _check "labwc rc.xml" "$XDG_CONFIG_HOME/labwc/rc.xml"
        _check "icon theme alias" "$XDG_DATA_HOME/icons/canopy/index.theme"
        _check "theme" "$XDG_DATA_HOME/themes/canopy"
        _check "fonts" "$XDG_DATA_HOME/fonts/canopy/SpaceGrotesk-Regular.ttf"
    fi
    if [ "$_fail" -gt 0 ]; then
        say "  $_fail component(s) missing - re-run this installer"
    else
        say "  all components present"
    fi
}

install_binary
install_compositor
install_session
install_helpers
install_greeter
install_mangowc
seed_config
seed_labwc
seed_toolkits
seed_assets
seed_icon_theme
repair_icon_theme_index
ensure_dependencies
verify_install

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