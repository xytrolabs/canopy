#!/usr/bin/env bash
# harness: xwayland=native
# Native-resolution X11 shapes use buffer pixels while their scene geometry
# remains logical. Exercise the same transitions on a scaled output.
export CANOPY_XWAYLAND_SHAPE_SCALE=2
source "$CANOPY_REPO/tests/harness/checks/protocol/xwayland_shape.sh"
