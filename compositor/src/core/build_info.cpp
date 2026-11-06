#include "core/build_info.h"

#include "canopy_git_revision.h"

#ifndef CANOPY_VERSION
#define CANOPY_VERSION "unknown"
#endif

namespace mahogany::build_info {

  std::string_view version() noexcept { return CANOPY_VERSION; }

  std::string_view revision() noexcept { return CANOPY_GIT_REVISION; }

} // namespace mahogany::build_info
