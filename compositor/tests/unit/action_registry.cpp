#include "check.h"
#include "config/keybind_parse.h"
#include "server/actions.h"

#include <cstddef>

using mahogany::actionHandlerFor;
using mahogany::actionRegistryComplete;
using mahogany::KeybindAction;

CANOPY_TEST(everyAdvertisedActionHasExactlyOneHandler) { CHECK(actionRegistryComplete()); }

CANOPY_TEST(everyActionEnumValueHasAHandler) {
  CHECK(actionHandlerFor(KeybindAction::None) == nullptr);
  for (size_t index = 1; index < static_cast<size_t>(KeybindAction::Count); ++index) {
    CHECK(actionHandlerFor(static_cast<KeybindAction>(index)) != nullptr);
  }
  CHECK(actionHandlerFor(KeybindAction::Count) == nullptr);
}

int main() { return RUN_TESTS(); }
