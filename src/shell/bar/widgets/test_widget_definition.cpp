#include "shell/bar/widgets/test_widget_definition.h"

const shade::bar::WidgetDefinition<std::monostate>& testWidgetDefinition() {
  static const shade::bar::WidgetDefinition<std::monostate> definition{
      .type = "test",
  };
  return definition;
}
