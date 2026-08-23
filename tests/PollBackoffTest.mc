using Toybox.Lang;
using Toybox.Test;

// R2-19: the foreground poll was a fixed 15s repeating timer with no outstanding-gate / deadline /
// backoff / jitter — queue + radio churn when the app is dead or the link flaps. The fix converts it to
// a self-rescheduling one-shot with an outstanding-gate, exponential backoff, and jitter. Only the pure
// backoff step lives in AppState (`pollBaseDelayMs`); the jitter, the outstanding-gate, and the reschedule
// loop live in FaBolusApp (sim/hardware-only, not in the test binary — see test.jungle). So we pin the
// pure step: base 15s doubling per miss level, capped at POLL_MAX_MS (120s). Style mirrors SentAtTest.
module PollBackoffTest {

    // The documented level → delay table (0=15s, 1=30s, 2=60s, 3=120s).
    (:test)
    function backoffLevelsMatch(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.pollBaseDelayMs(0), 15000, "level 0 = 15000");
        Test.assertEqualMessage(AppState.pollBaseDelayMs(1), 30000, "level 1 = 30000");
        Test.assertEqualMessage(AppState.pollBaseDelayMs(2), 60000, "level 2 = 60000");
        Test.assertEqualMessage(AppState.pollBaseDelayMs(3), 120000, "level 3 = 120000");
        return true;
    }

    // The delay is capped at POLL_MAX_MS beyond level 3 (never unbounded).
    (:test)
    function backoffCapsAtMax(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.pollBaseDelayMs(4), 120000, "level 4 capped at POLL_MAX_MS");
        Test.assertEqualMessage(AppState.pollBaseDelayMs(10), 120000, "level 10 still capped");
        Test.assertEqualMessage(AppState.POLL_MAX_MS, 120000, "POLL_MAX_MS is 120000");
        return true;
    }

    // Monotonic non-decreasing and never above the cap, for a sweep of levels.
    (:test)
    function backoffMonotonicAndBounded(logger as Test.Logger) as Lang.Boolean {
        var prev = 0;
        for (var lvl = 0; lvl <= 8; lvl += 1) {
            var d = AppState.pollBaseDelayMs(lvl);
            Test.assertMessage(d >= prev, "monotonic non-decreasing at level " + lvl.toString());
            Test.assertMessage(d <= AppState.POLL_MAX_MS, "never exceeds POLL_MAX_MS at level " + lvl.toString());
            prev = d;
        }
        return true;
    }
}
