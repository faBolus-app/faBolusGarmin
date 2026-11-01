using Toybox.Lang;

// The watch's preferences, set on the phone and sent as the config message: in full when the watch
// connects, on any change, and whenever the watch's poll names a revision other than the phone's.
//
// The revision is the phone's digest of the content, so the watch only ever compares it for equality.
// Until a config arrives every preference has its default, and bolusing is off.
module Prefs {
    (:background, :glance)
    var _c as Lang.Dictionary? = null;
    (:background, :glance)
    var _r as Lang.Number = 0;

    (:background)
    const SCREENS = ["glance", "glucose", "clock", "bolusonly", "alerts", "history", "details"];
    (:background)
    const DETAILS = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus",
                     "maxBasal", "autoCorrection"];
    (:background)
    const SLOTS = ["iob", "reservoir", "battery", "basal"];
    (:background)
    const CHART_HOURS = [3, 6, 12, 24];

    // Takes a config payload. Returns false, changing nothing, when it doesn't read: a config is used
    // whole or not at all, so the watch never mixes two of them.
    (:background)
    function accept(p as Lang.Dictionary, receivedAt as Lang.Number) as Lang.Boolean {
        var clean = cleaned(p);
        if (clean == null) { return false; }
        _c = clean;
        _r = receivedAt;
        return true;
    }

    (:background)
    function cleaned(p as Lang.Dictionary) as Lang.Dictionary? {
        var revision = Wire.str(p, "revision", Wire.MAX_ID);
        var bolus = Wire.obj(p, "bolus");
        var screens = Wire.obj(p, "screens");
        var complication = Wire.obj(p, "complication");
        var glucose = Wire.obj(p, "glucose");
        var windows = Wire.obj(p, "freshness");
        if (windows == null || revision == null || bolus == null || screens == null || complication == null || glucose == null) {
            return null;
        }
        var enabled = Wire.bool(bolus, "enabled");
        var readOnly = Wire.bool(bolus, "readOnly");
        var mode = Wire.token(bolus, "defaultMode", ["carbs", "units"]);
        var unitsStep = Wire.int(bolus, "unitsStepMU", 10, 10000);
        var carbStep = Wire.int(bolus, "carbStepG", 1, 50);
        var order = tokens(Wire.arr(screens, "order", 32), SCREENS);
        var first = Wire.token(screens, "default", SCREENS);
        var details = tokens(Wire.arr(p, "details", 32), DETAILS);
        var hours = numbers(Wire.arr(p, "chartHours", 4), CHART_HOURS);
        var slots = tokens(Wire.arr(complication, "slots", 3), SLOTS);
        var labels = Wire.bool(complication, "labels");
        var unit = Wire.token(glucose, "unit", ["mgdl", "mmol"]);
        var stale = Wire.int(glucose, "staleMinutes", 0, 60);
        var includable = Wire.int(glucose, "includableMinutes", 0, 240);
        var floor = Wire.int(glucose, "plotFloor", 0, 400);
        var ceiling = Wire.int(glucose, "plotCeiling", 100, 600);
        var iobMinutes = Wire.int(windows as Lang.Dictionary, "iobMinutes", 0, 60);
        var therapyMinutes = Wire.int(windows as Lang.Dictionary, "therapyMinutes", 0, 240);
        var statusMinutes = Wire.int(windows as Lang.Dictionary, "pumpStatusMinutes", 0, 240);
        if (enabled == null || readOnly == null || mode == null || unitsStep == null || carbStep == null
            || labels == null || order == null || order.size() == 0 || first == null || !Wire.contains(order, first)
            || details == null || hours == null || hours.size() == 0 || slots == null
            || unit == null || stale == null || includable == null || iobMinutes == null || therapyMinutes == null || statusMinutes == null || floor == null || ceiling == null || floor >= ceiling) {
            return null;
        }
        var out = {
            "revision" => revision, "bolusEnabled" => enabled, "readOnly" => readOnly, "defaultMode" => mode,
            "unitsStepMU" => unitsStep, "carbStepG" => carbStep, "screenOrder" => order, "defaultScreen" => first,
            "details" => details, "chartHours" => hours,
            "complicationSlots" => slots, "complicationLabels" => labels, "glucoseUnit" => unit, "staleMinutes" => stale, "includableMinutes" => includable, "iobMinutes" => iobMinutes, "therapyMinutes" => therapyMinutes,
            "pumpStatusMinutes" => statusMinutes,
            "plotFloor" => floor, "plotCeiling" => ceiling
        } as Lang.Dictionary;
        // Absent: never hide a stale reading.
        var hide = Wire.int(glucose, "hideDelayMinutes", 0, 1440);
        if (hide != null) { out["hideDelayMinutes"] = hide; }
        return out;
    }

    // The strings of `list` that are in `allowed`, in order; null when `list` is null or holds anything
    // else, or a value twice.
    (:background)
    function tokens(list as Lang.Array?, allowed as Lang.Array) as Lang.Array? {
        if (list == null) { return null; }
        var out = [] as Lang.Array;
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (!(v instanceof Lang.String) || !Wire.contains(allowed, v) || Wire.contains(out, v)) { return null; }
            out.add(v);
        }
        return out;
    }

    (:background)
    function numbers(list as Lang.Array?, allowed as Lang.Array) as Lang.Array? {
        if (list == null) { return null; }
        var out = [] as Lang.Array;
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (!(v instanceof Lang.Number) || allowed.indexOf(v) < 0 || out.indexOf(v) >= 0) { return null; }
            out.add(v);
        }
        return out;
    }

    // MARK: Storage. The app saves to CONFIG, the background service to BG_CONFIG.

    (:background)
    function save(key as Lang.String) as Void {
        var c = _c;
        if (c != null) { Store.save(key, { "c" => c, "r" => _r }); }
    }

    // Loads the config matching the status's revision when one does, else the newer copy.
    (:background, :glance)
    function load(statusRevision as Lang.String?) as Void {
        var a = Store.record(Store.CONFIG);
        var b = Store.record(Store.BG_CONFIG);
        var rec = null;
        if (statusRevision != null) {
            if (revisionOf(a) != null && statusRevision.equals(revisionOf(a))) { rec = a; }
            else if (revisionOf(b) != null && statusRevision.equals(revisionOf(b))) { rec = b; }
        }
        if (rec == null) { rec = Store.newer(a, b); }
        if (rec == null) { return; }
        var c = rec["c"];
        var r = rec["r"];
        if (c instanceof Lang.Dictionary && r instanceof Lang.Number) {
            _c = c;
            _r = r;
        }
    }

    (:background, :glance)
    function revisionOf(rec as Lang.Dictionary?) as Lang.String? {
        if (rec == null) { return null; }
        var c = rec["c"];
        if (!(c instanceof Lang.Dictionary)) { return null; }
        var v = c["revision"];
        return (v instanceof Lang.String) ? v : null;
    }

    // For tests: back to the defaults, as after a storage wipe.
    function clear() as Void {
        _c = null;
        _r = 0;
    }

    // MARK: Reading. Each has the default the watch uses before a config arrives.

    (:background, :glance)
    function revision() as Lang.String? {
        var c = _c;
        if (c == null) { return null; }
        var v = c["revision"];
        return (v instanceof Lang.String) ? v : null;
    }

    (:background, :glance)
    function value(key as Lang.String) as Lang.Object? {
        var c = _c;
        return (c == null) ? null : c[key] as Lang.Object?;
    }

    (:background, :glance)
    function flag(key as Lang.String, otherwise as Lang.Boolean) as Lang.Boolean {
        var v = value(key);
        return (v instanceof Lang.Boolean) ? v : otherwise;
    }

    (:background, :glance)
    function number(key as Lang.String, otherwise as Lang.Number) as Lang.Number {
        var v = value(key);
        return (v instanceof Lang.Number) ? v : otherwise;
    }

    (:background, :glance)
    function text(key as Lang.String, otherwise as Lang.String) as Lang.String {
        var v = value(key);
        return (v instanceof Lang.String) ? v : otherwise;
    }

    (:background)
    function list(key as Lang.String, otherwise as Lang.Array) as Lang.Array {
        var v = value(key);
        return (v instanceof Lang.Array) ? v : otherwise;
    }

    // Off until the phone turns it on.
    function bolusEnabled() as Lang.Boolean { return flag("bolusEnabled", false); }
    function readOnly() as Lang.Boolean { return flag("readOnly", false); }
    function defaultMode() as Lang.String { return text("defaultMode", "carbs"); }
    function unitsStep() as Lang.Number { return number("unitsStepMU", 50); }
    function carbStep() as Lang.Number { return number("carbStepG", 5); }
    function screenOrder() as Lang.Array { return list("screenOrder", ["glance", "alerts", "history", "details"]); }
    function defaultScreen() as Lang.String { return text("defaultScreen", "glance"); }
    function details() as Lang.Array {
        return list("details", ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target",
                                "maxBolus"]);
    }
    function chartHours() as Lang.Array { return list("chartHours", [3, 6, 12, 24]); }
    (:background)
    function complicationSlots() as Lang.Array { return list("complicationSlots", ["iob", "reservoir", "battery"]); }
    // Each slot's label names what it shows; off (the default), the value alone.
    (:background)
    function complicationLabels() as Lang.Boolean { return flag("complicationLabels", false); }
    (:background, :glance)
    function glucoseUnit() as Lang.String { return text("glucoseUnit", "mgdl"); }
    // IOB, the calculator's settings, and the pump's status values (reservoir, battery, basal) count as
    // current while younger than these: the phone's own windows. 0 counts nothing as current.
    (:background)
    function iobStaleSeconds() as Lang.Number { return number("iobMinutes", 5) * 60; }
    (:background)
    function therapyStaleSeconds() as Lang.Number { return number("therapyMinutes", 15) * 60; }
    (:background)
    function pumpStatusStaleSeconds() as Lang.Number { return number("pumpStatusMinutes", 15) * 60; }
    // A stale reading younger than this may be included in a correction when the user chooses to.
    function includableSeconds() as Lang.Number { return number("includableMinutes", 15) * 60; }
    // Seconds after which glucose is shown marked as stale; 0 marks every reading.
    (:background, :glance)
    function staleSeconds() as Lang.Number { return number("staleMinutes", 6) * 60; }
    // Seconds after going stale before glucose is hidden; null never hides it.
    (:background, :glance)
    function hideDelaySeconds() as Lang.Number? {
        var v = value("hideDelayMinutes");
        return (v instanceof Lang.Number) ? v * 60 : null;
    }
    function plotFloor() as Lang.Number { return number("plotFloor", 40); }
    function plotCeiling() as Lang.Number { return number("plotCeiling", 300); }
}
