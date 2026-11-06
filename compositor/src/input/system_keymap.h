#pragma once

#include "input/keyboard_layout.h"

namespace mahogany {

  // The X11 keymap systemd-localed reports (`localectl set-x11-keymap`). Empty when localed is unreachable, reports
  // no keymap, or reports one libxkbcommon cannot compile, and in builds without sd-bus.
  XkbNames querySystemKeymap();

} // namespace mahogany
