using Toybox.Lang;
using Toybox.Test;

// 13-04 (CX-G-07 re-verification): a background clear/re-fire must not leave stale dedup state so a new
// critical episode is suppressed. RE-VERIFIED against current source (not a new fix): the foreground
// FaBolusApp.notifyNewAlerts() (FaBolusApp.mc — the notifyNewAlerts() method) already rewrites the
// persisted seen-set to EXACTLY AppState.activeAlertIdentities() after surfacing:
//     var newAlerts = AppState.newAlertsSince(AppState.loadSeenAlerts());
//     AppState.saveSeenAlerts(AppState.activeAlertIdentities());
// — so a cleared alert's identity drops out of the seen-set the moment it leaves AppState.alerts, and a
// later re-fire of the SAME identity is NOT suppressed (newAlertsSince() sees it as new again).
// BgService.mc (the background temporal-event service, BgServiceDelegate.onTemporalEvent/onPhoneMessage)
// does not itself read or write the seen-set at all — it only forwards the compact alerts list via
// Background.exit(AppState.alerts); the seen-set rewrite happens ONLY in the foreground path above, which
// re-runs on the very next foreground statusRead regardless of whether the refresh that produced the new
// alerts list arrived via a background temporal event or a foreground poll. CX-G-07 is therefore ALREADY
// CLOSED by the existing VA-13 rewrite — this file pins that behavior as a regression guard rather than
// adding new (and redundant) background dedup-reset code. See 13-04-SUMMARY.md.
module BgDedupResetTest {

    function alert(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    // Mirrors the exact two-line rewrite FaBolusApp.notifyNewAlerts() performs, without its UI side
    // effects (Attention.vibrate / Ui.pushView via AlertConfirmDelegate) — notifyNewAlerts is private and
    // those side effects aren't what CX-G-07 is about, so this test module stays UI-free like its
    // AppState-pinning siblings (AppLivenessTest, HoldTeardownTest, OutcomeWatchdogTest).
    function notifyAndRewriteSeenSet() as Lang.Array {
        var newAlerts = AppState.newAlertsSince(AppState.loadSeenAlerts());
        AppState.saveSeenAlerts(AppState.activeAlertIdentities());
        return newAlerts;
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.saveSeenAlerts([]);
    }

    // Test 1 (the CX-G-07 case): after an episode clears (its identity leaves activeAlertIdentities) and
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
            "re-fire after a clear notifies again — not dedup-suppressed (CX-G-07)");
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
