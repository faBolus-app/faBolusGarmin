using Toybox.Lang;

// What a message from the phone does. The app and the background service both take status and config;
// everything else is the app's, because it's about what the user is looking at.
module Inbound {
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
            // last good status's bolus gate in use.
            if (!applyState(kind, data, now, Store.STATUS, Store.CONFIG)) { return kind; }
            Link.heard(now);
            if (kind == Wire.STATUS) {
                Alerts.onStatus(now);
                var at = Status.field("glucose", "at");
                var g = Status.glucose();
                if (at != null && g != null) { History.append(at, g); }
            }
            return kind;
        }
        Link.heard(now);
        var p = Wire.payload(data);
        if (kind == Wire.HISTORY) {
            History.accept(p);
        } else if (kind == Wire.OUTCOME) {
            BolusFlow.onOutcome(p, now);
        } else if (kind == Wire.DISMISS_RESULT) {
            Alerts.onDismissResult(p, now);
        }
        return kind;
    }

    // The status names a config revision the watch doesn't hold: it missed a change, or lost its
    // storage. Polling now, with its own revision, makes the phone send the config.
    function configBehind() as Lang.Boolean {
        var wanted = Status.revision();
        var held = Prefs.revision();
        return wanted != null && (held == null || !wanted.equals(held));
    }
}
