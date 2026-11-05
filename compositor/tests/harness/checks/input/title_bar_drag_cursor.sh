#!/usr/bin/env bash
# Rendered title bar cursors stay unchanged on press and within slop, then switch only for an actual drag.
set -euo pipefail
source "$(dirname "$CANOPY_HARNESS_LIB")/title_bar.sh"
title_bar_config
sed -i '/^\[appearance\]$/a drag_opacity = 1.0' "$CANOPY_CONFIG"
cat >>"$CANOPY_CONFIG" <<'CONFIG'
[input.focus]
follows_mouse = false
[[window_rule]]
match.title = "^drag-cursor-.*-client$"
title_bar = "off"
CONFIG
"$CANOPY" msg config-reload >/dev/null

# Capture inside the solid title bar (or the solid client buffer for a client-side move).
# This compares rendered cursors without depending on a particular installed cursor theme.
cursor_shot() {
  local image=$CANOPY_RUNTIME_DIR/$1.png
  grim -c -g "$((pointer_x - 12)),$((pointer_y - 12)) 48x24" "$image"
  echo "$image"
}

same_shot() {
  local changed
  read -r _ changed < <("$CANOPY_PIXEL_PROBE" "$1" diff "$2")
  ((changed == 0))
}

for layout in scrolling stacking; do
  "$CANOPY" msg workspace-set-layout "$layout" >/dev/null
  for decoration in server client; do
    title=drag-cursor-$layout-$decoration
    if [[ $decoration == server ]]; then
      env XDG_DECORATION=server "$CANOPY_FRACTIONAL_CLIENT" "$title" 480 300 \
        >"$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
    else
      "$CANOPY_SEAT_LOG_CLIENT" "$title" move-on-press >"$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
    fi
    client=$!
    title_bar_wait_field "$title" title_bar "$([[ $decoration == server ]] && echo true || echo false)"
    "$CANOPY" settle >/dev/null
    window=$(title_bar_window "$title")
    origin_x=$(jq -r '.x' <<<"$window")
    origin_y=$(jq -r '.y' <<<"$window")
    pointer_x=$((origin_x + 360))
    pointer_y=$((origin_y + 40))
    if [[ $decoration == server ]]; then
      pointer_y=$((origin_y - 14))
    fi
    pointer_hold 1280 720 move "$pointer_x" "$pointer_y" -- \
      press 272 mark pressed hold \
      move "$((pointer_x + 5))" "$pointer_y" mark slop hold \
      move "$((pointer_x + 25))" "$((pointer_y + 20))" mark dragged hold release 272
    normal=$(cursor_shot "$title-hover")
    pointer_step pressed
    if [[ $decoration == client ]]; then
      await_lines "$CANOPY_RUNTIME_DIR/$title.log" move-requested 1 0.025
    fi
    pressed=$(cursor_shot "$title-pressed")
    same_shot "$pressed" "$normal" || {
      echo "$title: a stationary press changed the cursor"
      exit 1
    }
    pointer_step slop
    pointer_x=$((pointer_x + 5))
    slop=$(cursor_shot "$title-slop")
    same_shot "$slop" "$normal" || {
      echo "$title: motion below the drag threshold changed the cursor"
      exit 1
    }
    pointer_step dragged
    pointer_x=$((pointer_x + 20))
    pointer_y=$((pointer_y + 20))
    dragged=$(cursor_shot "$title-dragged")
    ! same_shot "$dragged" "$normal" || {
      echo "$title: crossing the drag threshold did not change the cursor"
      exit 1
    }
    pointer_release
    "$CANOPY" settle >/dev/null
    window=$(title_bar_window "$title")
    pointer_x=$(jq -r '.x + 360' <<<"$window")
    pointer_y=$(jq -r '.y + 40' <<<"$window")
    if [[ $decoration == server ]]; then
      pointer_y=$(jq -r '.y - 14' <<<"$window")
    fi
    "$CANOPY_POINTER_CLIENT" 1280 720 move "$pointer_x" "$pointer_y"
    restored=$(cursor_shot "$title-restored")
    same_shot "$restored" "$normal" || {
      echo "$title: releasing the drag did not restore the cursor"
      exit 1
    }
    kill "$client"
    wait "$client" 2>/dev/null || true
    title_bar_wait_absent "$title"
  done
done
echo "server and client title bars keep the cursor through press and slop, change it for dragging, and restore on release"
