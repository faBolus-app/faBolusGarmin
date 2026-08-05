using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Background;
using Toybox.Time;
using Toybox.System;
using Toybox.Timer;
using Toybox.Attention;
using Toybox.Lang;

// App entry. Glance-first: requests pump status from the phone on launch and every 30s, listens
// for status/bolus updates, and republishes the BG complication so it shows on the watch face.
// A background temporal event refreshes the complication roughly every 5 minutes while the app
// isn't open. Thin remote — the iPhone owns the pump connection.
class FaBolusApp extends App.AppBase {
    private var _timer as Timer.Timer?;
    private var _eating as EatingRelay?;   // wrist eating-sensing relay (phone-gated)
    // True once a real view is on the stack (set in getInitialView). Gates surfacing a background-
    // arrived alert: a CIQ app must not pushView before its first view exists (cold-launch order is
    // onStart → onBackgroundData → getInitialView), so onBackgroundData only vibrates/pushes once this
    // is true; otherwise the alert stays "unseen" and the next foreground statusRead surfaces it.
    private var _foreground as Lang.Boolean = false;

    function initialize() { AppBase.initialize(); _eating = new EatingRelay(); }

    function onStart(state as Lang.Dictionary?) as Void {
        Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
        AppState.loadPersisted();            // show last-known BG instantly (no "--" flash)
        AppState.loadPrefs();                // restore configured screen order + default screen
        BgComplication.publish(null, null, 0);  // re-publish last-known reading to the complication
        requestStatus();
        _timer = new Timer.Timer();
        _timer.start(method(:requestStatus), 15000, true);   // refresh every 15s while open
        registerBackground();
    }

    function onStop(state as Lang.Dictionary?) as Void {
        if (_timer != null) { _timer.stop(); }
        if (_eating != null) { _eating.stop(); }
        _foreground = false;
    }

    function getInitialView() {
        _foreground = true;         // a view is about to be on the stack — safe to surface alerts now
        return Nav.initialView();   // the user-configured default screen
    }

    // Compact BG glance shown in the glance/widget carousel (devices that support glances).
    (:glance)
    function getGlanceView() {
        return [ new FaBolusGlanceView() ];
    }

    // The background service that refreshes the complication when the app is closed.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new BgServiceDelegate() ];
    }

    private function registerBackground() as Void {
        if (!(Toybox has :Background)) { return; }
        // Re-register every launch (registering replaces the schedule). The previous `last == null`
        // guard could skip registration after a sideload update — where the last-event time
        // persisted but the schedule was cleared — leaving the complication with no background
        // refresh at all. 5 min is the minimum interval Garmin allows.
        try {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } catch (e) {
            // Background not permitted on this device/config — foreground updates still work.
        }
    }

    function requestStatus() as Void {
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
    }

    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Lang.Dictionary) {
            // Phone toggles wrist eating-sensing (out-of-band, not a RemoteCommand). Advisory feature.
            var type = data["type"];
            if (type != null && (type as Lang.String).equals("eating_sense")) {
                if (_eating != null) {
                    if (data["on"] == true) { _eating.start(); } else { _eating.stop(); }
                }
                return;
            }
            AppState.handle(data as Lang.Dictionary);
            BgComplication.publishFromState();
            notifyNewAlerts(true);   // foreground: the app is open, so a view is up — safe to surface
            Ui.requestUpdate();
        }
    }

    // When a NEW pump alert arrives, vibrate and show an actionable confirmation to clear it. "New" =
    // an alert identity (AppState.alertIdentity, kind + "-" + id) not in the PERSISTED seen-set — not
    // merely a higher count. The old count comparison missed an alarm that replaced another at the same
    // count and re-fired whenever the list reshuffled; identity tracking fixes both.
    //
    // canSurface is false only when we can't legally pushView yet (a background-arrived alert delivered
    // to onBackgroundData before the first view exists). In that case we do NOTHING — crucially we do
    // NOT mark the alert seen — so it stays new and the next foreground statusRead surfaces it. Vibrate/
    // pushView therefore only ever happen in the foreground; the background never fakes them.
    private function notifyNewAlerts(canSurface as Lang.Boolean) as Void {
        if (!canSurface) { return; }
        var seen = AppState.loadSeenAlerts();
        var firstNew = null;   // most-serious NEW alert (the list is most-serious first)
        var active = [];       // identities currently active, used to rewrite the seen-set
        for (var i = 0; i < AppState.alerts.size(); i += 1) {
            var a = AppState.alerts[i] as Lang.Dictionary;
            var id = AppState.alertIdentity(a);
            active.add(id);
            if (firstNew == null && !AppState.containsStr(seen, id)) { firstNew = a; }
        }
        // Rewrite the seen-set to exactly the active identities: newly-surfaced ones are added, and a
        // cleared alert drops out — so if it re-fires later it counts as new again and re-notifies.
        AppState.saveSeenAlerts(active);
        if (firstNew != null) {
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(75, 400)]);
            }
            Ui.pushView(new Ui.Confirmation("Pump alert: " + firstNew["title"] + " — clear?"),
                        new AlertConfirmDelegate(firstNew["id"], firstNew["kind"]), Ui.SLIDE_UP);
        }
    }

    // Called when the background service exits with data. The 5-minute temporal event fetches fresh
    // status off-screen; BgService forwards ONLY the compact alerts list here (not the full status —
    // its history array can be large and would risk the background-data size limit). We refresh the
    // complication from the persisted reading and re-run the new-alert check. A background SERVICE
    // process cannot vibrate or pushView, so it never surfaces itself — surfacing happens HERE, in the
    // main app, and only once a view exists (_foreground). If we're not foreground yet (cold launch),
    // the alert is left unseen and the next foreground statusRead surfaces it.
    function onBackgroundData(data as App.PersistableType) as Void {
        if (data instanceof Lang.Array) {
            AppState.alerts = AppState.sanitizeAlerts(data as Lang.Array);
        }
        BgComplication.publishFromState();
        notifyNewAlerts(_foreground);
    }
}
