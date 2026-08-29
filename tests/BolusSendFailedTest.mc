using Toybox.Lang;
using Toybox.Test;

// A bolus send that fails must surface as "failed" — not leave a stuck "delivering…".
// AppState.noteBolusSendFailed(reqId?) is the pure/guarded state transition called both by
// RemoteComm.BolusCommListener.onError (async transport failure) and by sendBolusNow when the
// synchronous dispatch reports false. These pin that it only ever fires on the CORRECT in-flight,
// still-pending request and NEVER regresses a terminal outcome. AppState is compiled into the test
// binary (test.jungle). Style mirrors tests/CanBolusTest.mc / tests/OutcomeWatchdogTest.mc.
module BolusSendFailedTest {

    // Reset the in-flight bolus state to a known baseline (state persists across tests in a run).
    function baseline(reqId as Lang.String?, status as Lang.String?) as Void {
        AppState.pendingRequestId = reqId;
        AppState.status = status;
        AppState.message = null;
    }

    // delivering + matching reqId ⇒ flips to "failed" with the default message.
    (:test)
    function deliveringMatchFails(logger as Test.Logger) as Lang.Boolean {
        baseline("rid-1", "delivering");
        AppState.noteBolusSendFailed("rid-1");
        Test.assertEqualMessage(AppState.status, "failed", "delivering+match ⇒ failed");
        Test.assertEqualMessage(AppState.message, "Send failed — not delivered.", "default message set");
        return true;
    }

    // cancelling + matching reqId ⇒ also flips to "failed" (both are pending states).
    (:test)
    function cancellingMatchFails(logger as Test.Logger) as Lang.Boolean {
        baseline("rid-1", "cancelling");
        AppState.noteBolusSendFailed("rid-1");
        Test.assertEqualMessage(AppState.status, "failed", "cancelling+match ⇒ failed");
        return true;
    }

    // reqId mismatch (a late error for a superseded/other request) ⇒ untouched.
    (:test)
    function mismatchUnchanged(logger as Test.Logger) as Lang.Boolean {
        baseline("rid-1", "delivering");
        AppState.noteBolusSendFailed("rid-OTHER");
        Test.assertEqualMessage(AppState.status, "delivering", "mismatch ⇒ status unchanged");
        Test.assertMessage(AppState.message == null, "mismatch ⇒ message unchanged");
        return true;
    }

    // A terminal "delivered" is NEVER regressed to failed, even on a matching reqId.
    (:test)
    function deliveredNotRegressed(logger as Test.Logger) as Lang.Boolean {
        baseline("rid-1", "delivered");
        AppState.noteBolusSendFailed("rid-1");
        Test.assertEqualMessage(AppState.status, "delivered", "terminal delivered not regressed");
        return true;
    }

    // A null reqId is a no-op (never coerces / crashes / touches state).
    (:test)
    function nullReqIdNoop(logger as Test.Logger) as Lang.Boolean {
        baseline("rid-1", "delivering");
        AppState.noteBolusSendFailed(null);
        Test.assertEqualMessage(AppState.status, "delivering", "null reqId ⇒ no-op");
        return true;
    }

    // No in-flight request (pendingRequestId null) ⇒ no-op — guards the pendingRequestId==null branch.
    (:test)
    function noPendingNoop(logger as Test.Logger) as Lang.Boolean {
        baseline(null, "delivering");
        AppState.noteBolusSendFailed("rid-1");
        Test.assertEqualMessage(AppState.status, "delivering", "no pending request ⇒ no-op");
        return true;
    }

    // MainDelegate.pressBolusButton's CANCEL path must honor RemoteComm.send()'s Bool
    // exactly like the sibling bolus-send failure handling above — a failed dispatch (the phone
    // unreachable; System.getDeviceSettings().phoneConnected is NOT sim-controllable, so the sim/CI
    // default of "unreachable" gives us this branch deterministically — see tests/CanBolusTest.mc's
    // "not sim-controllable" note) must NOT flip status to "cancelling" (which would look done and
    // non-retryable) and must surface an error. canCancel() consults only bolusing()+pendingRequestId
    // (never `status`), so leaving status untouched keeps the cancel retryable — asserted directly.
    (:test)
    function cancelDispatchFailureKeepsRetryableAndSurfacesError(logger as Test.Logger) as Lang.Boolean {
        AppState.connection = "Delivering";   // bolusing() true
        AppState.pendingRequestId = "rid-cancel-1";
        AppState.status = "delivering";
        AppState.message = null;
        AppState.outcomeSentEpoch = 0;
        var md = new MainDelegate(true, "glance");
        md.pressBolusButton();
        if (!RemoteComm.phoneReachable()) {
            Test.assertEqualMessage(AppState.status, "delivering",
                "failed cancel dispatch ⇒ status untouched (never shows 'cancelling')");
            Test.assertMessage(AppState.message != null, "failed cancel dispatch ⇒ an error is surfaced");
            Test.assertEqualMessage(AppState.outcomeSentEpoch, 0,
                "failed cancel dispatch ⇒ the outcome watchdog is NOT re-stamped");
            Test.assertMessage(AppState.canCancel(), "cancel is still retryable (canCancel() unaffected)");
        }
        return true;
    }
}
