#include "shell/bar/widgets/caffeine_widget_definition.h"

const shade::bar::WidgetDefinition<std::monostate>& caffeineWidgetDefinition() {
  static const shade::bar::WidgetDefinition<std::monostate> definition{
      .type = "caffeine",
  };
  return definition;
}
