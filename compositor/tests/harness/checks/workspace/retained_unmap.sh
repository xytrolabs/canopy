#!/usr/bin/env bash
# An unmapped toplevel can outlive its last window. Its empty active workspace survives until departure, then pruning
# releases the old identity. Remapping a retained active workspace restores its trailing sentinel.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"

msg() { "$CANOPY" msg "$@" > /dev/null; }
active_id() { "$CANOPY" workspaces --json | jq -r '.[] | select(.active) | .id'; }
spawn() {
  "$CANOPY_UNMAP_CLIENT" "$1" > "$CANOPY_RUNTIME_DIR/$1.log" 2>&1 &
  await_window "$1"
}
assert_workspace() {
  local label=$1 filter=$2 state
  state=$("$CANOPY" workspaces --json)
  jq -e --arg id "$source_id" "$filter" <<< "$state" > /dev/null \
    || { echo "$label: $state"; exit 1; }
}
close_retained() {
  local count=$1
  msg window-close "$(window_by_title retained-empty | jq -r .id)"
  await_lines "$CANOPY_RUNTIME_DIR/retained-empty.log" 'unmapped$' "$count"
  for _ in $(seq 60); do
    ! window_by_title retained-empty > /dev/null && return
    sleep 0.025
  done
  echo "retained-empty stayed mapped after closing"
  exit 1
}
remap_retained() {
  printf r >&"$control_fd"
  await_window retained-empty
  "$CANOPY" settle
  [[ $(window_by_title retained-empty | jq -r .workspace) == "$source_id" ]] \
    || { echo "remap did not use the active workspace: $(window_by_title retained-empty)"; exit 1; }
}

cat >> "$CANOPY_CONFIG" <<'CONFIG'
[animation.workspaces]
duration_ms = 200
curve = "linear"
CONFIG
msg config-reload
spawn home
home_id=$(active_id)
msg workspace-switch 2
"$CANOPY" settle
source_id=$(active_id)
mkfifo "$CANOPY_RUNTIME_DIR/remap"
exec {control_fd}<>"$CANOPY_RUNTIME_DIR/remap"
REMAP_ON_STDIN=1 "$CANOPY_UNMAP_CLIENT" retained-empty <&"$control_fd" \
  > "$CANOPY_RUNTIME_DIR/retained-empty.log" 2>&1 &
retained_pid=$!
await_window retained-empty
msg workspace-switch 3
"$CANOPY" settle
spawn neighbor
neighbor_id=$(active_id)
msg workspace-switch 2
"$CANOPY" settle

close_retained 1
"$CANOPY" settle
kill -0 "$retained_pid"
assert_workspace 'closing the last window removed its active workspace' \
  'any(.[]; .id == $id and .active and .window_count == 0)'
"$CANOPY" clock-freeze
msg workspace-switch 1
"$CANOPY" clock-advance 100
assert_workspace 'the outgoing workspace vanished before its slide finished' 'any(.[]; .id == $id)'
"$CANOPY" clock-advance 200
assert_workspace 'the empty workspace survived departure with its toplevel still alive' 'all(.[]; .id != $id)'
"$CANOPY" clock-resume
"$CANOPY" settle
[[ $(active_id) == "$home_id" ]]
"$CANOPY" workspaces --json | jq -e --arg id "$neighbor_id" \
  'any(.[]; .id == $id and .index == 2 and .occupied)' > /dev/null

# The old workspace has been pruned. The same toplevel remaps onto the active trailing empty workspace.
trailing_index=$("$CANOPY" workspaces --json | jq 'max_by(.index).index')
msg workspace-switch "$trailing_index"
"$CANOPY" settle
source_id=$(active_id)
remap_retained
close_retained 2
"$CANOPY" settle
assert_workspace 'an unmapped toplevel still occupied the active trailing empty' \
  'length == 3 and any(.[]; .id == $id and .active and (.occupied | not) and .window_count == 0)'

# This remap retains its workspace membership, so no addView call can repair the missing sentinel.
remap_retained
assert_workspace 'remapping the retained workspace did not append a trailing empty' \
  'length == 4 and any(.[]; .id == $id and .active and .occupied) and (max_by(.index) | (.occupied | not))'
msg workspace-switch 1
"$CANOPY" settle
close_retained 3
"$CANOPY" settle
kill -0 "$retained_pid"
assert_workspace 'a background unmap left its empty inactive workspace behind' 'all(.[]; .id != $id)'

echo "retained unmapped toplevels release empty workspaces after departure and restore sentinels on remap"
