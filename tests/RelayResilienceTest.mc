using Toybox.Lang;
using Toybox.Test;

// FaBolusApp.mc is compiled into
// the test binary (see test.jungle), so these exercise the REAL shipping pollTick loop, not a
// stand-in.
//
// A throw from the dismiss-retry resend loop's own fallible call
// (RemoteComm.dismissAlert(), inside FaBolusApp.pollTick's dismiss-retry try/catch) must never be
// allowed to skip scheduleNextPoll() — since scheduleNextPoll() (owned by FaBolusApp) is the loop's
// only re-arm path. Test 1 proves the guard lives at pollTick: scheduleNextPoll() runs even when
// RemoteComm.dismissAlert() is forced to throw via the test-only RemoteComm.testDismissAlertThrows
// seam. (Retargeted from the now-removed ambient-HR relay's injectable double — that relay was
// removed as a dead, unused signal; this test's invariant survives via the retarget onto the
// dismiss-retry guard, the pollTick duty that remains.)
//
// Test 2 proves the fix doesn't double-schedule on the ordinary success path.
module RelayResilienceTest {

    // Test 1: scheduleNextPoll() STILL runs when the dismiss-retry
    // loop's RemoteComm.dismissAlert() call throws inside pollTick() — the one-shot foreground poll
    // loop is not permanently halted.
    (:test)
    function pollTickSchedulesDespiteDismissRetryThrow(logger as Test.Logger) as Lang.Boolean {
        AppState.dismissPending = {};
        AppState.dismissProvisional = {};
        var app = new FaBolusApp();
        // Seed exactly one unexpired due dismiss retry (mirrors DismissAckTest.mc's beginDismiss idiom).
        AppState.beginDismiss(5, 1, "Auto-off");
        RemoteComm.testDismissAlertThrows = true;
        Test.assertEqualMessage(app.scheduleCount(), 0, "no poll scheduled yet");
        Test.assertEqualMessage(app.pollGuardFailureCount(), 0, "no guard failure recorded yet");
        app.pollTick();   // would throw uncaught (failing this test) if the guard were missing
        Test.assertEqualMessage(app.scheduleCount(), 1,
            "scheduleNextPoll() ran exactly once despite the dismiss-retry throw");
        // 13-LW-01: the guard that used to silently swallow this throw now counts it.
        Test.assertEqualMessage(app.pollGuardFailureCount(), 1,
            "the dismiss-retry throw is now observable, not silently swallowed");
        RemoteComm.testDismissAlertThrows = false;
        return true;
    }

    // Test 2: a successful pollTick (no throw) still schedules the next poll exactly once — no
    // double-schedule on the ordinary success path.
    (:test)
    function pollTickSchedulesExactlyOnceOnSuccess(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        Test.assertEqualMessage(app.scheduleCount(), 0, "no poll scheduled yet");
        app.pollTick();
        Test.assertEqualMessage(app.scheduleCount(), 1, "scheduleNextPoll() ran exactly once");
        return true;
    }
}
