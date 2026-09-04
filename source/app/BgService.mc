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
    // The requestId minted for THIS service's statusRead request, retained so onPhoneMessage can
    // accept ONLY the correlated reply (the phone echoes it back). Same instance handles both callbacks.
    var mintedReqId as Lang.String? = null;

    function initialize() { ServiceDelegate.initialize(); }

    function onTemporalEvent() as Void {
        // The background service is a SEPARATE process from the foreground app — its AppState
        // starts at compile-time defaults. Restore the persisted prefs (staleness policy, display unit,
        // etc.) BEFORE the first publish so the "keep last-known reading" republish (and any "--"/stale
        // rendering) uses the phone-configured policy, not the defaults (e.g. a wrong staleSec would
        // mis-judge whether the last reading should show as stale).
        AppState.loadPrefs();
        BgComplication.publish(null, null, 0);   // keep last-known reading visible (or "--" if stale)

        if (System.getDeviceSettings().phoneConnected) {
            // This reply uses the SAME foreground-style
            // Comm.registerForPhoneAppMessages the app itself uses, inside the temporal event's
            // ~30s-bounded runtime window (the system terminates the service after ~30s regardless of
            // whether a reply arrived — see the onTemporalEvent try/catch below, which exits on any
            // failure). This is the ACCEPTED INTERIM best-effort bound: a reply that lands after the
            // window closes is simply missed (no crash, no stuck service — the next ~5-min temporal
            // event tries again). The more-robust push-wake is
            // Background.registerForPhoneAppMessageEvent (onPhoneAppMessage below), which doesn't
            // depend on the service's own bounded runtime.
            Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
            try {
                // Retain the minted id so we accept ONLY the phone's correlated reply (it echoes it).
                // ROUTINE mint (fires every ~5-min temporal event) — see
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
            // This service sent a statusRead and must publish + exit ONLY on the CORRELATED
            // reply — the phone echoes our minted requestId, so we match on it (falling back to the kind
            // discriminator for a legacy phone that doesn't echo). A non-reply dict (a stray bolusStatus
            // echo, etc.) OR a reply carrying a DIFFERENT requestId is IGNORED —
            // return WITHOUT exiting so the service stays alive for the real reply (the system still bounds
            // our total runtime). Exiting on it would drop the fresh read we're waiting for and republish stale.
            if (!AppState.isCorrelatedStatusReply(data as Lang.Dictionary, mintedReqId)) { return; }
            applyBackgroundStatus(data as Lang.Dictionary);
            // Background.exit's own doc documents an ExitDataSizeLimitException at ~8 KB ("the
            // process will not exit and should attempt to call Background.exit() again with less
            // data") — alertsForBackgroundExit() already budgets defensively under that limit, but the
            // fallback below is belt-and-suspenders for an unanticipated overshoot: Background.exit(null)
            // guarantees the exit ALWAYS completes rather than the temporal event silently expiring
            // unconsumed.
            try {
                Background.exit(AppState.alertsForBackgroundExit(AppState.alerts));
            } catch (e) {
                Background.exit(null);
            }
            return;
        }
        Background.exit(null);
    }

    // Event-driven push-wake. When the app is CLOSED and the phone pushes a fresh
    // status (GarminRemoteBridge on a new CGM value / critical alert), the system wakes THIS background
    // service via Background.registerForPhoneAppMessageEvent (registered in FaBolusApp.registerBackground)
    // and delivers the pushed message here — refreshing the wrist immediately instead of waiting for the
    // next ~5-min temporal poll. This is a FRESH service process, so its
    // AppState starts at compile-time defaults: restore the persisted prefs FIRST (mirrors
    // onTemporalEvent), then route the push through the SAME correlate→handle→publish→surface→exit path as
    // onPhoneMessage. A push-wake sent no request (mintedReqId == null) so isHandleablePush accepts a
    // `kind=="statusRead"` push via the kind fallback. A malformed / non-statusRead push changes nothing
    // and does NOT exit early (stays alive; the system bounds the wake), exactly like onPhoneMessage. The
    // background service CANNOT vibrate/pushView — a critical alert surfaces only via the
    // Toybox.Notifications dedup path in surfaceNewAlertsInBackground (never a dose).
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        AppState.loadPrefs();
        var data = msg.data;
        if (!AppState.isHandleablePush(data, mintedReqId)) { return; }   // no state change, no early exit
        applyBackgroundStatus(data as Lang.Dictionary);
        try {
            Background.exit(AppState.alertsForBackgroundExit(AppState.alerts));
        } catch (e) {
            Background.exit(null);
        }
    }

    // Shared parse→publish→surface body for a correlated background status message (onPhoneMessage +
    // onPhoneAppMessage). A background service process CANNOT vibrate or pushView (Toybox.Attention isn't a
    // documented background runtime context, and WatchUi.pushView() explicitly throws
    // Lang.OperationNotAllowedException when called from background), so the
    // FULL in-app confirm-to-clear surface still can't happen here. But it CAN show a system
    // notification (Toybox.Notifications.showNotification) — so a critical pump alert is not left completely
    // silent on the wrist while the app is suspended/closed. This is an ADDITIVE early signal only, tracked
    // via its own dedup set (AppState.pendingBgNotifyAlerts() / reconciledBgNotifiedAlerts()); it does not
    // mark anything "seen" for the main app's own notifyNewAlerts(), which still runs its full
    // vibrate+confirm flow the next time a view exists.
    function applyBackgroundStatus(data as Lang.Dictionary) as Void {
        AppState.handle(data);
        BgComplication.publishFromState();
        surfaceNewAlertsInBackground();
    }

    // Show a system notification for every alert AppState.pendingBgNotifyAlerts() reports as
    // not-yet-background-notified. Non-private (mirroring this codebase's existing test-only-seam
    // convention, e.g. FaBolusApp.scheduleCount()) so BgCriticalSurfaceTest.mc
    // could drive it directly if a future change makes that useful; today the pure dedup logic it wraps
    // (AppState.pendingBgNotifyAlerts() / AppState.reconciledBgNotifiedAlerts()) is what's actually unit-
    // tested, since Toybox.Notifications.showNotification() itself has no test-harness double. The
    // manifest's minSdkVersion is 5.1.0 (Notifications.showNotification's own @since level), so the
    // `Notifications has :showNotification` check below is always true at runtime on any firmware
    // this build can install on — kept as harmless defense-in-depth, mirroring this codebase's existing
    // `Attention has :vibrate` idiom (FaBolusApp.notifyNewAlerts), NOT as a signal of sub-5.1 support.
    //
    // This is the SOLE unguarded background exit path — the OLD code eagerly persisted the entire
    // active set as "already notified" (AppState.newBackgroundAlertsToNotify()) BEFORE attempting any
    // Notifications.showNotification() call, so a single throw both permanently dedup-suppressed every
    // alert in the batch (no self-heal — the background system-notification surface for critical alerts
    // silently defeated) AND, since nothing here was wrapped, propagated out of onPhoneMessage and
    // skipped its Background.exit() call entirely.
    // Fixed by trying EACH notification independently (a throw for one alert must not affect
    // the others) and persisting the dedup set only AFTER the attempts, restricted to what actually
    // posted (see AppState.reconciledBgNotifiedAlerts's own doc) — a failed post is left pending and
    // retried on the next temporal-event/phone-message tick instead of being dropped forever.
    function surfaceNewAlertsInBackground() as Void {
        var pending = AppState.pendingBgNotifyAlerts();
        if (pending.size() == 0) { return; }
        if (!(Toybox.Notifications has :showNotification)) { return; }
        var presented = [];
        for (var i = 0; i < pending.size(); i += 1) {
            var a = pending[i] as Lang.Dictionary;
            // Honor the phone-synced alert-intensity mode in the CLOSED-app path
            // too — in Silent mode the watch stays quiet (phone is the sole alerting surface), except the
            // opt-in critical-override wrist fallback. A suppressed alert is left OUT of `presented`, so it
            // stays pending (never marked notified) and would surface if the user later leaves Silent —
            // it is not permanently dropped. "vibrate"/"audible" modes surface as before.
            if (!AppState.shouldSurfaceInBackground(AppState.alertSeverityTier(a),
                    AppState.alertIntensityMode, AppState.alertCriticalOverridesDnd)) {
                continue;
            }
            try {
                Notifications.showNotification("faBolus", a["title"] as Lang.String, null);
                presented.add(AppState.alertIdentity(a));
            } catch (e) {
                // Deliberately NOT added to `presented`: reconciledBgNotifiedAlerts() below will NOT mark
                // this alert notified, so it is retried next cycle rather than permanently suppressed.
            }
        }
        // Persist EXACTLY (previously-notified ∩ still-active) ∪ presented-this-batch — ALWAYS, even when
        // `presented` ends up empty (every attempt threw), so a cleared alert still drops out (a re-fire
        // notifies again), while an alert whose post failed is never marked notified.
        AppState.saveBgNotifiedAlerts(AppState.reconciledBgNotifiedAlerts(presented));
    }
}

(:background)
class BgCommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Background.exit(null); }
}
