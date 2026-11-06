#pragma once

#include <string_view>

namespace mahogany::build_info {

  // build_info.cpp is the only unit that sees the generated revision header, so
  // a new commit recompiles it alone.
  std::string_view version() noexcept;

  std::string_view revision() noexcept;

} // namespace mahogany::build_info
