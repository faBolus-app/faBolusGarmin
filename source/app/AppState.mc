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
    // "glucose" = a current-glucose screen with no bolus button (users can add it to the order instead
    // of, or alongside, the bolus "glance").
    const ALL_SCREENS = ["glance", "glucose", "clock", "bolusonly", "alerts", "history", "details"];

    // Read-only mode pushed from the phone ("remotesReadOnly"): hide the bolus button everywhere.
    var readOnly as Lang.Boolean = false;

    // Details rows shown (in order) + which history ranges the plot cycles through on tap — both
    // mirrored from the phone ("detailsOrder" / "watchChartRanges" in the statusRead reply).
    var detailsOrder as Lang.Array = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"];
    const ALL_DETAILS = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"];
    var chartRanges as Lang.Array = [3, 6, 12, 24];
    // How the BG complication presents: "numericColor" (numeric value + range color + Latin trend
    // in the unit slot) or "stringTrend" (plain "124 ^" string). Mirrored from the phone.
    var complicationDisplay as Lang.String = "numericColor";

    // Load persisted layout at launch (getInitialView needs defaultScreen before any phone message).
    function loadPrefs() as Void {
        var so = Storage.getValue("screenOrder");
        if (so instanceof Lang.Array) { screenOrder = sanitizeOrder(so); }
        var ds = Storage.getValue("defaultScreen");
        if (ds instanceof Lang.String && contains(screenOrder, ds)) { defaultScreen = ds; }
        ensureValidDefault();
        var dord = Storage.getValue("detailsOrder");
        if (dord instanceof Lang.Array) {
            var s = sanitizeAgainst(dord, ALL_DETAILS);
            if (s.size() > 0) { detailsOrder = s; }
        }
        var cr = Storage.getValue("watchChartRanges");
        if (cr instanceof Lang.Array) {
            var sr = sanitizeRanges(cr);
            if (sr.size() > 0) { chartRanges = sr; ensureValidPlotHours(); }
        }
        var cdp = Storage.getValue("complicationDisplay");
        if (cdp instanceof Lang.String) { complicationDisplay = cdp; }
        // GA-08: restore the staleness policy so a restart / background launch honors the phone-synced
        // value instead of silently reverting to the 6-min default until the next statusRead.
        var ss = Storage.getValue("staleSec");
        if (ss instanceof Lang.Number && ss > 0) { staleSec = ss; }
        var hd = Storage.getValue("hideDelaySec");
        hideDelaySec = (hd instanceof Lang.Number && hd >= 0) ? hd : null;   // absent/null = never hide
    }

    // Keep only allowed string ids (de-duped), preserving the phone-chosen subset + order.
    function sanitizeAgainst(list as Lang.Array, allow as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.String && contains(allow, v) && !containsStr(out, v)) { out.add(v); }
        }
        return out;
    }

    // Keep only the allowed history ranges {3,6,12,24}, de-duped, preserving order.
    function sanitizeRanges(list as Lang.Array) as Lang.Array {
        var allowed = [3, 6, 12, 24];
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.Number && containsNum(allowed, v) && !containsNum(out, v)) { out.add(v); }
        }
        return out;
    }

    function containsStr(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.String && (list[i] as Lang.String).equals(v)) { return true; }
        }
        return false;
    }
    function containsNum(list as Lang.Array, v as Lang.Number) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.Number && (list[i] as Lang.Number) == v) { return true; }
        }
        return false;
    }
    function ensureValidPlotHours() as Void {
        if (chartRanges.size() > 0 && !containsNum(chartRanges, plotHours)) {
            plotHours = chartRanges[0] as Lang.Number;
        }
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

    // Advance to the next phone-enabled history range (wrapping). The set comes from the phone's
    // watchChartRanges; if the current window isn't in it, start at the first.
    function cyclePlotHours() as Void {
        if (chartRanges.size() == 0) { return; }
        var idx = -1;
        for (var i = 0; i < chartRanges.size(); i += 1) {
            if ((chartRanges[i] as Lang.Number) == plotHours) { idx = i; break; }
        }
        idx = (idx + 1) % chartRanges.size();
        plotHours = chartRanges[idx] as Lang.Number;
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

    // The pump is reachable when the phone reports it connected or actively delivering.
    // "Connecting…", "Scanning…", "Disconnected", "Error", and unknown ("") mean not reachable.
    function pumpConnected() as Lang.Boolean {
        return connection.equals("Connected") || bolusing();
    }

    // A bolus is currently being delivered ("Delivering…").
    function bolusing() as Lang.Boolean {
        return connection.find("Deliver") == 0;
    }

    // A new bolus is only possible when the phone (which owns the pump link) is reachable, the pump
    // is connected, and no bolus is already in flight. The Garmin never touches the pump directly.
    function canBolus() as Lang.Boolean {
        return RemoteComm.phoneReachable() && pumpConnected() && !bolusing();
    }

    // A bolus started from this watch is in flight and can be cancelled from the glance (e.g. after
    // the user left the delivery screen). Needs the request id we issued so the phone can correlate.
    function canCancel() as Lang.Boolean {
        return bolusing() && pendingRequestId != null;
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
    // Whether the phone has been seen bolusing since this request started, so a lost/late
    // terminal echo can be recovered from the connection state (see handle()).
    var sawPhoneBolusing as Lang.Boolean = false;

    function reset() as Void {
        mode = defaultMode; unitsValue = 0.0; carbsValue = 0;
        pendingRequestId = null; status = null; message = null; sawPhoneBolusing = false;
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
    // A wrist-side preview only: the phone (host) recomputes the authoritative dose with the same
    // oracle-backed calculator and runs the divergence guard before delivery.
    //
    // This is a hand-port of faBolusCore/BolusMath.estimate() — the faithful Tandem oracle logic
    // (audit C-01). Keep it in lockstep with that Swift/Java source. The key correctness point:
    //   • food = carbs / carbRatio
    //   • fromBG = (glucose - target) / isf   (SIGNED — a below-target BG is negative and REDUCES the dose)
    //   • fromIOB = -iob (only when iob > 0)   — IOB offsets a BG correction, never a bare carb dose
    //   • at/above target: add (fromBG + fromIOB) only if that sum is positive
    //   • below target: apply (fromBG + fromIOB) if it keeps the total positive, else floor total at 0
    // The old code floored the *correction* at 0 before combining, which dropped every below-target
    // reduction and over-recommended. Units mode is a manual fixed dose (no correction / IOB).
    // GA-04: the oracle's BolusCalcUnits.doublePrecision — BigDecimal.setScale(2, HALF_UP): round to two
    // decimals, ties AWAY from zero (so it matches faBolusCore/BolusMath.dp on every component). Monkey C's
    // Math.round is not HALF_UP for negatives, so we floor(|v|*100 + 0.5) and re-apply the sign.
    function dp2(v as Lang.Float) as Lang.Float {
        if (v >= 0.0) { return Math.floor(v * 100.0 + 0.5) / 100.0; }
        return -(Math.floor(-v * 100.0 + 0.5) / 100.0);
    }

    function computeUnits() as Lang.Float {
        var total;
        if (mode.equals("units")) {
            total = unitsValue;
        } else if (carbRatio > 0.0) {
            // GA-04: round EACH component to two decimals (half-up) before combining — exactly as the
            // oracle-backed host does. Combining unrounded components then rounding only the total drifted
            // by one 0.05 U pump increment on ~1.5% of inputs, and the host's 0.10 U tolerance accepted it,
            // so the delivered dose could differ from the number shown on the hold screen.
            var fromCarbs = dp2(carbsValue.toFloat() / carbRatio);
            var fromBG = 0.0;
            if (isf > 0 && glucose != null && !glucoseStale()) {   // never correct off a stale BG
                fromBG = dp2((glucose - targetBg).toFloat() / isf.toFloat());   // signed
            }
            var fromIOB = (iob > 0.0) ? dp2(-iob) : 0.0;
            total = fromCarbs;
            if (fromBG >= 0.0) {                        // at or above target
                var corr = fromBG + fromIOB;
                if (corr > 0.0) { total += corr; }      // else IOB cancels the correction → add nothing
            } else {                                    // below target — correction reduces the dose
                var corr = fromBG + fromIOB;
                if (total + corr > 0.0) { total += corr; }
                else { total = 0.0; }                   // would go negative → floor the total at 0
            }
            total = dp2(total);                         // oracle dp() on the combined total too
        } else {
            // FB-01: the carb ratio hasn't arrived from the phone. Do NOT silently assume 10 g/U (that
            // is an unverified guess that could misdose). Return 0 — `carbCalcAvailable()` is false, so
            // the UI shows "calculator unavailable" and blocks the bolus until the phone syncs settings.
            total = 0.0;
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

    // FB-01: a carb bolus can only be estimated on the wrist once the pump's carb ratio has synced from
    // the phone. Units mode never needs it. When false the UI shows "calculator unavailable" and blocks
    // the bolus (we do NOT fall back to an assumed 10 g/U).
    function carbCalcAvailable() as Lang.Boolean {
        return !mode.equals("carbs") || carbRatio > 0.0;
    }

    // Route an inbound phone message.
    function handle(data as Lang.Dictionary) as Void {
        var kind = data["kind"] as Lang.String?;
        if (kind == null) { return; }
        if (kind.equals("statusRead")) {
            // Guard the assignment (audit): a partial statusRead that omits bgMgdl must NOT null out the
            // last-known glucose (which would blank the value + disable correction dosing). Keep last.
            // GA-09: every field is range/finite-validated before it mutates state; a bad value returns
            // null and the last good reading is kept (see numRange/fltRange/validTrend/strCap).
            var bg = numRange(data["bgMgdl"], 0, 600); if (bg != null) { glucose = bg; }
            var t = validTrend(data["trend"]); if (t != null) { trend = t; }
            var i = fltRange(data["units"], 0.0, 100.0); if (i != null) { iob = i; }
            var cr = fltRange(data["carbRatio"], 1.0, 300.0); if (cr != null) { carbRatio = cr; }
            var isfv = numRange(data["isf"], 1, 1000); if (isfv != null) { isf = isfv; }
            var tb = numRange(data["targetBg"], 40, 400); if (tb != null) { targetBg = tb; }
            var mx = fltRange(data["maxBolusUnits"], 0.0, 100.0); if (mx != null) { maxUnits = mx; }
            var rv = fltRange(data["reservoirUnits"], 0.0, 1000.0); if (rv != null) { reservoir = rv; }
            var bt = numRange(data["batteryPercent"], 0, 100); if (bt != null) { battery = bt; }
            var cn = strCap(data["message"], 120); if (cn != null) { connection = cn; }
            // GA-03: the AUTHORITATIVE terminal outcome is the phone's bolusStatus echo (by requestId),
            // handled below — including the FB-02 "unknown" status when the pump outcome is genuinely
            // indeterminate. If we've seen the phone bolusing and it's no longer bolusing but the terminal
            // echo never arrived, do NOT fabricate "delivered" from the connection string (the old bug):
            // surface "unknown" and point the user to pump history. A cancel we initiated is the one case
            // we can still call "cancelled" (the user asked for it and we sent the cancel).
            if (bolusing()) {
                sawPhoneBolusing = true;
            } else if (sawPhoneBolusing && status != null && status.equals("cancelling")) {
                status = "cancelled";
            } else if (sawPhoneBolusing && status != null && status.equals("delivering")) {
                status = "unknown";
                if (message == null) { message = "Outcome unknown — check the pump/t:connect history."; }
            }
            // Don't overwrite last-bolus from a routine push while a bolus is in progress — that value
            // is still the PREVIOUS bolus mid-delivery and would flicker. The bolusStatus echo (or the
            // recovery above) settles it to the just-delivered amount.
            var deliveringNow = (status != null && (status.equals("delivering") || status.equals("cancelling")));
            var lb = fltRange(data["lastBolusUnits"], 0.0, 100.0); if (lb != null && !deliveringNow) { lastBolus = lb; }
            var ag = fltRange(data["glucoseAgeSec"], 0.0, 86400.0);
            if (ag != null) { readingEpoch = Time.now().value() - ag.toNumber(); }
            // A fresh bgMgdl with no age is "now" — otherwise it would inherit the previous reading's
            // epoch, immediately age out (lose its arrow) and be barred from correction dosing (audit).
            else if (bg != null) { readingEpoch = Time.now().value(); }
            // Staleness policy from the phone: glucoseStaleMinutes (>0), glucoseHideDelayMinutes
            // (0 = hide when stale, absent = never hide).
            var sm = numRange(data["glucoseStaleMinutes"], 1, 720); if (sm != null) { staleSec = sm * 60; }
            var hd = numRange(data["glucoseHideDelayMinutes"], 0, 1440);
            hideDelaySec = (hd != null) ? hd * 60 : null;
            // GA-08: persist the staleness policy so the glance / complication (separate launch contexts)
            // and a cold restart honor it before the next statusRead arrives.
            Storage.setValue("staleSec", staleSec);
            if (hideDelaySec != null) { Storage.setValue("hideDelaySec", hideDelaySec); }
            else { Storage.deleteValue("hideDelaySec"); }
            var hs = data["history"]; if (hs instanceof Lang.Array) { history = sanitizeHistory(hs); }
            var al = data["alerts"]; if (al instanceof Lang.Array) { alerts = sanitizeAlerts(al); }
            var ro = data["remotesReadOnly"]; if (ro instanceof Lang.Boolean) { readOnly = ro; }
            var bm = data["bolusMode"] as Lang.String?;
            if (bm != null && (bm.equals("units") || bm.equals("carbs"))) { defaultMode = bm; }
            var bi = fltRange(data["bolusIncrement"], 0.01, 5.0); if (bi != null) { stepU = bi; }
            var ci = numRange(data["carbIncrement"], 1, 100); if (ci != null) { stepC = ci; }
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
            var detOrderRaw = data["detailsOrder"];
            if (detOrderRaw instanceof Lang.Array) {
                var detOrderSan = sanitizeAgainst(detOrderRaw, ALL_DETAILS);
                if (detOrderSan.size() > 0) { detailsOrder = detOrderSan; Storage.setValue("detailsOrder", detailsOrder); }
            }
            var chartRaw = data["watchChartRanges"];
            if (chartRaw instanceof Lang.Array) {
                var chartSan = sanitizeRanges(chartRaw);
                if (chartSan.size() > 0) { chartRanges = chartSan; Storage.setValue("watchChartRanges", chartRanges); ensureValidPlotHours(); }
            }
            var cdisp = data["garminComplicationDisplay"];
            if (cdisp instanceof Lang.String && ((cdisp as Lang.String).equals("numericColor") || (cdisp as Lang.String).equals("stringTrend"))) {
                complicationDisplay = cdisp; Storage.setValue("complicationDisplay", complicationDisplay);
            }
        } else if (kind.equals("bolusStatus")) {
            var rid = strCap(data["requestId"], 64);
            if (pendingRequestId != null && rid != null && rid.equals(pendingRequestId)) {
                // GA-09: only adopt a recognized status token, and cap the message length.
                var st = data["status"];
                if (st instanceof Lang.String && containsStr(STATUS_TOKENS, st as Lang.String)) { status = st; }
                message = data.hasKey("message") ? strCap(data["message"], 160) : null;
                // Reflect the actual delivered amount from the outcome echo so "Last bolus" shows the
                // just-delivered value immediately (e.g. 0.05), not the previous bolus.
                if (status != null && (status.equals("delivered") || status.equals("cancelled"))) {
                    var du = fltRange(data["deliveredUnits"], 0.0, 100.0); if (du != null) { lastBolus = du; }
                }
            }
        }
    }
    const STATUS_TOKENS = ["delivering", "delivered", "cancelled", "cancelling", "failed", "unknown"];

    function isNum(v) as Lang.Boolean {
        return v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double;
    }
    function numOrNull(v) as Lang.Number? { return isNum(v) ? v.toNumber() : null; }
    function flt(v) as Lang.Float? { return isNum(v) ? v.toFloat() : null; }

    // GA-09: inbound-payload validation. A malformed / hostile phone message must not poison global
    // state — every physiological field is bounds- and finiteness-checked, strings are length-capped,
    // and nested arrays are size-capped with per-element validation. A rejected field returns null so
    // the caller KEEPS the last good value rather than adopting garbage.
    function isFiniteNum(v) as Lang.Boolean {
        if (!isNum(v)) { return false; }
        return v == v && v < 1.0e12 && v > -1.0e12;   // v==v rejects NaN; the bounds reject ±Inf / absurd
    }
    function numRange(v, lo as Lang.Number, hi as Lang.Number) as Lang.Number? {
        if (!isFiniteNum(v)) { return null; }
        var n = v.toNumber();
        return (n < lo || n > hi) ? null : n;
    }
    function fltRange(v, lo as Lang.Float, hi as Lang.Float) as Lang.Float? {
        if (!isFiniteNum(v)) { return null; }
        var f = v.toFloat();
        return (f < lo || f > hi) ? null : f;
    }
    function strCap(v, max as Lang.Number) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        var s = v as Lang.String;
        return (s.length() > max) ? s.substring(0, max) : s;
    }
    const TREND_TOKENS = ["flat", "up", "down", "upup", "downdown", "up45", "down45", ""];
    function validTrend(v) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        return containsStr(TREND_TOKENS, v as Lang.String) ? v : null;
    }
    // Keep the newest ≤288 finite readings in [0,600]; drop everything else.
    function sanitizeHistory(arr as Lang.Array) as Lang.Array {
        var out = [];
        var n = arr.size();
        var start = (n > 288) ? n - 288 : 0;
        for (var k = start; k < n; k += 1) {
            var v = numRange(arr[k], 0, 600);
            if (v != null) { out.add(v); }
        }
        return out;
    }
    // Keep ≤50 well-formed alert dicts (each must have id/kind/title of the right type).
    function sanitizeAlerts(arr as Lang.Array) as Lang.Array {
        var out = [];
        var lim = (arr.size() > 50) ? 50 : arr.size();
        for (var k = 0; k < lim; k += 1) {
            var e = arr[k];
            if (e instanceof Lang.Dictionary
                && isNum(e["id"]) && isNum(e["kind"]) && (e["title"] instanceof Lang.String)) {
                out.add({ "id" => e["id"], "kind" => e["kind"], "title" => strCap(e["title"], 80) });
            }
        }
        return out;
    }

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
