#include "shell/bar/widgets/weather_widget_definition.h"

const shade::bar::WidgetDefinition<WeatherWidget::Options>& weatherWidgetDefinition() {
  using shade::bar::field;
  using Options = WeatherWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "weather",
      .fields = {
          field<&Options::maxWidth>({
              .key = "max_length",
              .minValue = 40.0,
              .maxValue = 800.0,
              .step = 1.0,
          }),
          field<&Options::showCondition>({
              .key = "show_condition",
          }),
          field<&Options::showTemperature>({
              .key = "show_temperature",
          }),
      },
  };
  return definition;
}
