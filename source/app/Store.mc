using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;

// The Storage keys and who writes each. The app, the glance and the background service run as separate
// processes that share Storage, so every key has exactly one writer: the app writes the plain keys, the
// background service writes the "bg." keys, and readers take whichever copy arrived last.
module Store {
    (:background, :glance)
    const SCHEMA = "v2.schema";
    (:background, :glance)
    const SCHEMA_VERSION = 2;

    // Written by the app.
    (:background, :glance)
    const STATUS = "v2.status";
    (:background, :glance)
    const CONFIG = "v2.config";
    const HISTORY = "v2.history";
    const BOLUS = "v2.bolus";
    const ALERTS_SEEN = "v2.alertsSeen";
    const INTRO_SHOWN = "v2.introShown";
    const REQUEST_SEQ = "v2.requestSeq";

    // Written by the background service.
    (:background, :glance)
    const BG_STATUS = "v2.bg.status";
    (:background, :glance)
    const BG_CONFIG = "v2.bg.config";
    (:background)
    const BG_NOTIFIED = "v2.bg.notified";

    // The first launch of this version clears what the old version stored: none of its keys mean anything
    // to this one, and leaving them would keep its settings and alert history around. Only the app does
    // this; the background service and the glance read only keys of this version.
    function migrate() as Void {
        var v = Storage.getValue(SCHEMA);
        if (!(v instanceof Lang.Number) || v != SCHEMA_VERSION) {
            Storage.clearValues();
            Storage.setValue(SCHEMA, SCHEMA_VERSION);
        }
    }

    // A stored record: a dictionary, or null for anything else.
    (:background, :glance)
    function record(key as Lang.String) as Lang.Dictionary? {
        var v = Storage.getValue(key);
        return (v instanceof Lang.Dictionary) ? v : null;
    }

    // The newer of two stored copies, by when this watch received each ("r").
    (:background, :glance)
    function newer(a as Lang.Dictionary?, b as Lang.Dictionary?) as Lang.Dictionary? {
        if (a == null) { return b; }
        if (b == null) { return a; }
        var ra = a["r"];
        var rb = b["r"];
        var na = (ra instanceof Lang.Number) ? ra : 0;
        var nb = (rb instanceof Lang.Number) ? rb : 0;
        return (nb > na) ? b : a;
    }

    // Saves, reporting whether it worked: Storage throws when it's full.
    (:background)
    function save(key as Lang.String, value as Lang.Object) as Lang.Boolean {
        try {
            Storage.setValue(key, value as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }
}
