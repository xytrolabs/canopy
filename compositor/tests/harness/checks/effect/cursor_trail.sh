#!/usr/bin/env bash
# harness: outputs=2
# Shipped trail: curved path, finite fade, idle frames and output crossing.
set -euo pipefail
readonly IMAGE="$CANOPY_RUNTIME_DIR/trail.png"
cat >> "$CANOPY_CONFIG" <<TOML
[include]
files = ["$CANOPY_REPO/examples/effects/cursor/trail/effect.toml"]
[effects]
cursor = "trail"
in_capture = true
[output."HEADLESS-1"]
position = [0, 0]
[output."HEADLESS-2"]
position = [1280, 0]
TOML
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" clock-freeze > /dev/null
move() { "$CANOPY_POINTER_CLIENT" 2560 720 move "$1" "$2" > /dev/null; }
advance() { "$CANOPY" clock-advance "$1" > /dev/null; }
frames() { "$CANOPY" effect-frames --json | jq '[.outputs[].effect_frames] | add'; }
move 300 300
advance 40
move 400 300
advance 40
move 400 400
"$CANOPY" settle > /dev/null
grim -s 1 -o HEADLESS-1 "$IMAGE"
# Near the oldest sample: the curve bows off the chord midpoint before the corner.
read -r r g b < <("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 310 300)
(( r > 30 && g > 30 && b > 30 )) || { echo "trail did not follow previous segment: $r $g $b"; exit 1; }
read -r r g b < <("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 350 350)
(( r < 15 && g < 15 && b < 15 )) || { echo 'trail cut across the corner'; exit 1; }
advance 400
"$CANOPY" settle > /dev/null
grim -s 1 -o HEADLESS-1 "$IMAGE"
read -r r g b < <("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 310 300)
(( r < 15 && g < 15 && b < 15 )) || { echo 'expired trail left pixels'; exit 1; }
"$CANOPY" clock-resume > /dev/null
move 600 400
sleep 0.6 # real time: let the resumed motion clock expire the 300 ms tail
[[ $("$CANOPY" effect-frames --json | jq '[.outputs[].eligible] | add') == 0 ]] || { echo 'idle trail remained eligible'; exit 1; }
before=$(frames)
sleep 0.3 # real time: verify the idle effect schedules no further frames
[[ $(frames) == "$before" ]] || { echo 'idle trail kept requesting frames'; exit 1; }
move 800 400
move 1400 400
"$CANOPY" settle > /dev/null
grim -s 1 -o HEADLESS-1 "$IMAGE"
read -r r g b < <("$CANOPY_PIXEL_PROBE" "$IMAGE" pixel 700 400)
(( r < 15 && g < 15 && b < 15 )) || { echo 'output crossing left a tail'; exit 1; }
echo 'trail path, expiry, idle frame gating and output crossing verified'
