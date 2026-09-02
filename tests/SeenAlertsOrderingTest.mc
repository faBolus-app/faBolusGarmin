using Toybox.Lang;
using Toybox.Test;

// FaBolusApp.notifyNewAlerts() used to persist "seen" for EVERY active identity
// BEFORE the vibrate/pushView loop ran (AppState.saveSeenAlerts(AppState.activeAlertIdentities())) —
// so a partial-loop failure (a pushView that throws/can't run for one of several new alerts) could
// suppress an alert that never actually reached the wearer. This file pins the fix: 'seen' is now
// committed PER successfully-presented alert (AppState.reconciledSeenAlerts), driven by an explicit
// Ui.pushView failure model (pushAlertConfirm()). It also pins the companion push-count bound
// (AppState.capAlertPushes/MAX_ALERT_PUSHES) end-to-end through the real notifyNewAlerts() call.
//
// notifyNewAlerts()/pushAlertConfirm() are non-private specifically so this file can exercise the REAL
// production method (mirrors handlePhoneData's own rationale) — a FaBolusApp subclass overrides
// pushAlertConfirm() to simulate a per-identity pushView failure without a live view stack.
// FaBolusApp.mc is compiled into the test binary wholesale (see test.jungle).
module SeenAlertsOrderingTest {

    // A FaBolusApp double whose pushAlertConfirm() fails (returns false, as if Ui.pushView threw) for
    // exactly the ids in `_failIds`, and succeeds for every other alert — lets a test control, per
    // alert, which "presentations" actually happen without touching Ui.pushView at all.
    class SelectivelyFailingApp extends FaBolusApp {
        var _failIds as Lang.Array;
        function initialize(failIds as Lang.Array) {
            FaBolusApp.initialize();
            _failIds = failIds;
        }
        function pushAlertConfirm(a as Lang.Dictionary) as Lang.Boolean {
            return !AppState.containsNum(_failIds, a["id"]);
        }
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.saveSeenAlerts([]);
    }

    // Positive path: every pushAlertConfirm() succeeds ⇒ exactly the presented identities are marked
    // seen (both of them here).
    (:test)
    function allSuccessfulPresentsMarkExactlyPresented(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ { "id" => 7, "kind" => 8, "title" => "D" },
                             { "id" => 9, "kind" => 10, "title" => "E" } ];
        var app = new SelectivelyFailingApp([]);   // nothing fails
        app.notifyNewAlerts(true);
        var seen = AppState.loadSeenAlerts();
        Test.assertEqualMessage(seen.size(), 2, "both presented identities marked seen");
        Test.assertMessage(AppState.containsStr(seen, "8-7"), "first presented identity is seen");
        Test.assertMessage(AppState.containsStr(seen, "10-9"), "second presented identity is seen");
        return true;
    }

    // NEGATIVE PATH (the core fix): one failing pushView among several leaves THAT identity
    // unseen (it re-surfaces as "new" on the next check) while the ones that DID present are marked
    // seen and do not re-present.
    (:test)
    function partialFailureLeavesFailedUnseenButKeepsPresentedSeen(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ { "id" => 1, "kind" => 2, "title" => "A" },
                             { "id" => 3, "kind" => 4, "title" => "B" } ];
        var app = new SelectivelyFailingApp([3]);   // id=3 (identity "4-3") fails to present
        app.notifyNewAlerts(true);

        var seen = AppState.loadSeenAlerts();
        Test.assertMessage(AppState.containsStr(seen, "2-1"), "presented alert (2-1) is marked seen");
        Test.assertMessage(!AppState.containsStr(seen, "4-3"),
            "NEGATIVE PATH: the failed pushView (4-3) stays UNSEEN — not suppressed by the partial failure");

        // The failed one is still "new" — it will be retried on the very next check, not dropped.
        var stillNew = AppState.newAlertsSince(AppState.loadSeenAlerts());
        Test.assertEqualMessage(stillNew.size(), 1, "exactly one alert re-surfaces as new");
        Test.assertEqualMessage(AppState.alertIdentity(stillNew[0]), "4-3", "it's the one whose push failed");

        // A second pass (still failing) doesn't re-present the ALREADY-seen one, and still leaves 4-3 new.
        var app2 = new SelectivelyFailingApp([3]);
        app2.notifyNewAlerts(true);
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 1, "presented set unchanged (2-1 only)");
        return true;
    }

    // A wholly-failed/blocked present (the ONLY new alert's pushView fails) advances the seen-set
    // nothing at all.
    (:test)
    function whollyFailedPresentAdvancesNothing(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ { "id" => 5, "kind" => 6, "title" => "C" } ];
        var app = new SelectivelyFailingApp([5]);   // the only candidate fails
        app.notifyNewAlerts(true);
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 0,
            "nothing marked seen when the only push fails");
        return true;
    }

    // Background semantics preserved: canSurface=false (a background-arrived alert before the first
    // view exists) advances nothing, even with a successful-would-be push.
    (:test)
    function backgroundCallAdvancesNothing(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ { "id" => 11, "kind" => 12, "title" => "F" } ];
        var app = new SelectivelyFailingApp([]);   // would succeed if it ran
        app.notifyNewAlerts(false);                // NOT foreground yet
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 0, "background call marks nothing seen");
        return true;
    }

    // The push-count bound wired end-to-end: 6 simultaneously-new alerts ⇒ only the first
    // AppState.MAX_ALERT_PUSHES (4) are pushed+seen THIS batch, matching AlertsListView.MAX_ROWS — the
    // remaining 2 stay new for the next call, never dropped.
    (:test)
    function moreThanFourNewAlertsOnlyFourPushedAndSeenThisBatch(logger as Test.Logger) as Lang.Boolean {
        baseline();
        var six = [] as Lang.Array;
        for (var i = 0; i < 6; i += 1) { six.add({ "id" => i, "kind" => 1, "title" => "A" + i.toString() }); }
        AppState.alerts = six;
        var app = new SelectivelyFailingApp([]);   // all would succeed
        app.notifyNewAlerts(true);
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 4,
            "only the capped 4 are pushed+seen this batch");
        var stillNew = AppState.newAlertsSince(AppState.loadSeenAlerts());
        Test.assertEqualMessage(stillNew.size(), 2, "the remaining 2 stay new for the next batch");
        return true;
    }

    // Cleared-alert-drops-out is preserved even under the new per-alert commit path — the foreground
    // twin, but exercised through the REAL notifyNewAlerts()/reconciledSeenAlerts() this time, not the mirror in
    // BgDedupResetTest.mc).
    (:test)
    function clearedAlertDropsFromSeenAndCanReFire(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ { "id" => 20, "kind" => 21, "title" => "G" } ];
        var app = new SelectivelyFailingApp([]);
        app.notifyNewAlerts(true);
        Test.assertMessage(AppState.containsStr(AppState.loadSeenAlerts(), "21-20"), "seen after first notify");

        AppState.alerts = [];             // the pump/phone clears it
        app.notifyNewAlerts(true);        // no new alerts, but the seen-set must still prune to active
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 0, "cleared alert drops out of the seen-set");

        AppState.alerts = [ { "id" => 20, "kind" => 21, "title" => "G" } ];   // re-fires
        var reFired = AppState.newAlertsSince(AppState.loadSeenAlerts());
        Test.assertEqualMessage(reFired.size(), 1, "re-fire after a clear is new again — not suppressed");
        return true;
    }

    // Pure-function pin for AppState.reconciledSeenAlerts() itself (independent of the app subclass
    // plumbing above): result = (previously-seen ∩ still-active) ∪ presented.
    (:test)
    function reconciledSeenAlertsMergesCorrectly(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = [ { "id" => 30, "kind" => 31, "title" => "H" },
                             { "id" => 32, "kind" => 33, "title" => "I" } ];
        AppState.saveSeenAlerts(["31-30"]);   // "31-30" already seen; "33-32" is not
        var merged = AppState.reconciledSeenAlerts(["33-32"]);   // this batch presented "33-32"
        Test.assertEqualMessage(merged.size(), 2, "both active identities end up seen");
        Test.assertMessage(AppState.containsStr(merged, "31-30") && AppState.containsStr(merged, "33-32"),
            "previously-seen-and-still-active, plus newly-presented");

        // An active identity that is NEITHER previously seen NOR presented is excluded.
        AppState.alerts = [ { "id" => 30, "kind" => 31, "title" => "H" },
                             { "id" => 32, "kind" => 33, "title" => "I" },
                             { "id" => 34, "kind" => 35, "title" => "J" } ];
        var merged2 = AppState.reconciledSeenAlerts(["33-32"]);
        Test.assertEqualMessage(merged2.size(), 2, "the untouched third identity (35-34) is excluded");
        Test.assertMessage(!AppState.containsStr(merged2, "35-34"), "35-34 not seen — never presented/previously-seen");
        return true;
    }
}
