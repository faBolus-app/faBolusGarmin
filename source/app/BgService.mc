using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.Notifications;
using Toybox.System;

// The background service, while the app is closed. It runs in its own process with a small memory limit
// and writes only its own keys (BG_STATUS, BG_CONFIG, BG_NOTIFIED).
//
// Every five minutes it republishes the complication, so staleness shows as time passes, and asks the
// phone for a status. When the phone sends a message while the app is closed, the system wakes it with
// that message. Either way it publishes, posts a notification for each new alert the phone says to
// announce, and exits; the system ends it after 30 s regardless.
(:background, :typecheck(disableGlanceCheck))
class BgServiceDelegate extends System.ServiceDelegate {
    function initialize() { ServiceDelegate.initialize(); }

    function onTemporalEvent() as Void {
        var now = Status.now();
        Status.load();
        Prefs.load(Status.revision());
        BgComplication.publish(now);
        if (!System.getDeviceSettings().phoneConnected) {
            Background.exit(null);
            return;
        }
        Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
        try {
            Comm.transmit(Wire.poll(Prefs.revision(), null, false, false) as Comm.TransmitType, null, new BgListener());
        } catch (e) {
            Background.exit(null);
        }
    }

    // The answers to the poll: a config (when the poll named another revision) is saved, and the service
    // keeps waiting for the status, which ends it. Anything else is ignored.
    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (apply(data) && Wire.kindOf(data) == Wire.STATUS) { finish(); }
    }

    // A message that woke the service. There's nothing to wait for after it.
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        Status.load();
        Prefs.load(Status.revision());
        if (apply(msg.data)) {
            finish();
        } else {
            Background.exit(null);
        }
    }

    // True when it was a status or config and it read.
    function apply(data as Lang.Object?) as Lang.Boolean {
        if (!(data instanceof Lang.Dictionary)) { return false; }
        return Inbound.applyState(Wire.kindOf(data), data, Status.now(), Store.BG_STATUS, Store.BG_CONFIG);
    }

    function finish() as Void {
        BgComplication.publish(Status.now());
        notifyNew();
        // Tells the app, if it's running, to load what was saved.
        try {
            Background.exit(true);
        } catch (e) {
            Background.exit(null);
        }
    }

    // A notification for each new alert the phone says should vibrate; a quiet one waits for the app. One
    // that couldn't be posted stays new and is tried again next time.
    function notifyNew() as Void {
        if (!(Toybox has :Notifications) || !(Notifications has :showNotification)) { return; }
        var list = Alerts.list();
        var seen = Alerts.loadSet(Store.BG_NOTIFIED);
        var fresh = Alerts.unseen(list, seen);
        var posted = [] as Lang.Array;
        for (var i = 0; i < fresh.size(); i += 1) {
            var a = fresh[i] as Lang.Dictionary;
            if (!Wire.text(a, "intent", "").equals("alert")) { continue; }
            try {
                Notifications.showNotification("faBolus", Wire.text(a, "title", "Alert"), null);
                posted.add(Alerts.idOf(a));
            } catch (e) {
                // Left new; tried again next time.
            }
        }
        Store.save(Store.BG_NOTIFIED, Alerts.reconciled(list, seen, posted));
    }
}

(:background)
class BgListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Background.exit(null); }
}
