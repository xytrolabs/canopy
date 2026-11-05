#!/usr/bin/env bash
# A window mapped into the outgoing workspace during a slide must be hidden when the slide finishes.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"

cat >> "$CANOPY_CONFIG" <<'EOF'
[animation.workspaces]
duration_ms = 1000
curve = "linear"

[colors]
backdrop = "#000000FF"

[output."HEADLESS-1"]
workspaces = 2

[[window_rule]]
match.app_id = "^late-map$"
default_workspace = 1
default_focused = false
EOF
"$CANOPY" msg config-reload > /dev/null
"$CANOPY" clock-freeze
"$CANOPY" msg workspace-switch 2 > /dev/null
"$CANOPY" workspaces --json | jq -e '.[] | select(.name == "2" and .active)' > /dev/null
APP_ID=late-map "$CANOPY_UNMAP_CLIENT" late-map 1200 700 > "$CANOPY_RUNTIME_DIR/client.log" 2>&1 &
await_lines "$CANOPY_RUNTIME_DIR/client.log" 'mapped' 1
"$CANOPY" clock-advance 1200
"$CANOPY" clock-resume
"$CANOPY" settle
grim "$CANOPY_RUNTIME_DIR/late-map.png"
read -r _ _ blue < <("$CANOPY_PIXEL_PROBE" "$CANOPY_RUNTIME_DIR/late-map.png" mean)
if ((blue != 0)); then
  echo "inactive late-mapped window remains visible: mean blue=$blue"
  exit 1
fi
