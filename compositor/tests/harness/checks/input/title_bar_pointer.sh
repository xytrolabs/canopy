#!/usr/bin/env bash
# Modifier-free frame controls own their input and restore a dragged maximized float.
set -euo pipefail
source "$(dirname "$CANOPY_HARNESS_LIB")/title_bar.sh"
title_bar_config
title=ssd-float-pointer
log=$CANOPY_RUNTIME_DIR/pointer-window.log
env XDG_DECORATION=server LOG_POINTER=1 "$CANOPY_FRACTIONAL_CLIENT" "$title" 480 300 > "$log" 2>&1 &
title_bar_wait_box "$title" 480x300+173+109
"$CANOPY" settle > /dev/null

"$CANOPY_POINTER_CLIENT" 1280 720 move 300 95 press 272 move 620 275 release 272
title_bar_wait_box "$title" 480x300+493+289

# Moving only within the threshold and releasing must leave the normal box untouched.
"$CANOPY_POINTER_CLIENT" 1280 720 move 620 275 click 272
title_bar_wait_box "$title" 480x300+493+289
# A complete double-click toggles maximize, and another restores the same normal box.
"$CANOPY_POINTER_CLIENT" 1280 720 move 700 275 click 272 click 272
title_bar_wait_box "$title" 1264x676+8+36
"$CANOPY_POINTER_CLIENT" 1280 720 move 700 22 click 272 click 272
title_bar_wait_box "$title" 480x300+493+289

# Pressing close but releasing elsewhere cancels closure.
"$CANOPY_POINTER_CLIENT" 1280 720 move 959 275 press 272 move 750 350 release 272
title_bar_wait_box "$title" 480x300+493+289
"$CANOPY_POINTER_CLIENT" 1280 720 move 937 275 click 272
title_bar_wait_box "$title" 1264x676+8+36

# Clicking a maximized title bar is inert; dragging it restores its normal size under the pointer.
"$CANOPY_POINTER_CLIENT" 1280 720 move 600 22 click 272
title_bar_wait_box "$title" 1264x676+8+36
"$CANOPY_POINTER_CLIENT" 1280 720 move 800 22 press 272 move 830 180 release 272
title_bar_wait_field "$title" maximized false
title_bar_wait_field "$title" w 480
title_bar_wait_field "$title" h 300
"$CANOPY" settle > /dev/null
window=$(title_bar_window "$title")
x=$(jq -r '.x' <<< "$window")
y=$(jq -r '.y' <<< "$window")
((830 >= x && 830 < x + 480 && 180 >= y - 28 && 180 < y))
if rg -q '^pointer-button ' "$log"; then
  echo "decoration input leaked to the application: $(cat "$log")"
  exit 1
fi

# A content click proves the observer is live and restores ordinary pointer delivery.
"$CANOPY_POINTER_CLIENT" 1280 720 move "$((x + 100))" "$((y + 100))" click 272
await_lines "$log" 'pointer-button 272 1' 1
await_lines "$log" 'pointer-button 272 0' 1

# Left button placement reloads live and keeps close at the outer edge.
sed -i '/^\[appearance.title_bar\]$/a button_position = "left"' "$CANOPY_CONFIG"
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" settle > /dev/null
"$CANOPY_POINTER_CLIENT" 1280 720 move "$((x + 14))" "$((y - 14))" click 272
title_bar_wait_absent "$title"
echo "modifier-free title bar controls passed without client input leakage"
