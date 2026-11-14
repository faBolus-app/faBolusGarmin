using Toybox.Graphics as Gfx;
using Toybox.Lang;

// How values are written on the watch. Glucose is held in mg/dL and only shown in mmol/L; the factor is
// faBolusCore GlucoseUnit's.
module Display {
    (:background, :glance)
    const MGDL_PER_MMOL = 18.0182;
    // The Time-in-Range bands (Battelino 2019), as on the phone: below 70, 70–180, 181–250, above 250.
    (:glance)
    const GLUCOSE_LOW = 70;
    (:glance)
    const GLUCOSE_HIGH = 180;
    (:glance)
    const GLUCOSE_VERY_HIGH = 250;

    (:background, :glance)
    function glucose(mgdl as Lang.Number, unit as Lang.String) as Lang.String {
        if (unit.equals("mmol")) { return (mgdl.toFloat() / MGDL_PER_MMOL).format("%.1f"); }
        return mgdl.toString();
    }

    (:glance)
    function glucoseUnit(unit as Lang.String) as Lang.String {
        return unit.equals("mmol") ? "mmol/L" : "mg/dL";
    }

    function isfUnit(unit as Lang.String) as Lang.String {
        return unit.equals("mmol") ? "mmol/L/U" : "mg/dL/U";
    }

    (:glance)
    function rangeColor(mgdl as Lang.Number) as Gfx.ColorValue {
        if (mgdl < GLUCOSE_LOW) { return Gfx.COLOR_RED; }
        if (mgdl <= GLUCOSE_HIGH) { return Gfx.COLOR_GREEN; }
        if (mgdl <= GLUCOSE_VERY_HIGH) { return Gfx.COLOR_YELLOW; }
        return Gfx.COLOR_ORANGE;
    }

    // Milliunits as units, two decimals.
    (:background)
    function units(mU as Lang.Number) as Lang.String {
        return (mU.toFloat() / 1000.0).format("%.2f");
    }

    // "now", "3 min ago", "1h 4m ago", "3d ago"; "" for an unknown age.
    function ago(seconds as Lang.Number?) as Lang.String {
        if (seconds == null) { return ""; }
        var m = seconds / 60;
        if (m <= 0) { return "now"; }
        if (m < 60) { return m.toString() + " min ago"; }
        var h = m / 60;
        if (h >= 24) { return (h / 24).toString() + "d ago"; }
        var mm = m % 60;
        return (mm == 0) ? h.toString() + "h ago" : h.toString() + "h " + mm.toString() + "m ago";
    }

    // The connection line: what's wrong with the link to the phone or the pump, or the pump's state.
    function linkLine(now as Lang.Number) as Lang.String {
        if (Link.phoneTooOld()) { return "Update faBolus on phone"; }
        if (Link.watchTooOld()) { return "Update the watch app"; }
        if (!Link.reachable(now)) { return "Phone not connected"; }
        if (!Status.present()) { return "Waiting for phone"; }
        if (!Link.phoneLive(now)) { return "No reply from faBolus"; }
        var link = Status.pumpLink();
        if (link.equals("connected")) { return "Pump connected"; }
        if (link.equals("connecting") || link.equals("authenticating") || link.equals("scanning")) {
            return "Connecting to pump";
        }
        return "Pump not connected";
    }
}

// The glucose as every screen shows it: hidden after the hide delay, greyed when stale, never shown as
// current once it's older than the stale window.
module Glucose {
    // The reading's age in seconds, or null with none.
    function age(now as Lang.Number) as Lang.Number? { return Status.ageOf("glucose", now); }

    function stale(now as Lang.Number) as Lang.Boolean {
        var a = age(now);
        return a == null || a > Prefs.staleSeconds();
    }

    function isHidden(now as Lang.Number) as Lang.Boolean {
        var a = age(now);
        if (a == null || Status.glucose() == null) { return true; }
        var delay = Prefs.hideDelaySeconds();
        return delay != null && a > Prefs.staleSeconds() + delay;
    }

    function text(now as Lang.Number) as Lang.String {
        var g = Status.glucose();
        if (g == null || isHidden(now)) { return "--"; }
        return Display.glucose(g, Prefs.glucoseUnit());
    }

    function color(now as Lang.Number) as Gfx.ColorValue {
        var g = Status.glucose();
        if (g == null || stale(now) || isHidden(now)) { return Gfx.COLOR_LT_GRAY; }
        return Display.rangeColor(g);
    }

    // The trend arrow's token while the reading is current, else null.
    function trend(now as Lang.Number) as Lang.String? { return stale(now) ? null : Status.trend(); }
}
