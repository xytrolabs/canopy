#!/usr/bin/env bash
# Overview shortcut keys focus the labeled card, close the overview, and never leak to clients. Multi-key labels use
# sequential plain key presses, while disabling shortcuts leaves the overview open and continues swallowing input.
set -euo pipefail

readonly BTN_LEFT=272
readonly OUTPUT_W=1280
readonly OUTPUT_H=720
readonly POINTER="${CANOPY_POINTER_CLIENT:-./build-debug/tests/pointer-client}"
readonly CLIENT="${CANOPY_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly FIRST_LOG="$CANOPY_RUNTIME_DIR/shortcut-first.log"
readonly SECOND_LOG="$CANOPY_RUNTIME_DIR/shortcut-second.log"
readonly THIRD_LOG="$CANOPY_RUNTIME_DIR/shortcut-third.log"
readonly FOURTH_LOG="$CANOPY_RUNTIME_DIR/shortcut-fourth.log"
BASELINE=$(< "$CANOPY_CONFIG")

pointer() {
  "$POINTER" "$OUTPUT_W" "$OUTPUT_H" "$@"
}

wait_for_count() {
  local want=$1
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq 'length') -eq $want ]] && return 0
    sleep 0.1
  done
  echo "expected $want windows, got: $("$CANOPY" windows --json)"
  return 1
}

focused_title() {
  "$CANOPY" windows --json | jq -r '[.[] | select(.focused) | .title] | if length == 1 then .[0] else "none" end'
}

active_title() {
  "$CANOPY" windows --json | jq -r '[.[] | select(.active) | .title] | if length == 1 then .[0] else "none" end'
}

focus_title() {
  local title=$1 id
  id=$("$CANOPY" windows --json | jq -r --arg title "$title" '.[] | select(.title == $title) | .id')
  if [[ -z $id ]]; then
    echo "could not resolve window '$title': $("$CANOPY" windows --json)"
    return 1
  fi
  "$CANOPY" msg window-focus "$id" > /dev/null
}

write_config() {
  {
    printf '%s\n' "$BASELINE"
    printf '\n[animation.overview]\nduration_ms = 100\n'
    if [[ $# -gt 0 ]]; then
      printf '\n[overview]\n%s\n' "$1"
    fi
  } > "$CANOPY_CONFIG"
  "$CANOPY" msg config-reload > /dev/null
  finish
}

# Animation time only moves by clock-advance; 2000 ms finishes any animation in this check.
finish() {
  "$CANOPY" clock-advance 2000
}

"$CANOPY" clock-freeze
"$CLIENT" shortcut-first 1200 700 > "$FIRST_LOG" 2>&1 &
wait_for_count 1
"$CLIENT" shortcut-second 1200 700 > "$SECOND_LOG" 2>&1 &
wait_for_count 2
"$CLIENT" shortcut-third 1200 700 > "$THIRD_LOG" 2>&1 &
wait_for_count 3
focus_title shortcut-first
finish

write_config
"$CANOPY" msg overview-open > /dev/null
finish
# One virtual keyboard sends both keys, so the key after the overview closes reaches the client it focused. The pause
# only has to outlast the clock-advance that finishes the close.
"$POINTER" "$OUTPUT_W" "$OUTPUT_H" tap 4 pause 300 tap 30 &
pointer_pid=$!
for _ in $(seq 40); do
  [[ $(focused_title) == shortcut-third ]] && break
  sleep 0.025
done
if [[ $(focused_title) != shortcut-third ]]; then
  echo "single-key shortcut did not focus the third card: $("$CANOPY" windows --json)"
  exit 1
fi
finish
wait "$pointer_pid"
for _ in $(seq 40); do
  grep -q '^key 30 1$' "$THIRD_LOG" 2>/dev/null && break
  sleep 0.05
done
if ! grep -q '^key 30 1$' "$THIRD_LOG" 2>/dev/null; then
  echo "keyboard focus was not restored after shortcut selection: $(< "$THIRD_LOG")"
  exit 1
fi
if grep -q '^key 4 1$' "$FIRST_LOG" "$SECOND_LOG" "$THIRD_LOG" 2>/dev/null; then
  echo "overview shortcut key leaked to a client"
  exit 1
fi
if grep -q '^key 30 1$' "$FIRST_LOG" "$SECOND_LOG" 2>/dev/null; then
  echo "post-overview input reached a client other than the focused third card"
  exit 1
fi

write_config 'shortcut_keys = "12"'
"$CANOPY" msg overview-open > /dev/null
finish
pointer tap 3 tap 2
finish
if [[ $(focused_title) != shortcut-second ]]; then
  echo "multi-key shortcut 21 did not focus the second card: $("$CANOPY" windows --json)"
  exit 1
fi

write_config 'shortcuts = false'
"$CANOPY" msg overview-open > /dev/null
finish
pointer tap 2
finish
if [[ $(focused_title) != shortcut-second ]]; then
  echo "disabled overview shortcuts changed focus: $("$CANOPY" windows --json)"
  exit 1
fi
if grep -q '^key 2 1$' "$FIRST_LOG" "$SECOND_LOG" "$THIRD_LOG" 2>/dev/null; then
  echo "disabled overview shortcut input leaked to a client"
  exit 1
fi
"$CANOPY" msg overview-close > /dev/null

write_config
"$CANOPY" msg workspace-switch 2 > /dev/null
finish
"$CANOPY" msg overview-open > /dev/null
finish
"$CLIENT" shortcut-fourth 1200 700 > "$FOURTH_LOG" 2>&1 &
wait_for_count 4
finish
pointer tap 5
finish
if [[ $(active_title) != shortcut-fourth ]]; then
  echo "a new window stole an existing badge instead of receiving shortcut 4: $("$CANOPY" windows --json)"
  exit 1
fi

write_config
focus_title shortcut-first
finish
"$CANOPY" msg overview-open > /dev/null
finish
pointer move 620 360 press "$BTN_LEFT" move 760 360 release "$BTN_LEFT"
focus_title shortcut-second
finish
pointer tap 2
finish
if [[ $(active_title) != shortcut-first ]]; then
  echo "the dragged card lost its shortcut badge after drop: $("$CANOPY" windows --json)"
  exit 1
fi

echo "overview shortcuts keep stable IDs through mapping, scrolling, and drag-drop while honoring opt-out"
