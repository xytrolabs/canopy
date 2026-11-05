#!/usr/bin/env bash
# harness: outputs=2
# New windows inherit a temporary workspace's missing home. An explicit move
# adopts its destination, while a pending launch keeps an emptied refuge alive.
set -euo pipefail

readonly CLIENT="$CANOPY_UNMAP_CLIENT"
readonly START_FIFO="$CANOPY_RUNTIME_DIR/evacuated-arrival-start"
readonly TOKEN_FILE="$CANOPY_RUNTIME_DIR/evacuated-arrival-token"
readonly PENDING_LOG="$CANOPY_RUNTIME_DIR/evacuated-arrival-pending.log"

cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false

[output.HEADLESS-1]
workspaces = ["origin"]

[output.HEADLESS-2]
workspaces = ["local", "stay"]
EOF
"$CANOPY" msg config-reload > /dev/null

field() {
  "$CANOPY" windows --json | jq -r --arg title "$1" --arg field "$2" \
    '.[] | select(.title == $title) | .[$field]'
}

wait_for_window() {
  local title=$1 state=
  for _ in $(seq 60); do
    state=$("$CANOPY" windows --json)
    jq -e --arg title "$title" 'any(.[]; .title == $title)' <<< "$state" > /dev/null && return 0
    sleep 0.05
  done
  echo "window '$title' did not map: $state"
  return 1
}

spawn() {
  local title=$1 selector=$2 place=${3:-true} id
  local -a words
  read -ra words <<< "$selector"
  "$CANOPY" msg workspace-switch "${words[@]}" > /dev/null
  "$CLIENT" "$title" 800 600 > "$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
  wait_for_window "$title"
  if [[ $place == true ]]; then
    id=$(field "$title" id)
    "$CANOPY" msg window-focus "$id" > /dev/null
    "$CANOPY" msg window-move-to-workspace "${words[@]}" > /dev/null
  fi
}

spawn retained 'origin --output HEADLESS-1'
spawn moved-out 'origin --output HEADLESS-1'
spawn local 'local --output HEADLESS-2'
readonly LOCAL_HOME="$(field local workspace)"
"$CANOPY" output-destroy HEADLESS-1 > /dev/null
"$CANOPY" settle
readonly REFUGE="$(field retained workspace)"
readonly INDEX="$("$CANOPY" workspaces --json | jq -r --arg id "$REFUGE" '.[] | select(.id == $id) | .index')"
if [[ $REFUGE != HEADLESS-2:* || $REFUGE == "$LOCAL_HOME" || $(field moved-out workspace) != "$REFUGE" ]]; then
  echo "source windows did not enter a shared temporary workspace: $("$CANOPY" windows --json)"
  exit 1
fi

spawn newcomer "$INDEX --output HEADLESS-2" false
if [[ $(field newcomer workspace) != "$REFUGE" ]]; then
  echo "new window did not map in the selected temporary workspace: $("$CANOPY" windows --json)"
  exit 1
fi
"$CANOPY" msg window-focus "$(field moved-out id)" > /dev/null
"$CANOPY" msg window-move-to-workspace stay --output HEADLESS-2 > /dev/null
"$CANOPY" settle
readonly MOVED_HOME="$(field moved-out workspace)"
if [[ $MOVED_HOME != HEADLESS-2:* || $MOVED_HOME == "$REFUGE" ]]; then
  echo "explicit move did not leave the temporary workspace: $("$CANOPY" windows --json)"
  exit 1
fi

# Capture a launch while the temporary workspace still exists, but keep its
# client from connecting until the original output has reclaimed every window.
"$CANOPY" msg workspace-switch "$INDEX" --output HEADLESS-2 > /dev/null
mkfifo "$START_FIFO"
exec {start_fd}<>"$START_FIFO"
"$CANOPY" msg spawn \
  "printf '%s\n' \"\$XDG_ACTIVATION_TOKEN\" > '$TOKEN_FILE'; read -r _ < '$START_FIFO'; exec '$CLIENT' pending-arrival 800 600 > '$PENDING_LOG' 2>&1" \
  > /dev/null
for _ in $(seq 60); do
  [[ -s $TOKEN_FILE ]] && break
  sleep 0.05
done
if [[ ! -s $TOKEN_FILE ]]; then
  echo "delayed arrival did not receive a launch token"
  exit 1
fi

"$CANOPY" output-create HEADLESS-1 > /dev/null
"$CANOPY" settle
windows=$("$CANOPY" windows --json)
workspaces=$("$CANOPY" workspaces --json)
if ! jq -e --arg moved "$MOVED_HOME" --arg local "$LOCAL_HOME" '
  ([.[] | select(.title == "retained" or .title == "newcomer") | .workspace] | unique) as $returned |
  ($returned | length) == 1 and ($returned[0] | startswith("HEADLESS-1:")) and
  any(.[]; .title == "moved-out" and .workspace == $moved) and
  any(.[]; .title == "local" and .workspace == $local)
' <<< "$windows" > /dev/null; then
  echo "new window did not follow its home, or an explicit move was undone: $windows"
  exit 1
fi
if ! jq -e --arg refuge "$REFUGE" '
  any(.[]; .id == $refuge and .named and .name == "origin" and .occupied == false and .window_count == 0)
' <<< "$workspaces" > /dev/null; then
  echo "pending launch did not preserve the emptied temporary workspace: $workspaces"
  exit 1
fi

printf 'start\n' >&"$start_fd"
wait_for_window pending-arrival
for _ in $(seq 60); do
  "$CANOPY" settle
  windows=$("$CANOPY" windows --json)
  workspaces=$("$CANOPY" workspaces --json)
  if jq -e 'any(.[]; .title == "pending-arrival" and (.workspace | startswith("HEADLESS-1:")))' \
      <<< "$windows" > /dev/null && \
      jq -e 'length == 3 and all(.[]; .named)' <<< "$workspaces" > /dev/null; then
    echo "new arrivals returned home, explicit moves stayed local, and pending launches released their temporary workspace"
    exit 0
  fi
  sleep 0.05
done
echo "late arrival did not follow its available home or release its temporary workspace: $windows $workspaces"
exit 1
