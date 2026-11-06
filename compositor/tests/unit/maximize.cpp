#include "view/maximize.h"

#include "check.h"

using mahogany::maximizeRequestTargetsEdges;

CANOPY_TEST(freshClientMaximizeTargetsColumn) { CHECK(!maximizeRequestTargetsEdges(true, false, false)); }

CANOPY_TEST(clientCanLeaveEdgesMaximize) { CHECK(maximizeRequestTargetsEdges(false, true, false)); }

CANOPY_TEST(configuredPolicySendsFreshRequestToEdges) { CHECK(maximizeRequestTargetsEdges(true, false, true)); }

CANOPY_TEST(configuredPolicyUnmaximizeTargetsColumn) { CHECK(!maximizeRequestTargetsEdges(false, false, true)); }

int main() { return RUN_TESTS(); }
