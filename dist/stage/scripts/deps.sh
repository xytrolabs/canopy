#!/bin/sh
# deps.sh — check and install everything Canopy needs, on any distribution.
#
#   sh scripts/deps.sh plan            # what this machine is missing (default)
#   sh scripts/deps.sh plan --json     # machine-readable
#   sh scripts/deps.sh install         # put it there (needs sudo, asks first)
#   sh scripts/deps.sh build           # show the build dependency command
#
# Package names come from lib-distro.sh, which is the only file that knows about
# distributions. `plan` never changes anything.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib-distro.sh
. "$PROJECT_DIR/scripts/lib-distro.sh"

MODE="${1:-plan}"
FORMAT="text"
case "${2:-}" in
    --json|json) FORMAT="json" ;;
esac

FAMILY="$(canopy_family)"
DISTRO="$(canopy_distro_name)"
RUNTIME="$(canopy_pkgs runtime)"

check_bin() { command -v "$1" >/dev/null 2>&1; }

# Binaries the session itself needs. Everything else is a D-Bus service that is
# activated on demand and noticed by the shell if it is missing.
MISSING_BIN=""
PRESENT_BIN=""
for b in labwc canopy; do
    if check_bin "$b"; then PRESENT_BIN="$PRESENT_BIN $b"; else MISSING_BIN="$MISSING_BIN $b"; fi
done

MISSING_PORTAL=""
for p in xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr; do
    check_bin "$p" >/dev/null 2>&1 || canopy_pkg_available "$p" >/dev/null 2>&1 || MISSING_PORTAL="$MISSING_PORTAL $p"
done

say() { printf '%s\n' "$*"; }

if [ "$MODE" = "plan" ]; then
    if [ "$FORMAT" = "json" ]; then
        printf '{"family":"%s","distro":"%s","packages":"%s","missing_binaries":"%s","present_binaries":"%s"}\n' \
            "$FAMILY" "$DISTRO" "$RUNTIME" \
            "$(printf '%s' "$MISSING_BIN" | sed 's/^ *//')" \
            "$(printf '%s' "$PRESENT_BIN" | sed 's/^ *//')"
        exit 0
    fi

    say "distribution : $DISTRO ($FAMILY)"
    say "packages     : $RUNTIME"
    if [ -n "$PRESENT_BIN" ]; then
        say "present      :$PRESENT_BIN"
    fi
    if [ -n "$MISSING_BIN" ]; then
        say "missing      :$MISSING_BIN"
    else
        say "missing      : nothing on this machine"
    fi
    if [ -n "$MISSING_PORTAL" ]; then
        say "portals      : missing$MISSING_PORTAL (file dialogs and screen sharing will not work)"
    fi
    say ""
    say "install with :"
    canopy_install_hint runtime | sed 's/^/  /'
    say ""
    say "build with   :"
    canopy_install_hint build | sed 's/^/  /'
    exit 0
fi

if [ "$MODE" = "build" ]; then
    canopy_install_hint build
    exit 0
fi

if [ "$MODE" != "install" ]; then
    say "usage: $0 {plan|install|build} [--json]" >&2
    exit 2
fi

# ----------------------------------------------------------------- install ---
if [ -z "$MISSING_BIN$MISSING_PORTAL" ]; then
    say "Nothing to do: the Canopy runtime is already installed."
    exit 0
fi

say "distribution : $DISTRO ($FAMILY)"
say "package list : $RUNTIME"
say ""
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
    command -v sudo >/dev/null 2>&1 || { say "need root or sudo to install packages" >&2; exit 1; }
fi

set -x
case "$FAMILY" in
    arch) $SUDO pacman -S --needed --noconfirm $RUNTIME ;;
    fedora) $SUDO dnf install -y --skip-unavailable $RUNTIME ;;
    debian)
        $SUDO apt-get update
        $SUDO apt-get install -y $RUNTIME ;;
    suse) $SUDO zypper install -y $RUNTIME ;;
    *)
        set +x
        say "unknown distribution - install these yourself:" >&2
        say "  $RUNTIME" >&2
        exit 1 ;;
esac

set +x
say ""
say "Done. Re-run 'sh scripts/deps.sh plan' to confirm."