#!/usr/bin/env bash
# Core modifiers without keyboard focus, including implicit pointer grabs.
# harness: keyboard=none
set -euo pipefail
"${CANOPY_POINTER_MODIFIERS_CLIENT:-./build-debug/tests/pointer-modifiers-client}"
