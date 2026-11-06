#include "shell/bar/widgets/control_center_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const shade::bar::WidgetDefinition<ControlCenterWidget::Options>& controlCenterWidgetDefinition() {
  using Options = ControlCenterWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "control-center",
      .fields = shade::bar::glyphButtonFields<Options>(),
      .glyph = [](const Options& options) { return options.glyph; },
  };
  return definition;
}
