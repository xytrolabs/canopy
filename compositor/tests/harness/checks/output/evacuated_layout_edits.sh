#!/usr/bin/env bash
# harness: outputs=2
# Layout edits made while an output is absent belong to its temporary workspace,
# including column topology, widths, and a runtime switch to another layout.
set -euo pipefail

readonly CLIENT="$CANOPY_UNMAP_CLIENT"
readonly OFFSET=1280

cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false

[output.HEADLESS-1]
position = [0, 0]
workspaces = ["origin"]

[output.HEADLESS-2]
position = [1280, 0]
workspaces = ["local"]
EOF
"$CANOPY" msg config-reload > /dev/null

field() {
  "$CANOPY" windows --json | jq -r --arg title "$1" --arg field "$2" \
    '.[] | select(.title == $title) | .[$field]'
}

focus() {
  "$CANOPY" msg window-focus "$(field "$1" id)" > /dev/null
}

spawn() {
  local title=$1 count=$2 id
  "$CANOPY" msg workspace-switch origin --output HEADLESS-1 > /dev/null
  RESIZE_FILL_COLOR=0xFF5577AA "$CLIENT" "$title" 800 600 > "$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq 'length') == "$count" ]] && break
    sleep 0.05
  done
  id=$(field "$title" id)
  if [[ -z $id ]]; then
    echo "window '$title' did not map: $(< "$CANOPY_RUNTIME_DIR/$title.log")"
    return 1
  fi
  "$CANOPY" msg window-focus "$id" > /dev/null
  "$CANOPY" msg window-move-to-workspace origin --output HEADLESS-1 > /dev/null
}

snapshot() {
  "$CANOPY" windows --json | jq -c --argjson offset "$1" '
    [.[] | {title, column, row, x: (.x - $offset), y, w, h}] | sort_by(.title)
  '
}

select_refuge() {
  local workspace index
  workspace=$(field edit-c workspace)
  index=$("$CANOPY" workspaces --json | jq -r --arg id "$workspace" '.[] | select(.id == $id) | .index')
  if [[ $workspace != HEADLESS-2:* || -z $index ]]; then
    echo "source windows did not enter a temporary workspace: $("$CANOPY" windows --json)"
    return 1
  fi
  "$CANOPY" msg workspace-switch "$index" --output HEADLESS-2 > /dev/null
  focus edit-c
  "$CANOPY" settle
}

assert_returned_layout() {
  local label=$1 expected=$2 mode=$3 windows workspace state actual
  "$CANOPY" msg workspace-switch origin --output HEADLESS-1 > /dev/null
  focus edit-c
  "$CANOPY" settle
  windows=$("$CANOPY" windows --json)
  workspace=$(field edit-c workspace)
  state=$("$CANOPY" workspaces --json)
  if ! jq -e --arg workspace "$workspace" '
    length == 3 and all(.[]; .workspace == $workspace and (.workspace | startswith("HEADLESS-1:")))
  ' <<< "$windows" > /dev/null || \
      ! jq -e --arg workspace "$workspace" --arg mode "$mode" '
        any(.[]; .id == $workspace and .layout == $mode)
      ' <<< "$state" > /dev/null; then
    echo "$label did not return its windows and current layout mode: $windows $state"
    return 1
  fi
  actual=$(snapshot 0)
  if [[ $actual != "$expected" ]]; then
    echo "$label lost the revised temporary layout: expected $expected, got $actual"
    return 1
  fi
}

spawn edit-a 1
spawn edit-b 2
spawn edit-c 3
"$CANOPY" settle
readonly ORIGINAL="$(snapshot 0)"

"$CANOPY" output-destroy HEADLESS-1 > /dev/null
select_refuge

# Turn three independent columns into c,[b,a] after the home is already absent.
"$CANOPY" msg column-move-to-first > /dev/null
focus edit-b
"$CANOPY" msg window-consume-left > /dev/null
"$CANOPY" msg window-move-up > /dev/null
focus edit-c
"$CANOPY" msg window-set-primary-extent 0.67 > /dev/null
"$CANOPY" settle
readonly REVISED="$(snapshot "$OFFSET")"
if [[ $REVISED == "$ORIGINAL" ]] || ! jq -e '
  first(.[] | select(.title == "edit-a")) as $a |
  first(.[] | select(.title == "edit-b")) as $b |
  first(.[] | select(.title == "edit-c")) as $c |
  $c.column == 0 and $a.column == 1 and $b.column == 1 and
  $c.x < $a.x and $a.x == $b.x and $b.y < $a.y and $c.w > $a.w
' <<< "$REVISED" > /dev/null; then
  echo "temporary scrolling edits did not establish revised topology and width: $REVISED"
  exit 1
fi

"$CANOPY" output-create HEADLESS-1 > /dev/null
assert_returned_layout scrolling "$REVISED" scrolling

for mode in master dwindle; do
  "$CANOPY" output-destroy HEADLESS-1 > /dev/null
  select_refuge
  "$CANOPY" msg workspace-set-layout "$mode" > /dev/null
  "$CANOPY" msg window-set-primary-extent 0.63 > /dev/null
  "$CANOPY" settle
  workspace=$(field edit-c workspace)
  state=$("$CANOPY" workspaces --json)
  if ! jq -e --arg workspace "$workspace" --arg mode "$mode" '
    any(.[]; .id == $workspace and .layout == $mode and .layout_override)
  ' <<< "$state" > /dev/null; then
    echo "temporary workspace did not accept the $mode runtime override: $state"
    exit 1
  fi
  revised=$(snapshot "$OFFSET")
  "$CANOPY" output-create HEADLESS-1 > /dev/null
  assert_returned_layout "$mode runtime override" "$revised" "$mode"
done

echo "temporary workspace topology, widths, and runtime master and dwindle edits survived reconnection"
