using Toybox.Lang;
using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Time;
using Toybox.Application.Storage;

// Shared app state for the faBolus Garmin remote. Glance data comes from the phone
// (statusRead reply); carbs→units is computed locally from the pump's calculator settings so
// the hold-to-deliver screen can show the exact units.
module AppState {
    // HUD data (from phone)
    var glucose as Lang.Number? = null;   // mg/dL
    var trend as Lang.String = "";
    var iob as Lang.Float = 0.0;          // units
    var carbRatio as Lang.Float = 0.0;    // g/u
    var isf as Lang.Number = 0;           // mg/dL per unit
    var targetBg as Lang.Number = 0;      // mg/dL
    var maxUnits as Lang.Float = 25.0;
    // Extra pump status (from phone) for the details screen.
    var reservoir as Lang.Float = -1.0;   // units remaining (-1 = unknown)
    var battery as Lang.Number = -1;      // percent (-1 = unknown)
    var lastBolus as Lang.Float = -1.0;   // units of the last bolus (-1 = unknown)
    var connection as Lang.String = "";   // e.g. "Connected"
    var readingEpoch as Lang.Number = 0;  // unix sec the current BG was taken (0 = unknown)
    // Staleness policy, synced from the phone (statusRead). staleSec: age after which the reading is
    // stale (greyed + not used for carb→unit). hideDelaySec: extra age before hiding ("--"); null =
    // never hide (always greyed), 0 = hide as soon as stale. Defaults mirror the phone (6 min / never).
    var staleSec as Lang.Number = 360;
    var hideDelaySec as Lang.Number or Null = null;
    var history as Lang.Array = [];       // recent mg/dL (Numbers), oldest → newest, for the plot
    var alerts as Lang.Array = [];        // active pump alerts: dicts {id, kind, title}
    var plotHours as Lang.Number = 3;     // history-plot window: 3 → 6 → 12 → 24 → 3

    // Configurable layout (from phone settings, persisted so it survives restarts / offline launch).
    // The swipe order of the screens and which one opens first. Ids: glance/alerts/history/details.
    var screenOrder as Lang.Array = ["glance", "alerts", "history", "details"];
    var defaultScreen as Lang.String = "glance";
    const ALL_SCREENS = ["glance", "alerts", "history", "details"];

    // Load persisted layout at launch (getInitialView needs defaultScreen before any phone message).
    function loadPrefs() as Void {
        var so = Storage.getValue("screenOrder");
        if (so instanceof Lang.Array) { screenOrder = sanitizeOrder(so); }
        var ds = Storage.getValue("defaultScreen");
        if (ds instanceof Lang.String && contains(screenOrder, ds)) { defaultScreen = ds; }
        ensureValidDefault();
    }

    // Keep only known ids (de-duped), preserving the phone-chosen subset + order. Screens the user
    // hid are intentionally omitted. Falls back to all screens only if the result would be empty,
    // so the watch is never left with nothing to show.
    function sanitizeOrder(list as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.String && contains(ALL_SCREENS, v) && !contains(out, v)) { out.add(v); }
        }
        if (out.size() == 0) {
            for (var i = 0; i < ALL_SCREENS.size(); i += 1) { out.add(ALL_SCREENS[i]); }
        }
        return out;
    }

    // Ensures the default screen is one that's actually shown; otherwise falls back to the first.
    function ensureValidDefault() as Void {
        if (!contains(screenOrder, defaultScreen)) {
            defaultScreen = (screenOrder.size() > 0) ? (screenOrder[0] as Lang.String) : "glance";
        }
    }

    function contains(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.String && (list[i] as Lang.String).equals(v)) { return true; }
        }
        return false;
    }

    function cyclePlotHours() as Void {
        if (plotHours == 3) { plotHours = 6; }
        else if (plotHours == 6) { plotHours = 12; }
        else { plotHours = 3; }   // 3 → 6 → 12 → 3 (no 24 h on the watch)
    }

    // A cached BG older than 6 minutes must not be shown (per spec).
    function glucoseStale() as Lang.Boolean {
        if (glucose == null || readingEpoch <= 0) { return true; }
        return (Time.now().value() - readingEpoch) > staleSec;
    }
    // Past the hide delay → show "--" instead of the greyed value. null delay = never hide.
    function glucoseHidden() as Lang.Boolean {
        if (hideDelaySec == null) { return false; }
        if (readingEpoch <= 0) { return true; }
        return (Time.now().value() - readingEpoch) > (staleSec + hideDelaySec);
    }
    // Show the number whenever we have one — a stale reading is shown but marked (grayed + age
    // called out), never hidden. "--" only when there's no reading at all.
    function displayGlucose() as Lang.String {
        return glucose == null ? "--" : glucose.toString();
    }
    // Minutes since the current reading (-1 if unknown).
    function ageMinutes() as Lang.Number {
        if (readingEpoch <= 0) { return -1; }
        return (Time.now().value() - readingEpoch) / 60;
    }
    // Relative age label ("now", "3 min ago", "1h 4m ago"), or "" when unknown.
    function ageLabel() as Lang.String {
        var m = ageMinutes();
        if (m < 0) { return ""; }
        if (m == 0) { return "now"; }
        if (m < 60) { return m.toString() + " min ago"; }
        var h = m / 60; var mm = m % 60;
        return mm == 0 ? h.toString() + "h ago" : h.toString() + "h " + mm.toString() + "m ago";
    }

    // Bolus entry
    var mode as Lang.String = "carbs";    // "units" | "carbs"; default from phone settings
    var defaultMode as Lang.String = "carbs";
    var unitsValue as Lang.Float = 0.0;
    var carbsValue as Lang.Number = 0;
    var stepU as Lang.Float = 0.05;       // bolus increment (from phone settings)
    var stepC as Lang.Number = 5;         // carb increment (from phone settings)
    const MAX_CARBS = 200;

    // Delivery
    var deliverUnits as Lang.Float = 0.0; // captured when entering the hold screen
    var holdProgress as Lang.Float = 0.0; // 0..1 for the hold-to-deliver ring
    var pendingRequestId as Lang.String? = null;
    var status as Lang.String? = null;    // delivering/delivered/failed/...
    var message as Lang.String? = null;

    function reset() as Void {
        mode = defaultMode; unitsValue = 0.0; carbsValue = 0;
        pendingRequestId = null; status = null; message = null;
    }

    // Seed glucose/trend from the persisted complication value so the glance shows the last-known
    // reading immediately on open, instead of "--" while the first phone reply is in flight.
    function loadPersisted() as Void {
        var g = Storage.getValue(BgComplication.KEY_BG);
        if (g != null && isNum(g)) { glucose = g.toNumber(); }
        var t = Storage.getValue(BgComplication.KEY_TREND);
        if (t != null && t instanceof Lang.String) { trend = t; }
        var e = Storage.getValue(BgComplication.KEY_EPOCH);
        if (e != null && isNum(e)) { readingEpoch = e.toNumber(); }
    }

    function toggleMode() as Void {
        mode = mode.equals("units") ? "carbs" : "units";
    }

    // dir = +1 / -1
    function adjust(dir as Lang.Number) as Void {
        if (mode.equals("units")) {
            unitsValue += dir * stepU;
            if (unitsValue < 0.0) { unitsValue = 0.0; }
            if (unitsValue > maxUnits) { unitsValue = maxUnits; }
        } else {
            carbsValue += dir * stepC;
            if (carbsValue < 0) { carbsValue = 0; }
            if (carbsValue > MAX_CARBS) { carbsValue = MAX_CARBS; }
        }
    }

    // The units that will actually be delivered (rounded to 0.05, clamped to the pump max).
    // Mirrors the t:slim / iPhone calculator EXACTLY so a carb bolus from the watch matches the
    // pump: food = carbs / carbRatio, plus a correction that is reduced by IOB and *floored at 0*
    // (IOB reduces only the correction, never the carb coverage), then the whole floored at 0.
    // Units mode is a manual fixed dose (no correction / IOB).
    function computeUnits() as Lang.Float {
        var total;
        if (mode.equals("units")) {
            total = unitsValue;
        } else if (carbRatio > 0.0) {
            var food = carbsValue.toFloat() / carbRatio;
            var correction = 0.0;
            if (isf > 0 && glucose != null && !glucoseStale()) {                    // never correct off a stale BG
                correction = (glucose - targetBg).toFloat() / isf.toFloat() - iob;  // IOB reduces correction only
                if (correction < 0.0) { correction = 0.0; }                         // floored, like the t:slim
            }
            total = food + correction;
        } else {
            total = carbsValue.toFloat() / 10.0 - iob;   // fallback when no carb ratio — matches iPhone
        }
        total = Math.round(total * 20.0) / 20.0;   // 0.05 u steps
        if (total < 0.0) { total = 0.0; }
        if (total > maxUnits) { total = maxUnits; }
        return total;
    }

    function valueLabel() as Lang.String {
        if (mode.equals("units")) { return unitsValue.format("%.2f") + " U"; }
        return carbsValue.toString() + " g";
    }

    // Route an inbound phone message.
    function handle(data as Lang.Dictionary) as Void {
        var kind = data["kind"] as Lang.String?;
        if (kind == null) { return; }
        if (kind.equals("statusRead")) {
            glucose = numOrNull(data["bgMgdl"]);
            var t = data["trend"] as Lang.String?; if (t != null) { trend = t; }
            var i = flt(data["units"]); if (i != null) { iob = i; }
            var cr = flt(data["carbRatio"]); if (cr != null) { carbRatio = cr; }
            var isfv = numOrNull(data["isf"]); if (isfv != null) { isf = isfv; }
            var tb = numOrNull(data["targetBg"]); if (tb != null) { targetBg = tb; }
            var mx = flt(data["maxBolusUnits"]); if (mx != null) { maxUnits = mx; }
            var rv = flt(data["reservoirUnits"]); if (rv != null) { reservoir = rv; }
            var bt = numOrNull(data["batteryPercent"]); if (bt != null) { battery = bt; }
            var lb = flt(data["lastBolusUnits"]); if (lb != null) { lastBolus = lb; }
            var cn = data["message"] as Lang.String?; if (cn != null) { connection = cn; }
            var ag = flt(data["glucoseAgeSec"]);
            if (ag != null) { readingEpoch = Time.now().value() - ag.toNumber(); }
            // Staleness policy from the phone: glucoseStaleMinutes (>0), glucoseHideDelayMinutes
            // (0 = hide when stale, absent = never hide).
            var sm = numOrNull(data["glucoseStaleMinutes"]); if (sm != null && sm > 0) { staleSec = sm * 60; }
            var hd = numOrNull(data["glucoseHideDelayMinutes"]);
            hideDelaySec = (hd != null) ? hd * 60 : null;
            var hs = data["history"]; if (hs instanceof Lang.Array) { history = hs; }
            var al = data["alerts"]; if (al instanceof Lang.Array) { alerts = al; }
            var bm = data["bolusMode"] as Lang.String?; if (bm != null) { defaultMode = bm; }
            var bi = flt(data["bolusIncrement"]); if (bi != null && bi > 0.0) { stepU = bi; }
            var ci = numOrNull(data["carbIncrement"]); if (ci != null && ci > 0) { stepC = ci; }
            var so = data["screenOrder"];
            if (so instanceof Lang.Array) {
                screenOrder = sanitizeOrder(so);
                Storage.setValue("screenOrder", screenOrder);
            }
            var ds = data["defaultScreen"] as Lang.String?;
            if (ds != null && contains(screenOrder, ds)) {
                defaultScreen = ds;
                Storage.setValue("defaultScreen", ds);
            }
            ensureValidDefault();
        } else if (kind.equals("bolusStatus")) {
            var rid = data["requestId"] as Lang.String?;
            if (pendingRequestId != null && rid != null && rid.equals(pendingRequestId)) {
                status = data["status"] as Lang.String?;
                message = data.hasKey("message") ? data["message"] as Lang.String? : null;
            }
        }
    }

    function isNum(v) as Lang.Boolean {
        return v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double;
    }
    function numOrNull(v) as Lang.Number? { return isNum(v) ? v.toNumber() : null; }
    function flt(v) as Lang.Float? { return isNum(v) ? v.toFloat() : null; }

    function glucoseColor() as Gfx.ColorValue {
        if (glucose == null) { return Gfx.COLOR_LT_GRAY; }
        return rangeColor(glucose as Lang.Number);
    }

    // Range color for an arbitrary mg/dL value (used by the history plot).
    function rangeColor(g as Lang.Number) as Gfx.ColorValue {
        if (g < 70) { return Gfx.COLOR_RED; }
        if (g < 180) { return Gfx.COLOR_GREEN; }
        if (g < 250) { return Gfx.COLOR_YELLOW; }
        return Gfx.COLOR_ORANGE;
    }
}
