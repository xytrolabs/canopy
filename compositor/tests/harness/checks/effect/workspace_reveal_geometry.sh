#!/usr/bin/env bash
# Output-relative reveals survive every transform, fractional scale and nonzero layout origins.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"
readonly BASE="$CANOPY_RUNTIME_DIR/base.toml"
readonly IMAGE="$CANOPY_RUNTIME_DIR/geometry.png"
workspace_reveal_config
cp "$CANOPY_CONFIG" "$BASE"
"$CANOPY" msg config-reload > /dev/null
FILL_COLOR=0xFFFF0000 RESIZE_FILL_COLOR=0xFFFF0000 "$CANOPY_UNMAP_CLIENT" geometry-a 1280 720 > "$CANOPY_RUNTIME_DIR/a.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/a.log" mapped 1
"$CANOPY" msg window-toggle-fullscreen > /dev/null
"$CANOPY" settle
"$CANOPY" msg workspace-switch 2 > /dev/null
"$CANOPY" settle
FILL_COLOR=0xFF0000FF RESIZE_FILL_COLOR=0xFF0000FF "$CANOPY_UNMAP_CLIENT" geometry-b 1280 720 > "$CANOPY_RUNTIME_DIR/b.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/b.log" mapped 1
"$CANOPY" msg window-toggle-fullscreen > /dev/null
"$CANOPY" settle
for transform in normal 90 180 270 flipped flipped-90 flipped-180 flipped-270; do
  cp "$BASE" "$CANOPY_CONFIG"
  cat >> "$CANOPY_CONFIG" <<CONFIG
[output.HEADLESS-1]
position = [137, -53]
scale = 1.25
transform = "$transform"
workspace_axis = "horizontal"
CONFIG
  "$CANOPY" msg config-reload > /dev/null
  "$CANOPY" clock-freeze
  "$CANOPY" msg workspace-switch 1 > /dev/null
  "$CANOPY" clock-advance 1000
  "$CANOPY" clock-resume
  "$CANOPY" settle
  "$CANOPY" clock-freeze
  "$CANOPY" msg workspace-switch 2 > /dev/null
  "$CANOPY" clock-advance 500
  grim -s 1 -o HEADLESS-1 "$IMAGE"
  IFS=x read -r width height < <("$CANOPY_PIXEL_PROBE" "$IMAGE" size)
  left=$("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel "$((width / 4))" "$((height / 2))")
  right=$("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel "$((width * 3 / 4))" "$((height / 2))")
  [[ $left == '0 0 255' && $right == '255 0 0' ]] || {
    echo "$transform: logical reveal orientation failed, $width x $height: left=$left right=$right"; exit 1;
  }
  "$CANOPY" clock-advance 1000
  "$CANOPY" clock-resume
  "$CANOPY" settle
done
# Changing geometry during a held reveal must leave the native active destination intact.
"$CANOPY" clock-freeze
"$CANOPY" msg workspace-switch 1 > /dev/null
"$CANOPY" clock-advance 500
sed -i 's/^scale = 1.25$/scale = 1.5/; s/^transform = .*/transform = "normal"/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" clock-advance 1000
"$CANOPY" clock-resume
"$CANOPY" settle
grim -s 1 -o HEADLESS-1 "$IMAGE"
IFS=x read -r width height < <("$CANOPY_PIXEL_PROBE" "$IMAGE" size)
[[ $("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel "$((width / 2))" "$((height / 2))") == '255 0 0' ]]
echo 'eight transforms, fractional scale, nonzero origin and mid-reveal geometry change verified'
