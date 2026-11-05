#!/usr/bin/env bash
# A fullscreen layout float keeps its normal geometry through a tiled workspace and back.
set -euo pipefail
source "$(dirname "$CANOPY_HARNESS_LIB")/title_bar.sh"
cat >>"$CANOPY_CONFIG" <<'CONFIG'
[animation]
enabled = false
[appearance.title_bar]
mode = "forced"
[output.HEADLESS-1]
workspaces = 5
[[workspace]]
index = 5
layout.mode = "stacking"
CONFIG
"$CANOPY" msg config-reload >/dev/null
"$CANOPY" msg workspace-switch 5 >/dev/null
"$CANOPY_FRACTIONAL_CLIENT" restore-size 480 300 >"$CANOPY_RUNTIME_DIR/restore-size.log" 2>&1 &
title_bar_wait_field restore-size floating true
title_bar_wait_box restore-size 480x300+400+224
for mode in scrolling dwindle master; do
  "$CANOPY" msg workspace-switch 4 >/dev/null
  "$CANOPY" msg workspace-set-layout "$mode" >/dev/null
  "$CANOPY" msg workspace-switch 5 >/dev/null
  "$CANOPY" msg window-toggle-fullscreen >/dev/null
  title_bar_wait_field restore-size fullscreen true
  title_bar_wait_box restore-size 1280x720+0+0
  "$CANOPY" msg window-move-to-workspace 4 >/dev/null
  title_bar_wait_field restore-size floating false
  title_bar_wait_field restore-size fullscreen true
  "$CANOPY" msg window-move-to-workspace 5 >/dev/null
  title_bar_wait_field restore-size floating true
  title_bar_wait_field restore-size fullscreen true
  "$CANOPY" msg window-toggle-fullscreen >/dev/null
  title_bar_wait_field restore-size fullscreen false
  title_bar_wait_box restore-size 480x300+400+224
done
echo "fullscreen floats retained normal geometry across all tiling layouts"
