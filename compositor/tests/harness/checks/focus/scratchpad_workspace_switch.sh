#!/usr/bin/env bash
# Switching workspaces must not steal keyboard focus from a visible scratchpad.
# refocus(Output*) retains a focused, foreground scratchpad across a workspace
# switch; explicit actions use refocusExplicit().
set -euo pipefail

readonly CLIENT="${CANOPY_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly SCRATCHPAD=switch
readonly WS1=scratchpad-switch-ws1
readonly WS2=scratchpad-switch-ws2
readonly SCRATCH=scratchpad-switch-foreground

cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false

[[scratchpad]]
name = "switch"

[[window_rule]]
match.title = "^scratchpad-switch-foreground$"
default_floating = true
default_floating_size_px = { width = 420, height = 260 }
EOF
"$CANOPY" msg config-reload > /dev/null

windows() { "$CANOPY" windows --json; }

field_of() {
  windows | jq -r --arg title "$1" --arg field "$2" '.[] | select(.title == $title) | .[$field]'
}

wait_for_count() {
  local expected=$1 count=
  for _ in $(seq 80); do
    count=$(windows | jq 'length')
    [[ $count == "$expected" ]] && return 0
    sleep 0.1
  done
  echo "expected $expected windows, got $count: $(windows)"
  return 1
}

wait_for_field() {
  local title=$1 field=$2 expected=$3 actual=
  for _ in $(seq 80); do
    actual=$(field_of "$title" "$field")
    [[ $actual == "$expected" ]] && return 0
    sleep 0.1
  done
  echo "expected '$title' field '$field' to be '$expected', got '$actual': $(windows)"
  return 1
}

"$CLIENT" "$WS1" > "$CANOPY_RUNTIME_DIR/$WS1.log" 2>&1 &
wait_for_count 1
"$CANOPY" msg workspace-switch 2 > /dev/null
"$CLIENT" "$WS2" > "$CANOPY_RUNTIME_DIR/$WS2.log" 2>&1 &
wait_for_count 2
"$CANOPY" msg workspace-switch 1 > /dev/null
wait_for_field "$WS1" active true

"$CLIENT" "$SCRATCH" 420 260 > "$CANOPY_RUNTIME_DIR/$SCRATCH.log" 2>&1 &
wait_for_count 3
scratch_id=$(field_of "$SCRATCH" id)
"$CANOPY" msg window-focus "$scratch_id" > /dev/null
"$CANOPY" msg window-move-to-scratchpad "$SCRATCHPAD" > /dev/null
wait_for_field "$SCRATCH" scratchpad "$SCRATCHPAD"
"$CANOPY" msg scratchpad-toggle "$SCRATCHPAD" > /dev/null
wait_for_field "$SCRATCH" active true
"$CANOPY" msg window-focus "$scratch_id" > /dev/null
wait_for_field "$SCRATCH" active true

# The workspace switch under test: focus must stay on the foreground scratchpad.
"$CANOPY" msg workspace-switch 2 > /dev/null
wait_for_field "$SCRATCH" active true
for _ in $(seq 5); do
  sleep 0.1
  if [[ $(field_of "$SCRATCH" active) != true || $(field_of "$WS2" active) != false ]]; then
    echo "workspace switch stole focus from the visible scratchpad: $(windows)"
    exit 1
  fi
done

echo "workspace switch keeps focus on the visible scratchpad"
