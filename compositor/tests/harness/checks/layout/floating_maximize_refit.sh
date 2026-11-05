#!/usr/bin/env bash
# harness: outputs=1
# A maximized float keeps the margin a maximized tile keeps (layout struts, then one gap and the total border width on
# every side), so it is refit whenever those change: a gap, border, or strut reload, and the usable area a panel takes.
# A visible maximized scratchpad window follows the same reloads. Restoring still returns the pre-maximize box.
set -euo pipefail

readonly CLIENT="${CANOPY_FRACTIONAL_CLIENT:-./build-debug/tests/fractional-client}"
readonly LAYER_CLIENT="${CANOPY_LAYER_CLIENT:-./build-debug/tests/layer-client}"
readonly BASE_CONFIG="$CANOPY_RUNTIME_DIR/base-config.toml"

cp "$CANOPY_CONFIG" "$BASE_CONFIG"

# The base config plus `$1`, applied by a reload.
reload_with() {
  {
    cat "$BASE_CONFIG"
    cat << 'EOF'

[animation]
enabled = false

[[window_rule]]
match.title = "^refit-"
default_floating = true
default_floating_size = { width = 0.5, height = 0.5 }
EOF
    printf '%s\n' "$1"
  } > "$CANOPY_CONFIG"
  "$CANOPY" msg config-reload > /dev/null
  "$CANOPY" settle
}

field_of() {
  "$CANOPY" windows --json \
    | jq -r --arg title "$1" --arg field "$2" '.[] | select(.title == $title) | .[$field]'
}

# Waits for `$1` to sit at `$2`, given as WxH+X+Y.
assert_box() {
  local title=$1 expected=$2 actual=
  for _ in $(seq 80); do
    actual="$(field_of "$title" w)x$(field_of "$title" h)+$(field_of "$title" x)+$(field_of "$title" y)"
    [[ $actual == "$expected" ]] && return 0
    sleep 0.1
  done
  echo "expected '$title' at $expected, got $actual: $3"
  return 1
}

# Defaults: gap 8 and border 2 give an edge pad of 10 on the 1280x720 output.
reload_with ""
"$CLIENT" refit-float > "$CANOPY_RUNTIME_DIR/refit-float.log" 2>&1 &
assert_box refit-float 640x360+320+180 "the float did not open at half size"
"$CANOPY" msg window-focus-warp "$(field_of refit-float id)" > /dev/null
"$CANOPY" msg window-toggle-maximize > /dev/null
assert_box refit-float 1260x700+10+10 "maximize did not keep the default margin"

reload_with $'[layout]\ngap = 30'
assert_box refit-float 1216x656+32+32 "a gap reload did not refit the maximized float"

reload_with $'[appearance]\nborder_width = 4\nouter_border_width = 2'
assert_box refit-float 1252x692+14+14 "a border reload did not refit the maximized float"

reload_with $'[layout.struts]\nleft = 100'
assert_box refit-float 1160x700+110+10 "a strut reload did not refit the maximized float"

reload_with ""
assert_box refit-float 1260x700+10+10 "returning to the defaults did not refit the maximized float"

# A panel's exclusive zone shrinks the usable area; the float moves below it, and back once it goes.
"$LAYER_CLIENT" HEADLESS-1 40 > "$CANOPY_RUNTIME_DIR/panel.log" 2>&1 &
panel=$!
assert_box refit-float 1260x660+10+50 "a panel did not refit the maximized float"
kill "$panel"
wait "$panel" 2> /dev/null || true
assert_box refit-float 1260x700+10+10 "removing the panel did not refit the maximized float"

# Refits never replace the box a restore returns to.
"$CANOPY" msg window-toggle-maximize > /dev/null
assert_box refit-float 640x360+320+180 "restoring after refits did not return the pre-maximize box"

# A visible maximized scratchpad window follows a reload too.
"$CANOPY" msg window-move-to-scratchpad > /dev/null
"$CANOPY" msg scratchpad-toggle > /dev/null
"$CANOPY" settle
"$CANOPY" msg window-focus "$(field_of refit-float id)" > /dev/null
"$CANOPY" msg window-toggle-maximize > /dev/null
assert_box refit-float 1260x700+10+10 "the scratchpad window did not maximize inside the margin"
reload_with $'[layout]\ngap = 30'
assert_box refit-float 1216x656+32+32 "a gap reload did not refit the maximized scratchpad window"

echo "maximized floats and scratchpad windows were refit on gap, border, strut, and usable area changes"
