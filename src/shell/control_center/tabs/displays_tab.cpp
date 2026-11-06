#include "shell/control_center/tabs/displays_tab.h"

#include "compositors/compositor_platform.h"
#include "config/atomic_file.h"
#include "core/toml.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_button_style.h"
#include "ui/builders.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <sstream>
#include <string>

using namespace control_center;

namespace {

  constexpr double kMinScale = 0.25;
  constexpr double kMaxScale = 4.0;
  constexpr double kScaleStep = 0.25;

  std::string compositorConfigPath() {
    if (const char* xdg = std::getenv("XDG_CONFIG_HOME"); xdg != nullptr && *xdg != '\0') {
      return std::string(xdg) + "/canopywc/config.toml";
    }
    if (const char* home = std::getenv("HOME"); home != nullptr && *home != '\0') {
      return std::string(home) + "/.config/canopywc/config.toml";
    }
    return "canopywc/config.toml";
  }

  // Loads the compositor config, hands the output's table to `mutate`, and writes
  // it back atomically. Returns false (leaving the file untouched) if the file
  // exists but cannot be parsed, so a broken config is never clobbered.
  bool patchOutput(const std::string& name, const std::function<void(toml::table&)>& mutate) {
    const std::string path = compositorConfigPath();

    toml::table root;
    std::error_code ec;
    if (std::filesystem::exists(path, ec)) {
      try {
        root = toml::parse_file(path);
      } catch (...) {
        return false;
      }
    }

    auto* outputs = root["output"].as_table();
    if (outputs == nullptr) {
      root.insert_or_assign("output", toml::table{});
      outputs = root["output"].as_table();
    }
    if (outputs == nullptr) {
      return false;
    }

    auto* entry = (*outputs)[name].as_table();
    if (entry == nullptr) {
      outputs->insert_or_assign(name, toml::table{});
      entry = (*outputs)[name].as_table();
    }
    if (entry == nullptr) {
      return false;
    }

    mutate(*entry);

    std::ostringstream out;
    out << toml::toml_formatter{root};
    return writeTextFileAtomic(path, out.str());
  }

  bool clearOutput(const std::string& name) {
    const std::string path = compositorConfigPath();
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) {
      return true;
    }

    toml::table root;
    try {
      root = toml::parse_file(path);
    } catch (...) {
      return false;
    }

    auto* outputs = root["output"].as_table();
    if (outputs == nullptr) {
      return true;
    }
    outputs->erase(name);

    std::ostringstream out;
    out << toml::toml_formatter{root};
    return writeTextFileAtomic(path, out.str());
  }

  std::string outputListKey(const std::vector<WaylandOutput>& outputs) {
    std::string key;
    for (const auto& output : outputs) {
      key += output.connectorName.empty() ? std::to_string(output.name) : output.connectorName;
      key += ';';
    }
    return key;
  }

  std::string displayName(const WaylandOutput& output) {
    if (!output.connectorName.empty()) {
      return output.connectorName;
    }
    return "#" + std::to_string(output.name);
  }

  int effectiveWidth(const WaylandOutput& output) {
    return std::max(1, output.effectiveLogicalWidth());
  }

  int effectiveHeight(const WaylandOutput& output) {
    return std::max(1, output.effectiveLogicalHeight());
  }

  std::string rotationLabel(const WaylandOutput& output) {
    switch (output.effectiveTransform() & 3) {
      case 1:
        return "90\xC2\xB0";
      case 2:
        return "180\xC2\xB0";
      case 3:
        return "270\xC2\xB0";
      default:
        return "0\xC2\xB0";
    }
  }

  const char* transformName(int steps) {
    switch (((steps % 4) + 4) % 4) {
      case 1:
        return "90";
      case 2:
        return "180";
      case 3:
        return "270";
      default:
        return "normal";
    }
  }

} // namespace

DisplaysTab::DisplaysTab(CompositorPlatform* platform): m_platform(platform) {}

std::unique_ptr<Flex> DisplaysTab::create() {
  const float scale = contentScale();

  auto tab = ui::column({
      .out = &m_root,
      .align = FlexAlign::Stretch,
      .gap = Style::spaceMd * scale,
  });

  auto cardsScroll = ui::scrollView({
      .out = &m_cardsScroll,
      .contentScale = scale,
      .scrollbarVisible = true,
      .viewportPaddingH = 0.0F,
      .viewportPaddingV = 0.0F,
      .flexGrow = 1.0F,
      .configure = [](ScrollView& scrollView) {
        scrollView.clearFill();
        scrollView.clearBorder();
      },
  });
  m_cardsLayout = cardsScroll->content();
  m_cardsLayout->setDirection(FlexDirection::Vertical);
  m_cardsLayout->setAlign(FlexAlign::Stretch);
  m_cardsLayout->setGap(Style::spaceMd * scale);
  tab->addChild(std::move(cardsScroll));

  auto emptyState = ui::column(
      {.out = &m_emptyState,
       .align = FlexAlign::Center,
       .justify = FlexJustify::Center,
       .flexGrow = 1.0F,
       .visible = false},
      ui::label({
          .text = "No displays detected",
          .fontSize = Style::fontSizeBody * scale,
          .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
      })
  );
  tab->addChild(std::move(emptyState));

  return tab;
}

void DisplaysTab::onClose() {
  m_root = nullptr;
  m_emptyState = nullptr;
  m_cardsScroll = nullptr;
  m_cardsLayout = nullptr;
  m_cards.clear();
  m_lastOutputKey.clear();
}

void DisplaysTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_root == nullptr) {
    return;
  }

  rebuildCards();

  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);

  const float scale = contentScale();
  const float cardWidth = std::max(1.0F, m_cardsScroll != nullptr ? m_cardsScroll->contentViewportWidth() : contentWidth);
  const float cardInnerWidth = std::max(1.0F, cardWidth - Style::spaceMd * scale * 2.0F);
  for (auto& card : m_cards) {
    if (card.card != nullptr) {
      card.card->setMinWidth(cardWidth);
    }
    if (card.infoLabel != nullptr) {
      card.infoLabel->setMaxLines(1);
      card.infoLabel->setMaxWidth(cardInnerWidth);
    }
    if (card.detailLabel != nullptr) {
      card.detailLabel->setMaxLines(1);
      card.detailLabel->setMaxWidth(cardInnerWidth);
    }
  }

  m_root->layout(renderer);
}

void DisplaysTab::doUpdate(Renderer& /*renderer*/) {
  rebuildCards();
  refreshCardText();
}

void DisplaysTab::rebuildCards() {
  if (m_platform == nullptr || m_cardsLayout == nullptr) {
    return;
  }

  const auto& outputs = m_platform->outputs();
  const std::string key = outputListKey(outputs);
  if (key == m_lastOutputKey) {
    return;
  }
  m_lastOutputKey = key;

  for (auto& card : m_cards) {
    if (card.card != nullptr) {
      m_cardsLayout->removeChild(card.card);
    }
  }
  m_cards.clear();

  const bool empty = outputs.empty();
  if (m_emptyState != nullptr) {
    m_emptyState->setVisible(empty);
  }
  if (m_cardsScroll != nullptr) {
    m_cardsScroll->setVisible(!empty);
  }
  if (empty) {
    return;
  }

  const float scale = contentScale();

  for (const auto& output : outputs) {
    const std::string name = displayName(output);

    auto card = ui::column({
        .configure = [scale, opacity = panelCardOpacity()](Flex& section) {
          applySectionCardStyle(section, scale, opacity);
          section.setGap(Style::spaceMd * scale);
        },
    });

    Glyph* iconPtr = nullptr;
    Label* nameLabelPtr = nullptr;
    auto headerRow = ui::row(
        {.align = FlexAlign::Center, .gap = Style::spaceSm * scale},
        ui::glyph({
            .out = &iconPtr,
            .glyph = "device-desktop",
            .glyphSize = Style::fontSizeTitle * scale,
            .color = colorSpecFromRole(ColorRole::OnSurface),
        }),
        ui::label({
            .out = &nameLabelPtr,
            .text = name,
            .fontSize = Style::fontSizeBody * scale,
            .fontWeight = FontWeight::Bold,
            .color = colorSpecFromRole(ColorRole::OnSurface),
            .flexGrow = 1.0F,
        })
    );
    card->addChild(std::move(headerRow));

    Label* infoLabelPtr = nullptr;
    card->addChild(ui::label({
        .out = &infoLabelPtr,
        .text = "",
        .fontSize = Style::fontSizeCaption * scale,
        .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
    }));

    Label* detailLabelPtr = nullptr;
    card->addChild(ui::label({
        .out = &detailLabelPtr,
        .text = "",
        .fontSize = Style::fontSizeCaption * scale,
        .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
    }));

    // Placement relative to the other output, then rotation and scale.
    auto arrangeRow = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale});

    struct ActionSpec {
      const char* glyph;
      const char* tooltip;
      int direction;
    };
    const ActionSpec actions[] = {
        {"arrow-left", "Place left of the other display", 0},
        {"arrow-right", "Place right of the other display", 1},
        {"arrow-up", "Place above the other display", 2},
        {"arrow-down", "Place below the other display", 3},
        {"rotate-clockwise", "Rotate 90\xC2\xB0", -1},
        {"rotate-counterclockwise", "Rotate 90\xC2\xB0 the other way", -2},
        {"zoom-in", "Increase scale", -3},
        {"zoom-out", "Decrease scale", -4},
        {"restore", "Reset to automatic layout", -5},
    };

    for (const auto& action : actions) {
      if (m_cards.size() == 0 && action.direction >= 0) {
        // Placement needs a second display to be meaningful, but keep the
        // buttons visible: the reference falls back to the first output.
      }
      arrangeRow->addChild(ui::button({
          .glyph = action.glyph,
          .tooltip = action.tooltip,
          .onClick =
              [this, name, direction = action.direction] {
                if (direction < 0) {
                  switch (direction) {
                    case -1:
                      rotateOutput(name, 1);
                      break;
                    case -2:
                      rotateOutput(name, -1);
                      break;
                    case -3:
                      scaleOutput(name, kScaleStep);
                      break;
                    case -4:
                      scaleOutput(name, -kScaleStep);
                      break;
                    default:
                      resetOutput(name);
                      break;
                  }
                  return;
                }
                arrangeOutput(name, direction);
              },
          .configure = [scale](Button& button) { panel_button_style::configureHeaderIconButton(button, scale); },
      }));
    }
    card->addChild(std::move(arrangeRow));

    auto* cardPtr = card.get();
    m_cardsLayout->addChild(std::move(card));

    OutputCard entry;
    entry.name = name;
    entry.card = cardPtr;
    entry.infoLabel = infoLabelPtr;
    entry.detailLabel = detailLabelPtr;
    m_cards.push_back(std::move(entry));
  }

  refreshCardText();
}

void DisplaysTab::refreshCardText() {
  if (m_platform == nullptr) {
    return;
  }

  const auto& outputs = m_platform->outputs();
  for (auto& card : m_cards) {
    const auto it = std::ranges::find_if(outputs, [&](const WaylandOutput& output) {
      return displayName(output) == card.name;
    });
    if (it == outputs.end()) {
      continue;
    }

    if (card.infoLabel != nullptr) {
      const std::string info = std::to_string(it->width) + "x" + std::to_string(it->height) + "  \xC2\xB7  "
          + rotationLabel(*it) + "  \xC2\xB7  " + std::to_string(std::lround(it->configuredScale() * 100.0)) + "%";
      card.infoLabel->setText(info);
    }

    if (card.detailLabel != nullptr) {
      const std::string detail = "Position " + std::to_string(it->logicalX) + ", " + std::to_string(it->logicalY)
          + "  \xC2\xB7  logical " + std::to_string(effectiveWidth(*it)) + "x" + std::to_string(effectiveHeight(*it));
      card.detailLabel->setText(detail);
    }
  }
}

void DisplaysTab::arrangeOutput(const std::string& name, int direction) {
  if (m_platform == nullptr) {
    return;
  }

  const auto& outputs = m_platform->outputs();
  const auto self = std::ranges::find_if(outputs, [&](const WaylandOutput& output) { return displayName(output) == name; });
  if (self == outputs.end()) {
    return;
  }

  // Reference: the first other output, which is the one the user is arranging
  // around. With a single output there is nothing to arrange against.
  const auto reference = std::ranges::find_if(outputs, [&](const WaylandOutput& output) {
    return displayName(output) != name;
  });
  if (reference == outputs.end()) {
    return;
  }

  int x = reference->logicalX;
  int y = reference->logicalY;
  switch (direction) {
    case 0:
      x -= effectiveWidth(*self);
      break;
    case 1:
      x += effectiveWidth(*reference);
      break;
    case 2:
      y -= effectiveHeight(*self);
      break;
    default:
      y += effectiveHeight(*reference);
      break;
  }

  patchOutput(name, [x, y](toml::table& table) {
    toml::array position;
    position.push_back(static_cast<std::int64_t>(x));
    position.push_back(static_cast<std::int64_t>(y));
    table.insert_or_assign("position", std::move(position));
  });
}

void DisplaysTab::rotateOutput(const std::string& name, int steps) {
  if (m_platform == nullptr) {
    return;
  }

  const auto& outputs = m_platform->outputs();
  const auto self = std::ranges::find_if(outputs, [&](const WaylandOutput& output) { return displayName(output) == name; });
  if (self == outputs.end()) {
    return;
  }

  const int transform = ((self->effectiveTransform() + steps) % 4 + 4) % 4;
  const char* value = transformName(transform);
  patchOutput(name, [value](toml::table& table) { table.insert_or_assign("transform", std::string(value)); });
}

void DisplaysTab::scaleOutput(const std::string& name, double delta) {
  if (m_platform == nullptr) {
    return;
  }

  const auto& outputs = m_platform->outputs();
  const auto self = std::ranges::find_if(outputs, [&](const WaylandOutput& output) { return displayName(output) == name; });
  if (self == outputs.end()) {
    return;
  }

  const double current = self->configuredScale();
  const double next = std::clamp(std::round((current + delta) / kScaleStep) * kScaleStep, kMinScale, kMaxScale);
  patchOutput(name, [next](toml::table& table) { table.insert_or_assign("scale", next); });
}

void DisplaysTab::resetOutput(const std::string& name) {
  clearOutput(name);
}