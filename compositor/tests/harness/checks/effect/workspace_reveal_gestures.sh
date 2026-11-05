#!/usr/bin/env bash
# Synthetic wlr_cursor swipe events exercise the real three-finger handlers, including direct manipulation.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"
readonly IMAGE="$CANOPY_RUNTIME_DIR/gesture.png"
workspace_reveal_config
"$CANOPY" msg config-reload > /dev/null
for n in 1 2 3; do
  "$CANOPY" msg workspace-switch "$n" > /dev/null
  "$CANOPY" settle
  case $n in 1) color=0xFFFF0000;; 2) color=0xFF00FF00;; 3) color=0xFF0000FF;; esac
  FILL_COLOR=$color "$CANOPY_UNMAP_CLIENT" "gesture-$n" 1280 720 > "$CANOPY_RUNTIME_DIR/$n.log" 2>&1 &
  await_lines "$CANOPY_RUNTIME_DIR/$n.log" mapped 1
  "$CANOPY" msg window-toggle-fullscreen > /dev/null
  "$CANOPY" settle
done
"$CANOPY" msg workspace-switch 2 > /dev/null
"$CANOPY" settle
"$CANOPY_POINTER_CLIENT" 1280 720 move 640 360
"$CANOPY" clock-freeze
swipe() { "$CANOPY" swipe-test "$@" --json; }
frame() {
  "$CANOPY" clock-advance 1
  grim "$IMAGE"
  local top bottom
  top=$("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 640 180)
  bottom=$("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 640 540)
  [[ $top == "$1" && $bottom == "$2" ]] || { echo "gesture pixels: top=$top bottom=$bottom, expected $1 / $2"; return 1; }
}
active() { "$CANOPY" windows --json | jq -r '.[] | select(.active) | .title'; }
swipe begin 1000 > /dev/null
frame '0 255 0' '0 255 0'
swipe update 1100 0 -150 | jq -e '.reveal and (.progress == 0.5)' > /dev/null
frame '0 0 255' '0 255 0'
[[ $(active) == gesture-2 ]]
# Cross the base exactly, then select the participant on the opposite side.
swipe update 1200 0 150 | jq -e '.progress == 0' > /dev/null
frame '0 255 0' '0 255 0'
swipe update 1300 0 150 | jq -e '.reveal and (.progress == -0.5)' > /dev/null
frame '0 255 0' '255 0 0'
swipe end 1800 1 > /dev/null
"$CANOPY" clock-advance 1000
frame '0 255 0' '0 255 0'
[[ $(active) == gesture-2 ]]
# Release over the threshold follows native target selection and settling.
swipe begin 2000 > /dev/null
swipe update 2100 0 -240 > /dev/null
swipe end 2600 0 > /dev/null
[[ $(active) == gesture-3 ]]
"$CANOPY" clock-advance 1000
frame '0 0 255' '0 0 255'
# Spring settling after direct control uses the same live reveal binding.
sed -i 's/^curve = "linear"$/curve = "spring:1,120"/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
swipe begin 3000 > /dev/null
swipe update 3100 0 240 | jq -e '.reveal and (.progress == -0.8)' > /dev/null
swipe end 3600 0 > /dev/null
[[ $(active) == gesture-2 ]]
"$CANOPY" clock-advance 5000
frame '0 255 0' '0 255 0'
"$CANOPY" clock-resume
"$CANOPY" settle
echo 'direct swipe progress, zero crossing, reversed participant, cancellation, release and spring settling verified'
