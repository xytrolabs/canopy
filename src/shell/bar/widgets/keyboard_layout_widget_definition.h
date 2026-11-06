#pragma once

#include "shell/bar/widget_definition.h"
#include "shell/bar/widgets/keyboard_layout_widget.h"

[[nodiscard]] const shade::bar::WidgetDefinition<KeyboardLayoutWidget::Options>& keyboardLayoutWidgetDefinition();
