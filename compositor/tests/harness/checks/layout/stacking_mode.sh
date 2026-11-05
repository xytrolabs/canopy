#!/usr/bin/env bash
# Layout policy controls placement without turning explicit floats into tiles on exit.
set -euo pipefail
source "$(dirname "$CANOPY_HARNESS_LIB")/title_bar.sh"
cat >>"$CANOPY_CONFIG" <<'CONFIG'
[layout]
mode = "stacking"
new_exits_fullscreen = ["tiled"]
[animation]
enabled = false
[appearance]
border_width = 0
outer_border_width = 0
[appearance.title_bar]
mode = "off"
[[window_rule]]
match.title = "^explicit$"
default_floating = true
CONFIG
"$CANOPY" msg config-reload >/dev/null
spawn() {
  LOG_CONFIGURES=1 "$CANOPY_FRACTIONAL_CLIENT" "$1" 480 300 >"$CANOPY_RUNTIME_DIR/$1.log" 2>&1 &
  title_bar_wait_field "$1" floating true
}
focus() { "$CANOPY" msg window-focus-warp "$(title_bar_window "$1" | jq -r .id)" >/dev/null; }
layout() { "$CANOPY" msg workspace-set-layout "$1" >/dev/null; }
reject_toggle() {
  local reply
  if reply=$("$CANOPY" msg "$@" 2>&1); then
    echo "$* unexpectedly succeeded"
    return 1
  fi
  [[ $reply == *"window-toggle-floating needs a tiling layout"* ]]
}
spawn a
title_bar_wait_box a 480x300+400+210
first=$(rg -m 1 '^configure ' "$CANOPY_RUNTIME_DIR/a.log")
[[ $first == 'configure 480x300' || $first == 'configure 0x0' ]]
spawn b
title_bar_wait_box b 480x300+432+242
reject_toggle window-toggle-floating
reject_toggle window-toggle-floating "$(title_bar_window a | jq -r .id)"
focus b
"$CANOPY" msg window-focus-left >/dev/null
title_bar_wait_field a focused true
"$CANOPY" msg window-focus-down >/dev/null
title_bar_wait_field b focused true
spawn explicit
layout scrolling
title_bar_wait_field a floating false
title_bar_wait_field b floating false
title_bar_wait_field explicit floating true
layout stacking
title_bar_wait_field a floating true
title_bar_wait_field b floating true
# Fullscreen survives both policy transitions.
focus a
"$CANOPY" msg window-toggle-fullscreen >/dev/null
title_bar_wait_field a fullscreen true
layout dwindle
title_bar_wait_field a floating false
title_bar_wait_field a fullscreen true
layout stacking
title_bar_wait_field a floating true
title_bar_wait_field a fullscreen true
spawn incoming
title_bar_wait_field a fullscreen true
focus a
"$CANOPY" msg window-toggle-fullscreen >/dev/null
# A late identity rule changes placement intent, even though the window already floats.
cat >>"$CANOPY_CONFIG" <<'CONFIG'
[[window_rule]]
match.title = "^late$"
match.content_type = "game"
default_floating = true
CONFIG
"$CANOPY" msg config-reload >/dev/null
mkfifo "$CANOPY_RUNTIME_DIR/late-control"
exec 9<>"$CANOPY_RUNTIME_DIR/late-control"
CONTENT_TYPE_AFTER_MAP=game "$CANOPY_UNMAP_CLIENT" late 480 300 <&9 >"$CANOPY_RUNTIME_DIR/late.log" 2>&1 &
title_bar_wait_field late floating true
printf u >&9
await_lines "$CANOPY_RUNTIME_DIR/late.log" 'content-type-updated' 1
layout master
title_bar_wait_field a floating false
title_bar_wait_field b floating false
title_bar_wait_field late floating true
title_bar_wait_field explicit floating true
# The standard cycle includes the fourth mode and wraps back to scrolling.
layout toggle
title_bar_wait_field a floating true
[[ $("$CANOPY" workspaces --json | jq -r '.[] | select(.active) | .layout') == stacking ]]
layout toggle
title_bar_wait_field a floating false
[[ $("$CANOPY" workspaces --json | jq -r '.[] | select(.active) | .layout') == scrolling ]]
echo "stacking layout placement, transitions, focus, and rules verified"
