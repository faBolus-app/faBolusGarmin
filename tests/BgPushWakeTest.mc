using Toybox.Lang;
using Toybox.Test;

// Phase 20 (R2, D-04): event-driven background push-wake. BgServiceDelegate.onPhoneAppMessage routes a
// phone-pushed status through the SAME correlate→handle→publish→surface path as onPhoneMessage. The system
// callback can't be invoked from the unit binary (no PhoneAppMessage double), so these drive the extracted
// PURE seam (AppState.isHandleablePush) + the state-refresh (AppState.handle) + the background-notification
// queue (AppState.pendingBgNotifyAlerts) — the real logic behind the callback. A push-wake is a FRESH
// service instance that sent no request (mintedReqId == null), so a `kind=="statusRead"` push is accepted
// via the kind fallback. Style mirrors tests/StatusReplyTest.mc + tests/BgCriticalSurfaceTest.mc.
module BgPushWakeTest {

    function statusPush(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // A correlated statusRead push (no minted id — the push-wake sent no request) is handleable, and
    // handling it refreshes AppState (the alerts list is replaced from the pushed status).
    (:test)
    function handleableStatusPushRefreshesState(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppState.isHandleablePush(statusPush({}), null),
            "a statusRead push (mintedReqId null) is handleable via the kind fallback");

        AppState.saveSeenAlerts([]);
        AppState.saveBgNotifiedAlerts([]);
        AppState.alerts = [];
        AppState.handle(statusPush({ "alerts" => [ { "id" => 5, "kind" => 6, "title" => "Low reservoir" } ] }));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "a valid push refreshed AppState.alerts");
        Test.assertEqualMessage(AppState.alerts[0]["title"], "Low reservoir", "refreshed with the pushed alert");
        return true;
    }

    // A malformed / non-statusRead push is NOT handleable — the callback changes nothing and does not exit
    // early (mirrors onPhoneMessage's guard; the system bounds the wake). Guards the instanceof + kind checks.
    (:test)
    function malformedPushIsNotHandleable(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(!AppState.isHandleablePush(null, null), "NEGATIVE: null payload ⇒ not handleable");
        Test.assertMessage(!AppState.isHandleablePush("nope", null), "NEGATIVE: non-dict payload ⇒ not handleable");
        Test.assertMessage(!AppState.isHandleablePush({ "type" => "hr_ctl", "on" => true }, null),
            "NEGATIVE: a non-statusRead toggle ⇒ not handleable (no early exit)");
        Test.assertMessage(!AppState.isHandleablePush({}, null), "NEGATIVE: empty dict ⇒ not handleable");
        Test.assertMessage(!AppState.isHandleablePush({ "kind" => "bolusStatus" }, null),
            "NEGATIVE: a bolusStatus echo ⇒ not a handleable status push");
        return true;
    }

    // A genuinely-new pushed alert is queued for BACKGROUND surfacing via the Notifications dedup path
    // (never vibrate/pushView — the background service can't) — proven via the same pure queue
    // (pendingBgNotifyAlerts) that surfaceNewAlertsInBackground consumes.
    (:test)
    function newPushedAlertQueuedForBackgroundNotification(logger as Test.Logger) as Lang.Boolean {
        AppState.saveSeenAlerts([]);
        AppState.saveBgNotifiedAlerts([]);
        AppState.alerts = [];
        AppState.handle(statusPush({ "alerts" => [ { "id" => 9, "kind" => 3, "title" => "Occlusion detected" } ] }));
        var pending = AppState.pendingBgNotifyAlerts();
        Test.assertEqualMessage(pending.size(), 1, "a new pushed alert is queued for background notification");
        Test.assertEqualMessage(pending[0]["title"], "Occlusion detected", "the queued alert is the pushed one");
        return true;
    }
}
