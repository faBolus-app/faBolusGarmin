using Toybox.Lang;
using Toybox.Test;

// A background clear/re-fire must not
// leave stale dedup state so a new critical episode is suppressed. RE-VERIFIED against current source
// (not a new fix): the foreground FaBolusApp.notifyNewAlerts() rewrites the persisted
// seen-set to (previously-seen ∩ still-active) ∪ presented-this-batch
// (AppState.reconciledSeenAlerts) — so a cleared alert's identity drops out of the seen-set the moment
// it leaves AppState.alerts (same as the old, simpler `activeAlertIdentities()` rewrite this mirror
// used before), and a later re-fire of the SAME identity is NOT suppressed (newAlertsSince() sees it as new
// again). BgService.mc (the background temporal-event service,
// BgServiceDelegate.onTemporalEvent/onPhoneMessage) does not itself read or write the seen-set at all —
// it only forwards the compact alerts list via Background.exit(AppState.alerts); the seen-set rewrite
// happens ONLY in the foreground path above, which re-runs on the very next foreground statusRead
// regardless of whether the refresh that produced the new alerts list arrived via a background temporal
// event or a foreground poll. The dedup-reset concern is therefore ALREADY CLOSED by the existing
// seen-set rewrite — this file pins that behavior as a regression guard rather than adding new (and
// redundant) background dedup-reset code.
module BgDedupResetTest {

    function alert(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    // Mirrors FaBolusApp.notifyNewAlerts()'s CORRECTED seen-set rewrite for the
    // all-successful-presents case (`presented` = every new alert's identity), without its UI side
    // effects (Attention.vibrate / Ui.pushView via AlertConfirmDelegate) — this test module stays
    // UI-free like its AppState-pinning siblings (AppLivenessTest, HoldTeardownTest,
    // OutcomeWatchdogTest). The OLD mirror here (`saveSeenAlerts(activeAlertIdentities())`) was the exact
    // anti-pattern the real function fixed — updated so this regression guard tracks the real,
    // now-fixed algorithm instead of silently drifting onto a stale copy of the bug. The partial-failure
    // / count-bound cases are covered separately in tests/SeenAlertsOrderingTest.mc, which DOES exercise
    // the real notifyNewAlerts()/pushAlertConfirm() via a FaBolusApp subclass.
    function notifyAndRewriteSeenSet() as Lang.Array {
        var newAlerts = AppState.newAlertsSince(AppState.loadSeenAlerts());
        var presented = [];
        for (var i = 0; i < newAlerts.size(); i += 1) { presented.add(AppState.alertIdentity(newAlerts[i])); }
        AppState.saveSeenAlerts(AppState.reconciledSeenAlerts(presented));
        return newAlerts;
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.saveSeenAlerts([]);
    }

    // Test 1: after an episode clears (its identity leaves activeAlertIdentities) and
    // it later re-fires, the re-fire is NOT suppressed by the seen-set — it notifies again.
    (:test)
    function clearedAlertReFiresAfterDrop(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var first = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(first.size(), 1, "first sighting notifies");

        // Episode clears — the next refresh (foreground or background-forwarded) no longer includes it.
        AppState.alerts = [];
        var whileCleared = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(whileCleared.size(), 0, "nothing active while cleared");

        // Re-fire: the SAME identity (kind=2, id=1) comes back.
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var reFired = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(reFired.size(), 1,
            "re-fire after a clear notifies again — not dedup-suppressed");
        return true;
    }

    // Test 2: within a SINGLE un-cleared episode, dedup still suppresses repeats — no notification spam
    // on every poll while the same alert stays continuously active.
    (:test)
    function unclearedEpisodeStaysDeduped(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alert(1, 2, "Low reservoir") ];
        var first = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(first.size(), 1, "first sighting notifies");

        // Same alert still active on the next several refreshes — no re-notify.
        var second = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(second.size(), 0, "still-active alert is not re-notified");
        var third = notifyAndRewriteSeenSet();
        Test.assertEqualMessage(third.size(), 0, "still deduped on a later poll");
        return true;
    }
}
