using Toybox.Application.Storage;
using Toybox.Attention;
using Toybox.Lang;
using Toybox.System;

// The alerts the phone holds and has announced, mirrored: the phone is the authority, so the list is
// exactly the status's. The watch only decides when to announce a new one, by the phone's intent for it:
// "alert" is shown and vibrates, "quiet" is shown without vibrating. Do Not Disturb always wins.
//
// Each alert is announced once. The app keeps which ones it has shown (ALERTS_SEEN) and the background
// service which ones it has notified (BG_NOTIFIED); an alert that leaves the list leaves the set too, so
// one that comes back is announced again.
module Alerts {
    const MAX_ANNOUNCED = 4;

    (:background)
    function list() as Lang.Array { return Status.alerts(); }

    (:background)
    function idOf(a as Lang.Dictionary) as Lang.String {
        var id = a["id"];
        return (id instanceof Lang.String) ? id : "";
    }

    (:background)
    function ids(list as Lang.Array) as Lang.Array {
        var out = [] as Lang.Array;
        for (var i = 0; i < list.size(); i += 1) {
            var a = list[i];
            if (a instanceof Lang.Dictionary) { out.add(idOf(a)); }
        }
        return out;
    }

    // The alerts in `list` not in `seen`, in the phone's order (most severe first).
    (:background)
    function unseen(list as Lang.Array, seen as Lang.Array) as Lang.Array {
        var out = [] as Lang.Array;
        for (var i = 0; i < list.size(); i += 1) {
            var a = list[i];
            if (a instanceof Lang.Dictionary && !Wire.contains(seen, idOf(a))) { out.add(a); }
        }
        return out;
    }

    // What to keep as seen: what was seen and is still active, plus what was just announced.
    (:background)
    function reconciled(list as Lang.Array, seen as Lang.Array, announced as Lang.Array) as Lang.Array {
        var active = ids(list);
        var out = [] as Lang.Array;
        for (var i = 0; i < seen.size(); i += 1) {
            var id = seen[i];
            if (id instanceof Lang.String && Wire.contains(active, id) && !Wire.contains(out, id)) { out.add(id); }
        }
        for (var i = 0; i < announced.size(); i += 1) {
            var id = announced[i];
            if (id instanceof Lang.String && !Wire.contains(out, id)) { out.add(id); }
        }
        return out;
    }

    (:background)
    function loadSet(key as Lang.String) as Lang.Array {
        var v = Storage.getValue(key);
        return (v instanceof Lang.Array) ? v as Lang.Array : [];
    }

    // Whether any of `alerts` should vibrate: the phone's intent, and the watch's own settings.
    function shouldVibrate(alerts as Lang.Array) as Lang.Boolean {
        var s = System.getDeviceSettings();
        var dnd = (s has :doNotDisturb) ? s.doNotDisturb : false;
        var vibrateOn = (s has :vibrateOn) ? s.vibrateOn : true;
        if (dnd || !vibrateOn) { return false; }
        for (var i = 0; i < alerts.size(); i += 1) {
            var a = alerts[i];
            if (a instanceof Lang.Dictionary && "alert".equals(Wire.str(a, "intent", 16))) { return true; }
        }
        return false;
    }

    // A critical alert's pattern is longer and stronger than a warning's.
    function vibrate(alerts as Lang.Array) as Void {
        if (!(Attention has :vibrate)) { return; }
        var critical = false;
        for (var i = 0; i < alerts.size(); i += 1) {
            var a = alerts[i];
            if (a instanceof Lang.Dictionary && "critical".equals(Wire.str(a, "severity", 16))) { critical = true; }
        }
        var pattern = critical
            ? [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 400),
               new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 400)]
            : [new Attention.VibeProfile(70, 300), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(70, 300)];
        Attention.vibrate(pattern);
    }

    // MARK: Dismissing. A dismissable pump alert is asked to clear on the pump; the next status says
    // whether it's gone. The phone's answer only says what happened, for a message to the user.

    var _dismissId as Lang.String? = null;
    var _dismissNote as Lang.String? = null;
    // Cleared on the pump, with when (parallel arrays): hidden while statuses still list them, for a while.
    var _cleared as Lang.Array = [];
    var _clearedAt as Lang.Array = [];
    // The status the phone sends right after a clear can come before the pump's next alert read, so it may
    // still list the alert. Past this, a status that lists it is believed.
    const CLEARED_SEC = 60;

    function dismissable(a as Lang.Dictionary) as Lang.Boolean { return Wire.bool(a, "dismissable") == true; }

    // Sends the dismiss. False when the phone isn't connected; nothing is hidden then.
    function dismiss(alertId as Lang.String, now as Lang.Number) as Lang.Boolean {
        var id = Link.newRoutineId(now);
        var sent = Link.transmit(Wire.dismiss(id, alertId), new SendListener(new Lang.Method(Alerts, :sendFailed), id), now);
        _dismissId = sent ? id : null;
        _dismissNote = sent ? "Clearing…" : "Phone not connected — not cleared";
        return sent;
    }

    // Only the latest dismiss's failure is shown.
    function sendFailed(id as Lang.String) as Void {
        var mine = _dismissId;
        if (mine == null || !mine.equals(id)) { return; }
        _dismissId = null;
        _dismissNote = "Not sent — try again";
    }

    // The phone's answer to this watch's latest dismiss; an answer to an earlier one is ignored.
    function onDismissResult(p as Lang.Dictionary, now as Lang.Number) as Lang.Boolean {
        var id = Wire.str(p, "requestId", Wire.MAX_ID);
        var alertId = Wire.str(p, "alertId", Wire.MAX_ID);
        var result = Wire.str(p, "result", 16);
        var mine = _dismissId;
        if (id == null || alertId == null || result == null || mine == null || !id.equals(mine)) { return false; }
        _dismissId = null;
        if (result.equals("cleared")) {
            if (!Wire.contains(_cleared, alertId)) {
                _cleared.add(alertId);
                _clearedAt.add(now);
            }
            _dismissNote = null;
        } else if (result.equals("refused")) {
            _dismissNote = "Pump didn't clear it";
        } else if (result.equals("unsupported")) {
            _dismissNote = "Clear it on the pump";
        } else if (result.equals("notFound")) {
            _dismissNote = null;
        } else {
            _dismissNote = "No answer from pump";
        }
        return true;
    }

    // A new status is the authority on what's active, except for an alert cleared within CLEARED_SEC that
    // it still lists. One it leaves out is gone.
    function onStatus(now as Lang.Number) as Void {
        var active = ids(list());
        var keep = [] as Lang.Array;
        var keepAt = [] as Lang.Array;
        for (var i = 0; i < _cleared.size(); i += 1) {
            var at = _clearedAt[i] as Lang.Number;
            var id = _cleared[i] as Lang.String;
            if (Wire.contains(active, id) && now - at < CLEARED_SEC) {
                keep.add(id);
                keepAt.add(at);
            }
        }
        _cleared = keep;
        _clearedAt = keepAt;
    }

    // Of `fresh`, those the background service hasn't already notified: they vibrate when the app shows
    // them, and the others are only shown.
    function toVibrate(fresh as Lang.Array) as Lang.Array { return unseen(fresh, loadSet(Store.BG_NOTIFIED)); }

    // The list as shown: the status's, less what the pump has just confirmed cleared.
    function shown() as Lang.Array {
        var all = list();
        if (_cleared.size() == 0) { return all; }
        var out = [] as Lang.Array;
        for (var i = 0; i < all.size(); i += 1) {
            var a = all[i];
            if (a instanceof Lang.Dictionary && !Wire.contains(_cleared, idOf(a))) { out.add(a); }
        }
        return out;
    }

    // The alert shown now under `id`, or null once it's gone.
    function current(id as Lang.String) as Lang.Dictionary? {
        var all = shown();
        for (var i = 0; i < all.size(); i += 1) {
            var a = all[i];
            if (a instanceof Lang.Dictionary && idOf(a).equals(id)) { return a; }
        }
        return null;
    }

    function note() as Lang.String? { return _dismissNote; }

    function reset() as Void {
        _dismissId = null;
        _dismissNote = null;
        _cleared = [];
        _clearedAt = [];
    }
}
