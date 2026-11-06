#include "check.h"
#include "output/frame_schedule.h"

using mahogany::OutputFrameFollowup;
using mahogany::outputFrameFollowup;
using mahogany::TearingCommitRecovery;

CANOPY_TEST(nestedBackendCanScheduleFrames) {
  CHECK_EQ(outputFrameFollowup(false, nullptr, false, true), OutputFrameFollowup::Schedule);
}

CANOPY_TEST(activeNativeSessionCanScheduleFrames) {
  wlr_session session{};
  session.active = true;
  CHECK_EQ(outputFrameFollowup(false, &session, false, true), OutputFrameFollowup::Schedule);
}

CANOPY_TEST(inactiveNativeSessionCannotScheduleFrames) {
  wlr_session session{};
  session.active = false;
  CHECK_EQ(outputFrameFollowup(false, &session, false, true), OutputFrameFollowup::None);
}

CANOPY_TEST(stoppingCompositorCannotScheduleFrames) {
  wlr_session session{};
  session.active = true;
  CHECK_EQ(outputFrameFollowup(true, &session, false, true), OutputFrameFollowup::None);
}

CANOPY_TEST(failedCommitUsesDelayedRetry) {
  wlr_session session{};
  session.active = true;
  CHECK_EQ(outputFrameFollowup(false, &session, true, false), OutputFrameFollowup::RetryDelayed);
}

CANOPY_TEST(failedAnimatedFrameDoesNotScheduleImmediately) {
  wlr_session session{};
  session.active = true;
  CHECK_EQ(outputFrameFollowup(false, &session, true, true), OutputFrameFollowup::RetryDelayed);
}

CANOPY_TEST(idleSuccessfulFrameNeedsNoFollowup) {
  wlr_session session{};
  session.active = true;
  CHECK_EQ(outputFrameFollowup(false, &session, false, false), OutputFrameFollowup::None);
}

CANOPY_TEST(failedTearingCommitForcesARegularRecoveryCommit) {
  TearingCommitRecovery recovery;

  CHECK(recovery.requestTearing(true));
  recovery.recordCommit(true, false);

  CHECK(recovery.regularCommitPending());
  CHECK(!recovery.requestTearing(true));
}

CANOPY_TEST(failedRegularRecoveryStaysRegularUntilItSucceeds) {
  TearingCommitRecovery recovery;
  recovery.recordCommit(true, false);
  recovery.recordCommit(false, false);

  CHECK(recovery.regularCommitPending());
  CHECK(!recovery.requestTearing(true));

  recovery.recordCommit(false, true);
  CHECK(!recovery.regularCommitPending());
  CHECK(recovery.requestTearing(true));
}

CANOPY_TEST(rejectedTearingTestKeepsFailedRegularFallbackOnTheRegularPath) {
  TearingCommitRecovery recovery;
  recovery.forceRegularCommit();
  recovery.recordCommit(false, false);

  CHECK(recovery.regularCommitPending());
  CHECK(!recovery.requestTearing(true));

  recovery.recordCommit(false, true);
  CHECK(recovery.requestTearing(true));
}

CANOPY_TEST(ineligibleFramesNeverRequestTearing) {
  TearingCommitRecovery recovery;
  CHECK(!recovery.requestTearing(false));
  recovery.recordCommit(false, true);
  CHECK(!recovery.regularCommitPending());
}

CANOPY_TEST(effectFrameDelayFollowsRefreshOrCapsAtMaxFps) {
  CHECK_EQ(mahogany::effectFrameDelayMs(0, 1000, 990), uint64_t{0});
  CHECK_EQ(mahogany::effectFrameDelayMs(60, 1000, 1000), uint64_t{17});
  CHECK_EQ(mahogany::effectFrameDelayMs(60, 1010, 1000), uint64_t{7});
  CHECK_EQ(mahogany::effectFrameDelayMs(60, 1100, 1000), uint64_t{1});
  CHECK_EQ(mahogany::effectFrameDelayMs(1, 1000, 1000), uint64_t{1000});
}

CANOPY_TEST(effectFrameDelayWaitsAFullIntervalWhenTheLastFrameIsAhead) {
  CHECK_EQ(mahogany::effectFrameDelayMs(60, 990, 1000), uint64_t{17});
}

CANOPY_TEST(effectFrameDelayNeverDropsBelowOneMillisecond) {
  CHECK_EQ(mahogany::effectFrameDelayMs(2000, 1000, 1000), uint64_t{1});
}

int main() { return RUN_TESTS(); }
