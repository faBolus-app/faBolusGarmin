using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// sendBolusNow sets status="delivering" + a pendingRequestId, but the only authoritative advance
// is a phone bolusStatus echo. A lost request / dead phone / a fast bolus between polls used to leave the
// watch on "delivering…" forever. The fix stamps `outcomeSentEpoch` at send and a watchdog flips a stuck
// delivering/cancelling to an honest "unknown" after OUTCOME_DEADLINE_SEC (never fabricating delivered/
// cancelled, and KEEPING pendingRequestId so a late echo can still upgrade it). Back-out clears in-flight,
// and a new send is refused while an outcome is pending. These are pure AppState decisions (the HoldView
// timer / FaBolusApp poll that drive them aren't test-compiled — see test.jungle), so we pin THOSE.
// Style mirrors tests/CanBolusTest.mc. AppState is compiled into the test binary.
module OutcomeWatchdogTest {

    // Reset the in-flight/watchdog state so each case is order-independent.
    function baseline() as Void {
        AppState.status = null;
        AppState.message = null;
        AppState.pendingRequestId = null;
        AppState.sawPhoneBolusing = false;
        AppState.outcomeSentEpoch = 0;
        // reattemptBlocked() (used by reattemptBlockedWhilePending below) also consults
        // the durable tombstone now — clear any leftover from another test file so this stays
        // order-independent.
        AppState.clearUnresolvedTombstone();
    }

    // Past the deadline while delivering ⇒ flip to unknown + set a message; idempotent afterward.
    (:test)
    function deadlineExpiredFlipsToUnknown(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivering";
        AppState.pendingRequestId = "rid-1";
        AppState.outcomeSentEpoch = Time.now().value() - (AppState.OUTCOME_DEADLINE_SEC + 5);
        Test.assertMessage(AppState.outcomeDeadlineExpired(), "past the outcome deadline");
        Test.assertMessage(AppState.tickOutcomeWatchdog(), "watchdog reports it changed state");
        Test.assertEqualMessage(AppState.status, "unknown", "stuck delivering flipped to unknown");
        Test.assertMessage(AppState.message != null, "an explanatory message was set");
        Test.assertMessage(AppState.pendingRequestId != null,
            "pendingRequestId is KEPT so a late authoritative echo can still upgrade the outcome");
        Test.assertMessage(!AppState.tickOutcomeWatchdog(), "idempotent — no re-flip once unknown");
        return true;
    }

    // Within the deadline ⇒ no-op (still delivering).
    (:test)
    function withinDeadlineNoOp(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivering";
        AppState.outcomeSentEpoch = Time.now().value();   // just sent
        Test.assertMessage(!AppState.outcomeDeadlineExpired(), "within the deadline");
        Test.assertMessage(!AppState.tickOutcomeWatchdog(), "no flip within the deadline");
        Test.assertEqualMessage(AppState.status, "delivering", "still delivering");
        return true;
    }

    // A pending status with no send-stamp (outcomeSentEpoch == 0) must never expire (guard against a
    // spurious flip when we somehow lack a send time).
    (:test)
    function pendingWithNoStampNeverExpires(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivering";
        AppState.outcomeSentEpoch = 0;
        Test.assertMessage(!AppState.outcomeDeadlineExpired(), "no send-stamp ⇒ never expires");
        Test.assertMessage(!AppState.tickOutcomeWatchdog(), "no send-stamp ⇒ no flip");
        return true;
    }

    // A terminal outcome (delivered) is never regressed by the watchdog, even long past the deadline.
    (:test)
    function terminalDeliveredNeverRegressed(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivered";
        AppState.outcomeSentEpoch = Time.now().value() - 999;
        Test.assertMessage(!AppState.outcomePending(), "delivered is terminal (not pending)");
        Test.assertMessage(!AppState.tickOutcomeWatchdog(), "terminal outcome never flipped");
        Test.assertEqualMessage(AppState.status, "delivered", "delivered preserved");
        return true;
    }

    // The cancelling path is covered exactly like delivering (a cancel REQUEST isn't a confirmed cancel).
    (:test)
    function cancellingCovered(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "cancelling";
        AppState.outcomeSentEpoch = Time.now().value() - (AppState.OUTCOME_DEADLINE_SEC + 5);
        Test.assertMessage(AppState.outcomePending(), "cancelling is a pending outcome");
        Test.assertMessage(AppState.tickOutcomeWatchdog(), "cancelling past deadline flips");
        Test.assertEqualMessage(AppState.status, "unknown", "cancelling → unknown");
        return true;
    }

    // clearInFlight() nulls every in-flight field (used by HoldDelegate.onBack()).
    (:test)
    function clearInFlightNulls(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivering";
        AppState.message = "x";
        AppState.pendingRequestId = "rid-9";
        AppState.sawPhoneBolusing = true;
        AppState.outcomeSentEpoch = Time.now().value();
        AppState.clearInFlight();
        Test.assertMessage(AppState.status == null, "status nulled");
        Test.assertMessage(AppState.message == null, "message nulled");
        Test.assertMessage(AppState.pendingRequestId == null, "pendingRequestId nulled");
        Test.assertMessage(!AppState.sawPhoneBolusing, "sawPhoneBolusing cleared");
        Test.assertMessage(AppState.outcomeSentEpoch == 0, "outcomeSentEpoch cleared");
        return true;
    }

    // MainDelegate.pressBolusButton's cancel path, on a SUCCESSFUL RemoteComm.send()
    // dispatch, sets status="cancelling" AND re-stamps outcomeSentEpoch — matching
    // HoldDelegate.cancelDelivery exactly. RemoteComm.send() depends on
    // System.getDeviceSettings().phoneConnected, which is NOT sim-controllable (see
    // tests/CanBolusTest.mc's established idiom) — guard the positive-dispatch assertion on it exactly
    // like CanBolusTest does; the negative (undispatched) path is pinned deterministically in
    // tests/BolusSendFailedTest.mc (the sim/CI default is "unreachable").
    (:test)
    function cancelDispatchSuccessSetsCancellingAndRestampsWatchdog(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.connection = "Delivering";   // bolusing() true
        AppState.pendingRequestId = "rid-cancel-2";
        var md = new MainDelegate(true, "glance");
        md.pressBolusButton();
        if (RemoteComm.phoneReachable()) {
            Test.assertEqualMessage(AppState.status, "cancelling", "successful cancel dispatch ⇒ cancelling");
            Test.assertMessage(AppState.outcomeSentEpoch > 0,
                "successful cancel dispatch ⇒ outcomeSentEpoch re-stamped");
        }
        return true;
    }

    // reattemptBlocked() is true exactly while an outcome is pending (delivering/cancelling), false for
    // terminal or idle — this is the gate that stops sendBolusNow minting a second reqId.
    (:test)
    function reattemptBlockedWhilePending(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivering";
        Test.assertMessage(AppState.reattemptBlocked(), "delivering ⇒ reattempt blocked");
        AppState.status = "cancelling";
        Test.assertMessage(AppState.reattemptBlocked(), "cancelling ⇒ reattempt blocked");
        AppState.status = "delivered";
        Test.assertMessage(!AppState.reattemptBlocked(), "terminal ⇒ not blocked");
        AppState.status = null;
        Test.assertMessage(!AppState.reattemptBlocked(), "idle ⇒ not blocked");
        return true;
    }
}
