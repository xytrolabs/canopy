#pragma once

#include <string>

namespace shade::launcher {

  struct DmenuSocketPathResult {
    std::string path;
    std::string error;
  };

  [[nodiscard]] DmenuSocketPathResult resolveDmenuSocketPath();

} // namespace shade::launcher
