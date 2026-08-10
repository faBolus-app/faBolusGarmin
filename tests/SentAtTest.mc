using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// P11: the Garmin remote stamps a wall-clock `sentAt` (Unix seconds) into DELIVERY-AUTHORIZING
// (insulin-INCREASING) commands so the iPhone host can refuse a stale one (a bolus retransmitted
// minutes late is a double-dose hazard). These tests pin the invariant that the stamp is present on
// exactly the freshness-gated builders — bolusRequest / bolusRequestCarbs / resumePump — and ABSENT
// on the non-gated ones (cancelBolus etc.), and that its value is a plausible current wall-clock.
// RemoteComm.mc is compiled into the test binary (see test.jungle). Style mirrors HistoryEpochsTest.
module SentAtTest {

    // Asserts a composed command's `sentAt` is present, a positive Lang.Number, and within the
    // [before, after] wall-clock bracket captured around the build (seconds granularity, so equal is
    // the common case; a 1 s tick during the call is tolerated by the >= before / <= after bounds).
    function assertFreshStamp(cmd as Lang.Dictionary, before as Lang.Number, after as Lang.Number,
                              label as Lang.String) as Void {
        Test.assertMessage(cmd.hasKey("sentAt"), label + ": sentAt present");
        var v = cmd["sentAt"];
        Test.assertMessage(v instanceof Lang.Number, label + ": sentAt is a Lang.Number");
        Test.assertMessage(v > 0, label + ": sentAt positive");
        Test.assertMessage(v >= before && v <= after,
            label + ": sentAt within [before,after] wall-clock bracket");
    }

    // bolusRequest (units-only) carries a fresh sentAt.
    (:test)
    function bolusRequestStamped(logger as Test.Logger) as Lang.Boolean {
        var before = Time.now().value();
        var cmd = RemoteComm.bolusRequest(2.5, "rid-1", null);
        var after = Time.now().value();
        Test.assertEqualMessage(cmd["kind"], "bolusRequest", "kind");
        assertFreshStamp(cmd, before, after, "bolusRequest");
        return true;
    }

    // bolusRequestCarbs (carb variant, host recomputes) also carries a fresh sentAt.
    (:test)
    function bolusRequestCarbsStamped(logger as Test.Logger) as Lang.Boolean {
        var before = Time.now().value();
        var cmd = RemoteComm.bolusRequestCarbs(30, 120, 1.8, "rid-2", null, false);
        var after = Time.now().value();
        Test.assertEqualMessage(cmd["kind"], "bolusRequest", "kind");
        assertFreshStamp(cmd, before, after, "bolusRequestCarbs");
        return true;
    }

    // resumePump is insulin-INCREASING → stamped.
    (:test)
    function resumePumpStamped(logger as Test.Logger) as Lang.Boolean {
        var before = Time.now().value();
        var cmd = RemoteComm.resumePump("rid-3");
        var after = Time.now().value();
        Test.assertEqualMessage(cmd["kind"], "resumePump", "kind");
        assertFreshStamp(cmd, before, after, "resumePump");
        return true;
    }

    // cancelBolus is insulin-REDUCING (safety action) → deliberately NOT freshness-gated, NO stamp.
    (:test)
    function cancelBolusNotStamped(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.cancelBolus("rid-4");
        Test.assertEqualMessage(cmd["kind"], "cancelBolus", "kind");
        Test.assertMessage(!cmd.hasKey("sentAt"), "cancelBolus must NOT carry sentAt");
        return true;
    }

    // suspendPump is insulin-REDUCING → NO stamp (guards against copy-paste stamping the wrong set).
    (:test)
    function suspendPumpNotStamped(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.suspendPump("rid-5");
        Test.assertEqualMessage(cmd["kind"], "suspendPump", "kind");
        Test.assertMessage(!cmd.hasKey("sentAt"), "suspendPump must NOT carry sentAt");
        return true;
    }
}
