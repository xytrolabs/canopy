#include "shell/bar/widgets/text_widget_definition.h"

const shade::bar::WidgetDefinition<TextWidget::Options>& textWidgetDefinition() {
  using shade::bar::field;
  using Options = TextWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "text",
      .fields = {
          field<&Options::text>({
              .key = "text",
          }),
      },
  };
  return definition;
}
