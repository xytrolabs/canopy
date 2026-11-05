#!/usr/bin/env bash
# in_capture decides whether a window (or overlay) effect reaches a capture: false feeds grim and a toplevel capture
# the plain composition while the display keeps the effect live, and a reload flips what both captures show,
# including on a fading close snapshot after the last effect window closes. An unmap/remap cycle leaves exactly one
# live instance behind (no stale slot), and effect-only frames grow only for a preset that reads time.
set -euo pipefail
readonly IMAGE="$CANOPY_RUNTIME_DIR/effect-window-capture.png"
readonly BASE="$CANOPY_RUNTIME_DIR/effect-window-capture-base.toml"
cp "$CANOPY_CONFIG" "$BASE"

# Forces the red channel to its maximum, leaving green and blue as sampled. The blue term is invisible at 8 bits but
# keeps canopy_time an active uniform, so the display keeps this instance eligible while the effect stays hidden
# from a capture under in_capture = false.
cat > "$CANOPY_RUNTIME_DIR/tint.glsl" <<'GLSL'
vec4 window(vec2 uv) { vec4 c = canopy_sample(uv); return vec4(1.0, c.g, c.b + 0.001 * sin(canopy_time), c.a); }
GLSL
# The green term is invisible at 8 bits but keeps canopy_time an active uniform, so the program counts as time-reading.
cat > "$CANOPY_RUNTIME_DIR/pulse.glsl" <<'GLSL'
vec4 window(vec2 uv) { vec4 c = canopy_sample(uv); return vec4(c.r, c.g + 0.001 * sin(canopy_time), c.b, c.a); }
GLSL
# Passes the sample through unchanged and never reads canopy_time, so the program counts as static.
cat > "$CANOPY_RUNTIME_DIR/flat.glsl" <<'GLSL'
vec4 window(vec2 uv) { return canopy_sample(uv); }
GLSL

spawn() {
  FILL_COLOR=0xFF00FF00 "$CANOPY_UNMAP_CLIENT" "$1" 300 200 > "$CANOPY_RUNTIME_DIR/$1.log" 2>&1 &
  for _ in $(seq 80); do
    window=$("$CANOPY" windows --json | jq -c --arg title "$1" '.[] | select(.title == $title)')
    [[ -n $window ]] && break
    sleep 0.025
  done
  [[ -n $window ]]
  read -r x y w h id < <(jq -r '"\(.x) \(.y) \(.w) \(.h) \(.id)"' <<< "$window")
}
centre() { grim "$IMAGE"; "$CANOPY_PIXEL_PROBE" "$IMAGE" pixel "$((x + w / 2))" "$((y + h / 2))"; }
toplevel_centre() { grim -T "$id" "$IMAGE"; "$CANOPY_PIXEL_PROBE" "$IMAGE" pixel "$((w / 2))" "$((h / 2))"; }

### Section 1: steady-state policy on both grim and a toplevel capture, flipped by a reload.
cat "$BASE" > "$CANOPY_CONFIG"
cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false
[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = false
[effects]
window = "tint"
in_capture = false
[effects.preset.tint]
kind = "window"
shader = "tint.glsl"
[[window_rule]]
match.title = "^cap-window$"
default_floating = true
EOF
"$CANOPY" msg config-reload > /dev/null
spawn cap-window
"$CANOPY" settle > /dev/null

read -r r g b < <(centre)
if (( r > 40 )); then
  echo "in_capture = false still showed the window effect in grim: $r $g $b"
  exit 1
fi
read -r r g b < <(toplevel_centre)
if (( r > 40 )); then
  echo "in_capture = false still showed the window effect in a toplevel capture: $r $g $b"
  exit 1
fi
if ! "$CANOPY" effect-frames --json | jq -e '.outputs[0].eligible > 0' > /dev/null; then
  echo "the display did not keep the window effect eligible while in_capture = false"
  exit 1
fi

sed -i 's/^in_capture = false$/in_capture = true/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" settle > /dev/null
read -r r g b < <(centre)
if (( r < 200 )); then
  echo "in_capture = true did not show the window effect in grim: $r $g $b"
  exit 1
fi
read -r r g b < <(toplevel_centre)
if (( r < 200 )); then
  echo "in_capture = true did not show the window effect in a toplevel capture: $r $g $b"
  exit 1
fi

sed -i 's/^in_capture = true$/in_capture = false/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" settle > /dev/null
read -r r g b < <(centre)
if (( r > 40 )); then
  echo "reloading back to in_capture = false left the window effect in grim: $r $g $b"
  exit 1
fi
read -r r g b < <(toplevel_centre)
if (( r > 40 )); then
  echo "reloading back to in_capture = false left the window effect in a toplevel capture: $r $g $b"
  exit 1
fi
"$CANOPY" msg window-close "$id" > /dev/null
"$CANOPY" settle > /dev/null

### Section 2: a fading close snapshot follows the same policy.
cat "$BASE" > "$CANOPY_CONFIG"
cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = true
[animation.windows_in]
enabled = false
[animation.windows_move]
enabled = false
[animation.windows_out]
enabled = true
style = "fade"
duration_ms = 5000
curve = "linear"
[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = false
[effects]
window = ""
in_capture = false
[effects.preset.tint]
kind = "window"
shader = "tint.glsl"
[[window_rule]]
match.title = "^cap-snapshot$"
default_floating = true
EOF
"$CANOPY" msg config-reload > /dev/null
spawn cap-snapshot
"$CANOPY" msg effect-window-set tint --window "$id" > /dev/null
"$CANOPY" settle > /dev/null
if ! "$CANOPY" effect-frames --json | jq -e '.outputs[0].eligible > 0' > /dev/null; then
  echo "the display did not keep the window effect eligible before the close while in_capture = false"
  exit 1
fi
"$CANOPY" clock-freeze
"$CANOPY" msg window-close "$id" > /dev/null
for _ in $(seq 100); do
  [[ -z $("$CANOPY" windows --json | jq -c '.[] | select(.title == "cap-snapshot")') ]] && break
  sleep 0.02
done
"$CANOPY" clock-advance 1
# capture-runtime-prune: no owner remains; force preparation to prune the
# runtime-only program while the frozen closing copy still holds its version.
printf '\n[effects.pool.snapshot_unused]\nkind = "window"\nchoose = []\n' >> "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" effects --json | jq -e '.presets[] | select(.name == "tint") | .state == "unreferenced"' > /dev/null || { echo "capture-runtime-prune"; exit 1; }
# Remove every effect definition while the copied shader is still visible.
# Its retained requirements must continue to update output capture policy.
awk '/^\[effects.preset.tint\]$/ {skip=1; next} /^\[effects.pool.snapshot_unused\]$/ {skip=1; next} /^\[/ {skip=0} !skip {print}' "$CANOPY_CONFIG" > "$CANOPY_RUNTIME_DIR/snapshot-no-definitions.toml"
cp "$CANOPY_RUNTIME_DIR/snapshot-no-definitions.toml" "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" effects --json | jq -e '(.presets | length) == 0 and (.pools | length) == 0' > /dev/null || { echo "capture-no-definitions"; exit 1; }
read -r r g b < <(centre)
if (( r > 40 )); then
  echo "in_capture = false still showed the effect on a fading close snapshot: $r $g $b"
  exit 1
fi

sed -i 's/^in_capture = false$/in_capture = true/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
read -r r g b < <(centre)
if (( r < 200 )); then
  echo "in_capture = true did not show the effect on a fading close snapshot: $r $g $b"
  exit 1
fi
"$CANOPY" clock-advance 5000
"$CANOPY" clock-resume
"$CANOPY" settle > /dev/null

### Section 3: an unmap/remap cycle leaves exactly one live tint behind, no stale slot from the previous mapping.
cat "$BASE" > "$CANOPY_CONFIG"
cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false
[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = false
[effects]
window = "tint"
in_capture = false
[effects.preset.tint]
kind = "window"
shader = "tint.glsl"
[[window_rule]]
match.title = "^cap-cycle$"
default_floating = true
EOF
"$CANOPY" msg config-reload > /dev/null

eligible() {
  "$CANOPY" effect-frames --json | jq -er '.outputs[0].eligible' || {
    echo "effect-frames reported no .outputs[0].eligible" >&2
    return 1
  }
}

base_eligible=$(eligible)
mkfifo "$CANOPY_RUNTIME_DIR/cycle-control"
exec {cycle_fd}<>"$CANOPY_RUNTIME_DIR/cycle-control"
REMAP_ON_STDIN=1 "$CANOPY_UNMAP_CLIENT" cap-cycle 300 200 <&"$cycle_fd" \
  > "$CANOPY_RUNTIME_DIR/cap-cycle.log" 2>&1 &
for _ in $(seq 80); do
  window=$("$CANOPY" windows --json | jq -c '.[] | select(.title == "cap-cycle")')
  [[ -n $window ]] && break
  sleep 0.025
done
[[ -n $window ]]
cycle_id=$(jq -r .id <<< "$window")
"$CANOPY" settle > /dev/null
mapped_eligible=$(eligible)
if (( mapped_eligible != base_eligible + 1 )); then
  echo "mapping the window did not add exactly one eligible instance: $base_eligible -> $mapped_eligible"
  exit 1
fi

"$CANOPY" msg window-close "$cycle_id" > /dev/null
for _ in $(seq 80); do
  grep -q '^unmapped$' "$CANOPY_RUNTIME_DIR/cap-cycle.log" && break
  sleep 0.025
done
if ! grep -q '^unmapped$' "$CANOPY_RUNTIME_DIR/cap-cycle.log"; then
  echo "the client never unmapped: $(< "$CANOPY_RUNTIME_DIR/cap-cycle.log")"
  exit 1
fi
"$CANOPY" settle > /dev/null
unmapped_eligible=$(eligible)
if (( unmapped_eligible != base_eligible )); then
  echo "unmapping the window left a stale eligible instance: base=$base_eligible unmapped=$unmapped_eligible"
  exit 1
fi

printf r >&"$cycle_fd"
for _ in $(seq 80); do
  [[ $(grep -c '^mapped$' "$CANOPY_RUNTIME_DIR/cap-cycle.log" || true) -eq 2 ]] && break
  sleep 0.025
done
if [[ $(grep -c '^mapped$' "$CANOPY_RUNTIME_DIR/cap-cycle.log" || true) -ne 2 ]]; then
  echo "the client never remapped: $(< "$CANOPY_RUNTIME_DIR/cap-cycle.log")"
  exit 1
fi
"$CANOPY" settle > /dev/null
remapped_eligible=$(eligible)
if (( remapped_eligible != base_eligible + 1 )); then
  echo "remapping the window left a stale slot from the previous mapping: base=$base_eligible remapped=$remapped_eligible"
  exit 1
fi
exec {cycle_fd}>&-

### Section 4: effect-only frames grow for a time-reading window preset and stay flat for a static one.
frames() {
  "$CANOPY" effect-frames --json | jq -er '.outputs[0].effect_frames' || {
    echo "effect-frames reported no .outputs[0].effect_frames" >&2
    return 1
  }
}
sed -i 's/^window = "tint"$/window = "flat"/' "$CANOPY_CONFIG"
cat >> "$CANOPY_CONFIG" <<'EOF'

[effects.preset.flat]
kind = "window"
shader = "flat.glsl"
EOF
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" clock-resume
"$CANOPY" settle > /dev/null
static_before=$(frames)
sleep 0.3 # real time: a static window preset must produce no effect-only frames
static_after=$(frames)
if (( static_after != static_before )); then
  echo "a static window preset still produced effect-only frames: $static_before -> $static_after"
  exit 1
fi

sed -i 's/^window = "flat"$/window = "pulse"/' "$CANOPY_CONFIG"
cat >> "$CANOPY_CONFIG" <<'EOF'

[effects.preset.pulse]
kind = "window"
shader = "pulse.glsl"
EOF
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" settle > /dev/null
pulsing_before=$(frames)
sleep 0.3 # real time: effect-only frames arrive on the output's own timer
pulsing_after=$(frames)
if (( pulsing_after <= pulsing_before )); then
  echo "an advancing time-reading window preset requested no effect-only frames"
  exit 1
fi

echo "capture policy on grim and a toplevel capture, its reload flip, close-snapshot policy, unmap/remap slot reuse, and frame gating verified"
