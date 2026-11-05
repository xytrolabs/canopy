#!/usr/bin/env bash
# A tab maximized to edges covers the output only while it is shown; the group's other tabs keep the group's place and
# width.
set -euo pipefail

spawn_client() {
  foot --title="$1" sh -c 'sleep 120' > /dev/null 2>&1 &
}

wait_for_windows() {
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq 'length') == "$1" ]] && return 0
    sleep 0.1
  done
  echo "expected $1 window(s): $("$CANOPY" windows --json)"
  return 1
}

cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false
EOF
"$CANOPY" msg config-reload > /dev/null

spawn_client tab-a
wait_for_windows 1
spawn_client tab-b
wait_for_windows 2
"$CANOPY" msg window-consume-left > /dev/null
"$CANOPY" msg column-toggle-tabbed > /dev/null
"$CANOPY" msg column-focus-tab 1 > /dev/null
"$CANOPY" msg window-set-primary-extent 0.5 > /dev/null
"$CANOPY" settle

box() { "$CANOPY" windows --json | jq -c --arg title "$1" '.[] | select(.title == $title) | [.x, .y, .w, .h]'; }
group=$(box tab-a)

"$CANOPY" msg window-toggle-maximize-to-edges > /dev/null
"$CANOPY" settle
maximized=$(box tab-a)

"$CANOPY" msg column-focus-tab-next > /dev/null
"$CANOPY" settle
if [[ $(box tab-b) != "$group" ]]; then
  echo "expected tab-b in the group's box $group, got $(box tab-b)"
  exit 1
fi

"$CANOPY" msg column-focus-tab-previous > /dev/null
"$CANOPY" settle
if [[ $(box tab-a) != "$maximized" ]]; then
  echo "expected tab-a maximized again in $maximized, got $(box tab-a)"
  exit 1
fi

echo "the other tab kept the group's box, and the maximized tab covered the output again"
