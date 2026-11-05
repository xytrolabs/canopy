#!/usr/bin/env bash
# Each event must introduce a shader-only color during its transition and
# remove that color afterwards. Geometry settling alone cannot satisfy this.
set -euo pipefail
cat > "$CANOPY_RUNTIME_DIR/fixture-1.glsl" <<'GLSL'
vec4 animation(vec2 uv) { return vec4(1.0, 0.0, 0.0, 1.0); }
GLSL
readonly BASE="$CANOPY_RUNTIME_DIR/shader-events-base.toml"
readonly IMAGE="$CANOPY_RUNTIME_DIR/shader-events.png"
cp "$CANOPY_CONFIG" "$BASE"

configure() {
  cat "$BASE" > "$CANOPY_CONFIG"
  cat >> "$CANOPY_CONFIG" <<EOF

[animation]
duration_ms = 300
curve = "linear"
[animation.windows_in]
enabled = false
[effects.preset.${1}_fixture_1]
kind = "animation"
shader = "fixture-1.glsl"
[animation.$1]
enabled = true
effect = "${1}_fixture_1"
EOF
  "$CANOPY" msg config-reload > /dev/null
  "$CANOPY" clock-advance 1000
}

red_pixels() {
  grim "$IMAGE"
  "$CANOPY_PIXEL_PROBE" "$IMAGE" count 'r > 0.9 && g < 0.1 && b < 0.1'
}
assert_no_red() {
  local count
  count=$(red_pixels)
  if (( count > 40 )); then
    echo "$1: stale shader color before transition or after completion ($count pixels)"
    exit 1
  fi
}
assert_transition() {
  local count
  "$CANOPY" clock-advance 100
  count=$(red_pixels)
  if (( count < 120 )); then
    echo "$1: missing shader-only intermediate color ($count pixels)"
    exit 1
  fi
  "$CANOPY" clock-advance 1000
  assert_no_red "$1"
  echo "$1 shader transition verified"
}

# Animation time only moves by clock-advance: each 300 ms transition is sampled 100 ms after its trigger, and
# advancing 1000 ms finishes it.
"$CANOPY" clock-freeze
# Layer mapping is client-driven, so the transition starts only once the compositor has seen it.
wait_for_mapped_layers() {
  for _ in $(seq 100); do
    [[ $("$CANOPY" layers --json | jq '[.[] | select(.mapped)] | length') == "$1" ]] && return 0
    sleep 0.025
  done
  echo "timed out waiting for $1 mapped layer surfaces"
  exit 1
}

configure windows_move
"$CANOPY_UNMAP_CLIENT" shader-events-a 700 700 > "$CANOPY_RUNTIME_DIR/a.log" 2>&1 &
"$CANOPY_UNMAP_CLIENT" shader-events-b 700 700 > "$CANOPY_RUNTIME_DIR/b.log" 2>&1 &
for _ in $(seq 60); do
  [[ $("$CANOPY" windows --json | jq length) == 2 ]] && break
  sleep 0.05
done
"$CANOPY" clock-advance 1000
first=$("$CANOPY" windows --json | jq -r '.[] | select(.title == "shader-events-a") | .id')
second=$("$CANOPY" windows --json | jq -r '.[] | select(.title == "shader-events-b") | .id')
assert_no_red move
"$CANOPY" msg window-toggle-maximize > /dev/null
assert_transition resize

configure border
"$CANOPY" msg window-focus "$second" > /dev/null
"$CANOPY" clock-advance 1000
assert_no_red border
"$CANOPY" msg window-focus "$first" > /dev/null
assert_transition border

configure dim_unfocused
assert_no_red dim_unfocused
"$CANOPY" msg window-focus "$second" > /dev/null
assert_transition dim_unfocused

configure workspaces
assert_no_red workspaces
"$CANOPY" msg workspace-switch 2 > /dev/null
assert_transition workspaces
"$CANOPY" msg workspace-switch 1 > /dev/null
"$CANOPY" clock-advance 1000

configure overview
assert_no_red overview
"$CANOPY" msg overview-open > /dev/null
assert_transition overview
"$CANOPY" msg overview-close > /dev/null
assert_transition overview-close

configure scratchpad
"$CANOPY" msg window-move-to-scratchpad > /dev/null
"$CANOPY" clock-advance 1000
assert_no_red scratchpad
"$CANOPY" msg scratchpad-toggle > /dev/null
assert_transition scratchpad-show
"$CANOPY" msg scratchpad-toggle > /dev/null
assert_transition scratchpad-hide

configure layers
assert_no_red layers
"$CANOPY_LAYER_CLIENT" HEADLESS-1 40 > "$CANOPY_RUNTIME_DIR/layer.log" 2>&1 &
layer_pid=$!
wait_for_mapped_layers 1
assert_transition layer-open
kill -TERM "$layer_pid"
wait_for_mapped_layers 0
assert_transition layer-close
