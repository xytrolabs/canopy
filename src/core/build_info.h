#pragma once

#include <string>
#include <string_view>

namespace shade::build_info {

  [[nodiscard]] std::string_view version() noexcept;

  [[nodiscard]] std::string_view revision() noexcept;

  [[nodiscard]] std::string displayVersion();

} // namespace shade::build_info
