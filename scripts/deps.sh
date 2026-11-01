#!/bin/sh
# deps.sh — check and install everything Canopy needs, on any distribution.
#
#   sh scripts/deps.sh plan          # what this machine is missing (default)
#   sh scripts/deps.sh install       # put it there (needs sudo, asks first)
#   sh scripts/deps.sh plan --json   # machine-readable
#
# The package names come from lib-distro.sh, which is the only place that knows
# about distributions. `plan` never changes anything.
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

# Everything Canopy actually launches or links against. `labwc` and
# `quickshell` are executables; the rest are services or Qt QML plugins, which
# is why they are checked by name rather than by running them.
check_bin() { command -v "$1" >/dev/null 2>&1; }

MISSING_BIN=""
PRESENT_BIN=""
for b in labwc quickshell; do
    if check_bin "$b"; then PRESENT_BIN="$PRESENT_BIN $b"; else MISSING_BIN="$MISSING_BIN $b"; fi
done

# A binary can be present and still not be installable elsewhere; report what
# the release itself provides so "missing" means the same thing everywhere.
rc=0
canopy_pkg_available quickshell || rc=$?
case $rc in
    0) SHELL_PKG="available from $(canopy_family) packages" ;;
    1) SHELL_PKG="NOT packaged for this release" ;;
    *) SHELL_PKG="cannot tell (no package manager on PATH)" ;;
esac

# Qt QML modules: probe the import paths instead of relying on distributions
# shipping identically-named binary packages.
qml_module_present() {
    for d in \
        /usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml \
        "${XDG_DATA_HOME:-$HOME/.local/share}/../lib/qt6/qml"
    do
        [ -e "$d/$1" ] && return 0
    done
    return 1
}

MISSING_QML=""
for m in QtQuick QtQuick.Controls QtQuick.Layouts QtQuick.Window Qt5Compat; do
    qml_module_present "$(printf '%s' "$m" | tr '.' '/')" || MISSING_QML="$MISSING_QML $m"
done

SOURCE_NOTE="$(canopy_shell_from_source)"

say() { printf '%s\n' "$*"; }

if [ "$MODE" = "plan" ]; then
    if [ "$FORMAT" = "json" ]; then
        printf '{"family":"%s","distro":"%s","packages":"%s","missing_binaries":"%s","missing_qml":"%s","shell_from_source":"%s"}\n' \
            "$FAMILY" "$DISTRO" "$RUNTIME" \
            "$(printf '%s' "$MISSING_BIN" | sed 's/^ *//')" \
            "$(printf '%s' "$MISSING_QML" | sed 's/^ *//')" \
            "$(printf '%s' "$SOURCE_NOTE" | cut -d' ' -f1)"
        exit 0
    fi

    say "distribution : $DISTRO ($FAMILY)"
    say "packages     : $RUNTIME"
    say "quickshell   : $SHELL_PKG"
    if [ -n "$PRESENT_BIN" ]; then
        say "present      :$PRESENT_BIN"
    fi
    if [ -n "$MISSING_BIN" ]; then
        say "missing      :$MISSING_BIN"
    elif [ -z "$PRESENT_BIN" ]; then
        say "missing      : labwc quickshell"
    else
        say "missing      : nothing on this machine"
    fi
    if [ -n "$MISSING_QML" ]; then
        say "missing qml  :$MISSING_QML"
    fi
    say ""
    say "install with :"
    canopy_install_hint | sed 's/^/  /'
    case "$SOURCE_NOTE" in
        yes*)
            say ""
            say "shell runtime: $(printf '%s' "$SOURCE_NOTE" | cut -d' ' -f2-)"
            say "               sh scripts/build-quickshell.sh" ;;
    esac
    exit 0
fi

if [ "$MODE" != "install" ]; then
    say "usage: $0 {plan|install} [--json]" >&2
    exit 2
fi

# ----------------------------------------------------------------- install ---
if [ -z "$MISSING_BIN$MISSING_QML" ]; then
    say "Nothing to do: the runtime is already installed."
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

# The shell runtime is not a package everywhere - say so before pulling a
# hundred packages that will not include it.
if ! canopy_pkg_available quickshell; then
    say "quickshell is not available as a package here:"
    say "  $(canopy_shell_from_source | cut -d' ' -f2-)"
    say "  build it after this finishes: sh scripts/build-quickshell.sh"
    say ""
    case "$FAMILY" in
        debian) say "  (on trixie: apt-get install -t trixie-backports quickshell may be enough)" ;;
    esac
    say ""
fi

set -x
case "$FAMILY" in
    arch)
        $SUDO pacman -S --needed --noconfirm $RUNTIME ;;
    fedora)
        # --skip-unavailable keeps the run going when one name is not in this
        # Fedora release; the plan output already said which one.
        $SUDO dnf install -y --skip-unavailable $RUNTIME ;;
    debian)
        $SUDO apt-get update
        # quickshell only exists in backports on trixie; the rest come from the
        # release itself.
        $SUDO apt-get install -y $(printf '%s' "$RUNTIME" | tr ' ' '\n' | grep -v '^quickshell$' | tr '\n' ' ') || true
        $SUDO apt-get install -y -t trixie-backports quickshell 2>/dev/null \
            || say "quickshell not installed from backports - build it: sh scripts/build-quickshell.sh" ;;
    suse)
        $SUDO zypper install -y $RUNTIME ;;
    *)
        set +x
        say "unknown distribution - install these yourself:" >&2
        say "  $RUNTIME" >&2
        exit 1 ;;
esac

set +x
say ""
say "Done. Re-run 'sh scripts/deps.sh plan' to confirm."
