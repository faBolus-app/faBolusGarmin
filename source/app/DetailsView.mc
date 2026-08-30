using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Time as Time;

// Secondary screen (swipe up from the glance): all the other relevant pump data from the phone.
// One metric per row, centered, generously spaced so nothing overlaps. "--" when unknown.
class DetailsView extends Ui.View {
    function initialize() { View.initialize(); }

    private function f2(v as Lang.Float) as Lang.String {
        return v < 0.0 ? "--" : v.format("%.2f");
    }
    private function n0(v as Lang.Number) as Lang.String {
        return v < 0 ? "--" : v.toString();
    }

    // Tandem's own zone word, capitalized exactly as the UI-SPEC Copywriting Contract specifies —
    // an explicit literal table (never a runtime case-transform), so an out-of-set token can only
    // ever fall through to "" and never render.
    private function ciqZoneWord(token as Lang.String) as Lang.String {
        if (token.equals("increases")) { return "Increases"; }
        if (token.equals("decreases")) { return "Decreases"; }
        if (token.equals("maintains")) { return "Maintains"; }
        if (token.equals("stops")) { return "Stops"; }
        if (token.equals("delivers")) { return "Delivers"; }
        return "";
    }

    // Elapsed minutes computed HERE at draw time from the immutable source epoch, never transmitted
    // as a pre-computed age (mirrors AppState.ageMinutes()'s identical pattern for the glucose
    // reading). Clamped to 0 for a clock-skew/future stamp rather than a negative elapsed time.
    private function ciqSuspendElapsedMinutes() as Lang.Number {
        var start = AppState.ciqSuspendStartEpochSec;
        if (start == null) { return 0; }
        var mins = (Time.now().value() - (start as Lang.Number)) / 60;
        return mins < 0 ? 0 : mins;
    }

    // Elapsed minutes computed HERE at draw time from an immutable source epoch, never transmitted
    // as a pre-computed age. Clamped to 0 for a clock-skew/future stamp. Mirrors
    // ciqSuspendElapsedMinutes above and is deliberately kept as a separate generic helper so that
    // one stays unchanged — do not merge the two.
    private function elapsedMinutesSince(epoch as Lang.Number?) as Lang.Number {
        if (epoch == null) { return 0; }
        var mins = (Time.now().value() - (epoch as Lang.Number)) / 60;
        return mins < 0 ? 0 : mins;
    }

    // One labeled row per detail-field id (from the phone-mirrored AppState.detailsOrder), or null
    // for an unknown id. Mirrors the phone Details card / Apple-Watch Details page.
    private function detailRow(id as Lang.String) as Lang.String? {
        if (id.equals("iob")) { return "Active Insulin: " + f2(AppState.iob) + " U"; }
        if (id.equals("reservoir")) { return "Reservoir: " + f2(AppState.reservoir) + " U"; }
        // Append a Charging marker ONLY when the phone's most-recent statusRead positively reported
        // it (fail-closed AppState.batteryCharging) — never inferred from a rising percent.
        if (id.equals("battery")) {
            return "Battery: " + n0(AppState.battery) + "%" + (AppState.batteryCharging ? " · Charging" : "");
        }
        if (id.equals("cgm")) { return "CGM: " + (AppState.glucose != null ? AppState.displayGlucose() + " " + AppState.glucoseUnitLabel() : "--"); }
        if (id.equals("lastBolus")) { return "Last bolus: " + f2(AppState.lastBolus) + " U"; }
        if (id.equals("carbRatio")) { return "Carb ratio: " + (AppState.carbRatio > 0.0 ? AppState.carbRatio.format("%.0f") + " g/U" : "--"); }
        if (id.equals("isf")) { return "ISF: " + (AppState.isf > 0 ? AppState.formatMgdl(AppState.isf) + " " + AppState.isfUnitLabel() : "--"); }
        if (id.equals("target")) { return "Target: " + (AppState.targetBg > 0 ? AppState.formatMgdl(AppState.targetBg) + " " + AppState.glucoseUnitLabel() : "--"); }
        if (id.equals("maxBolus")) { return "Max bolus: " + f2(AppState.maxUnits) + " U"; }
        // A PRINTED word (Garmin has no VoiceOver) — row omitted entirely (never "--") unless
        // Control-IQ is running and the zone is a known token, never a stale/fabricated word.
        if (id.equals("ciqZone")) {
            if (AppState.controlIQEnabled && AppState.ciqZone != null) {
                var word = ciqZoneWord(AppState.ciqZone as Lang.String);
                return word.equals("") ? null : "Control-IQ: " + word;
            }
            return null;
        }
        // A PRINTED row (Garmin has no VoiceOver), shown ONLY when the pump's OWN control-state has
        // confirmed the ACTIVE suspend is Control-IQ's. Garmin has no generic deliverySuspended wire
        // signal to fall back to, so an absent/false attribution renders the row entirely ABSENT —
        // never a fabricated "Control-IQ paused" claim, and never a plain "Basal" row this watch never
        // had in the first place. "CIQ" (not the full "Control-IQ") to stay within the ~28-char
        // DetailsView.detailRow budget at FONT_XTINY — "Basal: Control-IQ paused (Nm)" runs 29-30+
        // chars, well past every other row's max (23); "Basal: CIQ paused (Nm)" holds at 22-23.
        if (id.equals("ciqSuspend")) {
            if (AppState.ciqSuspendedForLow != null && AppState.ciqSuspendedForLow &&
                AppState.ciqSuspendStartEpochSec != null) {
                var mins = ciqSuspendElapsedMinutes();
                return "Basal: CIQ paused (" + mins.toString() + "m)";
            }
            return null;
        }
        // A PRINTED row (Garmin has no VoiceOver), omitted entirely (never "--") unless an
        // auto-correction has actually been seen — no recent auto-correction is the common/expected
        // case, not an error (matches ciqZone's convention).
        if (id.equals("autoCorrection")) {
            if (AppState.lastAutoCorrectionEpochSec != null) {
                var mins = elapsedMinutesSince(AppState.lastAutoCorrectionEpochSec);
                return "Auto-correction: " + mins.toString() + "m ago";
            }
            return null;
        }
        // Remote MARKER only (no on-watch/Garmin timeline). "CIQ" (not the full "Control-IQ") to stay
        // within the ~28-char DetailsView.detailRow budget at FONT_XTINY, matching the ciqSuspend
        // row's precedent. Never speculates WHY.
        if (id.equals("couldNotDeliver")) {
            if (AppState.ciqLastCouldNotDeliverEpochSec != null) {
                var mins = elapsedMinutesSince(AppState.ciqLastCouldNotDeliverEpochSec);
                return "CIQ couldn't deliver (" + mins.toString() + "m)";
            }
            return null;
        }
        // TEXT-ONLY — no drawn bar. The honest "% of your configured max basal rate" text row,
        // computed LOCALLY from AppState.basalRate/maxBasalUnitsPerHour (never a pre-rendered
        // percentage on the wire). Row omitted entirely (never "0%"/"--") when the configured max is
        // unknown/absent (fail-closed) — mirrors ciqZone's row-absent convention. The label ALWAYS
        // contains "Basal" and ALWAYS shows both the current and configured max U/hr alongside the %
        // — this is faBolus's OWN construct, Tandem ships no such gauge, NEVER a Control-IQ figure.
        // "%.2f" (not "%.0f") to match the Copywriting Contract's exact U/hr precision; typical
        // values ("Basal 0.85/1.60 U/hr · 53%", 26 chars) hold well within the ~28-char FONT_XTINY
        // budget — only the extreme, unrealistic edge of current==max==the pump's absolute ceiling
        // (15.00 U/hr) reaches 27-29 chars, matching the ciqSuspend row's own documented over-budget
        // precedent above.
        if (id.equals("maxBasal")) {
            var fraction = AppState.maxBasalFraction();
            if (fraction == null) { return null; }
            var pct = (fraction * 100.0 + 0.5).toNumber();
            var maxV = AppState.maxBasalUnitsPerHour as Lang.Float;
            return "Basal " + AppState.basalRate.format("%.2f") + "/" + maxV.format("%.2f")
                 + " U/hr · " + pct.toString() + "%";
        }
        return null;
    }

    // PURE y-position helper, extracted so the collapsed-layout guard below is
    // unit-testable (the rest of DetailsView is view-code, so it stays sim/hardware-only). A phone-pushed
    // detailsOrder of only opt-in CIQ ids can collapse the visible rows down to just the always-appended
    // alerts row (size 1); the old `step = (bottom-top)/(rows.size()-1)` would then divide by zero and hand
    // a NaN/inf y to drawText. With a single row we center it in the band at `(top+bottom)/2.0`; with two or
    // more we space them evenly across `[top, bottom]` exactly as before. `rows` is never empty (the alerts
    // row is always appended), so rowCount<=0 can't occur — the `<= 1` guard covers it defensively anyway.
    // Returns a 0..1 band FRACTION; onUpdate multiplies by the drawable height.
    static function rowY(rowCount as Lang.Number, i as Lang.Number,
                         top as Lang.Float, bottom as Lang.Float) as Lang.Float {
        if (rowCount <= 1) { return (top + bottom) / 2.0; }
        var step = (bottom - top) / (rowCount - 1);
        return top + step * i;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Gfx.FONT_XTINY,
                    AppState.connection.equals("") ? "Pump status" : AppState.connection, vc);

        // Rows in the central band (0.20..0.84) so the round edges never clip the text. Which rows +
        // order come from the phone (AppState.detailsOrder); the alerts summary and the app version are
        // always appended locally, in that order.
        var alertCount = AppState.alerts.size();
        var rows = [];
        var order = AppState.detailsOrder;
        for (var i = 0; i < order.size(); i += 1) {
            var r = detailRow(order[i] as Lang.String);
            if (r != null) { rows.add(r); }
        }
        rows.add(alertCount > 0 ? ("Alerts: " + alertCount.toString()) : "No alerts");
        // Which watch build is on the wrist. Appended LOCALLY and unconditionally, exactly like the
        // alerts summary above and deliberately NOT a phone-pushed `detailsOrder` id: the app version is
        // watch-local knowledge the phone has no business supplying (and could not supply correctly — it
        // knows its OWN version, not which Garmin binary is installed). Always last, so it never pushes a
        // therapy value off the screen.
        rows.add(AppVersion.label());
        var top = 0.28, bottom = 0.80;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < rows.size(); i += 1) {
            dc.drawText(cx, h * rowY(rows.size(), i, top, bottom), Gfx.FONT_XTINY, rows[i], vc);
        }
    }
}
