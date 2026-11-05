#!/usr/bin/env bash
# Inherited rules, retained overview/close images, and a rule which revokes
# its own new window-capture session must all preserve the exclusion boundary.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"
readonly IMAGE="$CANOPY_RUNTIME_DIR/protection.png"
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[animation]
enabled = false
[appearance]
corner_radius = 0
[appearance.shadow]
enabled = false
[overview]
background_blur = false
[[window_rule]]
match.title = "^transient-parent$"
block_capture = true
[[window_rule]]
match.title = "^transient-child$"
block_capture = false
CONFIG
"$CANOPY" msg config-reload > /dev/null
frozen=false
assert_hidden() {
  if [[ $frozen == true ]]; then
    "$CANOPY" clock-advance 1 > /dev/null
  else
    "$CANOPY" settle > /dev/null
  fi
  capture_assert_hidden "$IMAGE"
}
TRANSIENT_SUITE=mapped-together FILL_COLOR=0xFFFF00FF "$CANOPY_UNMAP_CLIENT" transient-child 400 300 > "$CANOPY_RUNTIME_DIR/transient.log" 2>&1 &
await_window transient-child
parent=$(window_by_title transient-parent | jq -r .id)
child=$(window_by_title transient-child | jq -r .id)
assert_hidden
"$CANOPY_CAPTURE_CLIENT" --window "$child" > "$CANOPY_RUNTIME_DIR/denied-child.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/denied-child.log" 'session-stopped ' 1
if rg '^frame |protocol error' "$CANOPY_RUNTIME_DIR/denied-child.log"; then exit 1; fi
# A card follows its window's protection while the overview stays open. A
# rule reload closes the overview, so the toggle comes from a title change.
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[[window_rule]]
match.title = "^card-protected$"
block_capture = true
CONFIG
"$CANOPY" msg config-reload > /dev/null
mkfifo "$CANOPY_RUNTIME_DIR/card"
exec 7<> "$CANOPY_RUNTIME_DIR/card"
TITLE_AFTER_MAP=card-protected FILL_COLOR=0xFF00FF00 \
  "$CANOPY_UNMAP_CLIENT" card-open 400 300 <&7 > "$CANOPY_RUNTIME_DIR/card.log" 2>&1 &
await_window card-open
# An unprotected witness proves the overview is still open after the toggle.
FILL_COLOR=0xFF0000FF "$CANOPY_UNMAP_CLIENT" witness 400 300 > "$CANOPY_RUNTIME_DIR/witness.log" 2>&1 &
await_window witness
zoomed() {
  local w
  read -r _ _ w _ < <("$CANOPY_PIXEL_PROBE" "$IMAGE" bbox "$1")
  ((w > 0 && w < 400)) || { echo "$2 not shown at overview zoom: $w"; return 1; }
}
"$CANOPY" msg overview-open > /dev/null
# The transient cards were created while protected.
assert_hidden
zoomed 'g>0.9&&r<0.1&&b<0.1' card-open
printf t >&7
await_lines "$CANOPY_RUNTIME_DIR/card.log" title-updated 1
assert_hidden
zoomed 'b>0.9&&r<0.1&&g<0.1' witness
green=$("$CANOPY_PIXEL_PROBE" "$IMAGE" count 'g>0.9&&r<0.1&&b<0.1')
((green == 0)) || { echo "card kept capture after its window became protected: $green"; exit 1; }
"$CANOPY" msg overview-close > /dev/null
assert_hidden
# A close retains client images after unmap. Keep the transition at its start.
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[animation.windows_out]
enabled = true
style = "fade"
duration_ms = 5000
CONFIG
sed -i '0,/enabled = false/s//enabled = true/' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" settle > /dev/null
"$CANOPY" clock-freeze > /dev/null
frozen=true
"$CANOPY" msg window-close "$child" > /dev/null
"$CANOPY" msg window-close "$parent" > /dev/null
assert_hidden
"$CANOPY" clock-advance 6000 > /dev/null
"$CANOPY" clock-resume > /dev/null
frozen=false
# is_cast_target is evaluated inside the new-session callback. Revocation must
# reject copies immediately without destroying that callback's source in place.
cat >> "$CANOPY_CONFIG" <<'CONFIG'
[[window_rule]]
match.title = "^dynamic$"
match.is_cast_target = true
block_capture = true
CONFIG
"$CANOPY" msg config-reload > /dev/null
"$CANOPY_UNMAP_CLIENT" dynamic > "$CANOPY_RUNTIME_DIR/dynamic.log" 2>&1 &
await_window dynamic
id=$(window_by_title dynamic | jq -r .id)
"$CANOPY_CAPTURE_CLIENT" --window "$id" > "$CANOPY_RUNTIME_DIR/dynamic-capture.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/dynamic-capture.log" 'session-stopped ' 1
if rg '^frame |protocol error' "$CANOPY_RUNTIME_DIR/dynamic-capture.log"; then exit 1; fi
echo 'inherited protection, retained images, and reentrant session revocation verified'
