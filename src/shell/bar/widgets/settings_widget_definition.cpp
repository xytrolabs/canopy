#include "shell/bar/widgets/settings_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const shade::bar::WidgetDefinition<SettingsWidget::Options>& settingsWidgetDefinition() {
  using Options = SettingsWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "settings",
      .fields = shade::bar::glyphButtonFields<Options>(),
      .glyph = [](const Options& options) { return options.glyph; },
  };
  return definition;
}
