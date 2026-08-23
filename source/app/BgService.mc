using Toybox.System;
using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;

// Background service that refreshes the BG complication while the app is closed. On each
// temporal event it re-publishes the last-known reading (so a newly-added complication isn't
// blank), then asks the phone for a fresh status; when the phone replies it publishes the new
// value directly and exits. If the phone is unreachable it just exits — the persisted value
// stays on the face. Background phone reachability varies, so this is best-effort;
// foreground opens/glances remain the reliable refresh path.
(:background)
class BgServiceDelegate extends System.ServiceDelegate {
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
                Comm.transmit(RemoteComm.statusRead(RemoteComm.newRequestId()), null, new BgCommListener());
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
            // R2-15/VA-16: this service sent a statusRead and must publish + exit ONLY on the matching
            // statusRead reply. A non-statusReply dict (an eating_sense/hr_ctl toggle, a stray bolusStatus
            // echo, etc.) that lands first is IGNORED — return WITHOUT exiting so the service stays alive
            // for the real reply (the system still bounds our total runtime). Exiting on it would drop the
            // fresh read we're waiting for and republish stale state.
            if (!AppState.isStatusReply(data as Lang.Dictionary)) { return; }
            AppState.handle(data as Lang.Dictionary);
            BgComplication.publishFromState();
            // A background service process CANNOT vibrate or pushView, so it must not surface a new
            // alert itself. Instead it hands the freshly-parsed alerts to the main app; the main app's
            // onBackgroundData re-runs the new-alert check and surfaces it at the next foreground
            // moment. Forward ONLY the compact alerts list — NOT the full status (its history array can
            // be large) — to stay within the background-data payload limit.
            Background.exit(AppState.alerts);
            return;
        }
        Background.exit(null);
    }
}

(:background)
class BgCommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Background.exit(null); }
}
