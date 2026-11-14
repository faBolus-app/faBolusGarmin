using Toybox.Lang;

// The watch-face complications: glucose (id 0) and three slots the phone assigns (ids 1–3). Staleness is
// judged from each value's measurement time when it's published, and the app and the background service
// republish as time passes, so a value never sits on the face as current after the phone goes away.
//
// A face shows a complication's label or its number, and can't show how old either is, so a stale value is
// sent as no number and the label "--": never a value that passes for a current one.
module BgComplication {
    (:background)
    const GLUCOSE_ID = 0;
    (:background)
    const SLOT_IDS = [1, 2, 3];

    (:background)
    // Plain ASCII: a face draws the label in its own font, and Garmin's guidance for complications is Latin
    // characters only. Device fonts differ in which symbols they have, and a missing one shows as "?" or
    // nothing; Dexcom's arrows come from Garmin's own faces, a path third-party apps don't have.
    function arrowFor(token as Lang.String?) as Lang.String {
        if (token == null) { return ""; }
        if (token.equals("up")) { return "^"; }
        if (token.equals("upup")) { return "^^"; }
        if (token.equals("up45")) { return "/"; }
        if (token.equals("down")) { return "v"; }
        if (token.equals("downdown")) { return "vv"; }
        if (token.equals("down45")) { return "\\"; }
        if (token.equals("flat")) { return "->"; }
        return "";
    }

    // The glucose label: the reading with its arrow while current, "--" once stale. A face can't show the
    // reading's age, so a stale reading isn't shown at all rather than passing for a current one.
    (:background)
    function glucoseLabel(text as Lang.String, arrow as Lang.String, stale as Lang.Boolean) as Lang.String {
        if (stale) { return "--"; }
        return (arrow.length() > 0) ? text + " " + arrow : text;
    }

    // A slot's value, label and unit: [value or null, label, unit or null]. Each label names what it shows
    // ("IOB 1.25"), because the face only knows the slot as "Pump Status 1–3", unless the user turned the
    // names off ("1.25 U"). A value older than the phone's window (IOB's own, the pump status window for the others)
    // shows as "--", like an unknown one.
    (:background)
    function slot(token as Lang.String, now as Lang.Number) as Lang.Array {
        var age = Status.ageOf(token, now);
        var window = token.equals("iob") ? Prefs.iobStaleSeconds() : Prefs.pumpStatusStaleSeconds();
        if (age == null || age > window) { return [null, "--", null]; }
        if (token.equals("iob")) {
            var mU = Status.field("iob", "mU");
            if (mU == null) { return [null, "--", null]; }
            return [mU.toFloat() / 1000.0, named("IOB", Display.units(mU), "U"), "U"];
        }
        if (token.equals("reservoir")) {
            var mU = Status.field("reservoir", "mU");
            if (mU == null) { return [null, "--", null]; }
            // Whole units, as the pump shows it, rounded down.
            return [mU / 1000, named("Res", (mU / 1000).toString(), "U"), "U"];
        }
        if (token.equals("battery")) {
            var pct = Status.field("battery", "percent");
            if (pct == null) { return [null, "--", null]; }
            return [pct, named("Bat", pct.toString() + "%", ""), "%"];
        }
        if (token.equals("basal")) {
            var b = Status.part("basal");
            if (b == null) { return [null, "--", null]; }
            if (b["suspended"] == true) { return [0, Prefs.complicationLabels() ? "Basal off" : "Off", "U/h"]; }
            if (b["basalIQ"] == true) { return [0, Prefs.complicationLabels() ? "Basal-IQ off" : "BIQ", "U/h"]; }
            var rate = Status.field("basal", "mUPerHour");
            if (rate == null) { return [null, "--", null]; }
            return [rate.toFloat() / 1000.0, named(b["tempRate"] == true ? "Temp" : "Basal", Display.units(rate), "U/h"), "U/h"];
        }
        return [null, "--", null];
    }

    // "IOB 1.25" with names on, "1.25 U" with them off.
    (:background)
    function named(name as Lang.String, value as Lang.String, unit as Lang.String) as Lang.String {
        if (Prefs.complicationLabels()) { return name + " " + value; }
        return (unit.length() > 0) ? value + " " + unit : value;
    }

    // The glucose complication's value, label and unit: [value or null, label, unit or null]. The label for
    // a face that shows text, the number with the arrow as its unit for one that shows the value. The
    // complication's colour bands are mg/dL and can't follow the user's unit, so with mmol/L there is no
    // number, only the label: never a number in the wrong unit, or one the bands colour wrongly.
    (:background)
    function glucoseEntry(now as Lang.Number) as Lang.Array {
        var g = Status.glucose();
        var age = Status.ageOf("glucose", now);
        if (g == null || age == null || age > Prefs.staleSeconds()) { return [null, "--", null]; }
        var arrow = arrowFor(Status.trend());
        var unit = Prefs.glucoseUnit();
        var label = glucoseLabel(Display.glucose(g, unit), arrow, false);
        if (unit.equals("mmol")) { return [null, label, null]; }
        return [g, label, arrow];
    }

    (:background)
    function publish(now as Lang.Number) as Void {
        if (!(Toybox has :Complications)) { return; }
        var e = glucoseEntry(now);
        push(GLUCOSE_ID, e[0] as Lang.Numeric?, e[1] as Lang.String, e[2] as Lang.String?);
        var slots = Prefs.complicationSlots();
        for (var i = 0; i < SLOT_IDS.size(); i += 1) {
            var id = SLOT_IDS[i] as Lang.Number;
            if (i < slots.size() && slots[i] instanceof Lang.String) {
                var s = slot(slots[i] as Lang.String, now);
                push(id, s[0] as Lang.Numeric?, s[1] as Lang.String, s[2] as Lang.String?);
            } else {
                push(id, null, "--", null);
            }
        }
    }

    // One complication. A face that can't take the label still gets the value.
    (:background, :complications)
    function push(id as Lang.Number, value as Lang.Numeric?, label as Lang.String, unit as Lang.String?) as Void {
        var params = { :value => value, :shortLabel => label } as Lang.Dictionary;
        if (unit != null) { params[:unit] = unit; }
        try {
            Toybox.Complications.updateComplication(id, params as Toybox.Complications.Data);
        } catch (e) {
            try {
                Toybox.Complications.updateComplication(id, { :value => value } as Toybox.Complications.Data);
            } catch (e2) {
                // Not registered on this face.
            }
        }
    }

    (:background, :nocomplications)
    function push(id as Lang.Number, value as Lang.Numeric?, label as Lang.String, unit as Lang.String?) as Void {
    }
}
