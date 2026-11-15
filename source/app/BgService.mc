using Toybox.Application;
using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.Notifications;
using Toybox.System;

// The background service. It runs in its own process with a small memory limit and writes only its own
// keys (BG_STATUS, BG_CONFIG, BG_NOTIFIED, BG_NOTIFIED_AT, BG_SHOWN_GONE, BG_RESULTS).
//
// Every five minutes it republishes the complication, so staleness shows as time passes, and asks the
// phone for a status. When the system hands it a phone message, which it can do with the app open as well
// as closed, it takes that message. Each path ends in Background.exit: a message taken publishes, posts a
// notification for each new alert the phone says to announce, and exits with what the app, if it's open,
// needs to know (exitData). The system ends it after 30 s regardless, and then the app would never be told.
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

    // An answer to the poll. A status the phone sends after a config comes as a message of its own, to the
    // app or to the service woken for it, so nothing waits for it here.
    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void { take(Inbound.dataOf(msg)); }

    // A message that woke the service.
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        Status.load();
        Prefs.load(Status.revision());
        take(Inbound.dataOf(msg));
    }

    // Even a message that changes nothing (a status held on its way here, older than the one held, or what
    // isn't a message at all) ends in finish, so the alerts the held status lists are still considered.
    function take(data as Lang.Object?) as Void { finish(exitData(data, Status.now())); }

    // What the app is told of a message, once it's saved for the app: when the phone sent it (Status.heardTime),
    // as a number, for one that says (a status or bolus outcome), so one Connect IQ held doesn't count as
    // hearing from the phone now; {} for one that doesn't (a config or dismiss result). For one only the app
    // can act on (a chart, or a phone app that can't talk to this one) the message itself, {"at", "m"}, "at"
    // being when the phone sent a chart. Null for one that changes nothing.
    function exitData(data as Lang.Object?, now as Lang.Number) as Lang.Number or Lang.Dictionary or Null {
        var kind = Wire.kindOf(data);
        if (apply(data)) {
            var at = (kind == Wire.STATUS) ? Status.heardTime(Status.sentAt(), now)
                : ((kind == Wire.OUTCOME) ? Inbound.sentTime(Wire.payload(data as Lang.Dictionary), now) : null);
            return (at != null) ? at : {};
        }
        if (kind == Wire.HISTORY || kind == Wire.INCOMPATIBLE || kind == Wire.NEWER || kind == Wire.LEGACY) {
            var at = (kind == Wire.HISTORY) ? Inbound.sentTime(Wire.payload(data as Lang.Dictionary), now) : now;
            return { "at" => (at != null) ? at : 0, "m" => data };
        }
        return null;
    }

    // True when it was a status, config, bolus outcome or dismiss result and it was saved.
    function apply(data as Lang.Object?) as Lang.Boolean {
        if (!(data instanceof Lang.Dictionary)) { return false; }
        var kind = Wire.kindOf(data);
        if (kind == Wire.OUTCOME || kind == Wire.DISMISS_RESULT) { return saveResult(kind, Wire.payload(data)); }
        return Inbound.applyState(kind, data, Status.now(), Store.BG_STATUS, Store.BG_CONFIG);
    }

    // A result is what the user is waiting to see, and the phone sends it only so many times, so it's kept
    // for the app rather than lost. Each gets the next number, and the app applies each number once, in
    // order: replaying an old "delivering" would take a request back out of "check the pump". Only the
    // newest few are kept.
    function saveResult(kind as Lang.Number, p as Lang.Dictionary) as Lang.Boolean {
        var kept = Store.list(Store.BG_RESULTS);
        var last = (kept.size() > 0) ? kept[kept.size() - 1] : null;
        var n = (last instanceof Lang.Dictionary && last["n"] instanceof Lang.Number) ? last["n"] as Lang.Number : 0;
        kept.add({ "n" => n + 1, "k" => kind, "p" => p });
        if (kept.size() > MAX_SAVED_RESULTS) { kept = kept.slice(kept.size() - MAX_SAVED_RESULTS, null); }
        return Store.save(Store.BG_RESULTS, kept);
    }

    const MAX_SAVED_RESULTS = 4;

    function finish(out as Lang.Number or Lang.Dictionary or Null) as Void {
        BgComplication.publish(Status.now());
        notifyNew();
        leave(out);
    }

    // Tells the app, if it's running, to load what was saved, and when the phone was last heard from.
    function leave(out as Lang.Number or Lang.Dictionary or Null) as Void {
        try {
            Background.exit(out as Application.PersistableType);
        } catch (e) {
            // Over the size limit (a chart): the app is told the kind, and asks again.
            var small = (out instanceof Lang.Dictionary) ? { "at" => out["at"], "k" => Wire.kindOf(out["m"] as Lang.Object?) } : null;
            try {
                Background.exit(small as Application.PersistableType);
            } catch (e2) {
                Background.exit(null);
            }
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
