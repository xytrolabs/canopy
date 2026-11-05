#include "output/cursor_plane_pace.h"

#include "check.h"

#include <cstdint>

using canopy::cursorPlaneAdvance;
using canopy::CursorPlaneDamage;
using canopy::cursorPlaneDamageFor;
using canopy::CursorPlaneState;

namespace {
  const void* imageToken(std::uintptr_t value) { return reinterpret_cast<const void*>(value); }

  CursorPlaneState cursorAt(double x, double y, std::uintptr_t image = 1) {
    return CursorPlaneState{
        .valid = false,
        .enabled = true,
        .visible = true,
        .x = x,
        .y = y,
        .width = 24,
        .height = 24,
        .hotspot_x = 0,
        .hotspot_y = 0,
        .image = imageToken(image),
    };
  }

  CursorPlaneState hiddenCursor(double x = 0.0, double y = 0.0) {
    CursorPlaneState cursor = cursorAt(x, y);
    cursor.visible = false;
    cursor.image = nullptr;
    return cursor;
  }
} // namespace

CANOPY_TEST(firstSampleOnlySeedsTheState) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  CHECK(!cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous));
  CHECK(!previous.valid);
  CHECK(state.valid);
}

CANOPY_TEST(aStationaryCursorIsNeverDamaged) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  CHECK(!cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous));
  CHECK(!cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous));
}

CANOPY_TEST(movingDamagesLeaveAndEnterBoxes) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous);
  CHECK(cursorPlaneAdvance(&state, cursorAt(200.0, 150.0), &previous));
  const CursorPlaneDamage damage = cursorPlaneDamageFor(&previous, &state);
  CHECK(damage.has_leave);
  CHECK(damage.has_enter);
  CHECK(damage.leave_box.x == 10.0 && damage.leave_box.y == 10.0);
  CHECK(damage.enter_box.x == 200.0 && damage.enter_box.y == 150.0);
}

CANOPY_TEST(leavingDamagesTheExitedBox) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous);
  CHECK(cursorPlaneAdvance(&state, hiddenCursor(), &previous));
  const CursorPlaneDamage damage = cursorPlaneDamageFor(&previous, &state);
  CHECK(damage.has_leave);
  CHECK(!damage.has_enter);
  CHECK(damage.leave_box.x == 10.0 && damage.leave_box.y == 10.0);
}

CANOPY_TEST(anImageSwapAtTheSamePlaceIsATransition) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  cursorPlaneAdvance(&state, cursorAt(10.0, 10.0, 1), &previous);
  CHECK(cursorPlaneAdvance(&state, cursorAt(10.0, 10.0, 2), &previous));
  const CursorPlaneDamage damage = cursorPlaneDamageFor(&previous, &state);
  CHECK(damage.has_enter);
}

CANOPY_TEST(aHiddenCursorThatMovesReportsNoBoxes) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  cursorPlaneAdvance(&state, hiddenCursor(10.0, 10.0), &previous);
  CHECK(cursorPlaneAdvance(&state, hiddenCursor(400.0, 300.0), &previous));
  const CursorPlaneDamage damage = cursorPlaneDamageFor(&previous, &state);
  CHECK(!damage.has_leave);
  CHECK(!damage.has_enter);
}

CANOPY_TEST(advanceHandsBackTheReplacedSample) {
  CursorPlaneState state{};
  CursorPlaneState previous{};
  CHECK(!cursorPlaneAdvance(&state, cursorAt(10.0, 10.0), &previous));
  CHECK(!previous.valid);
  CHECK(cursorPlaneAdvance(&state, cursorAt(400.0, 300.0), &previous));
  CHECK(previous.valid);
  CHECK(previous.x == 10.0 && previous.y == 10.0);
}

int main() { return RUN_TESTS(); }
