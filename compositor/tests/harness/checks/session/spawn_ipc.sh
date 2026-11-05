#!/usr/bin/env bash
# A spawned IPC command releases its launch workspace. A launcher can query IPC before its window opens, and a
# spawned IPC command can hand startup placement to another spawn.
set -euo pipefail
source "$CANOPY_HARNESS_LIB"

readonly CLIENT="$CANOPY_UNMAP_CLIENT"
msg() { "$CANOPY" msg "$@" > /dev/null; }
active_id() { "$CANOPY" workspaces --json | jq -r '.[] | select(.active) | .id'; }
assert_source() {
  local present=$1 label=$2 state
  state=$("$CANOPY" workspaces --json)
  [[ $(jq -r --arg id "$source_id" 'any(.[]; .id == $id)' <<< "$state") == "$present" ]] \
    || { echo "$label: $state"; exit 1; }
}
await_absent() {
  for _ in $(seq 100); do
    ! window_by_title "$1" > /dev/null && return
    sleep 0.025
  done
  echo "window stayed mapped: $1"; exit 1
}
await_home() {
  for _ in $(seq 100); do
    [[ $(active_id) == "$home_id" ]] && return
    sleep 0.025
  done
  echo "spawned IPC did not switch to the home workspace: $("$CANOPY" workspaces --json)"
  exit 1
}

cat >> "$CANOPY_CONFIG" <<'CONFIG'
[animation.windows_in]
enabled = false
[animation.windows_out]
enabled = false
[animation.workspaces]
duration_ms = 100
curve = "linear"
CONFIG
msg config-reload
"$CLIENT" home > "$CANOPY_RUNTIME_DIR/home.log" 2>&1 &
await_window home
home_id=$(active_id)
msg workspace-switch 2
"$CANOPY" settle
"$CLIENT" file-manager > "$CANOPY_RUNTIME_DIR/file-manager.log" 2>&1 &
manager_pid=$!
await_window file-manager
source_id=$(active_id)
msg workspace-switch 3
"$CANOPY" settle
REQUEST_FULLSCREEN=1 FOLLOW_CONFIGURES=1 LOG_CONFIGURES=1 "$CLIENT" game \
  > "$CANOPY_RUNTIME_DIR/game.log" 2>&1 &
await_window game
await_lines "$CANOPY_RUNTIME_DIR/game.log" 'configured-state=.* fullscreen$' 1
game_id=$(window_by_title game | jq -r .id)
neighbor_id=$(active_id)
"$CANOPY" settle
msg workspace-switch 2
"$CANOPY" settle
kill "$manager_pid"
wait "$manager_pid" 2>/dev/null || true
await_absent file-manager
"$CANOPY" settle
msg spawn "'$CANOPY' msg workspace-previous"
await_home
"$CANOPY" settle
assert_source false 'spawned navigation retained its empty workspace'
"$CANOPY" workspaces --json | jq -e --arg id "$neighbor_id" \
  'any(.[]; .id == $id and .index == 2)' > /dev/null

for mode in helper nested; do
  # Moving the neighbor forward leaves an active empty workspace with occupied content after it.
  msg window-focus "$game_id"
  msg window-move-to-workspace-silent 3
  "$CANOPY" settle
  source_id=$(active_id)
  gate="$CANOPY_RUNTIME_DIR/$mode.gate"
  ready="$CANOPY_RUNTIME_DIR/$mode.ready"
  log="$CANOPY_RUNTIME_DIR/$mode.log"
  mkfifo "$gate"
  exec {gate_fd}<>"$gate"
  command="read -r _ < '$gate'; exec '$CLIENT' $mode > '$log' 2>&1"
  if [[ $mode == helper ]]; then
    msg spawn "'$CANOPY' windows --json > '$ready'; $command"
    await_lines "$ready" '\[' 1
  else
    inner_command="printf 'ready\\n' > '$ready'; $command"
    printf -v nested_command 'exec %q msg spawn %q' "$CANOPY" "$inner_command"
    msg spawn "$nested_command"
    await_lines "$ready" 'ready$' 1
  fi
  msg workspace-switch 1
  "$CANOPY" settle
  assert_source false "$mode launch left its pending workspace visible"
  printf 'start\n' >&"$gate_fd"
  await_window "$mode"
  "$CANOPY" settle
  [[ $(window_by_title "$mode" | jq -r .workspace) == "$source_id" && $(active_id) == "$home_id" ]] \
    || { echo "$mode target did not map silently on its launch workspace: $("$CANOPY" windows --json)"; exit 1; }
  msg window-close "$(window_by_title "$mode" | jq -r .id)"
  await_absent "$mode"
  "$CANOPY" settle
  assert_source false "$mode launch retained its workspace after the target closed"
  exec {gate_fd}>&-
done

echo "spawned IPC releases empty workspaces while launcher queries and nested spawns preserve delayed placement"
