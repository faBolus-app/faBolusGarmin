using Toybox.Lang;
using Toybox.Test;

// VA-13 + VA-14 (V-Audit): the pure alert-list helpers factored out of FaBolusApp.notifyNewAlerts and
// AlertConfirmDelegate (both excluded from the test binary). VA-13: newAlertsSince()/
// activeAlertIdentities() let the notifier surface EVERY new alert (the old code surfaced only the first
// but marked ALL seen, suppressing a 2nd simultaneous new alert forever). VA-14: removeAlert() is the
// optimistic-removal used only after a DISPATCHED dismiss. AppState is compiled into the test binary
// (test.jungle). Style mirrors tests/CanBolusTest.mc.
module AlertHelpersTest {

    // Two active alerts, most-serious first (the order the phone sends and the list preserves).
    function twoAlerts() as Lang.Array {
        return [ { "id" => 1, "kind" => 2, "title" => "A" },
                 { "id" => 3, "kind" => 4, "title" => "B" } ];
    }

    // VA-13: two never-seen alerts ⇒ both returned, most-serious-first; then after marking the active
    // set seen, newAlertsSince over the persisted seen-set is empty (nothing left new).
    (:test)
    function newAlertsSinceReturnsBothThenEmpty(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        var fresh = AppState.newAlertsSince([]);   // nothing seen yet
        Test.assertEqualMessage(fresh.size(), 2, "both alerts are new");
        // identity = kind + "-" + id → "2-1" then "4-3", most-serious first (order preserved).
        Test.assertEqualMessage(AppState.alertIdentity(fresh[0]), "2-1", "first is most-serious (2-1)");
        Test.assertEqualMessage(AppState.alertIdentity(fresh[1]), "4-3", "second is next (4-3)");

        // Mark the active identities seen (what notifyNewAlerts does after surfacing), then re-check.
        AppState.saveSeenAlerts(AppState.activeAlertIdentities());
        var again = AppState.newAlertsSince(AppState.loadSeenAlerts());
        Test.assertEqualMessage(again.size(), 0, "after saving the active set seen ⇒ nothing new");
        return true;
    }

    // VA-13: activeAlertIdentities returns every active identity in order.
    (:test)
    function activeIdentitiesInOrder(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        var ids = AppState.activeAlertIdentities();
        Test.assertEqualMessage(ids.size(), 2, "two identities");
        Test.assertEqualMessage(ids[0], "2-1", "most-serious identity first");
        Test.assertEqualMessage(ids[1], "4-3", "next identity second");
        return true;
    }

    // VA-13: one already-seen, one new ⇒ only the new one is returned.
    (:test)
    function newAlertsSinceFiltersSeen(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        var fresh = AppState.newAlertsSince(["2-1"]);   // "2-1" already seen
        Test.assertEqualMessage(fresh.size(), 1, "only the unseen one is new");
        Test.assertEqualMessage(AppState.alertIdentity(fresh[0]), "4-3", "the unseen identity");
        return true;
    }

    // VA-14: removeAlert drops exactly the (id, kind) match and leaves the rest.
    (:test)
    function removeAlertDropsExactMatch(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        AppState.removeAlert(1, 2);
        Test.assertEqualMessage(AppState.alerts.size(), 1, "one alert removed");
        var kept = AppState.alerts[0] as Lang.Dictionary;
        Test.assertMessage(kept["id"] == 3 && kept["kind"] == 4, "the OTHER alert is kept");
        return true;
    }

    // VA-14: a non-matching (id, kind) leaves the list unchanged.
    (:test)
    function removeAlertNonMatchUnchanged(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        AppState.removeAlert(9, 9);            // matches neither
        Test.assertEqualMessage(AppState.alerts.size(), 2, "non-match ⇒ nothing removed");
        // A right-id/wrong-kind (and vice-versa) must also NOT match — both keys must agree.
        AppState.removeAlert(1, 99);
        Test.assertEqualMessage(AppState.alerts.size(), 2, "id match but kind mismatch ⇒ nothing removed");
        return true;
    }
}
