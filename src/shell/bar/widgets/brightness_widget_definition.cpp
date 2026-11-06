#include "shell/bar/widgets/brightness_widget_definition.h"

const shade::bar::WidgetDefinition<BrightnessWidget::Options>& brightnessWidgetDefinition() {
  using shade::bar::field;
  using Options = BrightnessWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "brightness",
      .fields =
          {
              field<&Options::showGlyph>({
                  .key = "show_glyph",
              }),
              field<&Options::showLabel>({
                  .key = "show_label",
              }),
              field<&Options::showWhenUnavailable>({
                  .key = "show_when_unavailable",
              }),
          },
      .validateOptions = [](const Options& options) -> std::optional<std::string> {
        if (!options.showGlyph && !options.showLabel) {
          return "show_glyph and show_label cannot both be false";
        }
        return std::nullopt;
      },
  };
  return definition;
}
