#include "shell/bar/widgets/clipboard_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const shade::bar::WidgetDefinition<ClipboardWidget::Options>& clipboardWidgetDefinition() {
  using Options = ClipboardWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "clipboard",
      .fields = shade::bar::glyphButtonFields<Options>(),
      .glyph = [](const Options& options) { return options.glyph; },
  };
  return definition;
}
