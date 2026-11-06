#include "check.h"
#include "output/enable_overrides.h"

using mahogany::OutputEnableOverrides;
using mahogany::OutputIdentity;

namespace {

  OutputIdentity identified(std::string_view connector, std::string_view serial) {
    return {
        .connector = connector,
        .make = "Example",
        .model = "Panel",
        .serial = serial,
    };
  }

  OutputIdentity unidentified(std::string_view connector) {
    return {
        .connector = connector,
        .make = {},
        .model = {},
        .serial = {},
    };
  }

} // namespace

CANOPY_TEST(connectorOnlyOutputSurvivesRecreation) {
  OutputEnableOverrides overrides;
  const OutputIdentity output = unidentified("HEADLESS-1");
  overrides.remember(output, false);
  CHECK_EQ(overrides.resolve(output), std::optional(false));
}

CANOPY_TEST(uniqueMonitorFollowsItsDescriptorToAnotherConnector) {
  OutputEnableOverrides overrides;
  overrides.remember(identified("DP-1", "A"), false);

  CHECK_EQ(overrides.resolve(identified("DP-2", "A")), std::optional(false));
  CHECK_EQ(overrides.resolve(identified("DP-2", "A")), std::optional(false));
}

CANOPY_TEST(differentMonitorDoesNotInheritOldConnectorState) {
  OutputEnableOverrides overrides;
  overrides.remember(identified("DP-1", "A"), false);

  CHECK(!overrides.resolve(identified("DP-1", "B")).has_value());
  CHECK_EQ(overrides.resolve(identified("DP-2", "A")), std::optional(false));
}

CANOPY_TEST(identicalDescriptorsRemainConnectorBound) {
  OutputEnableOverrides overrides;
  overrides.remember(identified("DP-1", "same"), false);
  overrides.remember(identified("DP-2", "same"), true);

  CHECK_EQ(overrides.resolve(identified("DP-1", "same")), std::optional(false));
  CHECK_EQ(overrides.resolve(identified("DP-2", "same")), std::optional(true));
  CHECK(!overrides.resolve(identified("DP-3", "same")).has_value());
}

CANOPY_TEST(identifiedAndUnidentifiedOutputsDoNotShareConnectorState) {
  OutputEnableOverrides overrides;
  const OutputIdentity output = unidentified("DP-1");
  overrides.remember(output, false);
  CHECK(!overrides.resolve(identified("DP-1", "A")).has_value());

  overrides.clear();
  overrides.remember(identified("DP-1", "A"), false);
  CHECK(!overrides.resolve(output).has_value());
}

CANOPY_TEST(matchingAndUpdatesAreCaseInsensitive) {
  OutputEnableOverrides overrides;
  overrides.remember(identified("DP-1", "SERIAL"), false);
  overrides.remember(identified("dp-1", "serial"), true);

  CHECK_EQ(overrides.resolve(identified("Dp-1", "Serial")), std::optional(true));
}

CANOPY_TEST(clearDropsAllSessionOverrides) {
  OutputEnableOverrides overrides;
  const OutputIdentity output = unidentified("HEADLESS-1");
  overrides.remember(output, false);
  overrides.clear();
  CHECK(!overrides.resolve(output).has_value());
}

int main() { return RUN_TESTS(); }
