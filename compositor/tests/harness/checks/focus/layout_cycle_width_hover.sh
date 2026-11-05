#!/usr/bin/env bash
# Cycling the focused column to a narrower preset can expose its neighbor beneath a stationary pointer. Motion inside
# that newly exposed column must refresh hover focus without requiring a border crossing.
set -euo pipefail

readonly OUTPUT_W=1280
readonly OUTPUT_H=720
readonly POINTER="${CANOPY_POINTER_CLIENT:-./build-debug/tests/pointer-client}"
readonly CLIENT="${CANOPY_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"

spawn_client() { "$CLIENT" "$1" 1200 700 > /dev/null 2>&1 & }

wait_for_count() {
  local want=$1
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq 'length') -eq $want ]] && return 0
    sleep 0.05
  done
  echo "expected $want windows, got: $("$CANOPY" windows --json)"
  return 1
}

wait_for_active() {
  local want=$1
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq -r '[.[] | select(.active) | .title] | if length == 1 then .[0] else "none" end') == "$want" ]] && return 0
    sleep 0.05
  done
  echo "expected '$want' to be active: $("$CANOPY" windows --json)"
  return 1
}

cat >> "$CANOPY_CONFIG" <<'EOF'

[layout]
mode = "scrolling"
extent_presets = [0.4, 0.6]

[layout.scrolling]
default_extent_fraction = 0.6

[animation]
duration_ms = 1
curve = "linear"

[input.focus]
follows_mouse = true
EOF
"$CANOPY" msg config-reload > /dev/null

spawn_client scene-cycle-left
wait_for_count 1
spawn_client scene-cycle-right
wait_for_count 2
sleep 0.1

"$POINTER" "$OUTPUT_W" "$OUTPUT_H" move 100 360
wait_for_active scene-cycle-left
sleep 0.1
right_x=$("$CANOPY" windows --json | jq -r '.[] | select(.title == "scene-cycle-right") | .x')
pointer_x=$((right_x - 50))
"$POINTER" "$OUTPUT_W" "$OUTPUT_H" move "$pointer_x" 360
wait_for_active scene-cycle-left

"$CANOPY" msg window-cycle-primary-extent-back > /dev/null
sleep 0.1
wait_for_active scene-cycle-left

"$POINTER" "$OUTPUT_W" "$OUTPUT_H" move "$((pointer_x + 1))" 360
wait_for_active scene-cycle-right

echo "motion refreshed hover focus after a primary extent preset exposed another column beneath the pointer"
