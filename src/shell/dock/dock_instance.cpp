#include "shell/dock/dock_instance.h"

#include "compositors/compositor_platform.h"
#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/core/render_styles.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/dock/dock_geometry.h"
#include "shell/dock/dock_items.h"
#include "shell/surface/shadow.h"
#include "shell/tooltip/tooltip_manager.h"
#include "ui/builders.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"
#include "wayland/surface.h"

#include <algorithm>
#include <cmath>
#include <wayland-client-protocol.h>

namespace shell::dock {

  namespace {

    [[nodiscard]] bool dockUsesSlideAutoHide(const DockConfig& cfg, const DockInstance& instance) noexcept {
      if (cfg.smartAutoHide) {
        return !instance.smartAutoHidePinnedVisible;
      }
      return cfg.autoHide;
    }

    [[nodiscard]] bool dockUsesAnyAutoHide(const DockConfig& cfg) noexcept { return cfg.autoHide || cfg.smartAutoHide; }

    [[nodiscard]] bool workspaceKeyMatchesAssignment(std::string_view assignmentKey, const Workspace& workspace) {
      if (assignmentKey.empty()) {
        return false;
      }
      if (!workspace.id.empty() && assignmentKey == workspace.id) {
        return true;
      }
      if (!workspace.name.empty() && assignmentKey == workspace.name) {
        return true;
      }
      if (workspace.index > 0 && assignmentKey == std::to_string(workspace.index)) {
        return true;
      }
      return false;
    }

    [[nodiscard]] bool activeWorkspaceHasWindows(const CompositorPlatform& platform, wl_output* output) {
      const auto workspaces = platform.workspaces(output);
      const Workspace* active = nullptr;
      for (const auto& workspace : workspaces) {
        if (workspace.active) {
          active = &workspace;
          break;
        }
      }
      if (active == nullptr) {
        return false;
      }

      const auto assignments = platform.workspaceWindowAssignments(output);
      for (const auto& assignment : assignments) {
        if (workspaceKeyMatchesAssignment(assignment.workspaceKey, *active)) {
          return true;
        }
      }
      if (!assignments.empty()) {
        return false;
      }
      return active->occupied;
    }

    [[nodiscard]] bool smartAutoHideWantsPinnedVisible(const CompositorPlatform& platform, wl_output* output) {
      if (platform.hasOverviewState() && platform.isOverviewOpen()) {
        return true;
      }
      return !activeWorkspaceHasWindows(platform, output);
    }

    void applyDockScrollOffset(DockInstance& instance, const DockConfig& cfg) {
      if (instance.row == nullptr) {
        return;
      }
      instance.scrollOffset = std::clamp(instance.scrollOffset, 0.0F, instance.maxScrollOffset);
      if (shell::dock::isVerticalEdge(cfg.position)) {
        instance.row->setPosition(instance.row->x(), -instance.scrollOffset);
      } else {
        instance.row->setPosition(-instance.scrollOffset, instance.row->y());
      }
    }

    // ── Section islands ──────────────────────────────────────────────────────
    // One span per contiguous run of items that share a section. Spans are in
    // main-axis coordinates of the item row, which is what the layout already
    // produced, so islands never fight the flex layout or magnification.
    struct IslandSpan {
      DockSection section;
      float start;
      float end;
    };

    [[nodiscard]] float dockCellSize(const DockConfig& cfg) {
      // Matches kCellPad in dock_items.cpp: icon plus padding on both sides.
      constexpr float kCellPad = 6.0F;
      return static_cast<float>(cfg.iconSize) + kCellPad * 2.0F;
    }

    [[nodiscard]] std::vector<IslandSpan> computeIslandSpans(const DockInstance& instance, const DockConfig& cfg) {
      std::vector<IslandSpan> spans;
      const float cell = dockCellSize(cfg);

      for (std::size_t i = 0; i < instance.items.size() && i < instance.snapshot.items.size(); ++i) {
        const auto* area = instance.items[i].area;
        if (area == nullptr) {
          continue;
        }
        const auto section = instance.snapshot.items[i].section;
        const float start = instance.items[i].restMainPos;
        const float end = start + cell;
        if (!spans.empty() && spans.back().section == section) {
          spans.back().start = std::min(spans.back().start, start);
          spans.back().end = std::max(spans.back().end, end);
        } else {
          spans.push_back(IslandSpan{.section = section, .start = start, .end = end});
        }
      }

      // The launcher belongs to the pinned island, which is where it is drawn.
      if (cfg.launcherPosition != DockLauncherPosition::None && instance.launcherArea != nullptr) {
        const float launcherStart = instance.launcherRestMainPos;
        const float launcherEnd = launcherStart + cell;
        if (!spans.empty() && spans.front().section == DockSection::Pinned
            && cfg.launcherPosition == DockLauncherPosition::Start)
        {
          spans.front().start = std::min(spans.front().start, launcherStart);
          spans.front().end = std::max(spans.front().end, launcherEnd);
        } else if (spans.empty()) {
          spans.push_back(IslandSpan{.section = DockSection::Pinned, .start = launcherStart, .end = launcherEnd});
        }
      }

      return spans;
    }

    void applyPanelPaletteTo(Box& box, const DockConfig& cfg) {
      box.setFill(colorSpecFromRole(ColorRole::Surface, cfg.backgroundOpacity));
      box.setBorder(cfg.border, cfg.borderWidth);
    }

    // Draws one rounded background per section, inset by half the configured gap
    // so the islands read as separate surfaces without moving a single icon.
    void applySectionIslands(
        DockInstance& instance, const DockConfig& cfg, const DockPanelGeometry& panelGeometry,
        const DockConcaveShape& concave, bool vertical
    ) {
      const bool islands = cfg.sections == "islands";
      auto& boxes = instance.sectionPanels;

      if (!islands) {
        for (auto* box : boxes) {
          box->setOpacity(0.0F);
        }
        if (instance.panel != nullptr) {
          instance.panel->setOpacity(1.0F);
        }
        return;
      }

      if (instance.panel != nullptr) {
        instance.panel->setOpacity(0.0F);
      }
      if (instance.slideRoot == nullptr) {
        return;
      }

      const auto spans = computeIslandSpans(instance, cfg);
      while (boxes.size() < spans.size()) {
        auto* box = static_cast<Box*>(instance.slideRoot->addChild(ui::box({})));
        box->setClipChildren(false);
        box->setZIndex(0);
        boxes.push_back(box);
      }

      const float gap = static_cast<float>(std::max<std::int32_t>(0, cfg.sectionGap));
      const float insetL = concave.logicalInset.left;
      const float insetT = concave.logicalInset.top;
      const float insetR = concave.logicalInset.right;
      const float insetB = concave.logicalInset.bottom;

      for (std::size_t i = 0; i < boxes.size(); ++i) {
        auto* box = boxes[i];
        if (i >= spans.size()) {
          box->setOpacity(0.0F);
          continue;
        }
        box->setOpacity(1.0F);
        applyPanelPaletteTo(*box, cfg);
        box->setRadius(static_cast<float>(cfg.radius));

        // Shrink each island by half the gap on its own edges: two neighbouring
        // islands end up exactly `sectionGap` pixels apart.
        float start = spans[i].start - gap * 0.5F;
        float end = spans[i].end + gap * 0.5F;
        if (end - start < 4.0F) {
          end = start + 4.0F;
        }

        if (vertical) {
          box->setPosition(panelGeometry.panelX - insetL, panelGeometry.panelY + start - insetT);
          box->setSize(
              panelGeometry.panelW + insetL + insetR, (end - start) + insetT + insetB
          );
        } else {
          box->setPosition(panelGeometry.panelX + start - insetL, panelGeometry.panelY - insetT);
          box->setSize(
              (end - start) + insetL + insetR, panelGeometry.panelH + insetT + insetB
          );
        }
      }
    }

  } // namespace

  void prepareFrame(
      DockInstance& instance, DockInstanceDependencies deps, const DockInstanceCallbacks& callbacks, bool needsUpdate,
      bool needsLayout
  ) {
    if (instance.surface == nullptr) {
      return;
    }

    const auto width = instance.surface->width();
    const auto height = instance.surface->height();
    if (width == 0 || height == 0) {
      return;
    }

    deps.renderContext.makeCurrent(instance.surface->renderTarget());

    bool needsModelRebuild = false;
    if (needsUpdate || instance.sceneRoot == nullptr) {
      UiPhaseScope updatePhase(UiPhase::Update);
      if (callbacks.syncModel) {
        needsModelRebuild = callbacks.syncModel(instance);
      }
    }

    const bool needsSceneBuild = instance.sceneRoot == nullptr
        || static_cast<std::uint32_t>(std::round(instance.sceneRoot->width())) != width
        || static_cast<std::uint32_t>(std::round(instance.sceneRoot->height())) != height;
    if (needsSceneBuild || needsLayout || needsModelRebuild) {
      UiPhaseScope layoutPhase(UiPhase::Layout);
      if (needsModelRebuild && instance.sceneRoot != nullptr && callbacks.rebuildItems) {
        callbacks.rebuildItems(instance);
      }
      buildScene(instance, deps, callbacks);
    } else if (needsUpdate && callbacks.updateVisuals) {
      callbacks.updateVisuals(instance);
    }
  }

  void syncDockSlideLayerTransform(DockInstance& instance, const DockConfig& cfg) {
    if (instance.slideRoot == nullptr) {
      return;
    }
    if (dockUsesSlideAutoHide(cfg, instance) || instance.hideOpacity < 0.999F) {
      const float t = 1.0F - instance.hideOpacity;
      instance.slideRoot->setPosition(instance.slideHiddenDx * t, instance.slideHiddenDy * t);
    } else {
      instance.slideRoot->setPosition(0.0F, 0.0F);
    }
  }

  // Match the bar: while slid away use the edge strip (or full surface when pinned/hovered).
  // Never hit-test the slide-translated panel — that goes off-surface when smart_auto_hide
  // flips to pinned before hideOpacity recovers (dock rebuild on a new window).
  void
  syncDockAutoHideInputRegion(DockInstance& instance, const DockConfig& cfg, const DockPanelGeometry& panelGeometry) {
    if (instance.surface == nullptr) {
      return;
    }
    const int surfW = static_cast<int>(instance.surface->width());
    const int surfH = static_cast<int>(instance.surface->height());
    if (surfW <= 0 || surfH <= 0) {
      return;
    }

    if (!dockUsesAnyAutoHide(cfg)) {
      instance.surface->setInputRegion(
          shell::dock::computeInputRegion(cfg, panelGeometry, surfW, surfH, false, instance.fractionalScale)
      );
      return;
    }

    const bool fullSurface = instance.pointerInside || (cfg.smartAutoHide && instance.smartAutoHidePinnedVisible);
    if (fullSurface) {
      instance.surface->setInputRegion({InputRect{0, 0, surfW, surfH}});
      return;
    }
    instance.surface->setInputRegion(
        shell::dock::computeInputRegion(cfg, DockPanelGeometry{}, surfW, surfH, true, instance.fractionalScale)
    );
  }

  void applyDockCompositorBlur(DockInstance& instance, const DockConfig& cfg) {
    if (instance.surface == nullptr) {
      return;
    }
    if (!cfg.compositorBlur) {
      instance.surface->clearBlurRegion();
      return;
    }
    // Compositor blur is independent of scene opacity — clear it while auto-hide
    // has faded the dock out so a transparent buffer does not leave a blur halo.
    constexpr float kBlurVisibleOpacity = 0.02F;
    if (dockUsesAnyAutoHide(cfg) && instance.hideOpacity < kBlurVisibleOpacity) {
      instance.surface->clearBlurRegion();
      return;
    }
    if (instance.panel == nullptr) {
      return;
    }
    const auto concave = dockConcaveShape(cfg);
    float absX = 0.0F;
    float absY = 0.0F;
    Node::absolutePosition(instance.panel, absX, absY);

    const float insetL = concave.logicalInset.left;
    const float insetT = concave.logicalInset.top;
    const float insetR = concave.logicalInset.right;
    const float insetB = concave.logicalInset.bottom;
    const int px = static_cast<int>(std::lround(absX + insetL));
    const int py = static_cast<int>(std::lround(absY + insetT));
    const int pw = static_cast<int>(std::lround(instance.panel->width() - insetL - insetR));
    const int ph = static_cast<int>(std::lround(instance.panel->height() - insetT - insetB));
    auto blurStrips = Surface::tessellateShape(px, py, pw, ph, concave.corners, concave.logicalInset, concave.radii);
    instance.surface->setBlurRegion(blurStrips);
  }

  void buildScene(DockInstance& instance, DockInstanceDependencies deps, const DockInstanceCallbacks& callbacks) {
    uiAssertNotRendering("shell::dock::buildScene");
    if (instance.surface == nullptr) {
      return;
    }

    Renderer& renderer = instance.surface->renderTarget().renderer();

    const auto& cfg = instance.config;
    const bool vert = shell::dock::isVerticalEdge(cfg.position);

    const auto w = static_cast<float>(instance.surface->width());
    const auto h = static_cast<float>(instance.surface->height());

    const auto& shadowConfig = deps.config.config().shell.shadow;
    const auto panelGeometry = shell::dock::computePanelGeometry(cfg, shadowConfig, w, h);
    const auto concave = shell::dock::dockConcaveShape(cfg);

    if (instance.sceneRoot == nullptr) {
      instance.sceneRoot = ui::node({});
      instance.sceneRoot->setAnimationManager(&instance.animations);
      instance.sceneRoot->setSize(w, h);
      instance.sceneRoot->setOpacity(1.0F);

      auto slide = ui::node({});
      slide->setParticipatesInLayout(false);
      instance.slideRoot = instance.sceneRoot->addChild(std::move(slide));

      // Shadow
      if (shell::surface_shadow::enabled(cfg.shadow, shadowConfig)) {
        instance.shadow = static_cast<Box*>(instance.slideRoot->addChild(ui::box()));
      }

      // Panel background (icons render as a sibling so magnification can extend past the capsule).
      instance.panel = static_cast<Box*>(instance.slideRoot->addChild(
          ui::box({
              .configure = [concave](Box& box) {
                box.setCornerShapes(concave.corners);
                box.setLogicalInset(concave.logicalInset);
                box.setRadii(concave.radii);
                box.setClipChildren(false);
              },
          })
      ));
      instance.panel->setZIndex(0);

      // Clip overflow along the dock while retaining the cross-axis surface room used by magnification.
      auto viewport = ui::inputArea({});
      viewport->setClipChildren(true);
      viewport->setOnAxisHandler([inst = &instance](const InputArea::PointerData& data) {
        if (inst->row == nullptr || inst->maxScrollOffset <= 0.0F) {
          return false;
        }
        const auto& dockConfig = inst->config;
        const bool vertical = shell::dock::isVerticalEdge(dockConfig.position);
        const bool mainAxis =
            data.axis == (vertical ? WL_POINTER_AXIS_VERTICAL_SCROLL : WL_POINTER_AXIS_HORIZONTAL_SCROLL);
        const bool verticalWheelOnHorizontalDock = !vertical && data.axis == WL_POINTER_AXIS_VERTICAL_SCROLL;
        if (!mainAxis && !verticalWheelOnHorizontalDock) {
          return false;
        }

        inst->scrollOffset += data.scrollDelta(Style::scrollWheelStep);
        applyDockScrollOffset(*inst, dockConfig);
        inst->inputDispatcher.syncPointerHover();

        float viewportX = 0.0F;
        float viewportY = 0.0F;
        Node::absolutePosition(inst->viewport, viewportX, viewportY);
        (void)shell::dock::syncHoverPointerFromScene(
            *inst, dockConfig, viewportX + data.localX, viewportY + data.localY
        );
        if (inst->surface != nullptr) {
          inst->surface->requestFrameTick();
          inst->surface->requestRedraw();
        }
        return true;
      });
      instance.viewport = static_cast<InputArea*>(instance.slideRoot->addChild(std::move(viewport)));
      instance.row = static_cast<Flex*>(instance.viewport->addChild(makeDockItemRow(cfg, vert)));
      // Explicit z-order: island backgrounds (0) < viewport (1) < items (2).
      // Without this the section boxes were added last and sat on top of the
      // icon row, swallowing clicks.
      instance.viewport->setZIndex(1);
      instance.row->setZIndex(2);

      // Wire up InputDispatcher.
      instance.inputDispatcher.setSceneRoot(instance.sceneRoot.get());
      instance.inputDispatcher.setCursorShapeCallback([&platform =
                                                           deps.platform](std::uint32_t serial, std::uint32_t shape) {
        platform.setCursorShape(serial, shape);
      });
      instance.inputDispatcher.setHoverChangeCallback([inst = &instance](InputArea* /*old*/, InputArea* next) {
        TooltipManager::instance().onHoverChange(next, inst->surface->layerSurface(), inst->output);
      });

      // Populate items and wire up palette reactivity.
      if (callbacks.rebuildItems) {
        callbacks.rebuildItems(instance);
      }

      if (dockUsesAnyAutoHide(cfg)) {
        instance.smartAutoHidePinnedVisible =
            cfg.smartAutoHide && smartAutoHideWantsPinnedVisible(deps.platform, instance.output);
        instance.slideRoot->setOpacity(1.0F);
        const bool startHidden = cfg.smartAutoHide ? !instance.smartAutoHidePinnedVisible : cfg.autoHide;
        instance.hideOpacity = startHidden ? 0.0F : 1.0F;
      } else {
        instance.slideRoot->setOpacity(0.0F);
        instance.hideOpacity = 1.0F;
        instance.animations.animate(
            0.0F, 1.0F, Style::animSlow, Easing::EaseOutCubic,
            [slide = instance.slideRoot](float v) { slide->setOpacity(v); }, {}, instance.slideRoot
        );
      }

      instance.surface->setSceneRoot(instance.sceneRoot.get());
    } else {
      // Update corner shapes/radii/inset on reconfigure.
      instance.panel->setCornerShapes(concave.corners);
      instance.panel->setLogicalInset(concave.logicalInset);
      instance.panel->setRadii(concave.radii);
    }

    // Update root size on reconfigure.
    instance.sceneRoot->setSize(w, h);
    if (instance.slideRoot != nullptr) {
      instance.slideRoot->setSize(w, h);
    }

    // Shadow follows the same shape as the background
    if (instance.shadow != nullptr) {
      const auto shadowOff = shadowDirectionOffset(shadowConfig.direction);
      const auto shadowOffsetX = static_cast<float>(shadowOff.x);
      const auto shadowOffsetY = static_cast<float>(shadowOff.y);
      const RoundedRectStyle shadowStyle = shell::surface_shadow::style(
          shadowConfig, cfg.backgroundOpacity,
          shell::surface_shadow::Shape{
              .corners = concave.corners, .logicalInset = concave.logicalInset, .radius = concave.radii
          }
      );
      instance.shadow->setStyle(shadowStyle);
      instance.shadow->setZIndex(-1);
      instance.shadow->setPosition(
          panelGeometry.panelX - concave.logicalInset.left + shadowOffsetX,
          panelGeometry.panelY - concave.logicalInset.top + shadowOffsetY
      );
      instance.shadow->setSize(
          panelGeometry.panelW + concave.logicalInset.left + concave.logicalInset.right,
          panelGeometry.panelH + concave.logicalInset.top + concave.logicalInset.bottom
      );
    }

    // Panel
    applyPanelPalette(instance, cfg);
    instance.panel->setPosition(
        panelGeometry.panelX - concave.logicalInset.left, panelGeometry.panelY - concave.logicalInset.top
    );
    instance.panel->setSize(
        panelGeometry.panelW + concave.logicalInset.left + concave.logicalInset.right,
        panelGeometry.panelH + concave.logicalInset.top + concave.logicalInset.bottom
    );

    // The viewport follows the visible pill on its main axis and spans the surface on its cross axis,
    // allowing magnified icons to grow away from the screen edge without escaping past the pill ends.
    const auto contentLength = static_cast<float>(
        shell::dock::dockContentSize(cfg, instance.items.size() + shell::dock::dockLauncherButtonCount(cfg))
    );
    if (vert) {
      instance.viewport->setPosition(0.0F, panelGeometry.panelY);
      instance.viewport->setSize(w, panelGeometry.panelH);
      instance.row->setPosition(panelGeometry.panelX, 0.0F);
      instance.row->setSize(panelGeometry.panelW, contentLength);
      instance.maxScrollOffset = std::max(0.0F, contentLength - panelGeometry.panelH);
    } else {
      instance.viewport->setPosition(panelGeometry.panelX, 0.0F);
      instance.viewport->setSize(panelGeometry.panelW, h);
      instance.row->setPosition(0.0F, panelGeometry.panelY);
      instance.row->setSize(contentLength, panelGeometry.panelH);
      instance.maxScrollOffset = std::max(0.0F, contentLength - panelGeometry.panelW);
    }
    applyDockScrollOffset(instance, cfg);
    instance.row->layout(renderer);
    shell::dock::syncDockItemRestPositions(instance, cfg);
    applySectionIslands(instance, cfg, panelGeometry, concave, vert);

    if (dockUsesAnyAutoHide(cfg)) {
      const auto hiddenDelta = shell::dock::computeHiddenSlideDelta(cfg, shadowConfig, w, h, panelGeometry);
      instance.slideHiddenDx = hiddenDelta.first;
      instance.slideHiddenDy = hiddenDelta.second;
    } else {
      instance.slideHiddenDx = 0.0F;
      instance.slideHiddenDy = 0.0F;
    }
    syncDockSlideLayerTransform(instance, cfg);
    syncDockAutoHideInputRegion(instance, cfg, panelGeometry);

    applyDockCompositorBlur(instance, cfg);

    // Palette reactivity.
    instance.paletteConn = paletteChanged().connect([inst = &instance] {
      applyPanelPalette(*inst, inst->config);
      if (inst->surface)
        inst->surface->requestRedraw();
    });

    if (callbacks.updateVisuals) {
      callbacks.updateVisuals(instance);
    }
  }

  void applyPanelPalette(DockInstance& instance, const DockConfig& cfg) {
    if (instance.panel == nullptr)
      return;
    const float opacity = cfg.backgroundOpacity;
    instance.panel->setFill(colorSpecFromRole(ColorRole::Surface, opacity));
    instance.panel->setBorder(cfg.border, cfg.borderWidth);
  }

  void resizeSurface(DockInstance& instance, const DockConfig& cfg, const ShellConfig::ShadowConfig& shadowConfig) {
    if (instance.surface == nullptr) {
      return;
    }

    const auto surfaceGeometry = shell::dock::computeSurfaceGeometry(
        cfg, shadowConfig, instance.items.size() + shell::dock::dockLauncherButtonCount(cfg), instance.fractionalScale,
        instance.outputLogicalWidth, instance.outputLogicalHeight
    );

    if (instance.surface->width() != surfaceGeometry.surfaceW
        || instance.surface->height() != surfaceGeometry.surfaceH) {
      instance.surface->requestSize(surfaceGeometry.surfaceW, surfaceGeometry.surfaceH);
    }
  }

  void revealAutoHideDock(DockInstance& inst) {
    const auto& cfg = inst.config;
    if (!dockUsesAnyAutoHide(cfg) || inst.surface == nullptr || inst.slideRoot == nullptr) {
      return;
    }

    if (inst.hideAnimId != 0) {
      inst.animations.cancel(inst.hideAnimId);
      inst.hideAnimId = 0;
    }

    constexpr float kSettledThreshold = 0.999F;
    const float current = inst.hideOpacity;
    if (current >= kSettledThreshold) {
      syncDockAutoHideInputRegion(inst, cfg, DockPanelGeometry{});
      inst.surface->requestRedraw();
      return;
    }

    inst.hideAnimId = inst.animations.animate(
        current, 1.0F, Style::animNormal, Easing::EaseOutCubic,
        [&inst](float v) {
          inst.hideOpacity = v;
          syncDockSlideLayerTransform(inst, inst.config);
          applyDockCompositorBlur(inst, inst.config);
        },
        [&inst] { inst.hideAnimId = 0; }
    );
    syncDockAutoHideInputRegion(inst, cfg, DockPanelGeometry{});
    inst.surface->requestRedraw();
  }

  void startHideFadeOut(DockInstance& inst) {
    // xdg tooltips are not parent-transformed with the slide; destroy immediately
    // so they cannot remain pinned after auto-hide starts (#4177).
    TooltipManager::instance().forceDestroy();
    if (inst.hideAnimId != 0) {
      inst.animations.cancel(inst.hideAnimId);
      inst.hideAnimId = 0;
    }
    const float current = inst.hideOpacity;
    inst.hideAnimId = inst.animations.animate(
        current, 0.0F, Style::animNormal, Easing::EaseInQuad,
        [&inst](float v) {
          inst.hideOpacity = v;
          syncDockSlideLayerTransform(inst, inst.config);
          applyDockCompositorBlur(inst, inst.config);
        },
        [&inst] { inst.hideAnimId = 0; }
    );
    syncDockAutoHideInputRegion(inst, inst.config, DockPanelGeometry{});
    if (inst.surface) {
      inst.surface->requestRedraw();
    }
  }

} // namespace shell::dock
