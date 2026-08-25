using Toybox.Lang;
using Toybox.Test;

// 13-07 (CX-G-06): pins AppState.newBackgroundAlertsToNotify() — the pure dedup logic
// BgServiceDelegate.surfaceNewAlertsInBackground() (BgService.mc) wraps around
// Toybox.Notifications.showNotification(), which has no test-harness double and so cannot be invoked
// directly from this unit-test binary. This module therefore pins the SAME behavior BgDedupResetTest.mc
// pins for the foreground seen-set (CX-G-07), but against the independent bgNotifiedAlerts set (see
// AppState.mc's KEY_BG_NOTIFIED_ALERTS comment) — proving the two dedup sets are genuinely independent:
// a background-notified alert does NOT get marked seen for the foreground path, and vice versa.
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

    // Test 1: a genuinely new alert takes the background surface path (non-empty), and — proving the
    // two dedup sets are independent — the foreground seen-set is untouched by it.
    (:test)
    function newAlertTakesBackgroundSurfacePath(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];

        var surfaced = AppState.newBackgroundAlertsToNotify();
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
        var first = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(first.size(), 1, "first sighting surfaces");

        // Same alert, still active, on subsequent temporal-event/phone-message ticks.
        var second = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(second.size(), 0, "an already-notified, still-active alert does not resurface");
        var third = AppState.newBackgroundAlertsToNotify();
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
        var first = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(first.size(), 1, "first sighting surfaces");

        AppState.alerts = [];
        var whileCleared = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(whileCleared.size(), 0, "nothing active while cleared");

        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var reFired = AppState.newBackgroundAlertsToNotify();
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
        var first = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(first.size(), 1, "first alert surfaces");

        // A second, distinct alert (different id) joins the active set.
        AppState.alerts = [ alert(1, 2, "Low reservoir"), alert(9, 3, "Occlusion detected") ];
        var second = AppState.newBackgroundAlertsToNotify();
        Test.assertEqualMessage(second.size(), 1, "only the genuinely new second alert surfaces");
        Test.assertEqualMessage(second[0]["title"], "Occlusion detected", "the new alert is the occlusion one");
        return true;
    }
}
