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
    // Read by the background service too, so it doesn't post an alert the app has shown.
    (:background)
    const ALERTS_SEEN = "v2.alertsSeen";
    // When the app last showed each alert in ALERTS_SEEN (id => epoch seconds), so the service can tell that
    // showing apart from a later one.
    (:background)
    const ALERTS_SHOWN_AT = "v2.alertsShownAt";
    // How many times the app has seen each alert the background service notified leave the list since
    // (id => count): a notification stands only for the time an alert was up when it was posted.
    (:background)
    const ALERTS_GONE = "v2.alertsGone";
    const INTRO_SHOWN = "v2.introShown";
    const REQUEST_SEQ = "v2.requestSeq";
    // The number of the newest result in BG_RESULTS the app has applied.
    const BG_RESULTS_READ = "v2.bgResultsRead";

    // Written by the background service.
    (:background, :glance)
    const BG_STATUS = "v2.bg.status";
    (:background, :glance)
    const BG_CONFIG = "v2.bg.config";
    (:background)
    const BG_NOTIFIED = "v2.bg.notified";
    // For each alert in BG_NOTIFIED, its ALERTS_GONE count when it was posted (id => count).
    (:background)
    const BG_NOTIFIED_AT = "v2.bg.notifiedAt";
    // For each alert in ALERTS_SEEN the service has seen leave the list since, the ALERTS_SHOWN_AT of the
    // showing it outlived (id => epoch seconds): that showing no longer counts, though the app's set, kept up
    // to date only while it's open, still names it.
    (:background)
    const BG_SHOWN_GONE = "v2.bg.shownGone";
    // Bolus outcomes and dismiss results the system handed to the service, numbered, for the app.
    (:background)
    const BG_RESULTS = "v2.bg.results";

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

    // A stored list: an array, or empty for anything else.
    (:background)
    function list(key as Lang.String) as Lang.Array {
        var v = Storage.getValue(key);
        return ((v instanceof Lang.Array) ? v : []) as Lang.Array;
    }

    // A stored map: a dictionary, or empty for anything else.
    (:background)
    function map(key as Lang.String) as Lang.Dictionary {
        var v = record(key);
        return (v != null) ? v : {};
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

    // This build, as a record saved by it names it: a newer build can then tell that an earlier one kept
    // the record, by that build's reading of the phone's message.
    (:background, :glance)
    function build() as Lang.String { return AppRevision.SHORT + (AppRevision.DIRTY ? "+" : ""); }

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
