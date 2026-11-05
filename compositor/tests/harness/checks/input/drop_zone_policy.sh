#!/usr/bin/env bash
# Workspace overrides can enable drop zones; config and layout changes clear a held preview before stationary release.
set -euo pipefail
source "$(dirname "$CANOPY_HARNESS_LIB")/title_bar.sh"
cp "$CANOPY_CONFIG" "$CANOPY_RUNTIME_DIR/base.toml"
write_policy() {
  cp "$CANOPY_RUNTIME_DIR/base.toml" "$CANOPY_CONFIG"
  cat >>"$CANOPY_CONFIG" <<CONFIG
[layout]
mode = "stacking"
[layout.stacking]
drop_zones = false
[[workspace]]
index = 1
layout.stacking.drop_zones = $1
[[workspace]]
index = 2
layout.mode = "${2:-stacking}"
layout.stacking.drop_zones = false
[animation]
enabled = false
[appearance]
border_width = 0
outer_border_width = 0
[appearance.title_bar]
mode = "off"
[colors]
insert_hint = "#00FFFFFF"
[[window_rule]]
match.title = "^drop-zone-policy-"
default_floating = true
default_position = { x = 173, y = 109, anchor = "top_left" }
CONFIG
  "$CANOPY" msg config-reload >/dev/null
}
for change in option layout workspace_disabled workspace_tiling; do
  destination_mode=stacking
  [[ $change != workspace_tiling ]] || destination_mode=scrolling
  write_policy true "$destination_mode"
  "$CANOPY" msg workspace-switch 1 >/dev/null
  "$CANOPY" msg workspace-set-layout stacking >/dev/null
  title=drop-zone-policy-$change
  "$CANOPY_FRACTIONAL_CLIENT" "$title" 480 300 >"$CANOPY_RUNTIME_DIR/$change.log" 2>&1 &
  title_bar_wait_box "$title" 480x300+173+109
  pointer_hold 1280 720 move 400 240 mod logo press 272 move 0 360 -- release 272 mod none
  bounds=
  for _ in $(seq 60); do
    grim "$CANOPY_RUNTIME_DIR/enabled-$change.png"
    bounds=$("$CANOPY_PIXEL_PROBE" "$CANOPY_RUNTIME_DIR/enabled-$change.png" bbox 'r < 0.1 && g > 0.9 && b > 0.9')
    [[ $bounds == '8 8 628 704' ]] && break
    sleep 0.025
  done
  [[ $bounds == '8 8 628 704' ]] || {
    echo "workspace override did not enable drop zones: $bounds"
    exit 1
  }
  if [[ $change == option ]]; then
    write_policy false
  elif [[ $change == layout ]]; then
    "$CANOPY" msg workspace-set-layout scrolling >/dev/null
  else
    "$CANOPY" msg workspace-switch 2 >/dev/null
  fi
  "$CANOPY" settle >/dev/null
  grim "$CANOPY_RUNTIME_DIR/disabled-$change.png"
  bounds=$("$CANOPY_PIXEL_PROBE" "$CANOPY_RUNTIME_DIR/disabled-$change.png" bbox 'r < 0.1 && g > 0.9 && b > 0.9')
  [[ $bounds == '0 0 0 0' ]] || {
    echo "$change change left the held preview visible: $bounds"
    exit 1
  }
  pointer_release
  title_bar_wait_field "$title" region null
  title_bar_wait_field "$title" floating true
  title_bar_wait_field "$title" w 480
  title_bar_wait_field "$title" h 300
  if [[ $change == workspace_* ]]; then
    title_bar_wait_field "$title" workspace HEADLESS-1:2
  fi
  if [[ $change == option ]]; then
    "$CANOPY" msg window-set-region left >/dev/null
    title_bar_wait_field "$title" region left
    write_policy false
    title_bar_wait_field "$title" region left
    "$CANOPY" msg window-clear-region >/dev/null
    title_bar_wait_field "$title" region null
    title_bar_wait_field "$title" w 480
    title_bar_wait_field "$title" h 300
  fi
done
echo "workspace drop-zone overrides and stationary releases respect reloaded policy and layout changes"
