using Toybox.Application.Storage;
using Toybox.Communications as Comm;
using Toybox.Lang;

// What a message from the phone does. The app and the background service both take status and config, and
// the service keeps bolus outcomes and dismiss results for the app; everything else is the app's, because
// it's about what the user is looking at.
module Inbound {
    // A message's data, or null when what the system handed over isn't a phone message. It has handed over
    // null, and reading `data` from that ends the process with an error no catch sees.
    (:background)
    function dataOf(msg as Lang.Object?) as Lang.Object? {
        return (msg instanceof Comm.PhoneAppMessage) ? msg.data : null;
    }

    // The newest saved result applied, kept here as well as in storage: with storage full the stored number
    // isn't written, and every later delivery would replay the results.
    var _resultsRead as Lang.Number = 0;

    function reset() as Void { _resultsRead = 0; }

    // The results the background service was handed instead of the app (BgServiceDelegate.saveResult), each
    // once and in the order the service took them, whichever way the app learns of them.
    function applySavedResults(now as Lang.Number) as Void {
        var saved = Store.list(Store.BG_RESULTS);
        var read = Storage.getValue(Store.BG_RESULTS_READ);
        var last = (read instanceof Lang.Number && read > _resultsRead) ? read : _resultsRead;
        var newest = last;
        for (var i = 0; i < saved.size(); i += 1) {
            var entry = saved[i];
            if (!(entry instanceof Lang.Dictionary)) { continue; }
            var n = entry["n"];
            var p = entry["p"];
            if (!(n instanceof Lang.Number) || n <= newest || !(p instanceof Lang.Dictionary)) { continue; }
            if (entry["k"] == Wire.OUTCOME) {
                BolusFlow.onOutcome(p, now);
            } else if (entry["k"] == Wire.DISMISS_RESULT) {
                Alerts.onDismissResult(p, now);
            }
            newest = n;
        }
        _resultsRead = newest;
        if (newest != last) { Store.save(Store.BG_RESULTS_READ, newest); }
    }

    // What a status the app has just taken means here, whichever process it came through.
    function statusTaken(now as Lang.Number) as Void {
        Alerts.onStatus(now);
        var at = Status.field("glucose", "at");
        var g = Status.glucose();
        if (at != null && g != null) { History.append(at, g); }
    }

    // Applies a status or config and saves it under the caller's own key. True when it was one and it read.
    (:background)
    function applyState(kind as Lang.Number, data as Lang.Dictionary, now as Lang.Number,
                        statusKey as Lang.String, configKey as Lang.String) as Lang.Boolean {
        if (kind == Wire.STATUS) {
            if (!Status.accept(Wire.payload(data), now)) { return false; }
            Status.save(statusKey);
            return true;
        }
        if (kind == Wire.CONFIG) {
            if (!Prefs.accept(Wire.payload(data), now)) { return false; }
            Prefs.save(configKey);
            return true;
        }
        return false;
    }

    // The app's handling. Returns the message's kind.
    function handle(data as Lang.Object?, now as Lang.Number) as Lang.Number {
        var kind = Wire.kindOf(data);
        if (!(data instanceof Lang.Dictionary)) { return kind; }
        if (kind == Wire.LEGACY) {
            Link.heardLegacy(now);
            return kind;
        }
        if (kind == Wire.NEWER || kind == Wire.INCOMPATIBLE) {
            Link.heardNewer(now);
            return kind;
        }
        if (kind == Wire.UNRECOGNIZED || kind == Wire.MALFORMED) { return kind; }
        if (kind == Wire.STATUS || kind == Wire.CONFIG) {
            // One that doesn't read doesn't count as hearing from the phone, so a run of them can't keep the
            // last good status's bolus gate in use. A config carries no sentAt, so it says nothing about when
            // the phone was last there.
            if (!applyState(kind, data, now, Store.STATUS, Store.CONFIG)) { return kind; }
            if (kind == Wire.STATUS) {
                Link.heardAt(Status.heardTime(Status.sentAt(), now), now);
                statusTaken(now);
            }
            return kind;
        }
        var p = Wire.payload(data);
        // A dismiss result carries no sentAt either.
        if (kind == Wire.HISTORY || kind == Wire.OUTCOME) { Link.heardAt(sentTime(p, now), now); }
        if (kind == Wire.HISTORY) {
            History.accept(p);
        } else if (kind == Wire.OUTCOME) {
            BolusFlow.onOutcome(p, now);
        } else if (kind == Wire.DISMISS_RESULT) {
            Alerts.onDismissResult(p, now);
        }
        return kind;
    }

    // When a chart or bolus outcome counts as hearing from the phone, by its sentAt.
    (:background)
    function sentTime(p as Lang.Dictionary, now as Lang.Number) as Lang.Number? {
        return Status.heardTime(Wire.int(p, "sentAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX), now);
    }

    // The status names a config revision the watch doesn't hold: it missed a change, or lost its
    // storage. Polling now, with its own revision, makes the phone send the config.
    function configBehind() as Lang.Boolean {
        var wanted = Status.revision();
        var held = Prefs.revision();
        return wanted != null && (held == null || !wanted.equals(held));
    }
}
