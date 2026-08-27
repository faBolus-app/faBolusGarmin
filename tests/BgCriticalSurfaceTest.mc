using Toybox.Lang;
using Toybox.Test;

// 13-07 (CX-G-06): pins AppState.pendingBgNotifyAlerts() / AppState.reconciledBgNotifiedAlerts() — the
// pure dedup logic BgServiceDelegate.surfaceNewAlertsInBackground() (BgService.mc) wraps around
// Toybox.Notifications.showNotification(), which has no test-harness double and so cannot be invoked
// directly from this unit-test binary. This module therefore pins the SAME behavior BgDedupResetTest.mc
// pins for the foreground seen-set (CX-G-07), but against the independent bgNotifiedAlerts set (see
// AppState.mc's KEY_BG_NOTIFIED_ALERTS comment) — proving the two dedup sets are genuinely independent:
// a background-notified alert does NOT get marked seen for the foreground path, and vice versa.
//
// 13-HG-01 (codex HIGH): prior to this fix, a single Notifications.showNotification() throw both
// permanently dedup-suppressed every alert in the batch (the old newBackgroundAlertsToNotify()
// persisted activeAlertIdentities() as "already notified" BEFORE any showNotification attempt) AND
// escaped surfaceNewAlertsInBackground() unguarded, skipping the caller's own Background.exit(). The fix
// splits that single function into pendingBgNotifyAlerts() (pure query, no write) and
// reconciledBgNotifiedAlerts(presented) (pure reconcile, mirrors CX-G-10's reconciledSeenAlerts), with
// BgService.mc now trying each notification independently and persisting the dedup set only AFTER the
// attempts, restricted to what actually posted. simulateFullSurfaceSuccess() below reproduces the OLD
// function's exact behavior for tests 1-4 (every pending alert "successfully posts"); the new test 5
// exercises the throw case directly against the pure reconciliation primitive.
//
// Scope note (from 13-CXG06-FEASIBILITY.md): the wire alert dict ({id, kind, title}) carries no
// severity/critical field, and none exists elsewhere in this codebase. "A critical alert takes the
// surface path and a non-critical one does not" is therefore verified here as: a genuinely NEW alert
// takes the surface path (returned non-empty), and the SAME alert, once already background-notified and
// still active ("non-new" — the only distinction this wire schema supports), does not resurface.
module BgCriticalSurfaceTest {

    function alert(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.saveSeenAlerts([]);
        AppState.saveBgNotifiedAlerts([]);
    }

    // Test-only stand-in for "every pending alert's Notifications.showNotification() call succeeded" —
    // the happy path the real surfaceNewAlertsInBackground() takes when nothing throws. Fetches the
    // pending set, then persists it as fully presented (mirrors the OLD newBackgroundAlertsToNotify()'s
    // eager-write result exactly, since presented == pending here means reconciledBgNotifiedAlerts()
    // reduces to activeAlertIdentities()).
    function simulateFullSurfaceSuccess() as Lang.Array {
        var pending = AppState.pendingBgNotifyAlerts();
        var presented = [];
        for (var i = 0; i < pending.size(); i += 1) {
            presented.add(AppState.alertIdentity(pending[i] as Lang.Dictionary));
        }
        AppState.saveBgNotifiedAlerts(AppState.reconciledBgNotifiedAlerts(presented));
        return pending;
    }

    // Test 1: a genuinely new alert takes the background surface path (non-empty), and — proving the
    // two dedup sets are independent — the foreground seen-set is untouched by it.
    (:test)
    function newAlertTakesBackgroundSurfacePath(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];

        var surfaced = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(surfaced.size(), 1, "a genuinely new alert takes the background surface path");
        Test.assertEqualMessage(surfaced[0]["title"], "Low reservoir", "the surfaced alert is the new one");

        // Independence: the background surface never touches the foreground seen-set (CX-G-06 must not
        // regress CX-G-07's own dedup contract, pinned separately by BgDedupResetTest.mc).
        Test.assertEqualMessage(AppState.loadSeenAlerts().size(), 0,
            "background surfacing does not mark anything seen for the foreground path");
        return true;
    }

    // Test 2 (the plan's "a non-critical one does not" — reinterpreted per the feasibility spike's
    // scope note, since no severity field exists on the wire): the SAME still-active alert, already
    // background-notified once, does not resurface on a later tick.
    (:test)
    function alreadyNotifiedAlertDoesNotResurface(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var first = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(first.size(), 1, "first sighting surfaces");

        // Same alert, still active, on subsequent temporal-event/phone-message ticks.
        var second = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(second.size(), 0, "an already-notified, still-active alert does not resurface");
        var third = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(third.size(), 0, "stays deduped on a later tick");
        return true;
    }

    // Test 3 (CX-G-07 parity for the background path): after an alert clears (drops out of
    // AppState.alerts) and later re-fires with the SAME identity, it surfaces again — mirroring the
    // foreground contract BgDedupResetTest.mc pins, so a cleared-then-recurring critical episode is
    // never permanently suppressed on the wrist.
    (:test)
    function clearedAlertResurfacesAfterDrop(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var first = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(first.size(), 1, "first sighting surfaces");

        AppState.alerts = [];
        var whileCleared = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(whileCleared.size(), 0, "nothing active while cleared");

        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var reFired = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(reFired.size(), 1,
            "re-fire after a clear surfaces again — not permanently dedup-suppressed");
        return true;
    }

    // Test 4: a SECOND, distinct alert arriving alongside an already-notified one still surfaces on its
    // own (mirrors VA-13's "surface EVERY genuinely-new alert" fix for the foreground path — a second
    // simultaneous new alert must not be swallowed by the first one's dedup rewrite).
    (:test)
    function secondDistinctAlertStillSurfaces(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var first = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(first.size(), 1, "first alert surfaces");

        // A second, distinct alert (different id) joins the active set.
        AppState.alerts = [ alert(1, 2, "Low reservoir"), alert(9, 3, "Occlusion detected") ];
        var second = simulateFullSurfaceSuccess();
        Test.assertEqualMessage(second.size(), 1, "only the genuinely new second alert surfaces");
        Test.assertEqualMessage(second[0]["title"], "Occlusion detected", "the new alert is the occlusion one");
        return true;
    }

    // Test 5 (13-HG-01 regression, codex HIGH): a Notifications.showNotification() throw for a pending
    // alert must leave it un-deduped so it retries next cycle — modeled directly against the pure
    // reconciliation primitive since Notifications has no test-harness double. Passing an EMPTY
    // `presented` array to reconciledBgNotifiedAlerts() is exactly what BgService.mc's per-item
    // try/catch produces when EVERY attempt in the batch throws (the alert's identity never makes it
    // into `presented`) — the old code's eager saveBgNotifiedAlerts(activeAlertIdentities()) would have
    // wrongly marked it notified regardless.
    (:test)
    function throwLeavesAlertUnDeduped(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var pending = AppState.pendingBgNotifyAlerts();
        Test.assertEqualMessage(pending.size(), 1, "a new alert is pending notification");

        // Simulate every showNotification() call in the batch throwing: `presented` stays empty.
        AppState.saveBgNotifiedAlerts(AppState.reconciledBgNotifiedAlerts([]));

        var stillPending = AppState.pendingBgNotifyAlerts();
        Test.assertEqualMessage(stillPending.size(), 1,
            "a failed post is NOT marked notified — it stays pending for the next cycle");
        return true;
    }

    // Test 6 (13-HG-01 companion): a MIXED batch — one alert's post succeeds, a second's throws — only
    // dedups the one that actually posted; the failed one stays pending.
    (:test)
    function mixedBatchOnlyDedupsSuccessfulPost(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir"), alert(9, 3, "Occlusion detected") ];
        var pending = AppState.pendingBgNotifyAlerts();
        Test.assertEqualMessage(pending.size(), 2, "both alerts are pending notification");

        // Simulate alert id=1 posting successfully and alert id=9 throwing.
        AppState.saveBgNotifiedAlerts(
            AppState.reconciledBgNotifiedAlerts([ AppState.alertIdentity(alert(1, 2, "Low reservoir")) ]));

        var stillPending = AppState.pendingBgNotifyAlerts();
        Test.assertEqualMessage(stillPending.size(), 1, "only the failed post remains pending");
        Test.assertEqualMessage(stillPending[0]["title"], "Occlusion detected",
            "the still-pending alert is the one whose post threw");
        return true;
    }
}
