#!/usr/bin/env bash
# Stacking is a workspace layout: protect an ordinary layout-managed window,
# reveal two updating floats beneath it, and preserve protection on layout changes.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"
capture_config
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[layout]
mode = "stacking"
[[window_rule]]
match.title = "^left$"
default_floating_size_px = { width = 400, height = 400 }
default_position = { x = 100, y = 100, anchor = "top_left" }
[[window_rule]]
match.title = "^right$"
default_floating_size_px = { width = 400, height = 400 }
default_position = { x = 650, y = 100, anchor = "top_left" }
[[window_rule]]
match.title = "^protected$"
block_capture = false
default_floating_size_px = { width = 1280, height = 720 }
default_position = { x = 0, y = 0, anchor = "top_left" }
CONFIG
"$CANOPY" msg config-reload > /dev/null
readonly IMAGE="$CANOPY_RUNTIME_DIR/stacking-capture.png"
geometry() { "$CANOPY" windows --json | jq -c 'sort_by(.id) | map([.id,.x,.y,.w,.h,.floating])'; }
capture_clients 400
"$CANOPY" settle > /dev/null
[[ $("$CANOPY" workspaces --json | jq -r '.[] | select(.active) | .layout') == stacking ]]
"$CANOPY" windows --json | jq -e 'length == 3 and all(.floating)' > /dev/null
[[ $(window_by_title protected | jq -c '[.x,.y,.w,.h]') == '[0,0,1280,720]' ]]
grim "$IMAGE"
[[ $("$CANOPY_PIXEL_PROBE" "$IMAGE" count 'r>0.9&&b>0.9&&g<0.1') == 921600 ]]
before=$(geometry)
capture_set_protection true
"$CANOPY_CAPTURE_CLIENT" --output HEADLESS-1 > "$CANOPY_RUNTIME_DIR/output.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/output.log" 'frame ' 1
"$CANOPY" settle > /dev/null
[[ $(geometry) == "$before" ]]
capture_assert_hidden "$IMAGE"
read -r green blue < <("$CANOPY_PIXEL_PROBE" "$IMAGE" count 'g>0.9&&r<0.1&&b<0.1' 'b>0.9&&r<0.1&&g<0.1')
((green > 10000 && blue > 10000)) || { echo "missing underlying floats: $green $blue"; exit 1; }
printf R >&8
printf R >&9
await_lines "$CANOPY_RUNTIME_DIR/left.log" 'repainted ' 1
await_lines "$CANOPY_RUNTIME_DIR/right.log" 'repainted ' 1
"$CANOPY" settle > /dev/null
capture_assert_hidden "$IMAGE"
red=$("$CANOPY_PIXEL_PROBE" "$IMAGE" count 'r>0.9&&g<0.1&&b<0.1')
((red == green + blue)) || { echo "underlying floats stopped updating: $red != $green + $blue"; exit 1; }
# These windows float because of layout policy, not explicit floating intent.
# Changing the workspace layout must preserve exclusion even as they become tiles.
for layout in scrolling stacking; do
  "$CANOPY" msg workspace-set-layout "$layout" > /dev/null
  "$CANOPY" settle > /dev/null
  expected_floating=false
  if [[ $layout == stacking ]]; then expected_floating=true; fi
  [[ $(window_by_title protected | jq -r .floating) == "$expected_floating" ]]
  capture_assert_hidden "$IMAGE"
done
echo 'stacking layout exclusion, covered client updates, unchanged geometry, and layout transitions verified'

# Keep one other window protected while toggling the magenta window, so both
# frames use capture-role screen feedback. Old magenta history must be discarded.
cat > "$CANOPY_RUNTIME_DIR/remember.glsl" <<'GLSL'
vec4 screen(vec2 uv) { return max(canopy_sample(uv), canopy_sample_previous(uv)); }
GLSL
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[effects]
screen = "remember"
in_capture = true
[effects.preset.remember]
kind = "screen"
shader = "remember.glsl"
[[window_rule]]
match.title = "^left$"
block_capture = true
CONFIG
capture_set_protection false
"$CANOPY" settle > /dev/null
grim "$IMAGE"
(( $("$CANOPY_PIXEL_PROBE" "$IMAGE" count 'r>0.9&&b>0.9&&g<0.1') > 1000 ))
capture_set_protection true
capture_assert_hidden "$IMAGE"
sed -i 's/^in_capture = true$/in_capture = false/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
capture_assert_hidden "$IMAGE"
echo 'capture screen-feedback invalidation and both effects policies verified'
