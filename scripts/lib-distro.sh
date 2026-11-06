#!/bin/sh
# lib-distro.sh — the one place that knows what a distribution is called.
#
# Canopy is a desktop environment: a compositor, a native shell, and the
# services around them. Distributions disagree about package names, so this file
# answers three questions:
#
#   canopy_family          which package-manager family is this?
#   canopy_pkgs runtime    what do I install to run Canopy?
#   canopy_pkgs build      what do I need to build Canopy from source?
#
# Sourced by scripts/install.sh, scripts/deps.sh and scripts/build-release.sh.
#
#   sh scripts/lib-distro.sh family
#   sh scripts/lib-distro.sh runtime
#   CANOPY_FAMILY=debian sh scripts/lib-distro.sh runtime
#
# Canopy's shell is a native C++ binary with no Qt or GTK dependency, so the
# runtime list is only the compositor, the portals and the system services.

canopy_family() {
    if [ -n "${CANOPY_FAMILY:-}" ]; then
        printf '%s\n' "$CANOPY_FAMILY"
        return
    fi

    _cf_id=""
    _cf_like=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        _cf_id="${ID:-}"
        _cf_like="${ID_LIKE:-}"
    fi

    for _cf_c in $_cf_id $_cf_like; do
        case "$_cf_c" in
            arch|cachyos|endeavouros|manjaro|garuda|artix) printf 'arch\n'; return ;;
            fedora|rhel|centos|nobara) printf 'fedora\n'; return ;;
            debian|ubuntu|linuxmint|pop|zorin|elementary|neon) printf 'debian\n'; return ;;
            opensuse*|suse|sles|tumbleweed) printf 'suse\n'; return ;;
        esac
    done

    for _cf_c in pacman dnf apt-get zypper; do
        if command -v "$_cf_c" >/dev/null 2>&1; then
            case "$_cf_c" in
                pacman) printf 'arch\n' ;;
                dnf) printf 'fedora\n' ;;
                apt-get) printf 'debian\n' ;;
                zypper) printf 'suse\n' ;;
            esac
            return
        fi
    done

    printf 'unknown\n'
}

canopy_distro_name() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        printf '%s\n' "${PRETTY_NAME:-${NAME:-unknown}}"
        return
    fi
    printf 'unknown\n'
}

# canopy_pkgs runtime | build
canopy_pkgs() {
    _cp_family="$(canopy_family)"
    _cp_role="${1:-runtime}"

    case "$_cp_family:$_cp_role" in
        # ---------------------------------------------------------------- arch
        arch:runtime)
            # libseat is provided by seatd on Arch, not by a package called
            # "libseat": naming it directly breaks the install.
            printf '%s\n' "wlroots0.20 seatd libdrm libxkbcommon libinput mesa wayland wayland-protocols xorg-xwayland pipewire wireplumber networkmanager bluez upower polkit polkit-gnome grim slurp wl-clipboard xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk tomlplusplus sdbus-cpp libical" ;;
        # Optional second session (beta). Install with: install.sh --with-mangowc
        arch:mangowc)
            printf '%s\n' "mangowm" ;;
        arch:build)
            printf '%s\n' "base-devel meson ninja git wayland wayland-protocols sdbus-cpp libglvnd freetype2 fontconfig cairo pango harfbuzz libxkbcommon glib2 libsecret libsodium pipewire wireplumber polkit pam curl libwebp libjxl libsndfile librsvg libqalculate libxml2 md4c tomlplusplus libical nlohmann-json stb jemalloc" ;;

        # -------------------------------------------------------------- fedora
        fedora:runtime)
            printf '%s\n' "wlroots seatd libdrm libxkbcommon libinput mesa-dri-drivers xorg-x11-server-Xwayland NetworkManager pipewire wireplumber bluez upower polkit polkit-gnome grim slurp wl-clipboard xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr tomlplusplus sdbus-c++ libical" ;;
        fedora:build)
            printf '%s\n' "meson gcc-c++ just git wayland-devel wayland-protocols-devel libEGL-devel mesa-libGLES-devel freetype-devel fontconfig-devel cairo-devel pango-devel harfbuzz-devel libxkbcommon-devel glib2-devel libsecret-devel libsodium-devel sdbus-cpp-devel pipewire-devel wireplumber-devel pam-devel polkit-devel libcurl-devel libwebp-devel libjxl-devel libsndfile-devel librsvg2-devel libqalculate-devel libxml2-devel md4c-devel tomlplusplus-devel libical-devel json-devel stb_image_resize2-devel stb_image_write-devel jemalloc-devel" ;;
        # MangoWC is not packaged for this family; build it from source.
        fedora:mangowc)
            printf '\n' ;;

        # -------------------------------------------------------------- debian
        debian:runtime)
            printf '%s\n' "seatd libseat1 libdrm2 libxkbcommon0 libinput10 libegl1 xwayland pipewire wireplumber network-manager bluez upower polkitd polkit-gnome grim slurp wl-clipboard xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr libtomlplusplus3 libsdbus-c++2 libical3" ;;
        debian:build)
            printf '%s\n' "build-essential meson ninja-build just git libwayland-dev wayland-protocols libegl-dev libgles-dev libfreetype-dev libfontconfig-dev libcairo2-dev libpango1.0-dev libharfbuzz-dev libxkbcommon-dev libglib2.0-dev libsecret-1-dev libsodium-dev libsdbus-c++-dev libpipewire-0.3-dev libwireplumber-0.5-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libcurl4-openssl-dev libwebp-dev libjxl-dev libsndfile1-dev librsvg2-dev libqalculate-dev libxml2-dev libmd4c-dev libtomlplusplus-dev libical-dev nlohmann-json3-dev libstb-dev libjemalloc-dev" ;;

        # ---------------------------------------------------------------- suse
        suse:runtime)
            printf '%s\n' "seatd libseat1 libdrm2 libxkbcommon0 libinput10 Mesa-libEGL1 xwayland pipewire wireplumber NetworkManager bluez upower polkit polkit-gnome grim slurp wl-clipboard xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr tomlplusplus sdbus-c++ libical3" ;;
        suse:build)
            printf '%s\n' "meson gcc-c++ just git wayland-devel wayland-protocols-devel Mesa-libEGL-devel Mesa-libGLESv2-devel freetype2-devel fontconfig-devel cairo-devel pango-devel harfbuzz-devel libxkbcommon-devel glib2-devel libsecret-devel libsodium-devel sdbus-cpp-devel pipewire-devel wireplumber-devel pam-devel polkit-devel libcurl-devel libwebp-devel libjxl-devel libsndfile-devel librsvg-devel libqalculate-devel libxml2-devel md4c-devel tomlplusplus-devel libical-devel nlohmann_json-devel stb-devel jemalloc-devel" ;;
        # MangoWC is not packaged for this family; build it from source.
        suse:mangowc)
            printf '\n' ;;
        debian:mangowc)
            printf '\n' ;;

        *)
            printf '\n' ;;
    esac
}

canopy_install_cmd() {
    case "$(canopy_family)" in
        arch) printf 'pacman -S --needed --noconfirm\n' ;;
        fedora) printf 'dnf install -y\n' ;;
        debian) printf 'apt-get install -y\n' ;;
        suse) printf 'zypper install -y\n' ;;
        *) printf '\n' ;;
    esac
}

canopy_install_hint() {
    _ih_role="${1:-runtime}"
    _ih_pkgs="$(canopy_pkgs "$_ih_role")"
    case "$(canopy_family)" in
        arch) printf 'sudo pacman -S --needed %s\n' "$_ih_pkgs" ;;
        fedora) printf 'sudo dnf install %s\n' "$_ih_pkgs" ;;
        debian) printf 'sudo apt-get install %s\n' "$_ih_pkgs" ;;
        suse) printf 'sudo zypper install %s\n' "$_ih_pkgs" ;;
        *) printf '# unknown distribution: install labwc and the portals manually\n' ;;
    esac
}

# canopy_pkg_available NAME -> 0 available, 1 not, 2 cannot tell
canopy_pkg_available() {
    _pa_pkg="$1"
    case "$(canopy_family)" in
        arch)
            command -v pacman >/dev/null 2>&1 || return 2
            pacman -Si "$_pa_pkg" >/dev/null 2>&1 && return 0
            pacman -Q "$_pa_pkg" >/dev/null 2>&1 && return 0
            return 1 ;;
        fedora)
            command -v dnf >/dev/null 2>&1 || return 2
            rpm -q "$_pa_pkg" >/dev/null 2>&1 && return 0
            dnf -q info "$_pa_pkg" >/dev/null 2>&1 && return 0
            return 1 ;;
        debian)
            command -v apt-cache >/dev/null 2>&1 || return 2
            dpkg -s "$_pa_pkg" >/dev/null 2>&1 && return 0
            apt-cache show "$_pa_pkg" >/dev/null 2>&1 && return 0
            return 1 ;;
        *) return 2 ;;
    esac
}

# Best icon theme present, so Qt/GTK never point at a theme we do not have.
canopy_icon_theme() {
    for _it_t in kora Win11-black Win11-black-dark McMojave-circle Papirus Papirus-Dark breeze breeze-dark Adwaita hicolor; do
        for _it_d in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" /usr/share/icons /usr/local/share/icons; do
            if [ -d "$_it_d/$_it_t" ]; then
                printf '%s\n' "$_it_t"
                return
            fi
        done
    done
    printf 'hicolor\n'
}

# Best cursor theme present.
canopy_cursor_theme() {
    for _ct_t in Bibata-Modern-Ice breeze_cursors Adwaita default; do
        for _ct_d in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" /usr/share/icons; do
            if [ -d "$_ct_d/$_ct_t/cursors" ]; then
                printf '%s\n' "$_ct_t"
                return
            fi
        done
    done
    printf 'Adwaita\n'
}

# ---------------------------------------------------------------------- CLI ---
if [ "${0##*/}" = "lib-distro.sh" ]; then
    case "${1:-}" in
        family)   canopy_family ;;
        name)     canopy_distro_name ;;
        runtime)  canopy_pkgs runtime ;;
        build)    canopy_pkgs build ;;
        mangowc)  canopy_pkgs mangowc ;;
        hint)     canopy_install_hint "${2:-runtime}" ;;
        theme)    canopy_icon_theme ;;
        cursor)   canopy_cursor_theme ;;
        available) canopy_pkg_available "${2:?package name}" ;;
        *) printf 'usage: %s {family|name|runtime|build|mangowc|hint [runtime|build]|theme|cursor|available PKG}\n' "$0" >&2; exit 2 ;;
    esac
fi