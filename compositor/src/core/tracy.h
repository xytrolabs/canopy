#pragma once

// Zones for the compositor's per-frame work, alongside canopyfx's own zones
// for the render pass. No-ops without -Dtracy=enabled.
#ifdef TRACY_ENABLE
#include <tracy/Tracy.hpp>
#define CANOPY_ZONE(name) ZoneScopedN(name)
#else
#define CANOPY_ZONE(name)
#endif
