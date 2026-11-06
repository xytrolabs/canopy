#include "shell/bar/widgets/wallpaper_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const shade::bar::WidgetDefinition<WallpaperWidget::Options>& wallpaperWidgetDefinition() {
  using Options = WallpaperWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "wallpaper",
      .fields = shade::bar::glyphButtonFields<Options>(),
      .glyph = [](const Options& options) { return options.glyph; },
  };
  return definition;
}
