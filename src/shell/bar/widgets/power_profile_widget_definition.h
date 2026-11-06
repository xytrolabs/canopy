#pragma once

#include "shell/bar/widget_definition.h"

#include <variant>

[[nodiscard]] const shade::bar::WidgetDefinition<std::monostate>& powerProfileWidgetDefinition();
