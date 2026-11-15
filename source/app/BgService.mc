using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.Notifications;
using Toybox.System;

// The background service, while the app is closed. It runs in its own process with a small memory limit
// and writes only its own keys (BG_STATUS, BG_CONFIG, BG_NOTIFIED, BG_NOTIFIED_AT, BG_SHOWN_GONE).
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
        // Whatever the watch's Bluetooth flag says: it can say no phone while the phone's messages arrive.
        // With no phone, the listener's onError ends the service.
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

    // A notification for each new alert the phone says should vibrate; a quiet one waits for the app. Not
    // one the open app has already shown (it buzzed then), unless that one left the list and came back
    // while the app was closed. One that couldn't be posted stays new and is tried again next time.
    function notifyNew() as Void {
        if (!(Toybox has :Notifications) || !(Notifications has :showNotification)) { return; }
        var list = Alerts.list();
        var seen = Alerts.notifiedStanding();
        Alerts.noteShownGone(list);
        var due = Alerts.toPost(list, seen, Alerts.appShown());
        var gone = Store.map(Store.ALERTS_GONE);
        var at = Store.map(Store.BG_NOTIFIED_AT);
        var posted = [] as Lang.Array;
        for (var i = 0; i < due.size(); i += 1) {
            var a = due[i] as Lang.Dictionary;
            try {
                post(a);
                var id = Alerts.idOf(a);
                posted.add(id);
                // The notification stands until the app sees the alert leave the list again.
                at[id] = Alerts.goneCount(gone, id);
            } catch (e) {
                // Left new; tried again next time.
            }
        }
        var kept = Alerts.reconciled(list, seen, posted);
        var keptAt = {} as Lang.Dictionary;
        for (var i = 0; i < kept.size(); i += 1) { keptAt[kept[i]] = Alerts.goneCount(at, kept[i] as Lang.String); }
        Store.save(Store.BG_NOTIFIED, kept);
        Store.save(Store.BG_NOTIFIED_AT, keptAt);
    }

    // Separate so tests can record the posts.
    function post(a as Lang.Dictionary) as Void {
        Notifications.showNotification("faBolus", Wire.text(a, "title", "Alert"), null);
    }
}

(:background)
class BgListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Background.exit(null); }
}
