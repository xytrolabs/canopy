#include "input/keyboard_layout.h"

#include "check.h"

using mahogany::matchingLayoutGroup;

namespace {

  class Keymap {
  public:
    explicit Keymap(const char* layouts) : m_context(xkb_context_new(XKB_CONTEXT_NO_FLAGS)) {
      const xkb_rule_names names{
          .rules = nullptr,
          .model = nullptr,
          .layout = layouts,
          .variant = nullptr,
          .options = nullptr,
      };
      if (m_context != nullptr) {
        m_keymap = xkb_keymap_new_from_names(m_context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
      }
    }

    ~Keymap() {
      if (m_keymap != nullptr) {
        xkb_keymap_unref(m_keymap);
      }
      if (m_context != nullptr) {
        xkb_context_unref(m_context);
      }
    }

    Keymap(const Keymap&) = delete;
    Keymap& operator=(const Keymap&) = delete;

    xkb_keymap* get() const { return m_keymap; }

  private:
    xkb_context* m_context = nullptr;
    xkb_keymap* m_keymap = nullptr;
  };

} // namespace

CANOPY_TEST(matchesLayoutByNameAcrossDifferentOrders) {
  Keymap source("us,de");
  Keymap target("de,us");
  CHECK(source.get() != nullptr);
  CHECK(target.get() != nullptr);

  const auto group = matchingLayoutGroup(target.get(), source.get(), 1);
  CHECK(group.has_value());
  if (group.has_value()) {
    CHECK_EQ(*group, xkb_layout_index_t{0});
  }
}

CANOPY_TEST(leavesADeviceWithoutTheNamedLayoutUnchanged) {
  Keymap source("us,de");
  Keymap target("us,fr");
  CHECK(source.get() != nullptr);
  CHECK(target.get() != nullptr);
  CHECK(!matchingLayoutGroup(target.get(), source.get(), 1).has_value());
}

CANOPY_TEST(rejectsAnInvalidSourceGroup) {
  Keymap source("us,de");
  Keymap target("us,de");
  CHECK(source.get() != nullptr);
  CHECK(target.get() != nullptr);
  CHECK(!matchingLayoutGroup(target.get(), source.get(), 2).has_value());
}

namespace {
  const mahogany::XkbNames kSystem{
      .layout = "us", .variant = "intl", .options = "terminate:ctrl_alt_bksp", .model = "pc105"
  };
} // namespace

CANOPY_TEST(systemKeymapAppliesWhenConfigSetsNoXkbNames) {
  const mahogany::Config::Input input;
  CHECK(mahogany::usesSystemXkbNames(input));
  CHECK(mahogany::resolveXkbNames(input.keyboard, nullptr, kSystem) == kSystem);
}

CANOPY_TEST(anyConfiguredXkbNameReplacesTheWholeSystemKeymap) {
  mahogany::Config::Input input;
  input.keyboard.options = "caps:escape";
  CHECK(!mahogany::usesSystemXkbNames(input));
  const mahogany::XkbNames expected{.layout = "", .variant = "", .options = "caps:escape", .model = ""};
  CHECK(mahogany::resolveXkbNames(input.keyboard, nullptr, kSystem) == expected);
}

CANOPY_TEST(deviceXkbNamesReplaceTheSystemKeymap) {
  const mahogany::Config::Input input;
  mahogany::Config::Input::Device device;
  device.name = "kbd";
  device.layout = "de";
  const mahogany::XkbNames expected{.layout = "de", .variant = "", .options = "", .model = ""};
  CHECK(mahogany::resolveXkbNames(input.keyboard, &device, kSystem) == expected);
}

CANOPY_TEST(deviceClearingEveryXkbNameFallsBackToTheSystemKeymap) {
  mahogany::Config::Input input;
  input.keyboard.layout = "fr";
  mahogany::Config::Input::Device device;
  device.name = "kbd";
  device.layout = "";
  input.devices.push_back(device);
  CHECK(mahogany::usesSystemXkbNames(input));
  CHECK(mahogany::resolveXkbNames(input.keyboard, input.devices.data(), kSystem) == kSystem);
}

int main() { return RUN_TESTS(); }
