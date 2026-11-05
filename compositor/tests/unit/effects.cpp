#include "config/effects.h"

#include "check.h"
#include "config/config.h"
#include "scene/effect_ledger.h"
#include "scene/effect_registry.h"
#include "view/effects.h"

#include <cstdint>

using canopy::EffectKind;
using canopy::EffectPreset;
using canopy::Effects;

namespace {
  Effects twoPresets() {
    Effects effects;
    effects.presets.push_back(EffectPreset{.name = "pulse", .kind = EffectKind::Border, .shader = {.code = "x"}});
    effects.presets.push_back(EffectPreset{.name = "lines", .kind = EffectKind::Window, .shader = {.code = "y"}});
    return effects;
  }
} // namespace

CANOPY_TEST(effectKindsParseTheirCanonicalNamesOnly) {
  CHECK(canopy::parseEffectKind("animation") == EffectKind::Animation);
  CHECK(canopy::parseEffectKind("border") == EffectKind::Border);
  CHECK(canopy::parseEffectKind("window") == EffectKind::Window);
  CHECK(canopy::parseEffectKind("screen") == EffectKind::Screen);
  CHECK(canopy::parseEffectKind("cursor") == EffectKind::Cursor);
  CHECK(!canopy::parseEffectKind("Border"));
  CHECK(!canopy::parseEffectKind("overlay"));
  CHECK(!canopy::parseEffectKind(""));
  CHECK_EQ(canopy::effectKindName(EffectKind::Cursor), std::string_view("cursor"));
}

CANOPY_TEST(effectReferencesRequireAnExistingPresetOfTheRightKind) {
  const Effects effects = twoPresets();
  CHECK(canopy::findEffectPreset(effects, "pulse") != nullptr);
  CHECK(canopy::findEffectPreset(effects, "PULSE") == nullptr);
  CHECK(!canopy::effectReferenceError(effects, "", EffectKind::Border, false));
  CHECK(!canopy::effectReferenceError(effects, "pulse", EffectKind::Border, false));
  CHECK(canopy::effectReferenceError(effects, "pulse", EffectKind::Window, false));
  CHECK(canopy::effectReferenceError(effects, "pulse", EffectKind::Animation, false));
  Effects fades;
  fades.presets.push_back(EffectPreset{.name = "fade", .kind = EffectKind::Animation, .shader = {.code = "z"}});
  CHECK(!canopy::effectReferenceError(fades, "fade", EffectKind::Animation, false));
  CHECK(canopy::effectReferenceError(fades, "fade", EffectKind::Border, false));
  CHECK(canopy::effectReferenceError(effects, "missing", EffectKind::Window, false));
}

CANOPY_TEST(offIsOnlyValidWhereAnOverrideCanDisableTheDefault) {
  const Effects effects = twoPresets();
  CHECK(!canopy::effectReferenceError(effects, "off", EffectKind::Border, true));
  CHECK(canopy::effectReferenceError(effects, "off", EffectKind::Border, false));
}

CANOPY_TEST(clockSecondsKeepsMillisecondResolutionPastAFloatsExactRange) {
  // A raw millisecond count this large already exceeds a float's exact integer range (2^24, ~4.7
  // hours): a plain `static_cast<float>(msec) / 1000.0F` on it collapses a 1 ms step to nothing.
  // Measuring from an epoch keeps the value handed to clockSeconds() small, so the same step survives.
  constexpr uint64_t epoch = 7ULL * 24 * 3600 * 1000;
  const float naiveAt = static_cast<float>(epoch + 1) / 1000.0F;
  const float naiveBefore = static_cast<float>(epoch) / 1000.0F;
  CHECK_EQ(naiveAt, naiveBefore);

  const float at = canopy::effectClockSeconds(epoch + 1, epoch);
  const float before = canopy::effectClockSeconds(epoch, epoch);
  CHECK(at != before);
}

CANOPY_TEST(inertPresetsKeepTheirNameWithoutSource) {
  EffectPreset preset{.name = "broken", .kind = EffectKind::Screen};
  CHECK(preset.inert());
  preset.shader.code = "vec4 screen(vec2 uv) { return canopy_sample(uv); }";
  CHECK(!preset.inert());
}

CANOPY_TEST(ledgerCountsOnlyVisibleAdvancingTimeReaders) {
  canopy::EffectLedger ledger;
  int outputA = 0;
  int outputB = 0;
  int viewOne = 0;
  int viewTwo = 0;
  ledger.update(&viewOne, {.output = &outputA, .visible = true, .readsTime = true, .advancing = true});
  ledger.update(&viewTwo, {.output = &outputA, .visible = true, .readsTime = false, .advancing = true});
  CHECK_EQ(ledger.eligible(&outputA), 1U);
  CHECK_EQ(ledger.eligible(&outputB), 0U);
  CHECK_EQ(ledger.active(), 2U);

  // A frozen clock, animated = false, or speed = 0 all arrive as advancing = false.
  ledger.update(&viewOne, {.output = &outputA, .visible = true, .readsTime = true, .advancing = false});
  CHECK_EQ(ledger.eligible(&outputA), 0U);
  ledger.update(&viewOne, {.output = &outputA, .visible = true, .readsTime = true, .advancing = true});
  CHECK_EQ(ledger.eligible(&outputA), 1U);

  // Hidden or off-output instances never request frames.
  ledger.update(&viewOne, {.output = &outputA, .visible = false, .readsTime = true, .advancing = true});
  CHECK_EQ(ledger.eligible(&outputA), 0U);
  ledger.update(&viewOne, {.output = &outputB, .visible = true, .readsTime = true, .advancing = true});
  CHECK_EQ(ledger.eligible(&outputA), 0U);
  CHECK_EQ(ledger.eligible(&outputB), 1U);

  ledger.remove(&viewOne);
  CHECK_EQ(ledger.eligible(&outputB), 0U);
  CHECK_EQ(ledger.active(), 1U);
}

CANOPY_TEST(ledgerSuspensionAndOutputRemovalClearEligibility) {
  canopy::EffectLedger ledger;
  int output = 0;
  int screen = 0;
  int cursor = 0;
  ledger.update(&screen, {.output = &output, .visible = true, .readsTime = true, .advancing = true});
  ledger.update(&cursor, {.output = &output, .visible = true, .readsTime = true, .advancing = true});
  CHECK_EQ(ledger.eligible(&output), 2U);
  ledger.setSuspended(true);
  CHECK(ledger.suspended());
  CHECK_EQ(ledger.eligible(&output), 0U);
  CHECK_EQ(ledger.active(), 2U);
  ledger.setSuspended(false);
  CHECK_EQ(ledger.eligible(&output), 2U);
  ledger.removeOutput(&output);
  CHECK_EQ(ledger.eligible(&output), 0U);
  CHECK_EQ(ledger.active(), 0U);
}

CANOPY_TEST(ledgerUpdatesReplaceAnOwnersPreviousState) {
  canopy::EffectLedger ledger;
  int output = 0;
  int owner = 0;
  for (int i = 0; i < 3; ++i) {
    ledger.update(&owner, {.output = &output, .visible = true, .readsTime = true, .advancing = true});
  }
  CHECK_EQ(ledger.eligible(&output), 1U);
  CHECK_EQ(ledger.active(), 1U);
}

CANOPY_TEST(borderEffectsNeedFocusDecorationAndCalmNotFullscreen) {
  CHECK(canopy::borderEffectApplies({.focused = true, .decorated = true, .urgent = false, .fullscreen = false}));
  CHECK(!canopy::borderEffectApplies({.focused = false, .decorated = true, .urgent = false, .fullscreen = false}));
  CHECK(!canopy::borderEffectApplies({.focused = true, .decorated = false, .urgent = false, .fullscreen = false}));
  CHECK(!canopy::borderEffectApplies({.focused = true, .decorated = true, .urgent = true, .fullscreen = false}));
  CHECK(!canopy::borderEffectApplies({.focused = true, .decorated = true, .urgent = false, .fullscreen = true}));
}

CANOPY_TEST(borderUnfocusedStillNeedsDecorationAndCalmNotFullscreen) {
  // The opt-in widening (border_unfocused) opens only the focused gate; the
  // decorated, urgent and fullscreen gates still hold without focus.
  CHECK(
      canopy::borderEffectApplies(
          {.focused = false, .allowUnfocused = true, .decorated = true, .urgent = false, .fullscreen = false}
      )
  );
  CHECK(!canopy::borderEffectApplies(
      {.focused = false, .allowUnfocused = true, .decorated = false, .urgent = false, .fullscreen = false}
  ));
  CHECK(!canopy::borderEffectApplies(
      {.focused = false, .allowUnfocused = true, .decorated = true, .urgent = true, .fullscreen = false}
  ));
  CHECK(!canopy::borderEffectApplies(
      {.focused = false, .allowUnfocused = true, .decorated = true, .urgent = false, .fullscreen = true}
  ));
}

CANOPY_TEST(borderPaddingNeedsACompiledBorderPreset) {
  const EffectPreset border{.name = "ring", .kind = EffectKind::Border, .padding = 20};
  CHECK_EQ(canopy::borderPresetPadding(&border, true), 20);
  CHECK_EQ(canopy::borderPresetPadding(&border, false), 0);
  CHECK_EQ(canopy::borderPresetPadding(nullptr, true), 0);
  const EffectPreset window{.name = "tint", .kind = EffectKind::Window, .padding = 20};
  CHECK_EQ(canopy::borderPresetPadding(&window, true), 0);
}

CANOPY_TEST(effectPoolPoliciesAndReferenceConstraintsAreExplicit) {
  using canopy::EffectReferenceConstraint;
  using canopy::EffectSelectionPolicy;
  Effects effects = twoPresets();
  effects.pools.push_back({.name = "borders", .kind = EffectKind::Border, .members = {"pulse"}});
  CHECK(canopy::parseEffectSelectionPolicy("unused_first") == EffectSelectionPolicy::UnusedFirst);
  CHECK(canopy::parseEffectSelectionPolicy("round_robin") == EffectSelectionPolicy::RoundRobin);
  CHECK(canopy::parseEffectSelectionPolicy("random") == EffectSelectionPolicy::Random);
  CHECK(!canopy::parseEffectSelectionPolicy("Random"));
  CHECK(!canopy::parseEffectSelectionPolicy(""));
  CHECK_EQ(canopy::effectSelectionPolicyName(EffectSelectionPolicy::UnusedFirst), std::string_view("unused_first"));
  CHECK_EQ(canopy::effectSelectionPolicyName(EffectSelectionPolicy::RoundRobin), std::string_view("round_robin"));
  CHECK_EQ(canopy::effectSelectionPolicyName(EffectSelectionPolicy::Random), std::string_view("random"));
  CHECK(canopy::findEffectPool(effects, "borders") != nullptr);
  CHECK(canopy::findEffectPool(effects, "pulse") == nullptr);
  CHECK(canopy::effectReferenceError(effects, "borders", EffectKind::Border, false));
  CHECK(!canopy::effectReferenceError(
      effects, "borders", EffectKind::Border, false, EffectReferenceConstraint::PresetOrPool
  ));
  CHECK(!canopy::effectReferenceError(
      effects, "borders", EffectKind::Border, false, EffectReferenceConstraint::PoolRequired
  ));
  CHECK(
      canopy::effectReferenceError(
          effects, "borders", EffectKind::Window, false, EffectReferenceConstraint::PresetOrPool
      )
  );
  CHECK(
      canopy::effectReferenceError(
          effects, "pulse", EffectKind::Border, false, EffectReferenceConstraint::PoolRequired
      )
  );
  CHECK(
      !canopy::effectReferenceError(effects, "", EffectKind::Border, false, EffectReferenceConstraint::PresetOrPool)
  );
  CHECK(
      !canopy::effectReferenceError(effects, "off", EffectKind::Border, true, EffectReferenceConstraint::PresetOrPool)
  );
  CHECK(
      canopy::effectReferenceError(effects, "off", EffectKind::Border, false, EffectReferenceConstraint::PresetOrPool)
  );
}

int main() { return RUN_TESTS(); }
