#include "config/value_parse.h"

#include "check.h"

#include <array>

CANOPY_TEST(parsesSixDigitColorAsOpaque) {
  std::array<float, 4> color{};
  CHECK(canopy::parseColor("#ff8000", color));
  CHECK_NEAR(color[0], 1.0F, 0.001F);
  CHECK_NEAR(color[1], 0.50196F, 0.001F);
  CHECK_NEAR(color[2], 0.0F, 0.001F);
  CHECK_NEAR(color[3], 1.0F, 0.001F);
}

CANOPY_TEST(parsesEightDigitColorWithAlpha) {
  std::array<float, 4> color{};
  CHECK(canopy::parseColor("#00000080", color));
  CHECK_NEAR(color[0], 0.0F, 0.001F);
  CHECK_NEAR(color[3], 0.50196F, 0.001F);
}

CANOPY_TEST(colorHexIsCaseInsensitive) {
  std::array<float, 4> lower{};
  std::array<float, 4> upper{};
  CHECK(canopy::parseColor("#abcdef", lower));
  CHECK(canopy::parseColor("#ABCDEF", upper));
  CHECK(lower == upper);
}

CANOPY_TEST(rejectsMalformedColors) {
  std::array<float, 4> color{0.25F, 0.25F, 0.25F, 0.25F};
  const std::array<float, 4> before = color;

  CHECK(!canopy::parseColor("", color));
  CHECK(!canopy::parseColor("#", color));
  CHECK(!canopy::parseColor("ff8000", color));     // no leading '#'
  CHECK(!canopy::parseColor("#fff", color));       // 3-digit shorthand is not supported
  CHECK(!canopy::parseColor("#ffff", color));      // 4-digit shorthand is not supported
  CHECK(!canopy::parseColor("#ff80", color));      // wrong length
  CHECK(!canopy::parseColor("#ff800", color));     // wrong length
  CHECK(!canopy::parseColor("#gg8000", color));    // non-hex digits
  CHECK(!canopy::parseColor("#ff80000", color));   // wrong length
  CHECK(!canopy::parseColor("#ff8000000", color)); // wrong length

  // A rejected parse must not disturb the caller's value.
  CHECK(color == before);
}

CANOPY_TEST(parsesOutputModeWithoutRefresh) {
  canopy::OutputMode mode{};
  CHECK(canopy::parseOutputMode("1920x1080", mode));
  CHECK_EQ(mode.width, 1920);
  CHECK_EQ(mode.height, 1080);
  CHECK_EQ(mode.refreshMHz, 0);
}

CANOPY_TEST(parsesOutputModeWithRefresh) {
  canopy::OutputMode mode{};
  CHECK(canopy::parseOutputMode("2560x1440@165", mode));
  CHECK_EQ(mode.width, 2560);
  CHECK_EQ(mode.height, 1440);
  CHECK_EQ(mode.refreshMHz, 165000);
}

CANOPY_TEST(parsesFractionalRefresh) {
  canopy::OutputMode mode{};
  CHECK(canopy::parseOutputMode("1920x1080@59.951", mode));
  CHECK_EQ(mode.refreshMHz, 59951);
}

CANOPY_TEST(clampsOutOfRangeOutputMode) {
  canopy::OutputMode mode{};
  CHECK(canopy::parseOutputMode("0x0", mode));
  CHECK_EQ(mode.width, 1);
  CHECK_EQ(mode.height, 1);

  CHECK(canopy::parseOutputMode("99999x99999@5000", mode));
  CHECK_EQ(mode.width, 16384);
  CHECK_EQ(mode.height, 16384);
  CHECK_EQ(mode.refreshMHz, 1000000);
}

CANOPY_TEST(rejectsMalformedOutputModes) {
  canopy::OutputMode mode{};
  CHECK(!canopy::parseOutputMode("", mode));
  CHECK(!canopy::parseOutputMode("1920", mode));       // no separator
  CHECK(!canopy::parseOutputMode("x1080", mode));      // empty width
  CHECK(!canopy::parseOutputMode("1920x", mode));      // empty height
  CHECK(!canopy::parseOutputMode("1920x1080@", mode)); // empty refresh
  CHECK(!canopy::parseOutputMode("axb", mode));        // non-numeric
  CHECK(!canopy::parseOutputMode("1920x1080@abc", mode));
  CHECK(!canopy::parseOutputMode("1920x1080p", mode)); // trailing garbage
  CHECK(!canopy::parseOutputMode("1920 x 1080", mode));
}

CANOPY_TEST(validatesEnvironmentVariableNames) {
  CHECK(canopy::isEnvironmentVariableName("DXVK_HDR"));
  CHECK(canopy::isEnvironmentVariableName("_PRIVATE"));
  CHECK(canopy::isEnvironmentVariableName("A1"));

  CHECK(!canopy::isEnvironmentVariableName(""));
  CHECK(!canopy::isEnvironmentVariableName("1STARTS_WITH_DIGIT"));
  CHECK(!canopy::isEnvironmentVariableName("HAS-HYPHEN"));
  CHECK(!canopy::isEnvironmentVariableName("HAS.DOT"));
  CHECK(!canopy::isEnvironmentVariableName("NÄME"));
}

int main() { return RUN_TESTS(); }
