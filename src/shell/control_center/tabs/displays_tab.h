#pragma once

#include "shell/control_center/tab.h"

#include <memory>
#include <string>
#include <vector>

class Button;
class CompositorPlatform;
class Flex;
class Label;
class Renderer;
class ScrollView;

// Arranges physical outputs: side-by-side placement, rotation and scale.
//
// The compositor owns display state, so this tab does not talk protocol to it.
// It writes the same [output.<connector>] tables a user would write by hand
// (position / transform / scale) into ~/.config/canopywc/config.toml, and the
// compositor's config watcher hot-reloads and applies them. That keeps one
// source of truth for layout and needs no new IPC surface.
class DisplaysTab final : public Tab {
public:
  explicit DisplaysTab(CompositorPlatform* platform);

  std::unique_ptr<Flex> create() override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;

  void rebuildCards();
  void refreshCardText();

  // direction: 0 = left of reference, 1 = right, 2 = above, 3 = below
  void arrangeOutput(const std::string& name, int direction);
  void rotateOutput(const std::string& name, int steps);
  void scaleOutput(const std::string& name, double delta);
  void resetOutput(const std::string& name);

  struct OutputCard {
    std::string name;
    Flex* card = nullptr;
    Label* infoLabel = nullptr;
    Label* detailLabel = nullptr;
  };

  CompositorPlatform* m_platform = nullptr;
  Flex* m_root = nullptr;
  Flex* m_emptyState = nullptr;
  ScrollView* m_cardsScroll = nullptr;
  Flex* m_cardsLayout = nullptr;
  std::vector<OutputCard> m_cards;
  std::string m_lastOutputKey;
};