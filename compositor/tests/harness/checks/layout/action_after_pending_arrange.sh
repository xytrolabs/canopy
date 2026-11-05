#!/usr/bin/env bash
# A layout action must see the arrangement the previous action produced, even
# when no frame has run in between. The output runs at 4 Hz, so once settle
# returns, a master consume and a move-up both land before the next frame and
# the move runs while the consume's arrange is still pending.
set -euo pipefail

cat >> "$CANOPY_CONFIG" <<'EOF'

[animation]
enabled = false

[output.HEADLESS-1]
mode = "1280x720@4"

[[workspace]]
output = "HEADLESS-1"
index = 1
layout.mode = "master"
EOF
"$CANOPY" msg config-reload > /dev/null

for title in a b c; do
  foot --title "$title" sh -c 'sleep 120' > /dev/null 2>&1 &
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq --arg t "$title" 'map(select(.title == $t)) | length') -eq 1 ]] && break
    sleep 0.25
  done
done
"$CANOPY" settle

# Master a, stack rows c then b (new windows join the stack top); focus c.
"$CANOPY" msg window-focus "$("$CANOPY" windows --json | jq -r '.[] | select(.title == "c") | .id')" > /dev/null
"$CANOPY" settle
before=$("$CANOPY" windows --json | jq -r 'sort_by(.x, .y) | map(.title) | join("")')
if [[ $before != acb ]]; then
  echo "setup did not form master a over stack c,b: $before"
  exit 1
fi
"$CANOPY" settle
"$CANOPY" msg window-consume-left > /dev/null
"$CANOPY" msg window-move-up > /dev/null
"$CANOPY" settle

after=$("$CANOPY" windows --json | jq -r 'sort_by(.x, .y) | map(.title) | join("")')
if [[ $after != cab ]]; then
  echo "move-up after a pending consume did not put c above a in the master area: $after"
  exit 1
fi
echo "a layout action applies the arrange its predecessor left pending"
