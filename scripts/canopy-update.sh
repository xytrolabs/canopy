#!/bin/sh
# canopy-update — check for and install a newer Canopy release.
#
#   canopy-update check            # human readable
#   canopy-update check --json     # {"installed":..,"latest":..,"update_available":..}
#   canopy-update apply [--yes]    # download, verify, install, no questions
#
# Releases come from GitHub (github.com/xytrolabs/canopy), with the project site
# as a mirror. Resolution order:
#
#   1. CANOPY_BASE_URL, if set      — a self-hosted mirror (and what the tests
#                                     point at a local server)
#   2. GitHub Releases              — the canonical source
#   3. https://xytro.site/canopy    — mirror, used if GitHub is unreachable
#
# Override the repository with CANOPY_REPO, or force one source with
# CANOPY_UPDATE_SOURCE=github|site.
#
# Canopy is not packaged by any distribution, so it carries its own update path:
# the same self-extracting payload that installed it is what upgrades it. The
# shell calls this script from the "Software updates" card and, when
# auto-update is enabled, once a day.
set -eu

GH_REPO="${CANOPY_REPO:-xytrolabs/canopy}"
SITE_URL="${CANOPY_SITE_URL:-https://xytro.site/canopy}"
BASE_URL="${CANOPY_BASE_URL:-}"
SOURCE="${CANOPY_UPDATE_SOURCE:-auto}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

MODE="${1:-check}"
shift 2>/dev/null || true
ASSUME_YES=0
JSON=0
for a in "$@"; do
    case "$a" in
        --json) JSON=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
    esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'canopy-update: %s\n' "$*" >&2; exit 1; }

# Where is this install? A user install keeps VERSION next to the shell; a
# system install keeps it in /usr/local/share/canopy.
shell_dir() {
    for d in \
        "${XDG_CONFIG_HOME:-$HOME/.config}/canopy" \
        "$HOME/.config/canopy" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/noctalia" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/canopy" \
        "$HOME/.config/noctalia" \
        "$HOME/.config/quickshell/canopy" \
        /usr/local/share/canopy
    do
        [ -f "$d/VERSION" ] && { printf '%s\n' "$d"; return; }
    done
    printf '%s\n' ""
}

INSTALL_DIR="$(shell_dir)"
INSTALLED=""
if [ -n "$INSTALL_DIR" ]; then
    INSTALLED="$(tr -d ' \t\r\n' < "$INSTALL_DIR/VERSION")"
elif [ -f "$PROJECT_DIR/VERSION" ]; then
    INSTALLED="$(tr -d ' \t\r\n' < "$PROJECT_DIR/VERSION")"   # running from a checkout
fi

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
    else die "need curl or wget"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/canopy-update.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Release resolution: sets LATEST, REL_BASE and REL_SOURCE.
# ---------------------------------------------------------------------------
LATEST=""
REL_BASE=""
REL_SOURCE=""
GH_SHA256=""

# GitHub: read the newest release tag, then build the asset URLs from it.
# Constructing the URLs instead of parsing the asset list keeps this working
# with plain sed when python3 and jq are both absent.
resolve_github() {
    [ "$SOURCE" = "site" ] && return 1
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
    fetch "https://api.github.com/repos/$GH_REPO/releases/latest" "$TMP/gh.json" 2>/dev/null || return 1
    _tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP/gh.json" | head -1)"
    [ -n "$_tag" ] || return 1
    LATEST="$(printf '%s' "$_tag" | sed 's/^v//')"
    GH_SHA256="$(awk -v asset="canopy-$LATEST.run" '
        /"name"[[:space:]]*:/ { in_asset = index($0, "\"" asset "\"") > 0 }
        in_asset && /"digest"[[:space:]]*:/ {
            line = $0
            sub(/^.*sha256:/, "", line)
            sub(/".*/, "", line)
            if (length(line) == 64 && line !~ /[^0-9a-fA-F]/) print line
            exit
        }
    ' "$TMP/gh.json")"
    REL_BASE="https://github.com/$GH_REPO/releases/download/$_tag"
    REL_SOURCE="github"
    return 0
}

# Static mirror: releases/latest holds the payload's filename.
resolve_site() {
    _site="$1"
    [ -n "$_site" ] || return 1
    fetch "$_site/releases/latest" "$TMP/latest" 2>/dev/null || return 1
    _name="$(tr -d ' \t\r\n' < "$TMP/latest")"
    [ -n "$_name" ] || return 1
    LATEST="$(printf '%s' "$_name" | sed 's/^canopy-//; s/\.run$//')"
    REL_BASE="$_site/releases"
    REL_SOURCE="${2:-site}"
    return 0
}

if [ "$SOURCE" = "github" ]; then
    resolve_github || true
elif [ -n "$BASE_URL" ]; then
    # An explicit mirror is what the tests use; honour it first.
    resolve_site "$BASE_URL" "mirror" || true
else
    resolve_github || resolve_site "$SITE_URL" || true
fi

# Dotted dates compare correctly as strings (YYYY.MM.DD, zero padded); anything
# else needs the newest to simply differ.
update_available() {
    [ -z "$LATEST" ] && { echo "no"; return; }
    [ -z "$INSTALLED" ] && { echo "yes"; return; }
    if [ "$LATEST" = "$INSTALLED" ]; then echo "no"; else echo "yes"; fi
}

AVAILABLE="$(update_available)"

if [ "$MODE" = "check" ]; then
    if [ "$JSON" -eq 1 ]; then
        if [ -z "$LATEST" ]; then
            printf '{"installed":"%s","latest":"","update_available":false,"error":"no release found"}\n' "$INSTALLED"
        else
            printf '{"installed":"%s","latest":"%s","update_available":%s,"source":"%s"}\n' \
                "$INSTALLED" "$LATEST" "$([ "$AVAILABLE" = yes ] && echo true || echo false)" "$REL_SOURCE"
        fi
        exit 0
    fi
    if [ -z "$LATEST" ]; then
        say "installed: ${INSTALLED:-unknown}"
        say "no release found."
        say "  GitHub: https://github.com/$GH_REPO/releases"
        say "  site:   $SITE_URL"
        say "Neither answered, or no release has been published yet."
        exit 1
    fi
    say "installed: ${INSTALLED:-unknown}"
    say "latest:    $LATEST  ($REL_SOURCE)"
    if [ "$AVAILABLE" = "yes" ]; then
        say "status:    update available — run 'canopy-update apply'"
    else
        say "status:    up to date"
    fi
    exit 0
fi

[ "$MODE" = "apply" ] || die "usage: canopy-update {check [--json] | apply [--yes]}"

[ -n "$LATEST" ] || die "no release found (github.com/$GH_REPO/releases, $SITE_URL)"
if [ "$AVAILABLE" = "no" ]; then
    say "Already up to date ($INSTALLED)."
    exit 0
fi

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    printf 'Install Canopy %s (installed: %s)? [y/N] ' "$LATEST" "${INSTALLED:-none}"
    read -r reply || reply="n"
    case "$reply" in y|Y|yes|YES) ;; *) die "cancelled" ;; esac
fi

say "downloading canopy-$LATEST.run from $REL_SOURCE"
fetch "$REL_BASE/canopy-$LATEST.run" "$TMP/canopy.run" || die "download failed: $REL_BASE/canopy-$LATEST.run"

# Verify before executing anything. GitHub publishes the digest in release API
# metadata, not as a separate SHA256SUMS asset. The static site mirror does
# publish SHA256SUMS alongside the payload.
EXPECTED=""
if [ "$REL_SOURCE" = "github" ]; then
    EXPECTED="$GH_SHA256"
    [ -n "$EXPECTED" ] || die "GitHub release has no SHA-256 digest for canopy-$LATEST.run"
elif fetch "$REL_BASE/SHA256SUMS" "$TMP/SHA256SUMS" 2>/dev/null; then
    EXPECTED="$(grep " canopy-$LATEST.run\$" "$TMP/SHA256SUMS" | awk '{print $1}')"
fi

if [ -n "$EXPECTED" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$TMP/canopy.run" | awk '{print $1}')"
    else
        ACTUAL="$(shasum -a 256 "$TMP/canopy.run" | awk '{print $1}')"
    fi
    [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch — refusing to install"
    say "sha256 verified"
else
    say "warning: no checksum for canopy-$LATEST.run"
fi

say "installing"
sh "$TMP/canopy.run"

# The payload stamps its own VERSION, but the release name is the identity this
# updater compares against, so record it too: a payload rebuilt from a checkout
# would otherwise keep reporting its build date and offer the same update again.
NEW_DIR="$(shell_dir)"
if [ -n "$NEW_DIR" ]; then
    printf '%s\n' "$LATEST" > "$NEW_DIR/VERSION"
fi

say "done — installed $LATEST"
say "restart the shell to pick it up: pkill -x canopy"
