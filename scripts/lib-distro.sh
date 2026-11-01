#!/bin/sh
# lib-distro.sh — the one place that knows what a distribution is called.
#
# Canopy runs on any Wayland session that has labwc, quickshell and a Qt 6 QML
# runtime. Distributions disagree about package names, and some do not package
# the shell runtime at all, so this file answers three questions:
#
#   canopy_family          which package-manager family is this?
#   canopy_pkgs runtime    what do I install to make Canopy run?
#   canopy_pkgs build      what do I need to build the shell from source?
#
# Sourced by scripts/install.sh and scripts/deps.sh; also usable directly:
#
#   sh scripts/lib-distro.sh family
#   sh scripts/lib-distro.sh runtime        # with the right package manager
#   CANOPY_FAMILY=debian sh scripts/lib-distro.sh runtime
#
# CANOPY_FAMILY overrides detection (used by the tests and by image builds).
#
# Version notes verified 2026-11-01 against each distribution's own index:
#   Arch / CachyOS  labwc 0.20.2, quickshell 0.3.2   (both in `extra`)
#   Fedora 43       labwc 0.9.6, quickshell absent
#   Fedora 44/45    labwc 0.20.2 (F45) / 0.9.6 (F44), quickshell 0.2.1
#   Debian trixie   labwc 0.8.3, quickshell 0.3.0 in trixie-backports
#   Debian forky    labwc 0.20.2, quickshell 0.3.2
# Anything older than that cannot be met from packages, which is what
# canopy_shell_from_source / scripts/build-quickshell.sh are for.

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

    # Last resort: the package manager that exists beats os-release.
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
printf '%s\n' "labwc quickshell qt6-declarative qt6-wayland qt6-5compat qt6-svg xorg-xwayland pipewire networkmanager bluez upower grim wl-clipboard slurp qt6ct qt6ct" ;;
        arch:build)
            printf '%s\n' "base-devel cmake ninja git qt6-base qt6-declarative qt6-wayland qt6-shadertools jemalloc wayland wayland-protocols libxkbcommon pipewire networkmanager bluez upower" ;;

        # -------------------------------------------------------------- fedora
        fedora:runtime)
printf '%s\n' "labwc quickshell qt6-qtdeclarative qt6-qtwayland qt6-qt5compat qt6-qtsvg qt6-qtbase NetworkManager bluez pipewire grim upower wl-clipboard slurp qt6ct" ;;
        fedora:build)
            printf '%s\n' "cmake ninja-build gcc-c++ git qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwayland-devel qt6-qt5compat-devel jemalloc-devel wayland-devel wayland-protocols-devel libxkbcommon-devel pipewire-devel pulseaudio-libs-devel NetworkManager-libnm-devel upower-devel" ;;

        # -------------------------------------------------------------- debian
        # qml6-module-* names verified against the trixie Packages index;
        # quickshell itself only exists in trixie-backports and forky.
        debian:runtime)
printf '%s\n' "labwc quickshell qt6-wayland qml6-module-qtquick qml6-module-qtqml qml6-module-qtqml-workerscript qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-dialogs qml6-module-qt5compat-graphicaleffects libqt6svg6 xwayland pipewire network-manager bluez upower grim wl-clipboard slurp qt6ct qt6ct" ;;
        debian:build)
            printf '%s\n' "build-essential cmake ninja-build git qt6-base-dev qt6-declarative-dev qt6-wayland-dev qml6-module-qtquick qt6-svg-dev libjemalloc-dev libwayland-dev wayland-protocols libxkbcommon-dev libpipewire-0.3-dev libpulse-dev libnm-dev libupower-glib-dev" ;;

        # ---------------------------------------------------------------- suse
        # Not exercised: openSUSE does not package the shell runtime in a way
        # that has been verified, so only the base compositor is listed.
        suse:runtime)
printf '%s\n' "labwc qt6-wayland qt6-declarative-imports pipewire networkmanager bluez upower grim wl-clipboard slurp qt6ct" ;;
        suse:build)
            printf '%s\n' "gcc-c++ cmake ninja git qt6-base-devel qt6-declarative-devel qt6-wayland-devel wayland-devel wayland-protocols-devel libxkbcommon-devel" ;;

        *)
            printf '\n' ;;
    esac
}

# Which package manager command installs a list of packages?
canopy_install_cmd() {
    _ci_family="$(canopy_family)"
    case "$_ci_family" in
        arch) printf 'pacman -S --needed --noconfirm\n' ;;
        fedora) printf 'dnf install -y\n' ;;
        debian) printf 'apt-get install -y\n' ;;
        suse) printf 'zypper install -y\n' ;;
        *) printf '\n' ;;
    esac
}

# Human-readable command for the docs, with line wrapping left to the caller.
canopy_install_hint() {
    _ih_family="$(canopy_family)"
    _ih_pkgs="$(canopy_pkgs runtime)"
    case "$_ih_family" in
        arch) printf 'sudo pacman -S --needed %s\n' "$_ih_pkgs" ;;
        fedora) printf 'sudo dnf install %s\n' "$_ih_pkgs" ;;
        debian)
            printf 'sudo apt-get install %s\n' "$_ih_pkgs"
            printf '# quickshell lives in trixie-backports: add the suite, then\n'
            printf '#   sudo apt-get install -t trixie-backports quickshell\n'
            ;;
        suse) printf 'sudo zypper install %s\n' "$_ih_pkgs" ;;
*) printf '# unknown distribution: install labwc and quickshell manually\n' ;;
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

# Does this machine need the shell runtime built from source?
# Prints "yes <reason>" or "no".
canopy_shell_from_source() {
    if canopy_pkg_available quickshell; then
        printf 'no\n'
        return
    fi
    case "$(canopy_family)" in
        debian) printf 'yes quickshell is only in trixie-backports/forky on Debian\n' ;;
        fedora) printf 'yes quickshell is not packaged for this Fedora release\n' ;;
        arch) printf 'yes quickshell is missing from the configured repositories\n' ;;
        *) printf 'yes no package source known for this distribution\n' ;;
    esac
}

# Best icon theme present, so qt6ct never points at a theme we do not have.
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

# ---------------------------------------------------------------------- CLI ---
if [ "${0##*/}" = "lib-distro.sh" ]; then
    case "${1:-}" in
        family)   canopy_family ;;
        name)     canopy_distro_name ;;
        runtime)  canopy_pkgs runtime ;;
        build)    canopy_pkgs build ;;
        hint)     canopy_install_hint ;;
        theme)    canopy_icon_theme ;;
        source)   canopy_shell_from_source ;;
        available) canopy_pkg_available "${2:?package name}" ;;
        *) printf 'usage: %s {family|name|runtime|build|hint|theme|source|available PKG}\n' "$0" >&2; exit 2 ;;
    esac
fi
