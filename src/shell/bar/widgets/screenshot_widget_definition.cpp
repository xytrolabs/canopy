#include "shell/bar/widgets/screenshot_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const shade::bar::WidgetDefinition<ScreenshotWidget::Options>& screenshotWidgetDefinition() {
  using Options = ScreenshotWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "screenshot",
      .fields = shade::bar::glyphButtonFields<Options>(),
  };
  return definition;
}
