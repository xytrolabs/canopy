#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

rewrite_config() {
    local config_file="$1" program="$2"
    [ -f "$config_file" ] || return 0
    local tmp_file
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    if ! awk "$program" "$config_file" >"$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! cmp -s "$config_file" "$tmp_file"; then
        cat "$tmp_file" >"$config_file"
    fi
    rm -f "$tmp_file"
}

rewrite_config "$config_dir/hyprland.conf" '
    /#[[:space:]]*For Noctalia Color templates/ { pending = $0; next }
    /^[[:space:]]*source[[:space:]]*=.*canopy\.conf/ { pending = ""; next }
    pending != "" { print pending; pending = "" }
    { print }
    END { if (pending != "") print pending }
'
rewrite_config "$config_dir/hyprland.lua" '
    /--[[:space:]]*For Noctalia Color templates/ { pending = $0; next }
    /require\("canopy"\)\.apply_theme\(\)/ { pending = ""; next }
    pending != "" { print pending; pending = "" }
    { print }
    END { if (pending != "") print pending }
'

rm -f -- "$config_dir/canopy.conf" "$config_dir/canopy.lua"
