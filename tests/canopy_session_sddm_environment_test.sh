#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
session="$root/scripts/canopy-session"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Use no-op binaries so this test never kills or starts a compositor in the
# developer's real session. SDDM's X11 greeter may leave DISPLAY exported into
# the Wayland session it launches.
mkdir -p "$tmp/home/.local/bin" "$tmp/runtime"
ln -s /usr/bin/true "$tmp/home/.local/bin/canopywc"
ln -s /usr/bin/true "$tmp/home/.local/bin/pkill"

output=$(env -i \
  HOME="$tmp/home" \
  XDG_RUNTIME_DIR="$tmp/runtime" \
  DISPLAY=:0 \
  PATH=/usr/bin:/bin \
  sh "$session" 2>&1)

case "$output" in
  *"starting nested"*)
    printf '%s\n' "canopy_session_sddm_environment_test: inherited DISPLAY selected nested mode" >&2
    exit 1
    ;;
esac

grep -q 'nested=no backend=auto' "$tmp/home/.cache/canopy-session.log"
grep -q 'clearing inherited X11 DISPLAY=:0' "$tmp/home/.cache/canopy-session.log"
printf '%s\n' "canopy_session_sddm_environment_test: PASS"