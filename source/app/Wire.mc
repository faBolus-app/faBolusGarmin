using Toybox.Lang;

// The phone↔remote protocol, version 2, as the watch speaks it. contract/ (vendored from faBolus at
// contract/PIN) is the reference: every message here is tested against its golden fixtures.
//
// A message is {"version": 2, "kind": ..., "payload": {...}}. There are no floats on the wire: insulin is
// in milliunits and the carb ratio in milligrams per unit, so the watch's 32-bit Float never touches a dose.
module Wire {
    (:background, :glance)
    const VERSION = 2;

    // What an inbound message is.
    (:background)
    enum {
        UNRECOGNIZED = 0,
        STATUS = 1,
        CONFIG = 2,
        HISTORY = 3,
        OUTCOME = 4,
        DISMISS_RESULT = 5,
        INCOMPATIBLE = 6,
        // From the old phone app (version 1).
        LEGACY = 7,
        // From a newer phone app.
        NEWER = 8,
        // Version 2, but a kind the phone doesn't send or a payload that isn't an object.
        MALFORMED = 9
    }

    // Every kind version 1 had, so a message from the old phone app is recognized rather than ignored.
    (:background)
    const LEGACY_KINDS = ["statusRead", "bolusRequest", "bolusConfirm", "bolusStatus", "cancelBolus",
                          "dismissAlert", "dismissAck", "suspendPump", "resumePump"];

    (:background)
    function kindOf(data as Lang.Object?) as Lang.Number {
        if (!(data instanceof Lang.Dictionary)) { return UNRECOGNIZED; }
        var version = data["version"];
        var kind = data["kind"];
        if (version == null || (version instanceof Lang.Number && version == 1)) {
            if (kind instanceof Lang.String && contains(LEGACY_KINDS, kind)) { return LEGACY; }
            return UNRECOGNIZED;
        }
        if (!(version instanceof Lang.Number)) { return UNRECOGNIZED; }
        if (version > VERSION) { return NEWER; }
        if (version != VERSION) { return UNRECOGNIZED; }
        if (!(data["payload"] instanceof Lang.Dictionary) || !(kind instanceof Lang.String)) { return MALFORMED; }
        if (kind.equals("status")) { return STATUS; }
        if (kind.equals("config")) { return CONFIG; }
        if (kind.equals("history")) { return HISTORY; }
        if (kind.equals("bolusOutcome")) { return OUTCOME; }
        if (kind.equals("dismissResult")) { return DISMISS_RESULT; }
        if (kind.equals("incompatible")) { return INCOMPATIBLE; }
        return MALFORMED;
    }

    (:background)
    function payload(data as Lang.Dictionary) as Lang.Dictionary {
        var p = data["payload"];
        return (p instanceof Lang.Dictionary) ? p : {};
    }

    // MARK: Reading fields. Each returns null for a value that is absent, of the wrong type or out of
    // range, so a bad value is never used as if it were good.

    (:background, :glance)
    function int(d as Lang.Dictionary, key as Lang.String, lo as Lang.Number, hi as Lang.Number) as Lang.Number? {
        var v = d[key];
        if (!(v instanceof Lang.Number)) { return null; }
        return (v >= lo && v <= hi) ? v : null;
    }

    (:background, :glance)
    function str(d as Lang.Dictionary, key as Lang.String, max as Lang.Number) as Lang.String? {
        var v = d[key];
        if (!(v instanceof Lang.String)) { return null; }
        return (v.length() <= max) ? v : null;
    }

    (:background, :glance)
    function bool(d as Lang.Dictionary, key as Lang.String) as Lang.Boolean? {
        var v = d[key];
        return (v instanceof Lang.Boolean) ? v : null;
    }

    (:background, :glance)
    function obj(d as Lang.Dictionary, key as Lang.String) as Lang.Dictionary? {
        var v = d[key];
        return (v instanceof Lang.Dictionary) ? v : null;
    }

    // A string field, or `otherwise`.
    (:background)
    function text(d as Lang.Dictionary, key as Lang.String, otherwise as Lang.String) as Lang.String {
        var v = d[key];
        return (v instanceof Lang.String) ? v : otherwise;
    }

    (:background)
    function arr(d as Lang.Dictionary, key as Lang.String, max as Lang.Number) as Lang.Array? {
        var v = d[key];
        if (!(v instanceof Lang.Array)) { return null; }
        return (v.size() <= max) ? v : null;
    }

    // A token from a fixed set, or null.
    (:background, :glance)
    function token(d as Lang.Dictionary, key as Lang.String, allowed as Lang.Array) as Lang.String? {
        var v = str(d, key, 32);
        return (v != null && contains(allowed, v)) ? v : null;
    }

    (:background, :glance)
    function contains(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            var e = list[i];
            if (e instanceof Lang.String && e.equals(v)) { return true; }
        }
        return false;
    }

    // Limits, the same as the phone's (RemoteProtocol.WireLimits).
    (:background, :glance)
    const EPOCH_MIN = 1577836800;
    (:background, :glance)
    const EPOCH_MAX = 2147483647;
    (:background, :glance)
    const MAX_MU = 1000000;
    (:background, :glance)
    const MAX_GLUCOSE = 1000;
    (:background, :glance)
    const MAX_ID = 64;

    // MARK: Building what the watch sends.

    function envelope(kind as Lang.String, body as Lang.Dictionary) as Lang.Dictionary {
        return { "version" => VERSION, "kind" => kind, "payload" => body };
    }

    // Asks for a status. Names the config revision the watch holds (absent when it has none) and the bolus
    // request it is waiting on, so the phone resends what a lost message carried.
    (:background)
    function poll(revision as Lang.String?, awaiting as Lang.String?, history as Lang.Boolean,
                  freshGlucose as Lang.Boolean) as Lang.Dictionary {
        var body = { "history" => history, "freshGlucose" => freshGlucose, "appVersion" => AppVersion.NAME };
        if (revision != null) { body["configRevision"] = revision; }
        if (awaiting != null) { body["awaiting"] = awaiting; }
        return { "version" => VERSION, "kind" => "poll", "payload" => body };
    }

    // What the phone may ask the user to confirm before a dose goes (a refused outcome's `confirm`), and a
    // new request names once they went on (`confirmed`).
    const CONFIRMATIONS = ["tooManyBoluses", "maxHourlyBolus", "lowInsulin"];

    // `confirmed`, when not empty, names what the user confirmed for this dose.
    function bolusUnits(requestId as Lang.String, sentAt as Lang.Number, milliunits as Lang.Number,
                        confirmed as Lang.Array) as Lang.Dictionary {
        var body = {
            "requestId" => requestId, "sentAt" => sentAt, "mode" => "units", "mU" => milliunits,
            "includeStaleGlucose" => false
        };
        if (confirmed.size() > 0) { body["confirmed"] = confirmed; }
        return envelope("bolus", body);
    }

    // `glucose` is the reading the estimate used, absent when it used none, or with `declineCorrection` the
    // one the user chose carbs only for when asked whether to correct from it; `includeStale` is the user's
    // choice, for this attempt, to correct from a stale reading.
    function bolusCarbs(requestId as Lang.String, sentAt as Lang.Number, carbs as Lang.Number,
                        estimateMilliunits as Lang.Number, glucose as Lang.Number?,
                        includeStale as Lang.Boolean, confirmed as Lang.Array,
                        declineCorrection as Lang.Boolean) as Lang.Dictionary {
        return bolusCalculator(requestId, sentAt, carbs, null, estimateMilliunits, glucose, includeStale, confirmed,
                               declineCorrection);
    }

    // A calculator request: its food entry is `carbs` grams or, with carbs off on the pump, `foodMU`
    // milliunits of insulin; one of the two goes.
    function bolusCalculator(requestId as Lang.String, sentAt as Lang.Number, carbs as Lang.Number?,
                             foodMU as Lang.Number?, estimateMilliunits as Lang.Number, glucose as Lang.Number?,
                             includeStale as Lang.Boolean, confirmed as Lang.Array,
                             declineCorrection as Lang.Boolean) as Lang.Dictionary {
        var body = {
            "requestId" => requestId, "sentAt" => sentAt, "mode" => "carbs",
            "estimateMU" => estimateMilliunits, "includeStaleGlucose" => includeStale
        };
        if (foodMU != null) { body["foodMU"] = foodMU; } else { body["carbsG"] = carbs != null ? carbs : 0; }
        if (glucose != null) { body["glucoseMgdl"] = glucose; }
        if (confirmed.size() > 0) { body["confirmed"] = confirmed; }
        if (declineCorrection) { body["declineCorrection"] = true; }
        return envelope("bolus", body);
    }

    // The confirmation tokens in a list, each once, or null when any isn't one.
    function tokens(d as Lang.Dictionary, key as Lang.String, allowed as Lang.Array) as Lang.Array? {
        var list = arr(d, key, allowed.size());
        if (list == null) { return null; }
        var out = [] as Lang.Array;
        for (var i = 0; i < list.size(); i += 1) {
            var e = list[i];
            if (!(e instanceof Lang.String) || !contains(allowed, e) || contains(out, e)) { return null; }
            out.add(e);
        }
        return out;
    }

    function cancel(requestId as Lang.String, bolusRequestId as Lang.String?) as Lang.Dictionary {
        var body = { "requestId" => requestId };
        if (bolusRequestId != null) { body["bolusRequestId"] = bolusRequestId; }
        return envelope("cancel", body);
    }

    function dismiss(requestId as Lang.String, alertId as Lang.String) as Lang.Dictionary {
        return envelope("dismiss", { "requestId" => requestId, "alertId" => alertId });
    }
}
