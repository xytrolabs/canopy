#!/bin/sh -eu
# Compares the two abi probe builds. Field offsets must match exactly; canopyfx
# may only be larger, never smaller or differently ordered.
#
# Usage: abi_compare.sh <wlroots-probe> <canopyfx-probe>

wlroots_probe=$1
canopyfx_probe=$2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$wlroots_probe" > "$tmp/wlroots"
"$canopyfx_probe" > "$tmp/canopyfx"

status=0

# Every field wlroots declares must sit at the same offset in canopyfx.
grep '^offsetof' "$tmp/wlroots" > "$tmp/wlroots.off"
grep '^offsetof' "$tmp/canopyfx" > "$tmp/canopyfx.off"
if ! diff -u "$tmp/wlroots.off" "$tmp/canopyfx.off" > "$tmp/off.diff"; then
	echo "error: canopyfx scene struct field offsets diverge from wlroots"
	echo "       The compositor calls scene helpers canopyfx does not reimplement"
	echo "       (wlr_scene_xdg_surface_create, wlr_scene_subsurface_tree_create,"
	echo "       wlr_scene_attach_output_layout, ...) which resolve to libwlroots"
	echo "       and read these structs at wlroots offsets. A mismatch corrupts"
	echo "       memory silently."
	echo
	sed 's/^/  /' "$tmp/off.diff"
	echo
	echo "  Fix the field order in canopyfx/include/canopyfx/types/wlr_scene.h."
	echo "  Fields Canopy adds belong after every wlroots field."
	status=1
fi

# canopyfx extends these structs, so it must never be smaller than wlroots.
grep '^sizeof' "$tmp/wlroots" > "$tmp/wlroots.size"
while read -r line; do
	name=$(printf '%s\n' "$line" | sed 's/^sizeof(struct \([a-z_]*\)).*/\1/')
	want=$(printf '%s\n' "$line" | sed 's/.*>= //')
	got=$(grep "^sizeof(struct $name)" "$tmp/canopyfx" | sed 's/.*>= //')
	if [ "$got" -lt "$want" ]; then
		echo "error: struct $name is $got bytes in canopyfx, $want in wlroots"
		echo "       canopyfx extends this struct and can never be smaller."
		status=1
	fi
done < "$tmp/wlroots.size"

exit $status
