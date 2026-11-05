#!/usr/bin/env bash
# harness: outputs=3
# Explicit numeric workspace names remain selectable after output loss, while
# their receiving positions stay independent of their original names.
set -euo pipefail

readonly BASELINE="$(< "$CANOPY_CONFIG")"
readonly SETTINGS='
[animation]
enabled = false

[output.HEADLESS-1]
position = [0, 0]
workspaces = ["1", "2", "3", "4"]

[output.HEADLESS-2]
position = [1280, 0]
workspaces = ["5", "6", "7"]

[output.HEADLESS-3]
position = [2560, 0]
workspaces = ["8", "9", "10"]'

write_config() {
  printf '%s\n%s\n' "$BASELINE" "$SETTINGS" > "$CANOPY_CONFIG"
  if [[ $1 == disabled ]]; then
    sed -i '/^\[output.HEADLESS-[12]\]$/a enabled = false' "$CANOPY_CONFIG"
  elif [[ $1 == disabled-source ]]; then
    sed -i '/^\[output.HEADLESS-1\]$/a enabled = false' "$CANOPY_CONFIG"
    cat >> "$CANOPY_CONFIG" <<'EOF'

[[window_rule]]
match.title = "^disabled-rule-name$"
default_workspace = "1"
EOF
  fi
  "$CANOPY" msg config-reload > /dev/null
  "$CANOPY" settle
}

field() {
  "$CANOPY" windows --json | jq -r --arg title "$1" --arg field "$2" \
    '.[] | select(.title == $title) | .[$field]'
}

spawn() {
  local title=$1 selector=$2 count=$3 place=${4:-true} id
  local -a words
  read -ra words <<< "$selector"
  "$CANOPY" msg workspace-switch "${words[@]}" > /dev/null
  "$CANOPY_UNMAP_CLIENT" "$title" 800 600 > "$CANOPY_RUNTIME_DIR/$title.log" 2>&1 &
  for _ in $(seq 60); do
    [[ $("$CANOPY" windows --json | jq 'length') == "$count" ]] && break
    sleep 0.05
  done
  id=$(field "$title" id)
  if [[ -z $id ]]; then
    echo "window '$title' did not map: $(< "$CANOPY_RUNTIME_DIR/$title.log")"
    return 1
  fi
  if [[ $place == true ]]; then
    "$CANOPY" msg window-focus "$id" > /dev/null
    "$CANOPY" msg window-move-to-workspace "${words[@]}" > /dev/null
  fi
}

expect_selected() {
  local selector=$1 expected=$2 workspaces
  local -a words
  read -ra words <<< "$selector"
  "$CANOPY" msg workspace-switch "${words[@]}" > /dev/null
  workspaces=$("$CANOPY" workspaces --json)
  if ! jq -e --arg expected "$expected" \
      'any(.[]; .id == $expected and .focused)' <<< "$workspaces" > /dev/null; then
    echo "selector '$selector' did not focus workspace $expected: $workspaces"
    return 1
  fi
}

expect_evacuated() {
  local phase=$1 workspaces one four inventory
  "$CANOPY" settle
  workspaces=$("$CANOPY" workspaces --json)
  inventory=$(jq -c '[.[] | select(.output == "HEADLESS-3")] | sort_by(.index) | map(.name)' <<< "$workspaces")
  if [[ $inventory != '["8","9","10","1","4"]' ]]; then
    echo "$phase did not preserve the receiving inventory names: $workspaces"
    return 1
  fi
  one=$(field source-one workspace)
  four=$(field source-four workspace)
  if ! jq -e --arg one "$one" --arg four "$four" --argjson native "$NATIVE_IDS" '
    any(.[]; .id == $one and .named and .name == "1" and .index == 4) and
    any(.[]; .id == $four and .named and .name == "4" and .index == 5) and
    ([.[] | select(.output == "HEADLESS-3" and .index <= 3) | .id] == $native)
  ' <<< "$workspaces" > /dev/null; then
    echo "$phase replaced native workspaces or confused names with positions: $workspaces"
    return 1
  fi
  expect_selected '--name 1' "$one"
  expect_selected '--name 4' "$four"
  expect_selected '--name 1 --output HEADLESS-3' "$one"
  expect_selected '--name 1 --output HEADLESS-1' "$one"
  expect_selected '--name 4 --output HEADLESS-1' "$four"
  expect_selected '4 --output HEADLESS-3' "$one"
  expect_selected '5 --output HEADLESS-3' "$four"
}

expect_restored() {
  local phase=$1 workspaces
  "$CANOPY" settle
  workspaces=$("$CANOPY" workspaces --json)
  if ! jq -e --arg one "$(field source-one workspace)" --arg four "$(field source-four workspace)" '
    any(.[]; .id == $one and .output == "HEADLESS-1" and .name == "1" and .named) and
    any(.[]; .id == $four and .output == "HEADLESS-1" and .name == "4" and .named) and
    ([.[] | select(.output == "HEADLESS-3")] | length) == 3
  ' <<< "$workspaces" > /dev/null; then
    echo "$phase did not restore the original named workspaces: $workspaces"
    return 1
  fi
  expect_selected '--name 1' "$(field source-one workspace)"
  expect_selected '--name 4' "$(field source-four workspace)"
}

write_config enabled
spawn source-one '--name 1 --output HEADLESS-1' 1
spawn source-four '--name 4 --output HEADLESS-1' 2
spawn native-eight '--name 8 --output HEADLESS-3' 3
readonly NATIVE_IDS="$("$CANOPY" workspaces --json | jq -c '[.[] | select(.output == "HEADLESS-3") | .id]')"

"$CANOPY" output-destroy HEADLESS-2 > /dev/null
"$CANOPY" output-destroy HEADLESS-1 > /dev/null
expect_evacuated removal
"$CANOPY" msg config-reload > /dev/null
expect_evacuated absent-reload
"$CANOPY" output-create HEADLESS-1 > /dev/null
expect_restored reconnect
"$CANOPY" output-create HEADLESS-2 > /dev/null

write_config disabled
expect_evacuated disable
"$CANOPY" msg config-reload > /dev/null
expect_evacuated disabled-reload
write_config enabled
expect_restored reenable

# A retained disabled group must not make a global name look ambiguous when a
# rule opens from another enabled output, away from the receiving group.
write_config disabled-source
rule_refuge=$(field source-one workspace)
if [[ ${rule_refuge%%:*} == HEADLESS-2 ]]; then
  rule_start='--name 8 --output HEADLESS-3'
else
  rule_start='--name 5 --output HEADLESS-2'
fi
spawn disabled-rule-name "$rule_start" 4 false
if [[ $(field disabled-rule-name workspace) != "$rule_refuge" ]]; then
  echo "retained disabled group prevented the global opening rule from reaching its refugee: $("$CANOPY" windows --json)"
  exit 1
fi
write_config enabled
expect_restored rule-arrival-reenable
if [[ $(field disabled-rule-name workspace) != "$(field source-one workspace)" ]]; then
  echo "rule-routed arrival did not return with its original named workspace: $("$CANOPY" windows --json)"
  exit 1
fi

echo "named numeric workspaces survived removal, disable, reload, and reconnect without changing receiving positions"
