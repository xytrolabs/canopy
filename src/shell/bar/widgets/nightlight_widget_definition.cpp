#include "shell/bar/widgets/nightlight_widget_definition.h"

const shade::bar::WidgetDefinition<std::monostate>& nightlightWidgetDefinition() {
  static const shade::bar::WidgetDefinition<std::monostate> definition{
      .type = "nightlight",
  };
  return definition;
}
