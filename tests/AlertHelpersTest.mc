using Toybox.Lang;
using Toybox.Test;

// The pure alert-list helpers factored out of
// FaBolusApp.notifyNewAlerts and AlertConfirmDelegate. newAlertsSince()/activeAlertIdentities()
// let the notifier surface EVERY new alert (the old code surfaced only the first but marked ALL seen,
// suppressing a 2nd simultaneous new alert forever). removeAlert() drops an exact (id, kind)
// match (no longer called on a bare dispatch — see the statusRead-reconcile note below).
// statusRead-reconcile: markDismissSent()/isDismissSent()/reconcileDismissSent()
// replace the old optimistic local removal — a dispatched-but-unproven dismiss no longer suppresses the
// alert; only a fresh authoritative statusRead (simulated here by reassigning AppState.alerts) proves it
// absent. Also pins the corrected push-count bound (capAlertPushes/MAX_ALERT_PUSHES, the "50-vs-4"
// mismatch). AppState is compiled into the test binary (test.jungle). Style mirrors tests/CanBolusTest.mc.
module AlertHelpersTest {

    // Two active alerts, most-serious first (the order the phone sends and the list preserves).
    function twoAlerts() as Lang.Array {
        return [ { "id" => 1, "kind" => 2, "title" => "A" },
                 { "id" => 3, "kind" => 4, "title" => "B" } ];
    }

    // Two never-seen alerts ⇒ both returned, most-serious-first; then after marking the active
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

    // activeAlertIdentities returns every active identity in order.
    (:test)
    function activeIdentitiesInOrder(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        var ids = AppState.activeAlertIdentities();
        Test.assertEqualMessage(ids.size(), 2, "two identities");
        Test.assertEqualMessage(ids[0], "2-1", "most-serious identity first");
        Test.assertEqualMessage(ids[1], "4-3", "next identity second");
        return true;
    }

    // One already-seen, one new ⇒ only the new one is returned.
    (:test)
    function newAlertsSinceFiltersSeen(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        var fresh = AppState.newAlertsSince(["2-1"]);   // "2-1" already seen
        Test.assertEqualMessage(fresh.size(), 1, "only the unseen one is new");
        Test.assertEqualMessage(AppState.alertIdentity(fresh[0]), "4-3", "the unseen identity");
        return true;
    }

    // removeAlert drops exactly the (id, kind) match and leaves the rest.
    (:test)
    function removeAlertDropsExactMatch(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        AppState.removeAlert(1, 2);
        Test.assertEqualMessage(AppState.alerts.size(), 1, "one alert removed");
        var kept = AppState.alerts[0] as Lang.Dictionary;
        Test.assertMessage(kept["id"] == 3 && kept["kind"] == 4, "the OTHER alert is kept");
        return true;
    }

    // A non-matching (id, kind) leaves the list unchanged.
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

    // statusRead-reconcile: a dispatched dismiss is tracked as a PROVISIONAL flag — it must
    // NEVER mutate the active alerts list directly (that optimistic removal is exactly what the owner
    // decided to stop doing; see AlertConfirmDelegate.mc).
    (:test)
    function markDismissSentFlagsWithoutRemoving(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();
        AppState.dismissSentAlertIdentities = [];
        Test.assertMessage(!AppState.isDismissSent(1, 2), "not flagged before a dispatch");
        AppState.markDismissSent(1, 2);
        Test.assertMessage(AppState.isDismissSent(1, 2), "flagged provisional after a dispatched dismiss");
        Test.assertEqualMessage(AppState.alerts.size(), 2,
            "NEGATIVE PATH: markDismissSent never suppresses/removes the alert — an unproven dismissal "
            + "leaves the active list untouched");
        // Re-dispatching the same alert is idempotent — no duplicate identity.
        AppState.markDismissSent(1, 2);
        Test.assertMessage(AppState.isDismissSent(1, 2), "still flagged (idempotent)");
        return true;
    }

    // reconcileDismissSent(): an identity still present in `alerts` (the phone hasn't proven the dismiss
    // took effect yet) STAYS flagged — the alert is never suppressed on the strength of the dispatch
    // alone. Only once a fresh authoritative alerts list (simulated here) omits the identity does
    // reconcileDismissSent() drop the provisional flag — that's the actual "proof of absence."
    (:test)
    function reconcileKeepsStillActiveDropsOnceProvenAbsent(logger as Test.Logger) as Lang.Boolean {
        AppState.alerts = twoAlerts();          // "2-1", "4-3"
        AppState.dismissSentAlertIdentities = [];
        AppState.markDismissSent(1, 2);
        AppState.markDismissSent(3, 4);
        AppState.reconcileDismissSent();
        Test.assertMessage(AppState.isDismissSent(1, 2), "still active ⇒ NOT reconciled away yet");
        Test.assertMessage(AppState.isDismissSent(3, 4), "still active ⇒ NOT reconciled away yet");

        // Simulate the next authoritative statusRead: "2-1" is gone, "4-3" remains.
        AppState.alerts = [ twoAlerts()[1] ];
        AppState.reconcileDismissSent();
        Test.assertMessage(!AppState.isDismissSent(1, 2), "no longer active ⇒ proven absent ⇒ reconciled");
        Test.assertMessage(AppState.isDismissSent(3, 4), "still active ⇒ still flagged");
        return true;
    }

    // The push-count bound (the "50-vs-4 mismatch"): sanitizeAlerts stores up to 50 alerts, but a single
    // notify batch may only actively surface (vibrate + push a Confirmation for) at most
    // AppState.MAX_ALERT_PUSHES — matching AlertsListView.MAX_ROWS's 4-row display cap, which
    // FaBolusApp.mc's own doc comment already claimed but nothing previously enforced.
    (:test)
    function capAlertPushesBoundsToFour(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.MAX_ALERT_PUSHES, 4,
            "the intended push bound is 4, matching AlertsListView.MAX_ROWS");
        var six = [] as Lang.Array;
        for (var i = 0; i < 6; i += 1) { six.add({ "id" => i, "kind" => 1, "title" => "A" + i.toString() }); }
        var capped = AppState.capAlertPushes(six);
        Test.assertEqualMessage(capped.size(), 4, "6 candidates ⇒ capped to 4 for this batch");
        Test.assertEqualMessage(capped[0]["id"], 0, "order preserved (keeps the first — most-serious-first slice)");
        Test.assertEqualMessage(capped[3]["id"], 3, "keeps exactly the first 4, drops the rest for THIS batch");

        var three = [] as Lang.Array;
        for (var i = 0; i < 3; i += 1) { three.add({ "id" => i, "kind" => 1, "title" => "A" + i.toString() }); }
        var uncapped = AppState.capAlertPushes(three);
        Test.assertEqualMessage(uncapped.size(), 3, "under the bound ⇒ unchanged");
        return true;
    }
}
