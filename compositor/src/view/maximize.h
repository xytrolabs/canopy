#pragma once

namespace mahogany {

  // A maximize request targets the edges when already active or configured; an unmaximize exits the active mode.
  constexpr bool maximizeRequestTargetsEdges(bool requestedMaximized, bool edgesActive, bool configTargetsEdges) {
    return requestedMaximized ? (edgesActive || configTargetsEdges) : edgesActive;
  }

} // namespace mahogany
