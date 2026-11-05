#!/usr/bin/env bash
# A descendant-only effect changes the caster too. Freeze it on close so the
# removed border and its enlarged analytic shadow do not flash back into view.
set -euo pipefail
readonly IMAGE="$CANOPY_RUNTIME_DIR/border.png"
cat > "$CANOPY_RUNTIME_DIR/border.glsl" <<'GLSL'
vec4 animation(vec2 uv) { return vec4(0.0); }
GLSL
cat > "$CANOPY_RUNTIME_DIR/identity.glsl" <<'GLSL'
vec4 animation(vec2 uv) { return canopy_sample(uv); }
GLSL
cat >> "$CANOPY_CONFIG" <<'EOF'

[colors]
shadow = "#00FF00FF"
[colors.border]
focused = "#FF0000"
unfocused = "#800000"
[appearance]
border_width = 20
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = true
softness = 24
offset_x = 0
offset_y = 0
[animation]
duration_ms = 2000
curve = "linear"
[animation.windows_in]
enabled = false
[animation.windows_move]
enabled = false
[effects.preset.border_border]
kind = "animation"
shader = "border.glsl"
[animation.border]
enabled = true
effect = "border_border"
[effects.preset.windows_out_identity]
kind = "animation"
shader = "identity.glsl"
[animation.windows_out]
effect = "windows_out_identity"
[[window_rule]]
match.title = "^border-a$"
default_floating = true
default_position = { x = 200, y = 120, anchor = "top_left" }
[[window_rule]]
match.title = "^border-b$"
default_floating = true
default_position = { x = 800, y = 120, anchor = "top_left" }
EOF
"$CANOPY" msg config-reload > /dev/null
# Animation time only moves by clock-advance: samples land 200 ms into each 2000 ms timeline.
"$CANOPY" clock-freeze
for title in border-a border-b; do
  "$CANOPY_UNMAP_CLIENT" "$title" 300 300 > "$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
  for _ in $(seq 80); do
    window=$("$CANOPY" windows --json | jq -c --arg title "$title" '.[] | select(.title == $title)')
    [[ -n $window ]] && break
    sleep 0.025
  done
  [[ -n $window ]]
done
"$CANOPY" clock-advance 2000
"$CANOPY" settle
window=$("$CANOPY" windows --json | jq -c '.[] | select(.title == "border-a")')
id=$(jq -r .id <<< "$window")
x=$(jq -r '.x + (.w / 2 | floor)' <<< "$window")
y=$(jq -r '.y - 6' <<< "$window")
assert_shadow() {
  grim "$IMAGE"
  read -r r g b < <("$CANOPY_PIXEL_PROBE" "$IMAGE" mean "2x2+$x+$y")
  if ! (( g > 25 && r < 5 && b < 5 )); then
    echo "$1: border shader shadow did not follow the content edge: $r $g $b"; exit 1
  fi
}
"$CANOPY" msg window-focus "$id" > /dev/null
"$CANOPY" clock-advance 200
assert_shadow focus
"$CANOPY" msg window-close "$id" > /dev/null
"$CANOPY" clock-advance 200
assert_shadow closing
echo "descendant-only border silhouette and its closing snapshot shadow verified"
