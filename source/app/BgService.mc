using Toybox.System;
using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.Notifications;

// Background service that refreshes the BG complication while the app is closed. On each
// temporal event it re-publishes the last-known reading (so a newly-added complication isn't
// blank), then asks the phone for a fresh status; when the phone replies it publishes the new
// value directly and exits. If the phone is unreachable it just exits — the persisted value
// stays on the face. Background phone reachability varies, so this is best-effort;
// foreground opens/glances remain the reliable refresh path.
(:background)
class BgServiceDelegate extends System.ServiceDelegate {
    // R2-15: the requestId minted for THIS service's statusRead request, retained so onPhoneMessage can
    // accept ONLY the correlated reply (the phone echoes it back). Same instance handles both callbacks.
    var mintedReqId as Lang.String? = null;

    function initialize() { ServiceDelegate.initialize(); }

    function onTemporalEvent() as Void {
        // R2-16: the background service is a SEPARATE process from the foreground app — its AppState
        // starts at compile-time defaults. Restore the persisted prefs (staleness policy, display unit,
        // etc.) BEFORE the first publish so the "keep last-known reading" republish (and any "--"/stale
        // rendering) uses the phone-configured policy, not the defaults (e.g. a wrong staleSec would
        // mis-judge whether the last reading should show as stale).
        AppState.loadPrefs();
        BgComplication.publish(null, null, 0);   // keep last-known reading visible (or "--" if stale)

        if (System.getDeviceSettings().phoneConnected) {
            Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
            try {
                // R2-15: retain the minted id so we accept ONLY the phone's correlated reply (it echoes it).
                // 19-03 (G-M1): ROUTINE mint (fires every ~5-min temporal event) — see
                // RemoteComm.newRoutineRequestId().
                mintedReqId = RemoteComm.newRoutineRequestId();
                Comm.transmit(RemoteComm.statusRead(mintedReqId), null, new BgCommListener());
                return;   // wait for the reply; the system bounds our runtime
            } catch (e) {
                Background.exit(null);
            }
        } else {
            Background.exit(null);
        }
    }

    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Lang.Dictionary) {
            // R2-15/VA-16: this service sent a statusRead and must publish + exit ONLY on the CORRELATED
            // reply — the phone echoes our minted requestId, so we match on it (falling back to the kind
            // discriminator for a legacy phone that doesn't echo). A non-reply dict (an eating_sense/hr_ctl
            // toggle, a stray bolusStatus echo, etc.) OR a reply carrying a DIFFERENT requestId is IGNORED —
            // return WITHOUT exiting so the service stays alive for the real reply (the system still bounds
            // our total runtime). Exiting on it would drop the fresh read we're waiting for and republish stale.
            if (!AppState.isCorrelatedStatusReply(data as Lang.Dictionary, mintedReqId)) { return; }
            AppState.handle(data as Lang.Dictionary);
            BgComplication.publishFromState();
            // A background service process CANNOT vibrate or pushView (Toybox.Attention isn't a
            // documented background runtime context, and WatchUi.pushView() explicitly throws
            // Lang.OperationNotAllowedException when called from background — see
            // 13-CXG06-FEASIBILITY.md), so the FULL in-app confirm-to-clear surface still can't happen
            // here. But CX-G-06: it CAN show a system notification (Toybox.Notifications.showNotification,
            // documented by the SDK itself as the mechanism for "notify the user of an event from the
            // background") — so a critical pump alert is not left completely silent on the wrist while
            // the app is suspended/closed. This is an ADDITIVE early signal only, tracked via its own
            // dedup set (AppState.newBackgroundAlertsToNotify()); it does not mark anything "seen" for the
            // main app's own notifyNewAlerts(), which still runs its full vibrate+confirm flow the next
            // time a view exists. Forward ONLY the compact alerts list — NOT the full status (its history
            // array can be large) — to stay within the background-data payload limit.
            surfaceNewAlertsInBackground();
            Background.exit(AppState.alerts);
            return;
        }
        Background.exit(null);
    }

    // CX-G-06: show a system notification for every alert AppState.newBackgroundAlertsToNotify() reports
    // as not-yet-background-notified. Non-private (mirroring this codebase's existing test-only-seam
    // convention, e.g. FaBolusApp.scheduleCount()/EatingRelay.isRunning()) so BgCriticalSurfaceTest.mc
    // could drive it directly if a future change makes that useful; today the pure dedup logic it wraps
    // (AppState.newBackgroundAlertsToNotify()) is what's actually unit-tested, since
    // Toybox.Notifications.showNotification() itself has no test-harness double. The manifest's
    // minSdkVersion is 5.1.0 (Notifications.showNotification's own @since level), so the
    // `Notifications has :showNotification` check below is always true at runtime on any firmware
    // this build can install on — kept as harmless defense-in-depth, mirroring this codebase's existing
    // `Attention has :vibrate` idiom (FaBolusApp.notifyNewAlerts), NOT as a signal of sub-5.1 support.
    function surfaceNewAlertsInBackground() as Void {
        var newOnes = AppState.newBackgroundAlertsToNotify();
        if (newOnes.size() == 0) { return; }
        if (!(Toybox.Notifications has :showNotification)) { return; }
        for (var i = 0; i < newOnes.size(); i += 1) {
            var a = newOnes[i] as Lang.Dictionary;
            Notifications.showNotification("faBolus", a["title"] as Lang.String, null);
        }
    }
}

(:background)
class BgCommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Background.exit(null); }
}
